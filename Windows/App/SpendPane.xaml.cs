using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

namespace CodexBar.App;

public sealed partial class SpendPane : UserControl
{
    private Func<SpendQuery, CancellationToken, Task<AppResponse>>? request;
    private CancellationToken lifetime;
    private SpendPage? current;
    private int epoch;
    private int page;
    private int selectedDay;
    private int selectedDetailPoint;
    private SpendDetailQuery? detail;
    private bool applying;
    private bool loading;
    private bool pending;
    private bool active;
    private string? currency;

    public SpendPane()
    {
        InitializeComponent();
        ActualThemeChanged += (_, _) => { DrawChart(); DrawDetailChart(); };
    }

    internal void Configure(Func<SpendQuery, CancellationToken, Task<AppResponse>> request, CancellationToken lifetime)
    {
        this.request = request;
        this.lifetime = lifetime;
    }

    internal void SetActive(bool value)
    {
        active = value;
        if (value) { _ = RefreshAsync(); }
        else { Invalidate(); }
    }

    internal void Invalidate(bool clearDetail = true)
    {
        epoch++;
        if (clearDetail) { detail = null; selectedDetailPoint = 0; }
        current = null;
        BreakdownList.ItemsSource = null;
        ChartCanvas.Children.Clear();
        DayDetail.Text = "";
        DayPosition.Text = "";
        CostText.Text = "Unknown";
        TokensText.Text = "Unknown";
        ContextText.Text = "";
        ComparisonPanel.Visibility = Visibility.Collapsed;
        ComparisonRows.ItemsSource = null;
        PreviousPageButton.IsEnabled = NextPageButton.IsEnabled = false;
        PagePosition.Text = "";
        StatusText.Text = "Waiting for current cost data…";
        HourlyButton.IsEnabled = false;
        DetailPanel.Visibility = Visibility.Collapsed;
        DetailRows.ItemsSource = null;
        DetailCanvas.Children.Clear();
        DetailTitle.Text = DetailContext.Text = DetailPointText.Text = DetailPointPosition.Text = DetailPagePosition.Text = "";
    }

    internal async Task RefreshAsync()
    {
        if (request is null || lifetime.IsCancellationRequested || !active) return;
        if (loading) { pending = true; return; }
        loading = true;
        pending = false;
        var capturedEpoch = epoch;
        var query = Query();
        try
        {
            var result = await request(query, lifetime);
            if (lifetime.IsCancellationRequested || capturedEpoch != epoch) return;
            if (result.Status != "ok" || result.Spend is not { } value)
            {
                Invalidate();
                StatusText.Text = result.Status == "spendUnavailable"
                    ? "Cost data is unavailable. Enable cost collection from the tray, then refresh."
                    : "Cost data changed. Waiting for the current collection…";
                return;
            }
            if (value.Days != query.Days || value.Chart != query.Chart || value.Section != query.Section)
                throw new IOException("Spend response differs from the requested view.");
            if ((value.Comparisons is not null) != query.ComparePeriods)
                throw new IOException("Spend comparison response differs from the requested view.");
            if (query.Detail is { } selection && (value.SelectionRevision != selection.Revision
                || value.Detail?.Kind != selection.Kind)) throw new IOException("Spend detail selection changed.");
            Apply(value);
        }
        catch (Exception error) when (error is IOException or OperationCanceledException or InvalidOperationException
            or System.Text.Json.JsonException or System.ComponentModel.Win32Exception or UnauthorizedAccessException)
        {
            if (lifetime.IsCancellationRequested || capturedEpoch != epoch) return;
            Invalidate();
            StatusText.Text = "Cost connection interrupted. Waiting to reconnect…";
        }
        finally
        {
            loading = false;
            if (pending && !lifetime.IsCancellationRequested) { pending = false; _ = RefreshAsync(); }
        }
    }

    private SpendQuery Query() => new(
        int.Parse((PeriodPicker.SelectedItem as ComboBoxItem)?.Tag as string ?? "30"), currency,
        (SectionPicker.SelectedItem as ComboBoxItem)?.Tag as string ?? "providers",
        (ChartPicker.SelectedItem as ComboBoxItem)?.Tag as string ?? "cost", page, detail, CompareToggle.IsOn);

