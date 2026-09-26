using System.Text.Json.Serialization;

namespace CodexBar.App;

internal sealed record AppViewPreferences([property: JsonRequired] int SchemaVersion,
    [property: JsonRequired] string Navigation, [property: JsonRequired] int Days, string? Currency,
    [property: JsonRequired] string Section, [property: JsonRequired] string Chart,
    [property: JsonRequired] bool ComparePeriods, string? SelectedDay)
{
    public static AppViewPreferences Default => new(1, "overview", 30, null, "providers", "cost", false, null);
    public bool IsValid => SchemaVersion == 1 && (Navigation is "overview" or "spend" or "costSettings" or "settings")
        && (Days is 7 or 30 or 90 or 365) && (Section is "providers" or "models" or "projects" or "sessions")
        && (Chart is "cost" or "tokens") && (Currency is null || (Currency.Length == 3
            && Currency.All(character => character is >= 'A' and <= 'Z')))
        && (SelectedDay is null || (SelectedDay.Length == 10 && DateOnly.TryParseExact(SelectedDay, "yyyy-MM-dd",
            System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out _)));
}
internal sealed record ViewPreferenceMutation(string ExpectedRevision, AppViewPreferences Values);
internal sealed record ViewPreferencesPage([property: JsonRequired] string Status,
    [property: JsonRequired] string Revision, [property: JsonRequired] AppViewPreferences Values)
{
    public bool IsValid => (Status is "ready" or "invalid" or "unsupported" or "readFailed")
        && Revision is { Length: 64 }
        && Revision.All(character => character is >= '0' and <= '9' or >= 'a' and <= 'f')
        && Values is not null && Values.IsValid;
}

/// UI-thread owner of non-secret view choices. Coalesces intentional edits, but never retries an uncertain save.
internal sealed class ViewPreferencesSession
{
    private readonly Func<ViewPreferenceMutation?, CancellationToken, Task<AppResponse>> request;
    private readonly Action<AppViewPreferences> restore;
    private readonly Action<string, bool> status;
    private readonly CancellationToken lifetime;
    private readonly SemaphoreSlim serial = new(1, 1);
    private CancellationTokenSource? debounce;
    private ViewPreferencesPage? baseline;
    private long editVersion;
    private bool dirty;
    private bool blocked = true;
    private bool busy;
    private string message = "Loading saved view choices…";
    public AppViewPreferences Values { get; private set; } = AppViewPreferences.Default;

    public ViewPreferencesSession(Func<ViewPreferenceMutation?, CancellationToken, Task<AppResponse>> request,
        Action<AppViewPreferences> restore, Action<string, bool> status, CancellationToken lifetime)
    {
        this.request = request; this.restore = restore; this.status = status; this.lifetime = lifetime;
    }

    public void Change(AppViewPreferences values)
    {
        if (!values.IsValid || values == Values || lifetime.IsCancellationRequested) return;
        Values = values;
        editVersion++;
        dirty = true;
        if (blocked)
        {
            message = "View choices are kept for this window. Use Retry save to keep them for the next launch.";
            Publish();
            return;
        }
        message = "Saving view choices…";
        Publish();
        Schedule();
    }

    public async Task LoadAsync(bool retrySave = false)
    {
        CancelDebounce();
        try { await serial.WaitAsync(lifetime); }
        catch (OperationCanceledException) { return; }
        busy = true;
        Publish();
        var version = editVersion;
        var saveAfterLoad = false;
        try
        {
            var response = await request(null, lifetime);
            if (response.Status != "ok" || response.ViewPreferences is not { } page)
                throw new IOException("Missing view preferences.");
            baseline = page;
            if (page.Status != "ready")
            {
                blocked = true;
                message = page.Status == "unsupported"
                    ? "Saved view choices use another version. They have been preserved."
                    : "Saved view choices could not be read. They have been preserved.";
                return;
            }
            blocked = false;
            if (retrySave)
            {
                // Even identical observed values need a fresh persistence attempt after an uncertain flush.
                dirty = true;
                saveAfterLoad = true;
            }
            else if (version == editVersion)
            {
                Values = page.Values;
                dirty = false;
                restore(Values);
                message = "Saved view choices restored.";
            }
            else
            {
                dirty = true; // Keep an explicit edit made while loading; do not replace it with an older view.
                saveAfterLoad = true;
            }
        }
        catch (Exception error) when (IsConnectionFailure(error))
        {
            blocked = true;
            message = "View choices could not be loaded. Use Retry save or Restore saved view when connected.";
        }
        finally { busy = false; serial.Release(); Publish(); }
        if (saveAfterLoad) await FlushAsync();
    }

    public async Task FlushAsync(CancellationToken cancellation = default)
    {
        CancelDebounce();
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(lifetime, cancellation);
        try { await serial.WaitAsync(linked.Token); }
        catch (OperationCanceledException) { return; }
        busy = true;
        try
        {
            while (dirty && !blocked && baseline is { Status: "ready" } current && !linked.IsCancellationRequested)
            {
                var version = editVersion;
                var captured = Values;
                message = "Saving view choices…";
                Publish();
                var response = await request(new ViewPreferenceMutation(current.Revision, captured), linked.Token);
                if (response.ViewPreferences is { } observed) baseline = observed;
                if (response.Status != "ok" || response.ViewPreferences is not { Status: "ready" } saved
                    || saved.Values != captured)
                {
                    blocked = true;
                    message = response.Status == "settingsChanged"
                        ? "Saved view choices changed elsewhere. Retry save keeps this view; Restore saved view loads the stored choices."
                        : "Saving view choices could not be confirmed. Use Retry save or Restore saved view.";
                    return;
                }
                dirty = editVersion != version;
                message = dirty ? "Saving newer view choices…" : "View choices saved.";
            }
        }
        catch (Exception error) when (IsConnectionFailure(error))
        {
            blocked = true;
            message = "The save result is unknown. It was not retried. Use Retry save or Restore saved view when connected.";
        }
        finally { busy = false; serial.Release(); Publish(); }
    }

    private void Schedule()
    {
        CancelDebounce();
        debounce = CancellationTokenSource.CreateLinkedTokenSource(lifetime);
        _ = SaveAfterDelayAsync(debounce.Token);
    }
    private async Task SaveAfterDelayAsync(CancellationToken token)
    {
        try { await Task.Delay(TimeSpan.FromMilliseconds(400), token); }
        catch (OperationCanceledException) { return; }
        if (!token.IsCancellationRequested) await FlushAsync();
    }
    private void CancelDebounce()
    {
        debounce?.Cancel();
        debounce?.Dispose();
        debounce = null;
    }
    private void Publish() { if (!lifetime.IsCancellationRequested) status(message, !busy); }
    private static bool IsConnectionFailure(Exception error) =>
        error is IOException or OperationCanceledException or InvalidOperationException
        or System.Text.Json.JsonException or System.ComponentModel.Win32Exception or UnauthorizedAccessException;
}
