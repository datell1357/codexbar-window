#pragma once
#include "WidgetBackendClient.h"
#include "WidgetPublisher.h"
#include <cmath>
#include <map>
#include <optional>

namespace CodexBar::Widgets {
// The host must serialize this whole operation with event dispatch on its COM worker.
// Per-request pipe locking alone does not protect a multi-request publication transaction.
class WidgetCardRefresh final {
public:
    struct Result {
        std::uint64_t generation;
        bool retryRequired = false;
        std::vector<winrt::hstring> published;
        std::vector<winrt::hstring> failed;
        std::optional<double> nextRefreshEpochSeconds;
    };
    WidgetCardRefresh(WidgetPublisher& publisher, WidgetBackendClient& client)
        : publisher_(publisher), client_(client) {}

    Result Refresh(std::uint64_t generation, std::vector<WidgetHostInstance> const& inventory, bool dark) {
        RequireCurrent(generation);
        std::vector<winrt::hstring> ids;
        std::set<winrt::hstring> expected;
        if (inventory.size() > 128) throw winrt::hresult_invalid_argument();
        for (auto const& instance : inventory) {
            if (instance.id.empty() || !expected.insert(instance.id).second) throw winrt::hresult_invalid_argument();
            ids.push_back(instance.id);
        }
        try {
            auto manifest = Accepted(client_.PrepareCards(dark));
            RequireCurrent(generation);
            auto state = manifest.GetNamedString(L"state");
            if (state == L"pending" || state == L"withdrawn") {
                auto context = Clear(generation, ids);
                return Result{context, true, {}, {}, std::nullopt};
            }
            if (state != L"ready") throw winrt::hresult_invalid_argument();
            auto ticketText = manifest.GetNamedString(L"ticket");
            winrt::guid ticket{ticketText.c_str()};
            if (CanonicalWidgetGuid(ticket) != ticketText) throw winrt::hresult_invalid_argument();
            auto items = manifest.GetNamedArray(L"items");
            if (items.Size() != expected.size()) throw winrt::hresult_invalid_argument();
            std::map<winrt::hstring, winrt::hstring> states;
            for (auto const& value : items) {
                auto item = value.GetObject();
                auto id = item.GetNamedString(L"widgetID");
                auto itemState = item.GetNamedString(L"state");
                if (!expected.count(id) || !states.emplace(id, itemState).second ||
                    (itemState != L"ready" && itemState != L"customizing" &&
                     itemState != L"removed" && itemState != L"failed")) {
                    throw winrt::hresult_invalid_argument();
                }
            }
            Result result{generation};
            for (auto const& [id, itemState] : states) {
                RequireCurrent(generation);
                if (itemState == L"customizing") continue; // Preserve the OS settings form.
                auto card = Accepted(client_.ReadCard(ticket, id));
                RequireCurrent(generation);
                if (card.GetNamedString(L"ticket") != ticketText || card.GetNamedString(L"widgetID") != id ||
                    card.GetNamedString(L"state") != itemState) throw winrt::hresult_invalid_argument();
                if (itemState == L"removed") {
                    publisher_.Withdraw(generation, id); // Still an OS instance: do not ConfirmDeleted.
                    result.failed.push_back(id);
                    result.retryRequired = true;
                    continue;
                }
                auto templateJson = card.GetNamedString(L"template");
                auto dataJson = card.GetNamedString(L"data");
                auto next = card.GetNamedNumber(L"nextRefresh");
                if (!std::isfinite(next) || next <= 0 ||
                    winrt::to_string(templateJson).size() > 256 * 1024 ||
                    winrt::to_string(dataJson).size() > 256 * 1024) throw winrt::hresult_invalid_argument();
                // Reject protocol errors before entering the recoverable OS publication path.
                winrt::Windows::Data::Json::JsonObject::Parse(templateJson);
                winrt::Windows::Data::Json::JsonObject::Parse(dataJson);
                bool written = false;
                try {
                    publisher_.Publish(generation, id, templateJson, dataJson);
                    written = true;
                } catch (winrt::hresult_error const&) {
                    RequireCurrent(generation);
                    publisher_.Withdraw(generation, id); // Withdrawal failure is fatal, never hidden.
                }
                if (written && itemState == L"ready") result.published.push_back(id);
                else {
                    result.failed.push_back(id);
                    result.retryRequired = true;
                }
                if (!result.nextRefreshEpochSeconds || next < *result.nextRefreshEpochSeconds) {
                    result.nextRefreshEpochSeconds = next;
                }
            }
            RequireCurrent(generation);
            auto acknowledgement = Accepted(client_.AcknowledgeCards(ticket, result.published));
            RequireCurrent(generation);
            if (acknowledgement.GetNamedString(L"state") != L"acknowledged") {
                throw winrt::hresult_invalid_argument();
            }
            return result;
        } catch (...) {
            // A rejected/expired transfer must not leave partially published account data behind.
            // Never withdraw a newer account generation in response to an older failed request.
            if (publisher_.CurrentGeneration() == generation) Clear(generation, ids);
            throw;
        }
    }
private:
    static winrt::Windows::Data::Json::JsonObject Accepted(WidgetControlResponse const& response) {
        if (!response.accepted || !response.payload) throw winrt::hresult_error(E_FAIL);
        return response.payload;
    }
    void RequireCurrent(std::uint64_t generation) {
        if (publisher_.CurrentGeneration() != generation) throw winrt::hresult_illegal_method_call();
    }
    std::uint64_t Clear(std::uint64_t generation, std::vector<winrt::hstring> const& ids) {
        auto context = publisher_.BeginContext(ids, generation);
        if (!context.withdrawalFailures.empty()) throw winrt::hresult_error(E_FAIL);
        return context.generation;
    }
    WidgetPublisher& publisher_;
    WidgetBackendClient& client_;
};
}
