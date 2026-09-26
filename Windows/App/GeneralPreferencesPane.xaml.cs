using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CodexBar.App;

public sealed partial class GeneralPreferencesPane : UserControl
{
    private Func<GeneralPreferenceMutation?, CancellationToken, Task<AppResponse>>? exchange;
    private Action<bool>? savingChanged;
    private CancellationToken lifetime;
    private GeneralPreferencesPage? current;
    private int epoch;
    private bool active;
    private bool applying;
    private bool loading;
    private bool saving;
    private bool externalBusy;
    private bool pending;
    private string? notice;

    public GeneralPreferencesPane() { InitializeComponent(); }

    internal void Configure(Func<GeneralPreferenceMutation?, CancellationToken, Task<AppResponse>> exchange,
        Action<bool> savingChanged, CancellationToken lifetime)
    {
        this.exchange = exchange; this.savingChanged = savingChanged; this.lifetime = lifetime;
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
        if (value) Invalidate();
        else if (active) _ = RefreshAsync();
    }

    internal void Invalidate()
    {
        epoch++;
        current = null;
        SettingsControls.IsEnabled = false;
        StatusText.Text = "Waiting for current settings…";
    }

    internal async Task RefreshAsync()
    {
        if (exchange is null || !active || saving || externalBusy || lifetime.IsCancellationRequested) return;
        if (loading) { pending = true; return; }
        loading = true;
        pending = false;
        var capturedEpoch = epoch;
        try
        {
            var response = await exchange(null, lifetime);
            if (lifetime.IsCancellationRequested || capturedEpoch != epoch) return;
            if (response.Status != "ok" || response.GeneralPreferences is not { } value)
                throw new IOException("General preferences unavailable.");
            Apply(value);
        }
        catch (Exception error) when (TransportError(error))
        {
            if (lifetime.IsCancellationRequested || capturedEpoch != epoch) return;
            Invalidate();
            StatusText.Text = "Settings connection interrupted. Waiting to reconnect…";
        }
        finally
        {
            loading = false;
            if (pending && !lifetime.IsCancellationRequested) { pending = false; _ = RefreshAsync(); }
        }
    }

    private void Apply(GeneralPreferencesPage page)
    {
        current = page;
        applying = true;
        try
        {
            FrequencyPicker.SelectedItem = FrequencyPicker.Items.OfType<ComboBoxItem>()
                .First(item => (string)item.Tag == page.Values.Frequency);
            PowerPicker.SelectedItem = PowerPicker.Items.OfType<ComboBoxItem>()
                .First(item => (string)item.Tag == page.Values.LowPowerMode);
            StatusChecksToggle.IsOn = page.Values.StatusChecksEnabled;
            MenuRefreshToggle.IsOn = page.Values.RefreshOnMenuOpen;
            FrequencyHint.Text = page.Values.Frequency switch
            {
                "manual" => "Scheduled refreshes are off. You can still refresh manually.",
                "adaptiveAgentAware" => "This saved mode is unavailable on Windows. Choose another interval to enable scheduled refreshes.",
                "adaptive" => "Adjusts background refresh timing using menu activity and power conditions.",
                _ => "Changing the interval updates future refreshes. A refresh already in progress can finish."
            };
        }
        finally { applying = false; }
        SettingsControls.IsEnabled = !saving && !externalBusy;
        StatusText.Text = "Current general settings";
        Notice.Message = notice ?? "";
        Notice.IsOpen = notice is not null;
    }

    private async Task SaveAsync(GeneralPreferenceMutation mutation)
    {
        if (exchange is null || !active || saving || externalBusy || current is null || lifetime.IsCancellationRequested) return;
        saving = true;
        savingChanged?.Invoke(true);
        Invalidate();
        var capturedEpoch = epoch;
        StatusText.Text = "Saving preference…";
        try
        {
            var response = await exchange(mutation, lifetime);
            if (lifetime.IsCancellationRequested) return;
            notice = response.Status switch
            {
                "ok" => null,
                "settingsChanged" => "Settings changed elsewhere. Review the current values before trying again.",
                "settingsSaveFailed" => "The save could not be confirmed. Review the reloaded value before trying again.",
                _ => "The preference could not be saved. Review the current values before trying again."
            };
            if (capturedEpoch == epoch && active && response.GeneralPreferences is { } value) Apply(value);
        }
        catch (Exception error) when (TransportError(error))
        {
            if (lifetime.IsCancellationRequested) return;
            notice = "The save result is unknown. Settings will reload after reconnection. The change will not be sent again automatically.";
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
        if (applying || saving || externalBusy || current is null || sender is not ToggleSwitch toggle
            || toggle.Tag is not string key) return;
        await SaveAsync(new GeneralPreferenceMutation(key, current.Revision, Value: toggle.IsOn));
    }

    private async void ChoiceChanged(object sender, SelectionChangedEventArgs args)
    {
        if (applying || saving || externalBusy || current is null || sender is not ComboBox picker
            || picker.Tag is not string key || picker.SelectedItem is not ComboBoxItem item
            || !item.IsEnabled || item.Tag is not string choice) return;
        var previous = key == "frequency" ? current.Values.Frequency : current.Values.LowPowerMode;
        if (previous == choice) return;
        await SaveAsync(new GeneralPreferenceMutation(key, current.Revision, Choice: choice));
    }

    private static bool TransportError(Exception error) => error is IOException or OperationCanceledException
        or InvalidOperationException or System.Text.Json.JsonException or System.ComponentModel.Win32Exception
        or UnauthorizedAccessException;
}
