using System.Text.Json.Serialization;

namespace CodexBar.App;

internal sealed record SpendDetailQuery(string Kind, int? Index, string? Day, string Revision, int Page = 0);
internal sealed record CodexModelSelection(int[] Indices, string Revision, string Mode = "include")
{
    [JsonIgnore] public bool IsValid => Indices is { Length: <= 256 } && Indices.All(index => index is >= 0 and <= 1000000)
        && Indices.Distinct().Count() == Indices.Length && Indices.SequenceEqual(Indices.Order())
        && (Mode is "include" or "exclude") && Revision is { Length: 64 }
        && Revision.All(value => value is >= '0' and <= '9' or >= 'a' and <= 'f');
    public bool Includes(int index) => Mode == "include" ? Indices.Contains(index) : !Indices.Contains(index);
    public int Rank(int index) => Mode == "include" ? Array.BinarySearch(Indices, index) : index - Indices.Count(value => value < index);
    public static bool Matches(CodexModelSelection? first, CodexModelSelection? second) =>
        first is null ? second is null : second is not null && first.Revision == second.Revision
            && first.Mode == second.Mode && first.Indices.SequenceEqual(second.Indices);
}
internal sealed record SpendQuery(int Days, string? Currency, string Section, string Chart, int Page,
    SpendDetailQuery? Detail = null, bool ComparePeriods = false, int? CodexModelsPage = null,
    CodexModelSelection? CodexModel = null, string? CodexGranularity = null, string? CodexMetric = null,
    int? CodexCatalogPage = null);
internal sealed record SpendExportAction(string Kind, string ExpectedRevision);
public sealed record SpendComparisonRow([property: JsonRequired] int Days, [property: JsonRequired] string Title,
    [property: JsonRequired] string Range, [property: JsonRequired] string Cost, [property: JsonRequired] string Tokens,
    [property: JsonRequired] string Coverage, [property: JsonRequired] string Details);
public sealed record CodexModelRow([property: JsonRequired] string Title,
    [property: JsonRequired] string CurrentTokens, [property: JsonRequired] string PreviousTokens,
    [property: JsonRequired] string TokenChange, [property: JsonRequired] string CurrentCost,
    [property: JsonRequired] string PreviousCost, [property: JsonRequired] string CostChange,
    [property: JsonRequired] string Details, [property: JsonRequired] int SelectionIndex);
public sealed record CodexModelChoice([property: JsonRequired] string Title, [property: JsonRequired] int Index,
    [property: JsonRequired] bool Selected)
{
    [JsonIgnore] public string ActionTitle => Selected ? "Exclude" : "Include";
    [JsonIgnore] public string SelectionLabel => Selected ? "Included" : "Excluded";
}
internal sealed record CodexModelsPage([property: JsonRequired] string Context,
    [property: JsonRequired] string CurrentRange, [property: JsonRequired] string PreviousRange,
    [property: JsonRequired] int Page, [property: JsonRequired] int PageCount,
    [property: JsonRequired] int TotalRows, [property: JsonRequired] CodexModelRow[] Rows,
    [property: JsonRequired] string SelectionRevision, int? SelectedIndex,
    [property: JsonRequired] string SelectedLabel, [property: JsonRequired] string Granularity,
    [property: JsonRequired] string Metric, [property: JsonRequired] string TimelineContext,
    [property: JsonRequired] SpendPoint[] Timeline, CodexModelSelection? ModelSelection,
    [property: JsonRequired] int CatalogPage, [property: JsonRequired] int CatalogPageCount,
    [property: JsonRequired] int CatalogTotal, [property: JsonRequired] CodexModelChoice[] Choices,
    [property: JsonRequired] string ExportRevision)
{
    public bool IsValid => Context is not null && CurrentRange is not null && PreviousRange is not null
        && Page >= 0 && Page < PageCount && TotalRows >= 0
        && PageCount == Math.Max(1L, (TotalRows + 39L) / 40)
        && Rows is { Length: <= 40 } && Rows.Length == Math.Min(40L, TotalRows - Page * 40L)
        && Rows.All(row => row is not null && row.Title is not null && row.CurrentTokens is not null
            && row.PreviousTokens is not null && row.TokenChange is not null && row.CurrentCost is not null
            && row.PreviousCost is not null && row.CostChange is not null && row.Details is not null
            && row.SelectionIndex is >= 0 and <= 1000000)
        && SelectionRevision is { Length: 64 }
        && SelectionRevision.All(value => value is >= '0' and <= '9' or >= 'a' and <= 'f')
        && ExportRevision is { Length: 64 }
        && ExportRevision.All(value => value is >= '0' and <= '9' or >= 'a' and <= 'f')
        && CatalogTotal is >= 0 and <= 1000001 && CatalogPage >= 0 && CatalogPage < CatalogPageCount
        && CatalogPageCount == Math.Max(1L, (CatalogTotal + 39L) / 40)
        && (ModelSelection is null || ModelSelection.IsValid && ModelSelection.Revision == SelectionRevision
            && ModelSelection.Indices.All(index => index < CatalogTotal))
        && TotalRows == (ModelSelection is null ? CatalogTotal : ModelSelection.Mode == "include"
            ? ModelSelection.Indices.Length : CatalogTotal - ModelSelection.Indices.Length)
        && SelectedIndex == (ModelSelection is not null && TotalRows == 1 ? Rows.FirstOrDefault()?.SelectionIndex : null)
        && Rows.Select((row, index) => row.SelectionIndex < CatalogTotal
            && (ModelSelection?.Includes(row.SelectionIndex) ?? true)
            && (ModelSelection?.Rank(row.SelectionIndex) ?? row.SelectionIndex) == Page * 40 + index).All(value => value)
        && Choices is { Length: <= 40 } && Choices.Length == Math.Min(40L, CatalogTotal - CatalogPage * 40L)
        && Choices.Select((choice, index) => choice is not null && choice.Title is not null
            && choice.Index == CatalogPage * 40 + index && choice.Selected == (ModelSelection?.Includes(choice.Index) ?? true)).All(value => value)
        && SelectedLabel is not null && TimelineContext is not null
        && (Granularity is "daily" or "weekly" or "monthly")
        && (Metric is "tokens" or "cost" or "sessionReferences") && SpendPage.ValidPoints(Timeline);
}
public sealed record SpendRow([property: JsonRequired] string Title, [property: JsonRequired] string Subtitle,
    [property: JsonRequired] string Cost, [property: JsonRequired] string Tokens, [property: JsonRequired] string Details,
    int? SelectionIndex = null)
{
    [JsonIgnore] public Microsoft.UI.Xaml.Visibility DetailVisibility =>
        SelectionIndex is null ? Microsoft.UI.Xaml.Visibility.Collapsed : Microsoft.UI.Xaml.Visibility.Visible;
}
public sealed record SpendPoint([property: JsonRequired] string Label, [property: JsonRequired] string Detail,
    double? Value, [property: JsonRequired] int Level, [property: JsonRequired] int Row, [property: JsonRequired] int Column,
    string? DayKey = null);
