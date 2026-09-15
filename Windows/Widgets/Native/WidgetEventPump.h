#pragma once
#include "WidgetBackendClient.h"
#include "WidgetEventQueue.h"
#include <atomic>

namespace CodexBar::Widgets {
// Run on one COM-initialized worker. The owner holds all collaborators alive until Run returns.
class WidgetEventPump final {
public:
    enum class Exit { Cancelled, BackendRejected };
    using Apply = std::function<void(std::uint64_t, WidgetHostEvent const&, WidgetHostResponse const&)>;
    using CaptureContext = std::function<std::uint64_t()>;
    WidgetEventPump(WidgetEventQueue& queue, WidgetBackendClient& client, CaptureContext capture, Apply apply)
        : queue_(queue), client_(client), apply_(std::move(apply)), capture_(std::move(capture)) {
        if (!apply_ || !capture_) throw winrt::hresult_invalid_argument();
    }
    Exit Run() {
        if (started_.exchange(true)) throw winrt::hresult_illegal_method_call();
        try {
            while (auto event = queue_.WaitNext()) {
                auto generation = capture_();
                auto response = client_.Dispatch(*event);
                apply_(generation, *event, response);
                if (!response.accepted) {
                    // Surface the fixed error through Apply, then reconnect/reconcile. Never silently drop or replay it.
                    Cancel();
                    return Exit::BackendRejected;
                }
            }
            client_.Cancel();
            return Exit::Cancelled;
        } catch (...) {
            Cancel();
            throw;
        }
    }
    void Cancel() {
        queue_.Cancel();
        client_.Cancel();
    }
private:
    WidgetEventQueue& queue_;
    WidgetBackendClient& client_;
    Apply apply_;
    CaptureContext capture_;
    std::atomic_bool started_{false};
};
}
