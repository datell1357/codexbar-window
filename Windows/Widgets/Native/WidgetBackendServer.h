#pragma once
#include "WidgetPipeExchange.h"
#include <memory>

namespace CodexBar::Widgets {
// Runs on a dedicated COM-initialized worker, never on Swift's cooperative executor or a UI callback thread.
// Owner cancels the Swift session as well as this I/O object, then joins the worker before destruction.
class WidgetBackendServer final {
public:
    using Handler = std::function<std::string(std::string_view)>;
    WidgetBackendServer(std::shared_ptr<WidgetPipeExchange> pipe, Handler handler)
        : pipe_(std::move(pipe)), handler_(std::move(handler)) {
        if (!pipe_ || !handler_) throw winrt::hresult_invalid_argument();
    }
    void Run() {
        if (started_.exchange(true)) throw winrt::hresult_illegal_method_call();
        try {
            while (!cancelled_.load()) pipe_->ReceiveAndReply(handler_);
        } catch (...) {
            pipe_->Cancel();
            throw;
        }
    }
    void Cancel() noexcept {
        cancelled_.store(true);
        pipe_->Cancel();
    }
private:
    std::shared_ptr<WidgetPipeExchange> pipe_;
    Handler handler_;
    std::atomic_bool started_{false};
    std::atomic_bool cancelled_{false};
};
}
