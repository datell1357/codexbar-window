using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CodexBar.App;

public sealed partial class SpendPreferencesPane : UserControl
{
    private Func<SpendPreferencesQuery, CancellationToken, Task<AppResponse>>? read;
    private Func<SpendPreferencesQuery, SpendPreferenceMutation, CancellationToken, Task<AppResponse>>? write;
    private Action<bool>? savingChanged;
    private CancellationToken lifetime;
    private SpendPreferencesPage? current;
    private int page;
    private int epoch;
    private bool active;
    private bool applying;
    private bool loading;
    private bool saving;
    private bool externalBusy;
    private bool pending;
    private string? notice;

    public SpendPreferencesPane() { InitializeComponent(); }

    internal void Configure(Func<SpendPreferencesQuery, CancellationToken, Task<AppResponse>> read,
        Func<SpendPreferencesQuery, SpendPreferenceMutation, CancellationToken, Task<AppResponse>> write,
        Action<bool> savingChanged, CancellationToken lifetime)
    {
        this.read = read; this.write = write; this.savingChanged = savingChanged; this.lifetime = lifetime;
    }

    internal void SetActive(bool value)
    {
        active = value;
        if (value) _ = RefreshAsync();
        else Invalidate();
    }

    internal void SetExternalBusy(bool value)
    {
        externalBusy = value;
        SettingsControls.IsEnabled = !value && !saving && current is not null;
        if (!value && active) _ = RefreshAsync();
    }

    internal void Invalidate()
    {
        epoch++;
        current = null;
        SettingsControls.IsEnabled = false;
        SourceList.ItemsSource = null;
        SourceStatus.Text = PagePosition.Text = "";
        StatusText.Text = "Waiting for current settings…";
    }

    internal async Task RefreshAsync()
    {
        if (read is null || !active || lifetime.IsCancellationRequested || saving || externalBusy) return;
        if (loading) { pending = true; return; }
        loading = true;
        pending = false;
        var capturedEpoch = epoch;
        try
        {
            var response = await read(new SpendPreferencesQuery(page), lifetime);
            if (lifetime.IsCancellationRequested || capturedEpoch != epoch) return;
            if (response.Status != "ok" || response.SpendPreferences is not { } value)
                throw new IOException("Cost preferences are unavailable.");
            Apply(value);
        }
        catch (Exception error) when (TransportError(error))
        {
            if (lifetime.IsCancellationRequested || capturedEpoch != epoch) return;
            Invalidate();
            StatusText.Text = "Cost settings connection interrupted. Waiting to reconnect…";
        }
        finally
        {
            loading = false;
            if (pending && !lifetime.IsCancellationRequested) { pending = false; _ = RefreshAsync(); }
        }
    }

    private void Apply(SpendPreferencesPage value)
    {
        var rowsChanged = current is null || !current.Sources.SequenceEqual(value.Sources);
        current = value;
        page = value.Page;
        applying = true;
        try
        {
            CollectionToggle.IsOn = value.CollectionEnabled;
            LedgerToggle.IsOn = value.CodexLocalLedgerEnabled;
            OpenCodexToggle.IsOn = value.OpenCodexUsageLogsEnabled;
            HideNativeToggle.IsOn = value.HideNativeCodexWhenOpenCodexPresent;
            var codes = value.Currencies.Contains(value.PreferredCurrencyCode) ? value.Currencies
                : value.Currencies.Append(value.PreferredCurrencyCode).ToArray();
            if (CurrencyPicker.ItemsSource is not SpendCurrencyChoice[] existing
                || !existing.Select(choice => choice.Code).SequenceEqual(codes))
                CurrencyPicker.ItemsSource = codes.Select(code => new SpendCurrencyChoice(code,
                    code == "auto" ? "Original currencies" : code)).ToArray();
            CurrencyPicker.SelectedItem = ((SpendCurrencyChoice[])CurrencyPicker.ItemsSource)
                .First(choice => choice.Code == value.PreferredCurrencyCode);
            if (rowsChanged) SourceList.ItemsSource = value.Sources;
        }
        finally { applying = false; }
        SettingsControls.IsEnabled = !saving && !externalBusy;
        IncludeAllButton.IsEnabled = ExcludeAllButton.IsEnabled = value.SourcesAvailable;
        PreviousPageButton.IsEnabled = value.Page > 0;
        NextPageButton.IsEnabled = value.Page + 1 < value.PageCount;
        PagePosition.Text = value.SourcesAvailable ? $"Page {value.Page + 1} / {value.PageCount}" : "";
        SourceStatus.Text = value.SourcesAvailable
            ? $"{value.TotalSources} available source(s). Include/exclude all applies to every page. Sources missing from this collection keep their saved preference."
            : "Source selection is available after a current cost collection completes. General cost settings remain available.";
        StatusText.Text = value.Truncated ? "Current cost settings · some source names were shortened" : "Current cost settings";
        Notice.Message = notice ?? "";
        Notice.IsOpen = notice is not null;
    }

