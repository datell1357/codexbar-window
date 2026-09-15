#pragma once
#include <limits>
#include <mutex>
#include "WidgetEventCodec.h"
#include "WidgetResponseCodec.h"
#include "WidgetPipeExchange.h"
#include "WidgetHandshake.h"
#include "WidgetControlCodec.h"
#include <set>
#include <memory>
#include <objbase.h>

namespace CodexBar::Widgets {
// A fresh instance is required for every authenticated handshake. Sequence starts at zero on both peers.
class WidgetBackendClient final {
public:
    WidgetBackendClient(std::shared_ptr<WidgetPipeExchange> pipe, winrt::guid const& sessionId)
        : pipe_(std::move(pipe)), sessionId_(sessionId) {
        if (!pipe_) throw winrt::hresult_invalid_argument();
        NegotiateWidgetSession(*pipe_, sessionId_);
    }
    WidgetHostResponse Dispatch(WidgetHostEvent const& event) {
        std::scoped_lock lock(mutex_);
        if (failed_ || sequence_ == (std::numeric_limits<std::uint64_t>::max)()) {
            throw winrt::hresult_illegal_method_call();
        }
        try {
            winrt::guid requestId{};
            static_assert(sizeof(requestId) == sizeof(GUID));
            winrt::check_hresult(CoCreateGuid(reinterpret_cast<GUID*>(&requestId)));
            auto request = EncodeWidgetEvent(event, sessionId_, requestId, sequence_);
            auto bytes = pipe_->Exchange(request);
            auto response = DecodeWidgetResponse(bytes, sessionId_, requestId, sequence_, event);
            // Advance before applying any OS effect. A later rendering failure cannot replay a committed request.
            sequence_ = response.nextSequence;
            return response;
        } catch (...) {
            failed_ = true;
            pipe_->Cancel();
            throw;
        }
    }
    WidgetControlResponse PrepareCards(bool dark) {
        winrt::Windows::Data::Json::JsonObject fields;
        fields.Insert(L"theme", winrt::Windows::Data::Json::JsonValue::CreateStringValue(dark ? L"dark" : L"light"));
        return Control(L"prepare", fields);
    }
    WidgetControlResponse ReadCard(winrt::guid const& ticket, winrt::hstring const& widgetId) {
        winrt::Windows::Data::Json::JsonObject fields;
        fields.Insert(L"ticket", winrt::Windows::Data::Json::JsonValue::CreateStringValue(CanonicalWidgetGuid(ticket)));
        fields.Insert(L"widgetID", winrt::Windows::Data::Json::JsonValue::CreateStringValue(widgetId));
        return Control(L"card", fields);
    }
    WidgetControlResponse AcknowledgeCards(winrt::guid const& ticket, std::vector<winrt::hstring> const& ids) {
        if (ids.size() > 128 || std::set<winrt::hstring>(ids.begin(), ids.end()).size() != ids.size()) {
            throw winrt::hresult_invalid_argument();
        }
        winrt::Windows::Data::Json::JsonObject fields;
        winrt::Windows::Data::Json::JsonArray values;
        for (auto const& id : ids) values.Append(winrt::Windows::Data::Json::JsonValue::CreateStringValue(id));
        fields.Insert(L"ticket", winrt::Windows::Data::Json::JsonValue::CreateStringValue(CanonicalWidgetGuid(ticket)));
        fields.Insert(L"publishedIDs", values);
        return Control(L"acknowledge", fields);
    }
    void Cancel() noexcept { pipe_->Cancel(); }
private:
    WidgetControlResponse Control(winrt::hstring const& method, winrt::Windows::Data::Json::JsonObject fields) {
        using winrt::Windows::Data::Json::JsonValue;
        std::scoped_lock lock(mutex_);
        if (failed_ || sequence_ == (std::numeric_limits<std::uint64_t>::max)()) throw winrt::hresult_illegal_method_call();
        try {
            winrt::guid requestId{};
            winrt::check_hresult(CoCreateGuid(reinterpret_cast<GUID*>(&requestId)));
            fields.Insert(L"protocolVersion", JsonValue::CreateNumberValue(1));
            fields.Insert(L"sessionID", JsonValue::CreateStringValue(CanonicalWidgetGuid(sessionId_)));
            fields.Insert(L"requestID", JsonValue::CreateStringValue(CanonicalWidgetGuid(requestId)));
            fields.Insert(L"sequence", JsonValue::CreateStringValue(winrt::to_hstring(sequence_)));
            fields.Insert(L"method", JsonValue::CreateStringValue(method));
            auto request = winrt::to_string(fields.Stringify());
            if (request.size() > 16 * 1024) throw winrt::hresult_invalid_argument();
            auto response = DecodeWidgetControl(pipe_->Exchange(request), sessionId_, requestId, sequence_);
            sequence_ = response.nextSequence;
            return response;
        } catch (...) {
            failed_ = true; pipe_->Cancel();
            throw;
        }
    }
    std::shared_ptr<WidgetPipeExchange> pipe_;
    winrt::guid sessionId_;
    std::uint64_t sequence_ = 0;
    bool failed_ = false;
    std::mutex mutex_;
};
}
