using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

namespace CodexBar.App;

public sealed partial class SpendPane : UserControl
{
    private Func<SpendQuery, CancellationToken, Task<AppResponse>>? request;
    private Func<SpendQuery, SpendExportAction, CancellationToken, Task<AppResponse>>? export;
    private Action<SpendQuery, string?>? viewChanged;
    private const string AutomaticCurrency = "Automatic";
    private CancellationToken lifetime;
    private SpendPage? current;
    private int epoch;
    private int page;
    private int codexModelsPage;
    private int codexCatalogPage;
    private CodexModelSelection? codexModel;
    private int selectedCodexPoint;
    private string? codexSelectionNotice;
    private int selectedDay;
    private int selectedDetailPoint;
    private SpendDetailQuery? detail;
    private CodexSessionQuery? codexSessions;
    private bool revealDetail;
    private string? detailCurrency;
    private bool applying;
    private bool loading;
    private bool pending;
    private bool active;
    private bool exporting;
    private string? currency;
    private string? selectedDayKey;

    public SpendPane()
    {
        InitializeComponent();
        ActualThemeChanged += (_, _) => { DrawChart(); DrawDetailChart(); DrawCodexTimeline(); };
    }

    internal void Configure(Func<SpendQuery, CancellationToken, Task<AppResponse>> request,
        Func<SpendQuery, SpendExportAction, CancellationToken, Task<AppResponse>> export,
        Action<SpendQuery, string?> viewChanged, CancellationToken lifetime)
    {
        this.request = request;
        this.export = export;
        this.viewChanged = viewChanged;
        this.lifetime = lifetime;
    }

    internal void RestoreView(AppViewPreferences values)
    {
        applying = true;
        try
        {
            PeriodPicker.SelectedItem = PeriodPicker.Items.OfType<ComboBoxItem>()
                .FirstOrDefault(item => item.Tag as string == values.Days.ToString());
            SectionPicker.SelectedItem = SectionPicker.Items.OfType<ComboBoxItem>()
                .FirstOrDefault(item => item.Tag as string == values.Section);
            ChartPicker.SelectedItem = ChartPicker.Items.OfType<ComboBoxItem>()
                .FirstOrDefault(item => item.Tag as string == values.Chart);
            CompareToggle.IsOn = values.ComparePeriods;
            currency = values.Currency;
            CurrencyPicker.ItemsSource = currency is null ? new[] { AutomaticCurrency } : new[] { AutomaticCurrency, currency };
            CurrencyPicker.SelectedItem = currency ?? AutomaticCurrency;
            selectedDayKey = values.SelectedDay;
            selectedDay = 0;
            page = 0;
            codexModelsPage = 0;
            codexCatalogPage = 0;
            codexModel = null;
        }
        finally { applying = false; }
        Reload();
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
        if (clearDetail) { detail = null; codexSessions = null; detailCurrency = null; selectedDetailPoint = 0; revealDetail = false; }
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
        CodexModelsPanel.Visibility = Visibility.Collapsed;
        CodexModelsRows.ItemsSource = null;
        CodexModelsContext.Text = CodexModelsCurrentRange.Text = CodexModelsPreviousRange.Text = CodexModelsPosition.Text = "";
        PreviousCodexModelsButton.IsEnabled = NextCodexModelsButton.IsEnabled = false;
        CodexModelChoices.ItemsSource = null;
        CodexCatalogPosition.Text = "";
        PreviousCodexCatalogButton.IsEnabled = NextCodexCatalogButton.IsEnabled = false;
        CodexTimelineCanvas.Children.Clear();
        CodexModelScope.Text = CodexTimelineContext.Text = CodexTimelineDetail.Text = CodexTimelinePosition.Text = "";
        PreviousCodexPointButton.IsEnabled = NextCodexPointButton.IsEnabled = AllCodexModelsButton.IsEnabled = false;
        PreviousPageButton.IsEnabled = NextPageButton.IsEnabled = false;
        PagePosition.Text = "";
        StatusText.Text = "Waiting for current cost data…";
        HourlyButton.IsEnabled = false;
        DetailPanel.Visibility = Visibility.Collapsed;
        BackCodexSessionsButton.Visibility = Visibility.Collapsed;
        DetailRows.ItemsSource = null;
        DetailCanvas.Children.Clear();
        DetailTitle.Text = DetailContext.Text = DetailPointText.Text = DetailPointPosition.Text = DetailPagePosition.Text = "";
        ShareActions.IsEnabled = JSONActions.IsEnabled = CodexCSVActions.IsEnabled = false;
        ExportStatusText.Text = "";
    }