    private void Apply(SpendPage value)
    {
        var selectedLabel = current?.Points.ElementAtOrDefault(selectedDay)?.Label;
        var chartChanged = current is null || current.Chart != value.Chart || !current.Points.SequenceEqual(value.Points);
        var rowsChanged = current is null || !current.Rows.SequenceEqual(value.Rows);
        var comparisonsChanged = current?.Comparisons is not { } oldComparisons || value.Comparisons is not { } newComparisons
            || !oldComparisons.SequenceEqual(newComparisons);
        var detailRowsChanged = current?.Detail is not { } previousDetail || value.Detail is not { } nextDetail
            || !previousDetail.Rows.SequenceEqual(nextDetail.Rows);
        var detailChartChanged = current?.Detail is not { } previousChart || value.Detail is not { } nextChart
            || !previousChart.Points.SequenceEqual(nextChart.Points);
        current = value;
        page = value.Page;
        applying = true;
        try
        {
            if (CurrencyPicker.ItemsSource is not string[] existing || !existing.SequenceEqual(value.Currencies))
                CurrencyPicker.ItemsSource = value.Currencies;
            CurrencyPicker.SelectedItem = value.Currency;
            currency = value.Currency;
        }
        finally { applying = false; }
        CostText.Text = value.TotalCost;
        TokensText.Text = value.TotalTokens;
        ContextText.Text = value.Context;
        StatusText.Text = value.Stale ? "Stale collection" : value.Partial ? "Partial collection" : "Captured cost data";
        if (value.Truncated) StatusText.Text += " · Some display details were truncated";
        if (rowsChanged) BreakdownList.ItemsSource = value.Rows;
        ComparisonPanel.Visibility = value.Comparisons is null ? Visibility.Collapsed : Visibility.Visible;
        if (comparisonsChanged) ComparisonRows.ItemsSource = value.Comparisons;
        PagePosition.Text = value.TotalRows == 0 ? "No rows for this breakdown" : $"Page {value.Page + 1} / {value.PageCount} · {value.TotalRows} rows";
        PreviousPageButton.IsEnabled = value.Page > 0;
        NextPageButton.IsEnabled = value.Page + 1 < value.PageCount;
        if (chartChanged) DrawChart();
        var retained = selectedLabel is null ? -1 : Array.FindIndex(value.Points, point => point.Label == selectedLabel);
        selectedDay = retained >= 0 ? retained : Math.Clamp(selectedDay, 0, Math.Max(0, value.Points.Length - 1));
        ShowDay();
        DetailPanel.Visibility = value.Detail is null ? Visibility.Collapsed : Visibility.Visible;
        if (value.Detail is { } child)
        {
            if (detail is not null) detail = detail with { Page = child.Page };
            DetailTitle.Text = child.Title;
            DetailContext.Text = child.Context;
            if (detailRowsChanged) DetailRows.ItemsSource = child.Rows;
            if (detailChartChanged) DrawDetailChart();
            DetailPagePosition.Text = child.TotalRows == 0 ? "No model or source rows available"
                : $"Page {child.Page + 1} / {child.PageCount} · {child.TotalRows} rows";
            PreviousDetailButton.IsEnabled = child.Page > 0;
            NextDetailButton.IsEnabled = child.Page + 1 < child.PageCount;
            selectedDetailPoint = Math.Clamp(selectedDetailPoint, 0, Math.Max(0, child.Points.Length - 1));
            ShowDetailPoint();
        }
        else
        {
            DetailRows.ItemsSource = null;
            DetailCanvas.Children.Clear();
            DetailTitle.Text = DetailContext.Text = DetailPointText.Text = DetailPointPosition.Text = "";
        }
    }

    private void DrawChart()
    {
        Draw(ChartCanvas, current?.Points ?? [], current?.Chart == "tokens", index => { selectedDay = index; ShowDay(); });
    }

    private void DrawDetailChart() =>
        Draw(DetailCanvas, current?.Detail?.Points ?? [], false, index => { selectedDetailPoint = index; ShowDetailPoint(); });

