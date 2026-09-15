#pragma once
#include "WidgetBootstrap.h"
#include "WidgetPipeConnector.h"
#include "WidgetHostSessionRunner.h"

namespace CodexBar::Widgets {
// Construct ONLY after the private launcher channel authenticates delivery and transfers event ownership.
// Backend process/image trust comes independently from the launcher, never from the bootstrap JSON.
// InitializeWidgetComSecurity must already have succeeded in this dedicated host process.
// Construct/Run/destruct on the native MTA owner; other threads may call Cancel while ownership is retained.
class WidgetBootstrappedHost final {
public:
    WidgetBootstrappedHost(std::string_view authenticatedBootstrap, winrt::handle transferredEvent,
                          HANDLE trustedBackendProcess,
                          std::wstring const& installedBackendImage)
        : event_(std::move(transferredEvent)),
          bootstrap_(DecodeOwnedBootstrap(authenticatedBootstrap, event_.get())),
          backend_(RetainBackend(trustedBackendProcess)), queue_(std::make_shared<WidgetEventQueue>()),
          pipe_(ConnectWidgetBackend(bootstrap_.pipeName, backend_.get(), installedBackendImage)) {
        // The bootstrap event is now owned locally. Receiver makes its own wait-only duplicate during Run.
        // If connection/retention fails after adoption, member destruction closes this transferred handle.
    }
    WidgetBootstrappedHost(WidgetBootstrappedHost const&) = delete;
    WidgetBootstrappedHost& operator=(WidgetBootstrappedHost const&) = delete;
    ~WidgetBootstrappedHost() { Cancel(); } // Caller must have joined Run before destruction.

    WidgetHostSessionResult Run(std::function<void()> authenticateCaller, WidgetHostWorker::Report report) {
        if (started_.exchange(true) || cancelled_->load()) throw winrt::hresult_illegal_method_call();
        try {
            auto result = RunWidgetHostSession(queue_, pipe_, bootstrap_.sessionId, event_.get(), backend_.get(),
                std::move(authenticateCaller), std::move(report));
            Cancel();
            return result;
        } catch (...) {
            Cancel();
            throw;
        }
    }
    // External owners may retain the callback beyond host shutdown without retaining pipe handles.
    // Lock all three weak references for each invocation so an in-flight cancellation remains safe.
    std::function<void()> CancellationCallback() const {
        return [weakQueue = std::weak_ptr<WidgetEventQueue>(queue_),
                weakPipe = std::weak_ptr<WidgetPipeExchange>(pipe_),
                weakCancelled = std::weak_ptr<std::atomic_bool>(cancelled_)] {
            auto cancelled = weakCancelled.lock();
            auto queue = weakQueue.lock();
            auto pipe = weakPipe.lock();
            if (!cancelled || !queue || !pipe) return;
            cancelled->store(true);
            queue->Cancel();
            pipe->Cancel();
        };
    }
    void Cancel() {
        cancelled_->store(true);
        queue_->Cancel();
        pipe_->Cancel();
    }
private:
    static WidgetBootstrap DecodeOwnedBootstrap(std::string_view bytes, HANDLE event) {
        if (!event || event == INVALID_HANDLE_VALUE) throw winrt::hresult_invalid_argument();
        auto bootstrap = DecodeWidgetBootstrap(bytes);
        // Ownership comes from the authenticated channel, never from a number in JSON.
        if (bootstrap.invalidationHandle != reinterpret_cast<std::uintptr_t>(event)) {
            throw winrt::hresult_access_denied();
        }
        return bootstrap;
    }
    static winrt::handle RetainBackend(HANDLE process) {
        if (!process || process == INVALID_HANDLE_VALUE) throw winrt::hresult_invalid_argument();
        HANDLE retained = nullptr;
        winrt::check_bool(DuplicateHandle(GetCurrentProcess(), process, GetCurrentProcess(), &retained,
            PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, 0));
        return winrt::handle{retained};
    }
    winrt::handle event_; // Adopt first so decode and all later initialization failures close it.
    WidgetBootstrap bootstrap_;
    winrt::handle backend_;
    std::shared_ptr<WidgetEventQueue> queue_;
    std::shared_ptr<WidgetPipeExchange> pipe_;
    std::atomic_bool started_{false};
    std::shared_ptr<std::atomic_bool> cancelled_ = std::make_shared<std::atomic_bool>(false);
};
}
