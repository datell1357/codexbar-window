using Microsoft.UI.Xaml;

namespace CodexBar.App;

public partial class App : Application
{
    private MainWindow? window;

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        BackendChannel? channel = null;
        try { channel = BackendChannel.FromArguments(Environment.GetCommandLineArgs().Skip(1).ToArray()); }
        catch (Exception error) when (error is ArgumentException or InvalidOperationException
            or IOException or System.ComponentModel.Win32Exception or UnauthorizedAccessException)
        {
            // No command-line content, file paths or runtime exception details enter the view.
        }
        window = new MainWindow(channel);
        window.Activate();
    }
}
