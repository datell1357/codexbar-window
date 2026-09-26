using System.Text.Json.Serialization;

namespace CodexBar.App;

internal sealed record SpendDetailQuery(string Kind, int? Index, string? Day, string Revision, int Page = 0);
internal sealed record SpendQuery(int Days, string? Currency, string Section, string Chart, int Page,
    SpendDetailQuery? Detail = null, bool ComparePeriods = false);
internal sealed record SpendExportAction(string Kind, string ExpectedRevision);
public sealed record SpendComparisonRow([property: JsonRequired] int Days, [property: JsonRequired] string Title,
    [property: JsonRequired] string Range, [property: JsonRequired] string Cost, [property: JsonRequired] string Tokens,
    [property: JsonRequired] string Coverage, [property: JsonRequired] string Details);
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
    [property: JsonRequired] string SelectionRevision, SpendDetailPage? Detail, SpendComparisonRow[]? Comparisons)
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
