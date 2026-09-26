using System.Text.Json.Serialization;

namespace CodexBar.App;

internal sealed record SpendPreferencesQuery(int Page = 0);
internal sealed record SpendPreferenceMutation(string Key, string ExpectedRevision,
    bool? Value = null, string? Currency = null, int? SourceIndex = null);
public sealed record SpendCurrencyChoice(string Code, string Title);
public sealed record SpendSourcePreference([property: JsonRequired] int Index, [property: JsonRequired] string Title,
    [property: JsonRequired] bool Included)
{
    [JsonIgnore] public string State => Included ? "Included" : "Excluded";
    [JsonIgnore] public string ActionTitle => Included ? "Exclude" : "Include";
}
internal sealed record SpendPreferencesPage([property: JsonRequired] string Revision,
    [property: JsonRequired] bool CollectionEnabled, [property: JsonRequired] bool CodexLocalLedgerEnabled,
    [property: JsonRequired] bool OpenCodexUsageLogsEnabled, [property: JsonRequired] bool HideNativeCodexWhenOpenCodexPresent,
    [property: JsonRequired] string PreferredCurrencyCode, [property: JsonRequired] string[] Currencies,
    [property: JsonRequired] bool SourcesAvailable, [property: JsonRequired] int Page,
    [property: JsonRequired] int PageCount, [property: JsonRequired] int TotalSources,
    [property: JsonRequired] SpendSourcePreference[] Sources, [property: JsonRequired] bool Truncated)
{
    public bool IsValid => Revision is { Length: 64 }
        && Revision.All(character => character is >= '0' and <= '9' or >= 'a' and <= 'f')
        && CurrencyCode(PreferredCurrencyCode) && Currencies is { Length: > 0 and <= 256 }
        && Currencies.All(CurrencyCode) && Currencies.Distinct().Count() == Currencies.Length
        && TotalSources is >= 0 and <= 4096 && PageCount == Math.Max(1, (TotalSources + 39) / 40)
        && Page >= 0 && Page < PageCount && Sources is { Length: <= 40 }
        && Sources.Length == Math.Min(40, TotalSources - Page * 40)
        && Sources.Select((row, index) => row is not null && row.Index == Page * 40 + index
            && row.Title is not null).All(valid => valid)
        && (SourcesAvailable ? TotalSources > 0 : TotalSources == 0);

    private static bool CurrencyCode(string? code) => code == "auto"
        || (code is { Length: 3 } && code.All(character => character is >= 'A' and <= 'Z'));
}
