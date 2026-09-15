#include "WidgetHostProcess.h"
#include "WidgetLaunchChannel.h"
#include <CodexBarWidgetCallerPolicy.h>
#include <shellapi.h>

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    using namespace CodexBar::Widgets;
    try {
        int count = 0;
        auto arguments = CommandLineToArgvW(GetCommandLineW(), &count);
        if (!arguments) winrt::throw_last_error();
        bool privateLaunch = count == 2 && std::wstring_view(arguments[1]) == L"--private-bootstrap";
        LocalFree(arguments);
        if (!privateLaunch) return static_cast<int>(HRESULT_FROM_WIN32(ERROR_INVALID_PARAMETER));
        WidgetLaunchChannel channel;
        auto delivery = channel.ReadDelivery();
        auto cancellation = std::make_shared<WidgetHostCancellation>();
        channel.StartCancellation(cancellation);
        // Run owns COM initialization/security, callback registration and ordered teardown.
        // Policy is generated at build time, never supplied by argv or the bootstrap peer.
        auto result = RunWidgetHostProcessWithInstalledCallerPolicy(delivery.json,
            std::move(delivery.invalidation), channel.Backend(), channel.BackendImage(),
            InstalledCallerPolicy::PackageFamily, InstalledCallerPolicy::ExecutableNames(),
            [](winrt::hstring const&) {
                OutputDebugStringW(L"CodexBar widget operation reported an error.\n");
            }, cancellation);
        channel.StopCancellation();
        auto status = result.CompletionStatus();
        if (SUCCEEDED(status) && FAILED(channel.MonitorStatusAfterJoin())) status = channel.MonitorStatusAfterJoin();
        return static_cast<int>(status);
    } catch (...) {
        // Numeric exit status only; bootstrap data, account values and file paths are not logged.
        return static_cast<int>(winrt::to_hresult());
    }
}