    internal async Task RefreshAsync()
    {
        if (request is null || lifetime.IsCancellationRequested || !active) return;
        if (loading || exporting) { pending = true; return; }
        loading = true;
        pending = false;
        var capturedEpoch = epoch;
        var query = Query();
        if (detail is not null || codexSessions is not null) query = query with { Currency = detailCurrency };
        try
        {
            var result = await request(query, lifetime);
            if (lifetime.IsCancellationRequested || capturedEpoch != epoch) return;
            if (result.Status != "ok" || result.Spend is not { } value)
            {
                if (result.Status == "codexModelChanged") {
                    codexModel = null;
                    codexSessions = null;
                    codexModelsPage = 0;
                    codexCatalogPage = 0;
                    selectedCodexPoint = 0;
                    codexSelectionNotice = "The collection or privacy settings changed. The previous model filter was cleared; select a model again.";
                    pending = true;
                }
                if (result.Status == "codexSessionChanged") {
                    codexSessions = null;
                    codexSelectionNotice = "The collection or session references changed. Open the model's current or previous sessions again.";
                    pending = true;
                }
                Invalidate();
                StatusText.Text = result.Status == "spendUnavailable"
                    ? "Cost data is unavailable. Enable cost collection from the tray, then refresh."
                    : "Cost data changed. Waiting for the current collection…";
                return;
            }
            if (value.Days != query.Days || value.Chart != query.Chart || value.Section != query.Section)
                throw new IOException("Spend response differs from the requested view.");
            if (query.Currency is not null && value.Currency is not null && value.Currency != query.Currency)
                throw new IOException("Spend currency differs from the requested view.");
            if ((value.Comparisons is not null) != query.ComparePeriods)
                throw new IOException("Spend comparison response differs from the requested view.");
            if ((value.CodexModels is not null) != (query.CodexModelsPage is not null))
                throw new IOException("Codex model response differs from the requested view.");
            if (value.CodexModels is { } models && query.CodexModelsPage is { } requestedPage
                && models.Page != Math.Min(requestedPage, models.PageCount - 1))
                throw new IOException("Codex model page differs from the requested view.");
            if (value.CodexModels is { } modelView && (!CodexModelSelection.Matches(modelView.ModelSelection, query.CodexModel)
                || modelView.CatalogPage != Math.Min(query.CodexCatalogPage ?? 0, modelView.CatalogPageCount - 1)
                || modelView.Granularity != (query.CodexGranularity ?? "daily")
                || modelView.Metric != (query.CodexMetric ?? "tokens")))
                throw new IOException("Codex model selection or timeline differs from the requested view.");
            if (query.Detail is { } selection && (value.SelectionRevision != selection.Revision
                || value.Detail?.Kind != selection.Kind)) throw new IOException("Spend detail selection changed.");
            if (query.CodexSessions is { } sessions) {
                var child = value.Detail;
                if (child is null || value.CodexModels?.SelectionRevision != sessions.Revision
                    || child.Kind != (sessions.ReferenceIndex is null ? "codexSessions" : "codexSession")
                    || child.Page != Math.Min(sessions.Page, child.PageCount - 1))
                    throw new IOException("Codex session selection changed.");
            }
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
        (ChartPicker.SelectedItem as ComboBoxItem)?.Tag as string ?? "cost", page, detail, CompareToggle.IsOn,
        CodexModelsToggle.IsOn ? codexModelsPage : null,
        CodexModelsToggle.IsOn ? codexModel : null,
        CodexModelsToggle.IsOn ? (CodexGranularityPicker.SelectedItem as ComboBoxItem)?.Tag as string ?? "daily" : null,
        CodexModelsToggle.IsOn ? (CodexMetricPicker.SelectedItem as ComboBoxItem)?.Tag as string ?? "tokens" : null,
        CodexModelsToggle.IsOn ? codexCatalogPage : null,
        CodexModelsToggle.IsOn ? codexSessions : null);

    private void Apply(SpendPage value)
    {
        var retainedDay = selectedDayKey ?? current?.Points.ElementAtOrDefault(selectedDay)?.DayKey;
        var chartChanged = current is null || current.Chart != value.Chart || !current.Points.SequenceEqual(value.Points);
        var rowsChanged = current is null || !current.Rows.SequenceEqual(value.Rows);
        var comparisonsChanged = current?.Comparisons is not { } oldComparisons || value.Comparisons is not { } newComparisons
            || !oldComparisons.SequenceEqual(newComparisons);
        var codexModelsChanged = current?.CodexModels is not { } oldModels || value.CodexModels is not { } newModels
            || !oldModels.Rows.SequenceEqual(newModels.Rows);
        var codexTimelineChanged = current?.CodexModels is not { } oldTimeline || value.CodexModels is not { } newTimeline
            || oldTimeline.Metric != newTimeline.Metric || !oldTimeline.Timeline.SequenceEqual(newTimeline.Timeline);
        var choicesChanged = current?.CodexModels is not { } oldChoices || value.CodexModels is not { } newChoices
            || !oldChoices.Choices.SequenceEqual(newChoices.Choices);
        var detailRowsChanged = current?.Detail is not { } previousDetail || value.Detail is not { } nextDetail
            || !previousDetail.Rows.SequenceEqual(nextDetail.Rows);
        var detailChartChanged = current?.Detail is not { } previousChart || value.Detail is not { } nextChart
            || previousChart.Kind != nextChart.Kind || !previousChart.Points.SequenceEqual(nextChart.Points);
        current = value;
        UpdateExportActions();
        page = value.Page;
        applying = true;
        try
        {
            // Keep an explicitly selected but absent currency; a refresh must not choose another group.
            var choices = new[] { AutomaticCurrency }.Concat(value.Currencies)
                .Concat(currency is null ? Array.Empty<string>() : new[] { currency }).Distinct().ToArray();
            if (CurrencyPicker.ItemsSource is not string[] existing || !existing.SequenceEqual(choices))
                CurrencyPicker.ItemsSource = choices;
            CurrencyPicker.SelectedItem = currency ?? AutomaticCurrency;
        }
        finally { applying = false; }
        CostText.Text = value.TotalCost;
        TokensText.Text = value.TotalTokens;
        ContextText.Text = value.Context;
        if (currency is not null && value.Currency is null)
            ContextText.Text = $"The selected {currency} group is not in this collection. Select another currency or Automatic.\n" + ContextText.Text;
        else if (currency is null && value.Currency is not null)
            ContextText.Text = $"Automatic currency group: {value.Currency}.\n" + ContextText.Text;
        StatusText.Text = value.Stale ? "Stale collection" : value.Partial ? "Partial collection" : "Captured cost data";
        if (value.Truncated) StatusText.Text += " · Some display details were truncated";
        if (rowsChanged) BreakdownList.ItemsSource = value.Rows;
        ComparisonPanel.Visibility = value.Comparisons is null ? Visibility.Collapsed : Visibility.Visible;
        if (comparisonsChanged) ComparisonRows.ItemsSource = value.Comparisons;
        CodexModelsPanel.Visibility = value.CodexModels is null ? Visibility.Collapsed : Visibility.Visible;
        if (codexModelsChanged) CodexModelsRows.ItemsSource = value.CodexModels?.Rows;
        if (value.CodexModels is { } models)
        {
            codexModelsPage = models.Page;
            CodexModelsContext.Text = models.Context;
            CodexModelsCurrentRange.Text = models.CurrentRange;
            CodexModelsPreviousRange.Text = models.PreviousRange;
            CodexModelsPosition.Text = models.TotalRows == 0 ? "No model rows in these periods"
                : $"Page {models.Page + 1} / {models.PageCount} · {models.TotalRows} models";
            PreviousCodexModelsButton.IsEnabled = models.Page > 0;
            NextCodexModelsButton.IsEnabled = models.Page + 1 < models.PageCount;
            CodexModelScope.Text = models.SelectedLabel;
            AllCodexModelsButton.IsEnabled = models.ModelSelection is not null;
            if (choicesChanged) CodexModelChoices.ItemsSource = models.Choices;
            codexCatalogPage = models.CatalogPage;
            CodexCatalogPosition.Text = models.CatalogTotal == 0 ? "No model choices"
                : $"Choices {models.CatalogPage + 1} / {models.CatalogPageCount} · {models.CatalogTotal} models";
            PreviousCodexCatalogButton.IsEnabled = models.CatalogPage > 0;
            NextCodexCatalogButton.IsEnabled = models.CatalogPage + 1 < models.CatalogPageCount;
            CodexTimelineContext.Text = (codexSelectionNotice is null ? "" : codexSelectionNotice + "\n") + models.TimelineContext;
            if (codexTimelineChanged) DrawCodexTimeline();
            selectedCodexPoint = Math.Clamp(selectedCodexPoint, 0, Math.Max(0, models.Timeline.Length - 1));
            ShowCodexPoint();
        }
        PagePosition.Text = value.TotalRows == 0 ? "No rows for this breakdown" : $"Page {value.Page + 1} / {value.PageCount} · {value.TotalRows} rows";
        PreviousPageButton.IsEnabled = value.Page > 0;
        NextPageButton.IsEnabled = value.Page + 1 < value.PageCount;
        if (chartChanged) DrawChart();
        var retained = retainedDay is null ? -1 : Array.FindIndex(value.Points, point => point.DayKey == retainedDay);
        selectedDay = retained >= 0 ? retained : selectedDayKey is not null ? -1
            : Math.Clamp(selectedDay, 0, Math.Max(0, value.Points.Length - 1));
        ShowDay();
        DetailPanel.Visibility = value.Detail is null ? Visibility.Collapsed : Visibility.Visible;
        BackCodexSessionsButton.Visibility = value.Detail?.Kind == "codexSession" ? Visibility.Visible : Visibility.Collapsed;
        if (value.Detail is { } child)
        {
            if (detail is not null) detail = detail with { Page = child.Page };
            if (codexSessions is not null) codexSessions = codexSessions with { Page = child.Page };
            DetailTitle.Text = child.Title;
            DetailContext.Text = child.Context;
            if (revealDetail) {
                revealDetail = false;
                DispatcherQueue.TryEnqueue(() => { if (active && current?.Detail is not null) DetailPanel.StartBringIntoView(); });
            }
            if (detailRowsChanged) DetailRows.ItemsSource = child.Rows;
            if (detailChartChanged) DrawDetailChart();
            DetailPagePosition.Text = child.TotalRows == 0
                ? child.Kind == "codexSessions" ? "No linked session references in this period" : "No model or source rows available"
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
        Draw(ChartCanvas, current?.Points ?? [], current?.Chart == "tokens", SelectDay);
    }

    private void UpdateExportActions()
    {
        JSONActions.IsEnabled = !exporting && active && current?.Currency is not null;
        ShareActions.IsEnabled = JSONActions.IsEnabled && current is { Stale: false };
        CodexCSVActions.IsEnabled = JSONActions.IsEnabled && current?.CodexModels is not null;
    }

    private async void ExportClicked(object sender, RoutedEventArgs args)
    {
        if (exporting || export is null || current is not { Currency: not null } captured
            || sender is not Button { Tag: string kind } || lifetime.IsCancellationRequested) return;
        if (kind is not ("preview" or "copyText" or "copyImage" or "saveImage" or "copyJSON" or "saveJSON"
            or "copyModelsCSV" or "saveModelsCSV")) return;
        var modelExport = kind is "copyModelsCSV" or "saveModelsCSV";
        if (modelExport && captured.CodexModels is null) return;
        var capturedEpoch = epoch;
        var query = Query() with { Days = captured.Days, Currency = captured.Currency, Detail = null,
            ComparePeriods = false, CodexSessions = null };
        if (modelExport) {
            var models = captured.CodexModels!;
            query = query with { CodexModelsPage = 0, CodexCatalogPage = 0, CodexModel = models.ModelSelection,
                CodexGranularity = models.Granularity, CodexMetric = models.Metric };
        } else {
            query = query with { CodexModelsPage = null, CodexModel = null, CodexGranularity = null,
                CodexMetric = null, CodexCatalogPage = null };
        }
        var action = new SpendExportAction(kind, modelExport ? captured.CodexModels!.ExportRevision : captured.SelectionRevision);
        exporting = true;
        UpdateExportActions();
        ExportStatusText.Text = "Sending to the Windows share/export controls…";
        try
        {
            var response = await export(query, action, lifetime);
            if (lifetime.IsCancellationRequested || capturedEpoch != epoch) return;
            ExportStatusText.Text = response.Status switch
            {
                "queued" => "Request queued. Follow any Windows preview or save dialog, then check the clipboard or chosen file.",
                "actionBusy" => "Another share/export action is pending or open. Finish it before trying again.",
                "spendChanged" => "Costs or settings changed. Reload costs before sharing or exporting.",
                "codexModelChanged" => "The model collection changed. Reload costs and select the models again.",
                "spendUnavailable" => "No current cost collection is available for this action.",
                _ => "The share/export request was not accepted. Reload costs before trying again."
            };
            if (response.Status is "spendChanged" or "spendUnavailable" or "codexModelChanged") pending = true;
        }
        catch (Exception error) when (error is IOException or OperationCanceledException or InvalidOperationException
            or System.Text.Json.JsonException or System.ComponentModel.Win32Exception or UnauthorizedAccessException)
        {
            if (lifetime.IsCancellationRequested || capturedEpoch != epoch) return;
            ExportStatusText.Text = "The connection was interrupted. The action may already have started. Check the clipboard or Windows dialog before retrying; it was not sent again.";
        }
        finally
        {
            exporting = false;
            UpdateExportActions();
            if (pending && !lifetime.IsCancellationRequested) { pending = false; _ = RefreshAsync(); }
        }
    }

    private void DrawDetailChart() =>
        Draw(DetailCanvas, current?.Detail?.Points ?? [], false,
            index => { selectedDetailPoint = index; ShowDetailPoint(); });

    private void DrawCodexTimeline() =>
        Draw(CodexTimelineCanvas, current?.CodexModels?.Timeline ?? [], false, index => { selectedCodexPoint = index; ShowCodexPoint(); });
    private void ShowCodexPoint()
    {
        var points = current?.CodexModels?.Timeline ?? [];
        var point = points.ElementAtOrDefault(selectedCodexPoint);
        CodexTimelineDetail.Text = point?.Detail ?? "No model timeline is available.";
        CodexTimelinePosition.Text = point is null ? "" : $"{selectedCodexPoint + 1} / {points.Length}";
        PreviousCodexPointButton.IsEnabled = selectedCodexPoint > 0;
        NextCodexPointButton.IsEnabled = selectedCodexPoint + 1 < points.Length;
    }
    private void PreviousCodexPoint(object sender, RoutedEventArgs args)
    { selectedCodexPoint = Math.Max(0, selectedCodexPoint - 1); ShowCodexPoint(); }
    private void NextCodexPoint(object sender, RoutedEventArgs args)
    {
        selectedCodexPoint = Math.Min(Math.Max(0, (current?.CodexModels?.Timeline.Length ?? 0) - 1), selectedCodexPoint + 1);
        ShowCodexPoint();
    }
    private void FocusCodexModel(object sender, RoutedEventArgs args)
    {
        if (current?.CodexModels is not { } models || sender is not Button { Tag: int index }
            || !models.Rows.Any(row => row.SelectionIndex == index)) return;
        codexModel = new CodexModelSelection([index], models.SelectionRevision);
        codexSessions = null;
        codexModelsPage = selectedCodexPoint = 0;
        codexSelectionNotice = null;
        Reload(false);
    }
    private void ClearCodexModel(object sender, RoutedEventArgs args)
    {
        codexSessions = null;
        codexModel = null;
        codexModelsPage = selectedCodexPoint = 0;
        codexSelectionNotice = null;
        Reload(false);
    }
    private void ClearAllCodexModels(object sender, RoutedEventArgs args)
    {
        if (current?.CodexModels is not { } models) return;
        codexModel = new CodexModelSelection([], models.SelectionRevision);
        codexSessions = null;
        codexModelsPage = selectedCodexPoint = 0;
        codexSelectionNotice = null;
        Reload(false);
    }
    private void ToggleCodexModel(object sender, RoutedEventArgs args)
    {
        if (current?.CodexModels is not { } models || sender is not Button { Tag: int index }
            || !models.Choices.Any(choice => choice.Index == index)) return;
        var mode = codexModel?.Mode ?? "exclude";
        var indices = codexModel?.Indices.ToHashSet() ?? new HashSet<int>();
        if (!indices.Remove(index)) indices.Add(index);
        if (indices.Count > 256) {
            codexSelectionNotice = "A custom model selection can contain up to 256 included or excluded entries. Use All models to reset it.";
            CodexTimelineContext.Text = codexSelectionNotice + "\n" + models.TimelineContext;
            return;
        }
        codexModel = mode == "exclude" && indices.Count == 0 ? null
            : new CodexModelSelection(indices.Order().ToArray(), models.SelectionRevision, mode);
        codexSessions = null;
        codexModelsPage = selectedCodexPoint = 0;
        codexSelectionNotice = null;
        Reload(false);
    }
    private void PreviousCodexCatalogPage(object sender, RoutedEventArgs args)
    { if (codexCatalogPage > 0) { codexCatalogPage--; Reload(false); } }
    private void NextCodexCatalogPage(object sender, RoutedEventArgs args)
    {
        if (current?.CodexModels is { } models && codexCatalogPage + 1 < models.CatalogPageCount)
        { codexCatalogPage++; Reload(false); }
    }
    private void CodexTimelineChanged(object sender, SelectionChangedEventArgs args)
    {
        if (applying || request is null) return;
        selectedCodexPoint = 0;
        Reload(false);
    }

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
        DayDetail.Text = point?.Detail ?? (selectedDayKey is not null
            ? $"The saved day {selectedDayKey} is not in this view. Select a day to inspect it."
            : "No chart data is available.");
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
        codexSessions = null;
        detail = new SpendDetailQuery(current.Section == "projects" ? "project" : "session", index, null, current.SelectionRevision);
        detailCurrency = current.Currency;
        selectedDetailPoint = 0;
        revealDetail = true;
        Reload(false);
    }
    private void OpenCurrentCodexSessions(object sender, RoutedEventArgs args) => OpenCodexSessions(sender, "current");
    private void OpenPreviousCodexSessions(object sender, RoutedEventArgs args) => OpenCodexSessions(sender, "previous");
    private void OpenCodexSessions(object sender, string period)
    {
        if (current?.Currency is null || current.CodexModels is not { } models
            || sender is not Button { Tag: int index } || !models.Rows.Any(row => row.SelectionIndex == index)) return;
        detail = null;
        codexSessions = new CodexSessionQuery(index, period, models.SelectionRevision);
        detailCurrency = current.Currency;
        selectedDetailPoint = 0;
        revealDetail = true;
        Reload(false);
    }
    private void OpenCodexSession(object sender, RoutedEventArgs args)
    {
        if (codexSessions is not { } sessions || current?.Detail is not { Kind: "codexSessions" } child
            || sender is not Button { Tag: int index } || !child.Rows.Any(row => row.SelectionIndex == index)) return;
        codexSessions = sessions with { ReferenceIndex = index, Page = 0 };
        selectedDetailPoint = 0;
        revealDetail = true;
        Reload(false);
    }
    private void BackToCodexSessions(object sender, RoutedEventArgs args)
    {
        if (codexSessions is not { ReferenceIndex: not null } sessions) return;
        codexSessions = sessions with { ReferenceIndex = null, Page = sessions.ReferenceIndex.Value / 40 };
        selectedDetailPoint = 0;
        revealDetail = true;
        Reload(false);
    }
    private void ShowHourly(object sender, RoutedEventArgs args)
    {
        if (current?.Chart != "cost" || current.Currency is null
            || current.Points.ElementAtOrDefault(selectedDay)?.DayKey is not { } day) return;
        codexSessions = null;
        detail = new SpendDetailQuery("hourly", null, day, current.SelectionRevision);
        detailCurrency = current.Currency;
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
        if (codexSessions is { Page: > 0 } sessions) {
            codexSessions = sessions with { Page = sessions.Page - 1 };
            Reload(false);
            return;
        }
        if (detail is null || detail.Page == 0) return;
        detail = detail with { Page = detail.Page - 1 };
        Reload(false);
    }
    private void NextDetailPage(object sender, RoutedEventArgs args)
    {
        if (codexSessions is { } sessions && current?.Detail is { } modelChild && modelChild.Page + 1 < modelChild.PageCount) {
            codexSessions = sessions with { Page = modelChild.Page + 1 };
            Reload(false);
            return;
        }
        if (detail is null || current?.Detail is not { } child || child.Page + 1 >= child.PageCount) return;
        detail = detail with { Page = child.Page + 1 };
        Reload(false);
    }
    private void SelectDay(int index)
    {
        if (current?.Points.ElementAtOrDefault(index) is not { } point) return;
        selectedDay = index;
        selectedDayKey = point.DayKey;
        ShowDay();
        SaveView();
    }
    private void PreviousDay(object sender, RoutedEventArgs args) => SelectDay(Math.Max(0, selectedDay - 1));
    private void NextDay(object sender, RoutedEventArgs args) =>
        SelectDay(Math.Min(Math.Max(0, (current?.Points.Length ?? 0) - 1), selectedDay + 1));
    private void PreviousPage(object sender, RoutedEventArgs args) { if (page > 0) { page--; Reload(); } }
    private void NextPage(object sender, RoutedEventArgs args) { if (current is not null && page + 1 < current.PageCount) { page++; Reload(); } }
    private void QueryChanged(object sender, SelectionChangedEventArgs args)
    {
        if (applying || request is null) return;
        page = 0;
        codexModelsPage = 0;
        if (ReferenceEquals(sender, PeriodPicker) || ReferenceEquals(sender, ChartPicker)) selectedDayKey = null;
        if (ReferenceEquals(sender, PeriodPicker)) { codexModel = null; codexCatalogPage = 0; selectedCodexPoint = 0; codexSelectionNotice = null; }
        SaveView();
        Reload();
    }
    private void ComparisonChanged(object sender, RoutedEventArgs args)
    {
        if (applying || request is null) return;
        SaveView();
        Reload();
    }
    private void CodexModelsChanged(object sender, RoutedEventArgs args)
    {
        if (applying || request is null) return;
        codexModelsPage = 0;
        codexModel = null;
        codexCatalogPage = 0;
        selectedCodexPoint = 0;
        codexSelectionNotice = null;
        Reload();
    }
    private void PreviousCodexModelsPage(object sender, RoutedEventArgs args)
    {
        if (codexModelsPage > 0) { codexModelsPage--; Reload(false); }
    }
    private void NextCodexModelsPage(object sender, RoutedEventArgs args)
    {
        if (current?.CodexModels is { } models && codexModelsPage + 1 < models.PageCount)
        { codexModelsPage++; Reload(false); }
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
        var choice = CurrencyPicker.SelectedItem as string;
        currency = choice == AutomaticCurrency ? null : choice;
        codexCatalogPage = 0;
        codexModel = null;
        selectedCodexPoint = 0;
        codexSelectionNotice = null;
        page = 0;
        codexModelsPage = 0;
        SaveView();
        Reload();
    }
    private void SaveView() { if (!applying) viewChanged?.Invoke(Query(), selectedDayKey); }
    private void Reload(bool clearDetail = true) { Invalidate(clearDetail); pending = true; _ = RefreshAsync(); }
}