    private async Task SaveAsync(SpendPreferenceMutation mutation)
    {
        if (write is null || saving || externalBusy || current is null || lifetime.IsCancellationRequested) return;
        saving = true;
        savingChanged?.Invoke(true);
        Invalidate();
        var capturedEpoch = epoch;
        StatusText.Text = "Saving cost preference…";
        try
        {
            var response = await write(new SpendPreferencesQuery(page), mutation, lifetime);
            if (lifetime.IsCancellationRequested) return;
            notice = response.Status switch
            {
                "ok" => null,
                "settingsChanged" => "Settings or cost sources changed elsewhere. Review the current values before trying again.",
                "settingsSaveFailed" => "The save could not be confirmed. Review the reloaded setting before trying again.",
                _ => "The preference could not be saved. Review the current values before trying again."
            };
            if (capturedEpoch == epoch && active && response.SpendPreferences is { } value) Apply(value);
        }
        catch (Exception error) when (TransportError(error))
        {
            if (lifetime.IsCancellationRequested) return;
            notice = "The save result is unknown. Current settings will reload after reconnection. The change will not be sent again automatically.";
            if (capturedEpoch == epoch) Invalidate();
        }
        finally
        {
            saving = false;
            savingChanged?.Invoke(false);
            if (!lifetime.IsCancellationRequested)
            {
                SettingsControls.IsEnabled = !externalBusy && current is not null;
                Notice.Message = notice ?? "";
                Notice.IsOpen = notice is not null;
                await RefreshAsync();
            }
        }
    }

    private async void SettingChanged(object sender, RoutedEventArgs args)
    {
        if (applying || saving || current is null || sender is not ToggleSwitch toggle || toggle.Tag is not string key) return;
        await SaveAsync(new SpendPreferenceMutation(key, current.Revision, Value: toggle.IsOn));
    }
    private async void CurrencyChanged(object sender, SelectionChangedEventArgs args)
    {
        if (applying || saving || current is null || CurrencyPicker.SelectedItem is not SpendCurrencyChoice choice
            || choice.Code == current.PreferredCurrencyCode || !current.Currencies.Contains(choice.Code)) return;
        await SaveAsync(new SpendPreferenceMutation("preferredCurrencyCode", current.Revision, Currency: choice.Code));
    }
    private async void SourceChanged(object sender, RoutedEventArgs args)
    {
        if (saving || current is null || sender is not Button button || button.Tag is not int index) return;
        if (current.Sources.FirstOrDefault(row => row.Index == index) is not { } source) return;
        await SaveAsync(new SpendPreferenceMutation("sourceIncluded", current.Revision, Value: !source.Included, SourceIndex: index));
    }
    private async void IncludeAll(object sender, RoutedEventArgs args)
    {
        if (current is { SourcesAvailable: true } value)
            await SaveAsync(new SpendPreferenceMutation("allSourcesIncluded", value.Revision, Value: true));
    }
    private async void ExcludeAll(object sender, RoutedEventArgs args)
    {
        if (current is { SourcesAvailable: true } value)
            await SaveAsync(new SpendPreferenceMutation("allSourcesIncluded", value.Revision, Value: false));
    }
    private void PreviousPage(object sender, RoutedEventArgs args)
    {
        if (saving || page == 0) return;
        page--; Invalidate(); pending = true; _ = RefreshAsync();
    }
    private void NextPage(object sender, RoutedEventArgs args)
    {
        if (saving || current is null || page + 1 >= current.PageCount) return;
        page++; Invalidate(); pending = true; _ = RefreshAsync();
    }
    private static bool TransportError(Exception error) => error is IOException or OperationCanceledException
        or InvalidOperationException or System.Text.Json.JsonException or System.ComponentModel.Win32Exception or UnauthorizedAccessException;
}