    private void Draw(Canvas canvas, SpendPoint[] points, bool tokens, Action<int> select)
    {
        canvas.Children.Clear();
        if (points.Length == 0) return;
        var accentColor = Application.Current.Resources.TryGetValue("SystemAccentColor", out var resource)
            && resource is Windows.UI.Color color ? color : Microsoft.UI.Colors.SteelBlue;
        var accent = new SolidColorBrush(accentColor);
        var foreground = Foreground;
        var maximum = Math.Max(1, points.Max(point => point.Value ?? 0));
        canvas.Width = tokens ? Math.Max(650, (points.Max(point => point.Column) + 1) * 14)
            : Math.Max(650, points.Length * 9);
        canvas.Height = tokens ? 112 : 200;
        for (var index = 0; index < points.Length; index++)
        {
            var point = points[index];
            var height = tokens ? 12 : point.Value is null ? 3 : Math.Max(2, point.Value.Value / maximum * 180);
            var rectangle = new Rectangle { Width = tokens ? 12 : 7, Height = height,
                Fill = (tokens ? point.Level <= 1 : point.Value is null) ? foreground : accent,
                Opacity = tokens ? point.Level switch { 0 => 0.12, 1 => 0.5, 2 => 0.2, _ => 0.35 + (point.Level - 3) * 0.2 } : 1 };
            var button = new Button { Content = rectangle, Padding = new Thickness(0), BorderThickness = new Thickness(0),
                Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent), Width = tokens ? 14 : 9,
                Height = tokens ? 14 : 200, VerticalContentAlignment = VerticalAlignment.Bottom, IsTabStop = false };
            AutomationProperties.SetName(button, point.Detail);
            ToolTipService.SetToolTip(button, point.Detail);
            var captured = index;
            button.Click += (_, _) => select(captured);
            Canvas.SetLeft(button, tokens ? point.Column * 14 : index * 9);
            Canvas.SetTop(button, tokens ? point.Row * 14 : 0);
            canvas.Children.Add(button);
        }
    }

    private void ShowDay()
    {
        var point = current?.Points.ElementAtOrDefault(selectedDay);
        DayDetail.Text = point?.Detail ?? "No chart data is available.";
        DayPosition.Text = point is null ? "" : $"{selectedDay + 1} / {current!.Points.Length}";
        HourlyButton.IsEnabled = current?.Chart == "cost" && point?.DayKey is not null && current.Currency is not null;
    }
    private void ShowDetailPoint()
    {
        var points = current?.Detail?.Points;
        var point = points?.ElementAtOrDefault(selectedDetailPoint);
        DetailPointText.Text = point?.Detail ?? "No daily or hourly samples are available for this detail.";
        DetailPointPosition.Text = point is null ? "" : $"{selectedDetailPoint + 1} / {points!.Length}";
    }
    private void OpenDetail(object sender, RoutedEventArgs args)
    {
        if (current is null || current.Currency is null || sender is not Button button || button.Tag is not int index
            || current.Section is not ("projects" or "sessions")) return;
        detail = new SpendDetailQuery(current.Section == "projects" ? "project" : "session", index, null, current.SelectionRevision);
        selectedDetailPoint = 0;
        Reload(false);
    }
    private void ShowHourly(object sender, RoutedEventArgs args)
    {
        if (current?.Chart != "cost" || current.Currency is null
            || current.Points.ElementAtOrDefault(selectedDay)?.DayKey is not { } day) return;
        detail = new SpendDetailQuery("hourly", null, day, current.SelectionRevision);
        selectedDetailPoint = 0;
        Reload(false);
    }
    private void CloseDetail(object sender, RoutedEventArgs args) => Reload();
    private void PreviousDetailPoint(object sender, RoutedEventArgs args) { selectedDetailPoint = Math.Max(0, selectedDetailPoint - 1); ShowDetailPoint(); }
    private void NextDetailPoint(object sender, RoutedEventArgs args)
    {
        selectedDetailPoint = Math.Min(Math.Max(0, (current?.Detail?.Points.Length ?? 0) - 1), selectedDetailPoint + 1);
        ShowDetailPoint();
    }
    private void PreviousDetailPage(object sender, RoutedEventArgs args)
    {
        if (detail is null || detail.Page == 0) return;
        detail = detail with { Page = detail.Page - 1 };
        Reload(false);
    }
    private void NextDetailPage(object sender, RoutedEventArgs args)
    {
        if (detail is null || current?.Detail is not { } child || child.Page + 1 >= child.PageCount) return;
        detail = detail with { Page = child.Page + 1 };
        Reload(false);
    }
    private void PreviousDay(object sender, RoutedEventArgs args) { selectedDay = Math.Max(0, selectedDay - 1); ShowDay(); }
    private void NextDay(object sender, RoutedEventArgs args) { selectedDay = Math.Min(Math.Max(0, (current?.Points.Length ?? 0) - 1), selectedDay + 1); ShowDay(); }
    private void PreviousPage(object sender, RoutedEventArgs args) { if (page > 0) { page--; Reload(); } }
    private void NextPage(object sender, RoutedEventArgs args) { if (current is not null && page + 1 < current.PageCount) { page++; Reload(); } }
    private void QueryChanged(object sender, SelectionChangedEventArgs args)
    {
        if (applying || request is null) return;
        page = 0;
        Reload();
    }
    private void ComparisonChanged(object sender, RoutedEventArgs args)
    {
        if (applying || request is null) return;
        Reload();
    }
    private void ShowComparisonPeriod(object sender, RoutedEventArgs args)
    {
        if (sender is not Button button || button.Tag is not int days) return;
        var item = PeriodPicker.Items.OfType<ComboBoxItem>().FirstOrDefault(value => value.Tag as string == days.ToString());
        if (item is not null) PeriodPicker.SelectedItem = item;
    }
    private void CurrencyChanged(object sender, SelectionChangedEventArgs args)
    {
        if (applying || request is null) return;
        currency = CurrencyPicker.SelectedItem as string;
        page = 0;
        Reload();
    }
    private void Reload(bool clearDetail = true) { Invalidate(clearDetail); pending = true; _ = RefreshAsync(); }
}
