#pragma once
#include <cstdint>
#include <functional>
#include <utility>
#include <winrt/Microsoft.Windows.Widgets.Providers.h>

namespace CodexBar::Widgets {
// Copy callback values immediately: OS callback objects must not escape their invocation.
struct WidgetHostInstance {
    winrt::hstring id;
    winrt::hstring definitionId;
    std::int32_t size;
};
struct WidgetHostEvent {
    enum class Kind { Created, Deleted, Action, ContextChanged, Activated, Deactivated, CustomizationRequested };
    Kind kind;
    WidgetHostInstance instance;
    winrt::hstring verb;
    winrt::hstring data;
};

struct WidgetProvider final : winrt::implements<WidgetProvider,
    winrt::Microsoft::Windows::Widgets::Providers::IWidgetProvider,
    winrt::Microsoft::Windows::Widgets::Providers::IWidgetProvider2> {
    // Sink must enqueue into the host's bounded serialized dispatcher and throw if it cannot accept an event.
    // COM caller authentication must be enforced before that dispatcher applies actions or settings.
    explicit WidgetProvider(std::function<void(WidgetHostEvent)> sink);
    void CreateWidget(winrt::Microsoft::Windows::Widgets::Providers::WidgetContext context);
    void DeleteWidget(winrt::hstring const& id, winrt::hstring const& customState);
    void OnActionInvoked(winrt::Microsoft::Windows::Widgets::Providers::WidgetActionInvokedArgs args);
    void OnWidgetContextChanged(winrt::Microsoft::Windows::Widgets::Providers::WidgetContextChangedArgs args);
    void Activate(winrt::Microsoft::Windows::Widgets::Providers::WidgetContext context);
    void Deactivate(winrt::hstring id);
    void OnCustomizationRequested(winrt::Microsoft::Windows::Widgets::Providers::WidgetCustomizationRequestedArgs args);
    static WidgetHostInstance Capture(winrt::Microsoft::Windows::Widgets::Providers::WidgetContext const& context);
private:
    static void ValidateId(winrt::hstring const& id);
    std::function<void(WidgetHostEvent)> sink_;
};
}
