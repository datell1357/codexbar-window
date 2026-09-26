using System.Text.Json.Serialization;

namespace CodexBar.App;

internal sealed record SpendQuery(int Days, string? Currency, string Section, string Chart, int Page);
public sealed record SpendRow([property: JsonRequired] string Title, [property: JsonRequired] string Subtitle,
    [property: JsonRequired] string Cost, [property: JsonRequired] string Tokens, [property: JsonRequired] string Details);
public sealed record SpendPoint([property: JsonRequired] string Label, [property: JsonRequired] string Detail,
    double? Value, [property: JsonRequired] int Level, [property: JsonRequired] int Row, [property: JsonRequired] int Column);
internal sealed record SpendPage([property: JsonRequired] int Days, [property: JsonRequired] string[] Currencies,
    string? Currency, [property: JsonRequired] string Section, [property: JsonRequired] string Chart,
    [property: JsonRequired] int Page, [property: JsonRequired] int PageCount, [property: JsonRequired] int TotalRows,
    [property: JsonRequired] string TotalCost, [property: JsonRequired] string TotalTokens,
    [property: JsonRequired] string Context, [property: JsonRequired] bool Stale, [property: JsonRequired] bool Partial,
    [property: JsonRequired] bool Truncated, [property: JsonRequired] SpendRow[] Rows, [property: JsonRequired] SpendPoint[] Points)
{
    public bool IsValid => Days is >= 1 and <= 365 && Page >= 0 && PageCount >= 1 && Page < PageCount && TotalRows >= 0
        && Currencies is { Length: <= 256 } && Currencies.All(code => code is { Length: 3 }
            && code.All(character => character is >= 'A' and <= 'Z'))
        && (Currency is null || Currencies.Contains(Currency))
        && (Section is "providers" or "models" or "projects" or "sessions")
        && (Chart is "cost" or "tokens") && TotalCost is not null && TotalTokens is not null && Context is not null
        && Rows is { Length: <= 40 } && Rows.All(row => row is not null && row.Title is not null
            && row.Subtitle is not null && row.Cost is not null && row.Tokens is not null && row.Details is not null)
        && Points is { Length: <= 365 } && Points.All(point => point is not null && point.Label is not null
            && point.Detail is not null && point.Level is >= 0 and <= 6 && point.Row is >= 0 and <= 6
            && point.Column is >= 0 and < 365 && (point.Value is null || (double.IsFinite(point.Value.Value) && point.Value >= 0)));
}
