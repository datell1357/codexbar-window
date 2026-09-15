#pragma once
#include <functional>
#include <mutex>
#include <memory>

namespace CodexBar::Widgets {
// One slot per host launch. Cancellation is sticky; never reuse the slot for a reconnect.
class WidgetHostCancellation final {
public:
    void Publish(std::function<void()> callback) {
        auto owned = std::make_shared<std::function<void()>>(std::move(callback));
        bool invoke;
        std::shared_ptr<std::function<void()>> previous;
        {
            std::scoped_lock lock(mutex_);
            previous = std::move(callback_);
            callback_ = owned;
            invoke = cancelled_;
        }
        // Call outside the lock: cancellation may wake a worker that also releases this slot.
        if (invoke && *owned) (*owned)();
    }
    void Cancel() {
        std::shared_ptr<std::function<void()>> callback;
        {
            std::scoped_lock lock(mutex_);
            cancelled_ = true;
            callback = callback_;
        }
        if (callback && *callback) (*callback)();
    }
    void Clear() noexcept {
        std::shared_ptr<std::function<void()>> previous;
        {
            std::scoped_lock lock(mutex_);
            previous = std::move(callback_);
        }
        // Destroy captured state outside the mutex. In-flight callers retain their own reference.
    }
private:
    std::mutex mutex_;
    bool cancelled_ = false;
    std::shared_ptr<std::function<void()>> callback_;
};
}
