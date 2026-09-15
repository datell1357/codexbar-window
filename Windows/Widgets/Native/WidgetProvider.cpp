#include "WidgetProvider.h"
#include <winrt/Windows.Data.Json.h>

namespace CodexBar::Widgets {
namespace Providers = winrt::Microsoft::Windows::Widgets::Providers;
WidgetProvider::WidgetProvider(std::function<void(WidgetHostEvent)> sink) : sink_(std::move(sink)) {
    if (!sink_) throw winrt::hresult_invalid_argument();
}
void WidgetProvider::ValidateId(winrt::hstring const& id) {
    if (id.empty() || id.size() > 256 || winrt::to_string(id).size() > 256) throw winrt::hresult_invalid_argument();
    for (auto ch : id) {
        if (ch < 0x20 || (ch >= 0x7f && ch <= 0x9f)) throw winrt::hresult_invalid_argument();
    }
}
WidgetHostInstance WidgetProvider::Capture(Providers::WidgetContext const& context) {
    auto id = context.Id();
    auto definition = context.DefinitionId();
    ValidateId(id); ValidateId(definition);
    return {id, definition, static_cast<std::int32_t>(context.Size())};
}
void WidgetProvider::CreateWidget(Providers::WidgetContext context) {
    sink_({WidgetHostEvent::Kind::Created, Capture(context), {}, {}});
}
void WidgetProvider::DeleteWidget(winrt::hstring const& id, winrt::hstring const&) {
    ValidateId(id);
    sink_({WidgetHostEvent::Kind::Deleted, {id, {}, 0}, {}, {}});
}
void WidgetProvider::OnActionInvoked(Providers::WidgetActionInvokedArgs args) {
    auto instance = Capture(args.WidgetContext());
    auto verb = args.Verb();
    auto data = args.Data();
    if (verb != L"codexbar.switchProvider" && verb != L"codexbar.saveWidgetSettings" &&
        verb != L"codexbar.cancelWidgetSettings") throw winrt::hresult_invalid_argument();
    if (data.size() > 4096 || winrt::to_string(data).size() > 4096) throw winrt::hresult_invalid_argument();
    winrt::Windows::Data::Json::JsonObject::Parse(data);
    sink_({WidgetHostEvent::Kind::Action, std::move(instance), verb, data});
}
void WidgetProvider::OnWidgetContextChanged(Providers::WidgetContextChangedArgs args) {
    sink_({WidgetHostEvent::Kind::ContextChanged, Capture(args.WidgetContext()), {}, {}});
}
void WidgetProvider::Activate(Providers::WidgetContext context) {
    sink_({WidgetHostEvent::Kind::Activated, Capture(context), {}, {}});
}
void WidgetProvider::OnCustomizationRequested(Providers::WidgetCustomizationRequestedArgs args) {
    sink_({WidgetHostEvent::Kind::CustomizationRequested, Capture(args.WidgetContext()), {}, {}});
}
void WidgetProvider::Deactivate(winrt::hstring id) {
    ValidateId(id);
    sink_({WidgetHostEvent::Kind::Deactivated, {id, {}, 0}, {}, {}});
}
}
