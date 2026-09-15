#include "WidgetPublisher.h"
#include <limits>
#include <winrt/Windows.Data.Json.h>

namespace CodexBar::Widgets {
using winrt::Microsoft::Windows::Widgets::Providers::WidgetManager;
using winrt::Microsoft::Windows::Widgets::Providers::WidgetUpdateRequestOptions;

WidgetPublisher::WidgetPublisher() : manager_(WidgetManager::GetDefault()) {}

std::vector<WidgetHostInstance> WidgetPublisher::ReadInventory() {
    auto infos = manager_.GetWidgetInfos();
    if (infos.size() > 128) throw winrt::hresult_invalid_argument();
    std::set<winrt::hstring> ids;
    std::vector<WidgetHostInstance> result;
    result.reserve(infos.size());
    for (auto const& info : infos) {
        auto context = info.WidgetContext();
        ValidateId(context.Id());
        if (!ids.insert(context.Id()).second) throw winrt::hresult_invalid_argument();
        result.push_back(WidgetProvider::Capture(context));
    }
    return result;
}

void WidgetPublisher::ConfirmDeleted(std::uint64_t generation, winrt::hstring const& id) {
    ValidateId(id);
    std::scoped_lock lock(mutex_);
    if (generation != generation_) throw winrt::hresult_illegal_method_call();
    known_.erase(id);
    // Do not reopen a failed context here. BeginContext must retry all remaining withdrawals first.
}

void WidgetPublisher::ValidateId(winrt::hstring const& id) {
    if (id.empty() || id.size() > 256 || winrt::to_string(id).size() > 256) {
        throw winrt::hresult_invalid_argument();
    }
    for (auto ch : id) {
        if (ch < 0x20 || (ch >= 0x7f && ch <= 0x9f)) throw winrt::hresult_invalid_argument();
    }
}

void WidgetPublisher::WriteBlank(winrt::hstring const& id) {
    WidgetUpdateRequestOptions options{id};
    options.Template(LR"({"type":"AdaptiveCard","version":"1.6","body":[]})");
    options.Data(L"{}");
    options.CustomState(L"");
    manager_.UpdateWidget(options);
}

std::uint64_t WidgetPublisher::CurrentGeneration() {
    std::scoped_lock lock(mutex_);
    return generation_;
}

void WidgetPublisher::InvalidateContext() {
    std::scoped_lock lock(mutex_);
    ready_ = false;
    if (generation_ == (std::numeric_limits<std::uint64_t>::max)()) {
        throw winrt::hresult_illegal_method_call();
    }
    ++generation_;
    // No WidgetManager calls here: the signal receiver need not own a COM apartment.
}

WidgetPublisher::Context WidgetPublisher::BeginContext(std::vector<winrt::hstring> const& inventory,
    std::optional<std::uint64_t> expectedGeneration) {
    if (inventory.size() > 128) throw winrt::hresult_invalid_argument();
    std::set<winrt::hstring> current;
    for (auto const& id : inventory) {
        ValidateId(id);
        if (!current.insert(id).second) throw winrt::hresult_invalid_argument();
    }
    std::scoped_lock lock(mutex_);
    if (expectedGeneration && *expectedGeneration != generation_) throw winrt::hresult_illegal_method_call();
    ready_ = false;
    if (generation_ == (std::numeric_limits<std::uint64_t>::max)()) throw winrt::hresult_illegal_method_call();
    // Finish bounded allocations before performing any OS writes. On an allocation failure,
    // the prior known set remains intact and publishing remains disabled.
    auto requested = current;
    current.insert(known_.begin(), known_.end());
    if (current.size() > 256) throw winrt::hresult_invalid_argument();
    Context result{generation_ + 1, {}};
    result.withdrawalFailures.reserve(current.size());
    ++generation_;
    known_.swap(current); // Retain every attempted ID before the first call that can throw.
    for (auto iterator = known_.begin(); iterator != known_.end();) {
        bool withdrawn = false;
        try { WriteBlank(*iterator); withdrawn = true; }
        catch (winrt::hresult_error const&) { result.withdrawalFailures.push_back(*iterator); }
        // Successful obsolete IDs no longer need retry; configured OS instances remain eligible for Publish.
        // Unexpected exceptions leave the unprocessed and failed IDs in known_ for terminal cleanup.
        if (withdrawn && requested.find(*iterator) == requested.end()) iterator = known_.erase(iterator);
        else ++iterator;
    }
    ready_ = result.withdrawalFailures.empty();
    return result;
}

void WidgetPublisher::Publish(std::uint64_t generation, winrt::hstring const& id,
                              winrt::hstring const& templateJson, winrt::hstring const& dataJson) {
    ValidateId(id);
    constexpr std::size_t maxBytes = 256 * 1024;
    if (templateJson.size() > maxBytes || dataJson.size() > maxBytes ||
        winrt::to_string(templateJson).size() > maxBytes || winrt::to_string(dataJson).size() > maxBytes) {
        throw winrt::hresult_invalid_argument();
    }
    // Decode before acquiring the publication lock; no template/data content is logged.
    winrt::Windows::Data::Json::JsonObject::Parse(templateJson);
    winrt::Windows::Data::Json::JsonObject::Parse(dataJson);
    std::scoped_lock lock(mutex_);
    if (!ready_ || generation != generation_ || known_.find(id) == known_.end()) {
        throw winrt::hresult_illegal_method_call();
    }
    WidgetUpdateRequestOptions options{id};
    options.Template(templateJson);
    options.Data(dataJson);
    options.CustomState(L"");
    manager_.UpdateWidget(options);
}

void WidgetPublisher::Withdraw(std::uint64_t generation, winrt::hstring const& id) {
    ValidateId(id);
    std::scoped_lock lock(mutex_);
    if (generation != generation_ || known_.find(id) == known_.end()) throw winrt::hresult_illegal_method_call();
    WriteBlank(id);
}
}
