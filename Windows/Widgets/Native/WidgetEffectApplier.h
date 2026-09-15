#pragma once
#include "WidgetPublisher.h"
#include "WidgetResponseCodec.h"
#include <functional>

namespace CodexBar::Widgets {
// Called by the single event pump. Refresh enqueues a complete inventory refresh carrying this native generation.
class WidgetEffectApplier final {
public:
    using Refresh = std::function<void(std::uint64_t, std::vector<WidgetHostInstance> const&)>;
    using Report = std::function<void(winrt::hstring const&)>;
    WidgetEffectApplier(WidgetPublisher& publisher, Refresh refresh, Report report)
        : publisher_(publisher), refresh_(std::move(refresh)), report_(std::move(report)) {
        if (!refresh_ || !report_) throw winrt::hresult_invalid_argument();
    }
    static bool CanRefreshAfterRejection(WidgetHostEvent const& event, WidgetHostResponse const& response) {
        // Only an authenticated, sequence-consumed settings conflict is recoverable here.
        // Never replay the rejected mutation or continue after account-context/protocol/auth failures.
        return !response.accepted && response.consumed && response.error == L"settingsChanged" &&
            event.kind == WidgetHostEvent::Kind::Action;
    }
    void Apply(std::uint64_t generation, WidgetHostEvent const& event, WidgetHostResponse const& response) {
        if (publisher_.CurrentGeneration() != generation) throw winrt::hresult_illegal_method_call();
        if (!response.accepted) {
            auto inventory = publisher_.ReadInventory();
            auto context = WithdrawInventory(generation, inventory);
            report_(response.error);
            if (!context.withdrawalFailures.empty()) throw winrt::hresult_error(E_FAIL);
            if (CanRefreshAfterRejection(event, response)) refresh_(context.generation, inventory);
            return; // Other rejections still close the connection in the worker.
        }
        if (response.effect == L"customization") {
            if (event.kind != WidgetHostEvent::Kind::CustomizationRequested || response.widgetId != event.instance.id) {
                throw winrt::hresult_invalid_argument();
            }
            publisher_.Publish(generation, response.widgetId, response.templateJson, response.dataJson);
        } else if (response.effect == L"removed" || response.effect == L"refreshRequired") {
            if (response.effect == L"removed") publisher_.ConfirmDeleted(generation, response.widgetId);
            auto inventory = publisher_.ReadInventory();
            auto context = WithdrawInventory(generation, inventory);
            if (!context.withdrawalFailures.empty()) throw winrt::hresult_error(E_FAIL);
            refresh_(context.generation, inventory);
        } else if (response.effect != L"idle") { throw winrt::hresult_invalid_argument(); }
    }
private:
    WidgetPublisher::Context WithdrawInventory(std::uint64_t generation, std::vector<WidgetHostInstance> const& inventory) {
        std::vector<winrt::hstring> ids;
        ids.reserve(inventory.size());
        for (auto const& instance : inventory) ids.push_back(instance.id);
        return publisher_.BeginContext(ids, generation);
    }
    WidgetPublisher& publisher_;
    Refresh refresh_;
    Report report_;
};
}
