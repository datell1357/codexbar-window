using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CodexBar.App;

public sealed partial class MainWindow : Window
{
    private readonly BackendChannel? channel;
    private readonly CancellationTokenSource lifetime = new();
    private AppSnapshot? snapshot;
    private ulong activation;
    private bool applying;
    private bool saving;
    private string? actionNotice;

    internal MainWindow(BackendChannel? channel)
    {
        this.channel = channel;
        InitializeComponent();
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1040, 760));
        Closed += (_, _) => { lifetime.Cancel(); channel?.Dispose(); };
        if (channel is null)
        {
            StatusText.Text = "Open CodexBar from its tray menu.";
            Notice.Message = "The running CodexBar tray connects this window to your usage and settings.";
            Notice.IsOpen = true;
        }
        else
        {
            SpendView.Configure((query, token) => channel.SendAsync("spend", null, token, query), lifetime.Token);
            _ = PollAsync();
        }
    }

    private async Task PollAsync()
    {
        while (!lifetime.IsCancellationRequested)
        {
            try
            {
                if (channel!.BackendExited) { Close(); return; }
                if (!saving) await SendAsync("snapshot");
                if (!saving && snapshot is not null && SpendPage.Visibility == Visibility.Visible)
                    await SpendView.RefreshAsync();
                await Task.Delay(TimeSpan.FromSeconds(2), lifetime.Token);
            }
            catch (OperationCanceledException) when (lifetime.IsCancellationRequested) { return; }
        }
    }

    private async Task SendAsync(string method, SettingMutation? mutation = null)
    {
        if (channel is null || lifetime.IsCancellationRequested) return;
        try
        {
            var result = await channel.SendAsync(method, mutation, lifetime.Token);
            if (lifetime.IsCancellationRequested) return;
            if (result.Status == "stopped") { Close(); return; }
            if (result.Status == "ok" && method != "snapshot") actionNotice = null;
            if (result.Status != "ok")
            {
                actionNotice = result.Status switch
                {
                    "settingsChanged" => "Settings changed elsewhere. Review the current values and try again.",
                    "settingsSaveFailed" => "CodexBar could not save this setting. Check the displayed value before trying again.",
                    "unsupportedVersion" => "The app and tray versions do not match. Install them from the same release.",
                    _ => "CodexBar could not complete the request. Reopen the window and try again."
                };
            }
            if (result.Snapshot is { } current) Apply(current);
            else
            {
                ClearSnapshot();
                if (actionNotice is not null) { Notice.Message = actionNotice; Notice.IsOpen = true; }
            }
            if (result.Activation != activation)
            {
                activation = result.Activation;
                Activate();
            }
        }
        catch (Exception error) when (error is IOException or OperationCanceledException
            or System.Text.Json.JsonException or InvalidOperationException or UnauthorizedAccessException
            or System.ComponentModel.Win32Exception)
        {
            if (lifetime.IsCancellationRequested) return;
            StatusText.Text = "Connection interrupted. Reconnecting…";
            // Withdraw stale data, particularly after a privacy-setting mutation with an uncertain reply.
            ClearSnapshot();
            Notice.Message = method == "setSetting"
                ? "The save result is unknown. Current settings will reload after reconnection."
                : "Usage will return when the tray connection is restored.";
            if (method == "setSetting") actionNotice = Notice.Message;
            Notice.IsOpen = true;
        }
    }

    private void ClearSnapshot()
    {
        RefreshButton.IsEnabled = false;
        SettingsControls.IsEnabled = false;
        snapshot = null;
        ProviderList.ItemsSource = null;
        SpendView.Invalidate();
    }

    private void Apply(AppSnapshot value)
    {
        if (snapshot?.Settings.HidePersonalInfo != value.Settings.HidePersonalInfo) SpendView.Invalidate();
        snapshot = value;
        applying = true;
        try
        {
            PrivacyToggle.IsOn = value.Settings.HidePersonalInfo;
            OptionalToggle.IsOn = value.Settings.ShowOptionalCreditsAndExtraUsage;
            UsedToggle.IsOn = value.Settings.UsageBarsShowUsed;
            ResetToggle.IsOn = value.Settings.ResetTimesShowAbsolute;
        }
        finally { applying = false; }
        StatusText.Text = value.Refreshing ? "Updating usage…" :
            value.Providers.Length == 0 ? "No usage available. Enable providers from the tray." : "Connected to CodexBar";
        RefreshButton.IsEnabled = !value.Refreshing && !saving;
        SettingsControls.IsEnabled = !saving;
        Notice.Message = string.Join(Environment.NewLine, value.Notices);
        if (value.Truncated) Notice.Message += Environment.NewLine + "Some details are available from the tray.";
        if (actionNotice is not null) Notice.Message = actionNotice + Environment.NewLine + Notice.Message;
        Notice.IsOpen = value.Notices.Length > 0 || value.Truncated || actionNotice is not null;
        Filter();
    }

    private async void Refresh(object sender, RoutedEventArgs args)
    {
        RefreshButton.IsEnabled = false;
        await SendAsync("refresh");
    }

    private async void SettingChanged(object sender, RoutedEventArgs args)
    {
        if (applying || saving || snapshot is null || sender is not ToggleSwitch toggle || toggle.Tag is not string key) return;
        saving = true;
        SpendView.Invalidate();
        SettingsControls.IsEnabled = false;
        RefreshButton.IsEnabled = false;
        if (key == "hidePersonalInfo" && toggle.IsOn)
        {
            ProviderList.ItemsSource = null;
        }
        try { await SendAsync("setSetting", new SettingMutation(key, toggle.IsOn, snapshot.SettingsRevision)); }
        finally
        {
            saving = false;
            if (snapshot is not null)
            {
                SettingsControls.IsEnabled = true;
                RefreshButton.IsEnabled = !snapshot.Refreshing;
            }
        }
    }

    private void Search(object sender, TextChangedEventArgs args) => Filter();
    private void Filter()
    {
        if (ProviderList is null || SearchBox is null) return;
        var query = SearchBox.Text.Trim();
        ProviderList.ItemsSource = snapshot?.Providers.Where(card =>
            query.Length == 0 || card.Title.Contains(query, StringComparison.CurrentCultureIgnoreCase)).ToArray();
    }

    private void Navigate(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (OverviewPage is null || SpendPage is null || SettingsPage is null) return;
        var tag = (args.SelectedItem as NavigationViewItem)?.Tag as string ?? "overview";
        OverviewPage.Visibility = tag == "overview" ? Visibility.Visible : Visibility.Collapsed;
        SpendPage.Visibility = tag == "spend" ? Visibility.Visible : Visibility.Collapsed;
        SpendView.SetActive(tag == "spend");
        SettingsPage.Visibility = tag == "settings" ? Visibility.Visible : Visibility.Collapsed;
    }
}
