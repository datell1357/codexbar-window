using System.Text.Json.Serialization;

namespace CodexBar.App;

internal sealed record GeneralPreferenceMutation(string Key, string ExpectedRevision,
    bool? Value = null, string? Choice = null);
internal sealed record GeneralPreferenceValues(
    [property: JsonRequired] string Frequency,
    [property: JsonRequired] string LowPowerMode,
    [property: JsonRequired] bool StatusChecksEnabled,
    [property: JsonRequired] bool RefreshOnMenuOpen)
{
    public bool IsValid => (Frequency is "manual" or "oneMinute" or "twoMinutes" or "fiveMinutes"
        or "fifteenMinutes" or "thirtyMinutes" or "adaptive" or "adaptiveAgentAware")
        && (LowPowerMode is "off" or "on" or "automatic");
}
internal sealed record GeneralPreferencesPage(
    [property: JsonRequired] string Revision,
    [property: JsonRequired] GeneralPreferenceValues Values)
{
    public bool IsValid => Revision is { Length: 64 } && Revision.All(character =>
        character is >= '0' and <= '9' or >= 'a' and <= 'f') && Values is { IsValid: true };
}
