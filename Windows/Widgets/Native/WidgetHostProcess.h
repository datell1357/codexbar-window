#pragma once
#include "WidgetComSecurity.h"
#include "WidgetHostCancellation.h"
#include "WidgetCallerAuthenticator.h"
#include "WidgetCallerDiscovery.h"
#include "WidgetBootstrappedHost.h"
#include <optional>

namespace CodexBar::Widgets {
struct WidgetHostProcessResult {
    HRESULT startup = S_OK;
    std::optional<WidgetHostSessionResult> session;

    // Use only after Run returns. Preserve detailed fields for diagnostics; this is the exit decision.
    HRESULT CompletionStatus() const noexcept {
        if (FAILED(startup)) return startup;
        if (!session) return E_UNEXPECTED;
        auto const& value = *session;
        // Cleanup failures require attention even if the operation also failed.
        HRESULT failures[]{value.registrationCleanup, value.receiverCleanup,
            value.worker.producerShutdown, value.worker.withdrawal,
            value.operation, value.worker.operation, value.receiver.error};
        for (auto failure : failures) if (FAILED(failure)) return failure;
        using Phase = WidgetInvalidationReceiver::Status::Phase;
        switch (value.receiver.phase) {
        case Phase::Cancelled:
            return S_OK;
        case Phase::BackendExited:
            return HRESULT_FROM_WIN32(ERROR_BROKEN_PIPE);
        case Phase::Created:
        case Phase::Running:
        case Phase::Failed:
        default:
            return E_UNEXPECTED;
        }
    }
};

// One invocation per dedicated host process, on its main/non-UI thread. Reconnect launches a new process.
// Caller must authenticate bootstrap delivery BEFORE calling and provide an independently trusted backend.
// The authenticated channel transfers its already-owned event via std::move; every exit closes it.
// Never construct that owner solely from untrusted JSON or close the source after transferring it.
inline WidgetHostProcessResult RunWidgetHostProcess(
    std::string_view authenticatedBootstrap, winrt::handle transferredEvent,
    HANDLE trustedBackendProcess, std::wstring const& installedBackendImage,
    std::function<void()> authenticateCaller, WidgetHostWorker::Report report,
    std::function<void(std::function<void()>)> publishCancellation,
    std::function<void()> validateStartup = {}) {
    WidgetHostProcessResult result;
    if (!authenticateCaller || !report || !publishCancellation) {
        result.startup = E_INVALIDARG;
        return result;
    }
    struct Apartment {
        Apartment() { winrt::init_apartment(winrt::apartment_type::multi_threaded); }
        ~Apartment() { winrt::uninit_apartment(); }
    };
    try {
        Apartment apartment;
        InitializeWidgetComSecurity();
        if (validateStartup) validateStartup();
        // Destructor ordering keeps the host and its receiver/WinRT objects inside the live apartment.
        WidgetBootstrappedHost host(authenticatedBootstrap, std::move(transferredEvent),
            trustedBackendProcess, installedBackendImage);
        publishCancellation(host.CancellationCallback());
        result.session = host.Run(std::move(authenticateCaller), std::move(report));
    } catch (...) {
        result.startup = winrt::to_hresult();
    }
    // Consumers must inspect startup AND each session cleanup result, not merely session presence.
    return result;
}
// Production entry for an independently established set of Widgets broker process handles.
// The caller must not pass the backend process as a substitute for discovering the actual COM caller.
inline WidgetHostProcessResult RunWidgetHostProcessWithTrustedCallers(
    std::string_view authenticatedBootstrap, winrt::handle transferredEvent,
    HANDLE trustedBackendProcess, std::wstring const& installedBackendImage,
    std::vector<HANDLE> const& trustedWidgetCallers, std::wstring const& installedWidgetPackageFamily,
    WidgetHostWorker::Report report,
    std::function<void(std::function<void()>)> publishCancellation) {
    try {
        auto authenticator = std::make_shared<WidgetCallerAuthenticator>(trustedWidgetCallers);
        return RunWidgetHostProcess(authenticatedBootstrap, std::move(transferredEvent),
            trustedBackendProcess, installedBackendImage,
            [authenticator] { authenticator->Authenticate(); }, std::move(report), std::move(publishCancellation),
            [authenticator, installedWidgetPackageFamily] {
                authenticator->ValidateInstalledPackages(installedWidgetPackageFamily);
            });
    } catch (...) {
        WidgetHostProcessResult result;
        result.startup = winrt::to_hresult();
        return result;
    }
}

// Discover and pin callers after COM initialization; no package/name wildcard fallback is permitted.
inline WidgetHostProcessResult RunWidgetHostProcessWithInstalledCallerPolicy(
    std::string_view authenticatedBootstrap, winrt::handle transferredEvent,
    HANDLE trustedBackendProcess, std::wstring const& installedBackendImage,
    std::wstring const& packageFamily, std::vector<std::wstring> const& executableNames,
    WidgetHostWorker::Report report, std::function<void(std::function<void()>)> publishCancellation) {
    try {
        // Written once before class registration; callbacks only read the fully initialized authenticator.
        auto holder = std::make_shared<std::shared_ptr<WidgetCallerAuthenticator>>();
        return RunWidgetHostProcess(authenticatedBootstrap, std::move(transferredEvent),
            trustedBackendProcess, installedBackendImage,
            [holder] {
                if (!*holder) throw winrt::hresult_access_denied();
                (*holder)->Authenticate();
            }, std::move(report), std::move(publishCancellation),
            [holder, packageFamily, executableNames] {
                auto processes = DiscoverWidgetCallers(packageFamily, executableNames);
                std::vector<HANDLE> borrowed;
                for (auto const& process : processes) borrowed.push_back(process.get());
                *holder = std::make_shared<WidgetCallerAuthenticator>(borrowed);
                (*holder)->ValidateInstalledPackages(packageFamily);
            });
    } catch (...) {
        WidgetHostProcessResult result;
        result.startup = winrt::to_hresult();
        return result;
    }
}

// Launcher-facing overload: Cancel before publication is remembered and delivered during startup.
inline WidgetHostProcessResult RunWidgetHostProcessWithInstalledCallerPolicy(
    std::string_view authenticatedBootstrap, winrt::handle transferredEvent,
    HANDLE trustedBackendProcess, std::wstring const& installedBackendImage,
    std::wstring const& packageFamily, std::vector<std::wstring> const& executableNames,
    WidgetHostWorker::Report report, std::shared_ptr<WidgetHostCancellation> cancellation) {
    if (!cancellation) {
        WidgetHostProcessResult result;
        result.startup = E_INVALIDARG;
        return result;
    }
    struct ReleaseSlot {
        std::shared_ptr<WidgetHostCancellation> value;
        ~ReleaseSlot() { value->Clear(); }
    } release{cancellation};
    return RunWidgetHostProcessWithInstalledCallerPolicy(authenticatedBootstrap, std::move(transferredEvent),
        trustedBackendProcess, installedBackendImage, packageFamily, executableNames, std::move(report),
        [cancellation](std::function<void()> callback) { cancellation->Publish(std::move(callback)); });
}

}