internal sealed record SpendDetailPage([property: JsonRequired] string Kind, [property: JsonRequired] string Title,
    [property: JsonRequired] string Context, [property: JsonRequired] int Page, [property: JsonRequired] int PageCount,
    [property: JsonRequired] int TotalRows, [property: JsonRequired] SpendRow[] Rows, [property: JsonRequired] SpendPoint[] Points)
{
    public bool IsValid => (Kind is "project" or "session" or "hourly") && Title is not null && Context is not null
        && Page >= 0 && PageCount > Page && TotalRows >= 0 && SpendPage.ValidRows(Rows) && SpendPage.ValidPoints(Points);
}
internal sealed record SpendPage([property: JsonRequired] int Days, [property: JsonRequired] string[] Currencies,
    string? Currency, [property: JsonRequired] string Section, [property: JsonRequired] string Chart,
    [property: JsonRequired] int Page, [property: JsonRequired] int PageCount, [property: JsonRequired] int TotalRows,
    [property: JsonRequired] string TotalCost, [property: JsonRequired] string TotalTokens,
    [property: JsonRequired] string Context, [property: JsonRequired] bool Stale, [property: JsonRequired] bool Partial,
    [property: JsonRequired] bool Truncated, [property: JsonRequired] SpendRow[] Rows, [property: JsonRequired] SpendPoint[] Points,
    [property: JsonRequired] string SelectionRevision, SpendDetailPage? Detail, SpendComparisonRow[]? Comparisons,
    CodexModelsPage? CodexModels)
{
    public bool IsValid => Days is >= 1 and <= 365 && Page >= 0 && PageCount >= 1 && Page < PageCount && TotalRows >= 0
        && Currencies is { Length: <= 256 } && Currencies.All(code => code is { Length: 3 }
            && code.All(character => character is >= 'A' and <= 'Z'))
        && (Currency is null || Currencies.Contains(Currency))
        && (Section is "providers" or "models" or "projects" or "sessions")
        && (Chart is "cost" or "tokens") && TotalCost is not null && TotalTokens is not null && Context is not null
        && SelectionRevision is { Length: 64 }
        && SelectionRevision.All(character => character is >= '0' and <= '9' or >= 'a' and <= 'f')
        && ValidRows(Rows) && ValidPoints(Points) && (Detail is null || Detail.IsValid)
        && (CodexModels is null || CodexModels.IsValid)
        && (Comparisons is null || (Comparisons.Length == 4 && Comparisons.All(row => row is not null
            && row.Title is not null && row.Range is not null && row.Cost is not null && row.Tokens is not null
            && row.Coverage is not null && row.Details is not null)
            && Comparisons.Select(row => row.Days).SequenceEqual(new[] { 7, 30, 90, 365 })));

    internal static bool ValidRows(SpendRow[]? rows) => rows is { Length: <= 40 } && rows.All(row =>
        row is not null && row.Title is not null && row.Subtitle is not null && row.Cost is not null
        && row.Tokens is not null && row.Details is not null && (row.SelectionIndex is null || row.SelectionIndex >= 0));

    internal static bool ValidPoints(SpendPoint[]? points) => points is { Length: <= 365 } && points.All(point => point is not null && point.Label is not null
            && point.Detail is not null && point.Level is >= 0 and <= 6 && point.Row is >= 0 and <= 6
            && point.Column is >= 0 and < 365 && (point.Value is null || (double.IsFinite(point.Value.Value) && point.Value >= 0))
            && (point.DayKey is null || DateOnly.TryParseExact(point.DayKey, "yyyy-MM-dd",
                System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out _)));
}
