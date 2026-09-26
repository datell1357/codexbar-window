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
    private bool applying;
    private bool loading;
    private bool pending;
    private bool active;
    private string? currency;

    public SpendPane()
    {
        InitializeComponent();
        ActualThemeChanged += (_, _) => DrawChart();
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

    internal void Invalidate()
    {
        epoch++;
        current = null;
        BreakdownList.ItemsSource = null;
        ChartCanvas.Children.Clear();
        DayDetail.Text = "";
        DayPosition.Text = "";
        CostText.Text = "Unknown";
        TokensText.Text = "Unknown";
        ContextText.Text = "";
        PreviousPageButton.IsEnabled = NextPageButton.IsEnabled = false;
        PagePosition.Text = "";
        StatusText.Text = "Waiting for current cost data…";
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
            Apply(value, query);
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
        (ChartPicker.SelectedItem as ComboBoxItem)?.Tag as string ?? "cost", page);

    private void Apply(SpendPage value, SpendQuery query)
    {
        var selectedLabel = current?.Points.ElementAtOrDefault(selectedDay)?.Label;
        var chartChanged = current is null || current.Chart != value.Chart || !current.Points.SequenceEqual(value.Points);
        var rowsChanged = current is null || !current.Rows.SequenceEqual(value.Rows);
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
        PagePosition.Text = value.TotalRows == 0 ? "No rows for this breakdown" : $"Page {value.Page + 1} / {value.PageCount} · {value.TotalRows} rows";
        PreviousPageButton.IsEnabled = value.Page > 0;
        NextPageButton.IsEnabled = value.Page + 1 < value.PageCount;
        if (chartChanged) DrawChart();
        var retained = selectedLabel is null ? -1 : Array.FindIndex(value.Points, point => point.Label == selectedLabel);
        selectedDay = retained >= 0 ? retained : Math.Clamp(selectedDay, 0, Math.Max(0, value.Points.Length - 1));
        ShowDay();
    }

    private void DrawChart()
    {
        ChartCanvas.Children.Clear();
        if (current is null || current.Points.Length == 0) return;
        var accentColor = Application.Current.Resources.TryGetValue("SystemAccentColor", out var resource)
            && resource is Windows.UI.Color color ? color : Microsoft.UI.Colors.SteelBlue;
        var accent = new SolidColorBrush(accentColor);
        var foreground = Foreground;
        var maximum = Math.Max(1, current.Points.Max(point => point.Value ?? 0));
        var tokens = current.Chart == "tokens";
        ChartCanvas.Width = tokens ? Math.Max(650, (current.Points.Max(point => point.Column) + 1) * 14)
            : Math.Max(650, current.Points.Length * 9);
        ChartCanvas.Height = tokens ? 112 : 200;
        for (var index = 0; index < current.Points.Length; index++)
        {
            var point = current.Points[index];
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
            button.Click += (_, _) => { selectedDay = captured; ShowDay(); };
            Canvas.SetLeft(button, tokens ? point.Column * 14 : index * 9);
            Canvas.SetTop(button, tokens ? point.Row * 14 : 0);
            ChartCanvas.Children.Add(button);
        }
    }

    private void ShowDay()
    {
        var point = current?.Points.ElementAtOrDefault(selectedDay);
        DayDetail.Text = point?.Detail ?? "No chart data is available.";
        DayPosition.Text = point is null ? "" : $"{selectedDay + 1} / {current!.Points.Length}";
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
    private void CurrencyChanged(object sender, SelectionChangedEventArgs args)
    {
        if (applying || request is null) return;
        currency = CurrencyPicker.SelectedItem as string;
        page = 0;
        Reload();
    }
    private void Reload() { Invalidate(); pending = true; _ = RefreshAsync(); }
}
