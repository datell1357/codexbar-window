#pragma once
#include <atomic>
#include <mutex>
#include "WidgetHostWorker.h"
#include <thread>

namespace CodexBar::Widgets {
// Dedicated non-UI receiver thread. Start/StopAndJoin belong to the native host owner; worker outlives this object.
// Both supplied handles are LOCAL handles received from the trusted launcher, never numeric values from a pipe.
// The invalidation event MUST be unnamed, auto-reset, and unique to this host/backend session.
class WidgetInvalidationReceiver final {
public:
    enum class Exit { Cancelled, BackendExited };
    WidgetInvalidationReceiver(WidgetHostWorker& worker, HANDLE invalidationEvent, HANDLE backendProcess)
        : worker_(worker), event_(DuplicateWaitHandle(invalidationEvent)), backend_(DuplicateWaitHandle(backendProcess)),
          cancellation_(CreateEventW(nullptr, TRUE, FALSE, nullptr)) {
        winrt::check_bool(static_cast<bool>(cancellation_));
    }
    struct Status {
        enum class Phase { Created, Running, Cancelled, BackendExited, Failed };
        Phase phase;
        HRESULT error;
    };
    WidgetInvalidationReceiver(WidgetInvalidationReceiver const&) = delete;
    WidgetInvalidationReceiver& operator=(WidgetInvalidationReceiver const&) = delete;
    ~WidgetInvalidationReceiver() {
        // Destruction occurs only on the owner, never on the receiver thread. Explicit StopAndJoin reports errors.
        SetEvent(cancellation_.get());
        if (thread_.joinable()) thread_.join();
    }
    void Start() {
        std::scoped_lock lock(lifecycle_);
        if (started_ || stopped_) throw winrt::hresult_illegal_method_call();
        started_ = true;
        phase_.store(Status::Phase::Running);
        try {
            thread_ = std::thread([this] {
                try {
                    auto exit = Run();
                    phase_.store(exit == Exit::Cancelled ? Status::Phase::Cancelled : Status::Phase::BackendExited);
                } catch (...) {
                    error_.store(winrt::to_hresult());
                    phase_.store(Status::Phase::Failed);
                }
            });
        } catch (...) {
            error_.store(winrt::to_hresult());
            phase_.store(Status::Phase::Failed);
            worker_.Cancel();
            throw;
        }
    }
    Status CurrentStatus() const {
        auto phase = phase_.load();
        return {phase, error_.load()};
    }
    void StopAndJoin() {
        std::scoped_lock lock(lifecycle_);
        stopped_ = true;
        Cancel();
        if (thread_.joinable()) {
            if (thread_.get_id() == std::this_thread::get_id()) throw winrt::hresult_illegal_method_call();
            thread_.join();
        }
    }
    void Cancel() { winrt::check_bool(SetEvent(cancellation_.get())); }
private:
    Exit Run() {
        try {
            // Prioritize shutdown/backend death over changes when multiple handles are signaled.
            HANDLE handles[]{cancellation_.get(), backend_.get(), event_.get()};
            for (;;) {
                auto result = WaitForMultipleObjects(3, handles, FALSE, INFINITE);
                if (result == WAIT_OBJECT_0) return Exit::Cancelled;
                if (result == WAIT_OBJECT_0 + 1) {
                    // The backend cannot acknowledge another card. Cancellation wakes the COM worker,
                    // whose terminal cleanup withdraws retained content even when the pipe is idle.
                    worker_.InvalidateContext();
                    worker_.Cancel();
                    return Exit::BackendExited;
                }
                if (result == WAIT_OBJECT_0 + 2) {
                    worker_.InvalidateContext();
                    continue;
                }
                if (result == WAIT_FAILED) winrt::throw_last_error();
                throw winrt::hresult_error(E_UNEXPECTED);
            }
        } catch (...) {
            worker_.Cancel(); // Receiver failure must not leave an unmonitored provider running.
            throw;
        }
    }
    static winrt::handle DuplicateWaitHandle(HANDLE handle) {
        if (!handle || handle == INVALID_HANDLE_VALUE) throw winrt::hresult_invalid_argument();
        HANDLE duplicate = nullptr;
        winrt::check_bool(DuplicateHandle(GetCurrentProcess(), handle, GetCurrentProcess(), &duplicate,
            SYNCHRONIZE, FALSE, 0));
        return winrt::handle{duplicate};
    }
    WidgetHostWorker& worker_;
    winrt::handle event_;
    winrt::handle backend_;
    winrt::handle cancellation_;
    std::mutex lifecycle_;
    std::thread thread_;
    bool started_ = false;
    bool stopped_ = false;
    std::atomic<Status::Phase> phase_{Status::Phase::Created};
    std::atomic<HRESULT> error_{S_OK};
};
}
