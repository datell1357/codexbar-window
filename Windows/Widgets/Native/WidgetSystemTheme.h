#pragma once
#include "WidgetEventQueue.h"
#include <memory>
#include <winrt/Windows.UI.ViewManagement.h>

namespace CodexBar::Widgets {
// Create/close on the host COM worker. Queue outlives this observer and its Close call.
class WidgetSystemTheme final {
    struct State {
        explicit State(WidgetEventQueue& value) : queue(value) {}
        std::mutex mutex;
        WidgetEventQueue& queue;
        bool closed = false;
        bool dark = false;
        HRESULT error = S_OK;
    };
    static bool ReadSystem(winrt::Windows::UI::ViewManagement::UISettings const& settings) {
        auto color = settings.GetColorValue(winrt::Windows::UI::ViewManagement::UIColorType::Background);
        // Classify the system background; card foregrounds remain selected by the matching theme.
        return 299 * static_cast<int>(color.R) + 587 * static_cast<int>(color.G) +
            114 * static_cast<int>(color.B) < 128000;
    }
public:
    explicit WidgetSystemTheme(WidgetEventQueue& queue) : state_(std::make_shared<State>(queue)) {
        std::weak_ptr<State> weak = state_;
        subscription_ = settings_.ColorValuesChanged(winrt::auto_revoke,
            [weak](auto const& sender, auto const&) noexcept {
                auto state = weak.lock();
                if (!state) return;
                std::scoped_lock lock(state->mutex);
                if (state->closed) return;
                try {
                    auto dark = ReadSystem(sender);
                    state->dark = dark;
                    state->error = S_OK;
                    // Foreground/high-contrast palette changes can keep the same dark/light classification.
                    state->queue.RequestRefresh();
                } catch (...) {
                    state->error = winrt::to_hresult();
                    // Wake the worker so its next theme read surfaces the error. Queue cancellation
                    // can reject this wake during shutdown; no exception crosses the OS callback.
                    try { state->queue.RequestRefresh(); } catch (...) {}
                }
            });
        contrastSubscription_ = accessibility_.HighContrastChanged(winrt::auto_revoke,
            [weak](auto const&, auto const&) noexcept {
                auto state = weak.lock();
                if (!state) return;
                std::scoped_lock lock(state->mutex);
                if (state->closed) return;
                // Swift captures current system colors when preparing the replacement card batch.
                try { state->queue.RequestRefresh(); } catch (...) {}
            });
        // Subscribe before the first read so a concurrent change cannot be permanently missed.
        std::scoped_lock lock(state_->mutex);
        state_->dark = ReadSystem(settings_);
    }
    WidgetSystemTheme(WidgetSystemTheme const&) = delete;
    WidgetSystemTheme& operator=(WidgetSystemTheme const&) = delete;
    ~WidgetSystemTheme() { Close(); }
    bool Dark() const {
        std::scoped_lock lock(state_->mutex);
        if (state_->closed) throw winrt::hresult_illegal_method_call();
        winrt::check_hresult(state_->error);
        return state_->dark;
    }
    void Close() noexcept {
        {
            std::scoped_lock lock(state_->mutex);
            state_->closed = true;
        }
        // Revoke outside the state lock: an in-flight callback may be waiting for that lock.
        subscription_.revoke();
        contrastSubscription_.revoke();
    }
private:
    std::shared_ptr<State> state_;
    winrt::Windows::UI::ViewManagement::UISettings settings_;
    winrt::Windows::UI::ViewManagement::UISettings::ColorValuesChanged_revoker subscription_;
    winrt::Windows::UI::ViewManagement::AccessibilitySettings accessibility_;
    winrt::Windows::UI::ViewManagement::AccessibilitySettings::HighContrastChanged_revoker contrastSubscription_;
};
}
