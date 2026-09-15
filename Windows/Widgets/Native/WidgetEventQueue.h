#pragma once
#include "WidgetProvider.h"
#include <condition_variable>
#include <chrono>
#include <deque>
#include <mutex>
#include <optional>

namespace CodexBar::Widgets {
// The provider callback enqueues copied values; exactly one host consumer dispatches events in order.
// The owner must Cancel and join that consumer before destroying this queue.
class WidgetEventQueue final {
public:
    void Push(WidgetHostEvent event) {
        std::unique_lock lock(mutex_);
        if (cancelled_) throw winrt::hresult_illegal_method_call();
        if (events_.size() >= 256) throw winrt::hresult_error(HRESULT_FROM_WIN32(ERROR_BUSY));
        events_.push_back(std::move(event));
        lock.unlock();
        changed_.notify_one();
    }
    // Thread-safe, bounded notification for theme/manual refresh. This is not account invalidation.
    // A request made during an active refresh remains pending for a subsequent snapshot.
    void RequestRefresh() {
        {
            std::scoped_lock lock(mutex_);
            if (cancelled_) throw winrt::hresult_illegal_method_call();
            refreshRequested_ = true;
        }
        changed_.notify_one();
    }
    // Call only after the publisher barrier has rejected older generations.
    void RequestWithdrawal() {
        {
            std::scoped_lock lock(mutex_);
            if (cancelled_) throw winrt::hresult_illegal_method_call();
            withdrawalRequested_ = true;
        }
        changed_.notify_one();
    }
    struct Wake {
        enum class Kind { Event, Invalidation, Refresh, Deadline, Cancelled };
        Kind kind;
        std::optional<WidgetHostEvent> event;
    };
    Wake WaitUntil(std::optional<std::chrono::steady_clock::time_point> deadline) {
        std::unique_lock lock(mutex_);
        auto ready = [this] { return cancelled_ || withdrawalRequested_ || !events_.empty() || refreshRequested_; };
        if (deadline) changed_.wait_until(lock, *deadline, ready);
        else changed_.wait(lock, ready);
        if (cancelled_) return {Wake::Kind::Cancelled, std::nullopt};
        // Account withdrawal outranks user actions and timers; never starve it behind callback traffic.
        if (withdrawalRequested_) {
            withdrawalRequested_ = false;
            return {Wake::Kind::Invalidation, std::nullopt};
        }
        // Deliver queued settings/actions before requesting another card snapshot.
        if (!events_.empty()) {
            auto event = std::move(events_.front());
            events_.pop_front();
            return {Wake::Kind::Event, std::move(event)};
        }
        if (refreshRequested_) {
            refreshRequested_ = false;
            return {Wake::Kind::Refresh, std::nullopt};
        }
        return {Wake::Kind::Deadline, std::nullopt};
    }
    std::optional<WidgetHostEvent> WaitNext() {
        // Legacy event-only consumers have no refresh handler; a refresh wake is not shutdown.
        for (;;) {
            auto wake = WaitUntil(std::nullopt);
            if (wake.kind == Wake::Kind::Event) return std::move(wake.event);
            if (wake.kind == Wake::Kind::Cancelled) return std::nullopt;
            if (wake.kind == Wake::Kind::Invalidation) throw winrt::hresult_illegal_method_call();
        }
    }
    // Shutdown discards unprocessed actions; the host separately drains any already executing operation.
    void Cancel() {
        {
            std::scoped_lock lock(mutex_);
            cancelled_ = true;
            events_.clear();
            refreshRequested_ = false;
            withdrawalRequested_ = false;
        }
        changed_.notify_all();
    }
private:
    std::mutex mutex_;
    std::condition_variable changed_;
    std::deque<WidgetHostEvent> events_;
    bool cancelled_ = false;
    bool refreshRequested_ = false;
    bool withdrawalRequested_ = false;
};
}
