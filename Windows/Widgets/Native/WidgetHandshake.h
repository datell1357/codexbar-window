#pragma once
#include "WidgetPipeExchange.h"
#include "WidgetResponseCodec.h"
#include <objbase.h>

namespace CodexBar::Widgets {
inline void NegotiateWidgetSession(WidgetPipeExchange& pipe, winrt::guid const& sessionId) {
    using winrt::Windows::Data::Json::JsonObject;
    using winrt::Windows::Data::Json::JsonValue;
    try {
        winrt::guid requestId{};
        winrt::check_hresult(CoCreateGuid(reinterpret_cast<GUID*>(&requestId)));
        JsonObject hello;
        hello.Insert(L"protocolVersion", JsonValue::CreateNumberValue(1));
        hello.Insert(L"method", JsonValue::CreateStringValue(L"hello"));
        hello.Insert(L"sessionID", JsonValue::CreateStringValue(CanonicalWidgetGuid(sessionId)));
        hello.Insert(L"requestID", JsonValue::CreateStringValue(CanonicalWidgetGuid(requestId)));
        hello.Insert(L"maximumFrameBytes", JsonValue::CreateNumberValue(MaximumWidgetFramePayload));
        hello.Insert(L"maximumEventBytes", JsonValue::CreateNumberValue(16 * 1024));
        auto bytes = pipe.Exchange(winrt::to_string(hello.Stringify()));
        if (bytes.size() > 4096) throw winrt::hresult_invalid_argument();
        auto response = JsonObject::Parse(winrt::to_hstring(bytes));
        if (response.GetNamedNumber(L"protocolVersion") != 1 || response.GetNamedString(L"method") != L"hello" ||
            !response.GetNamedBoolean(L"accepted") || response.GetNamedString(L"sessionID") != CanonicalWidgetGuid(sessionId) ||
            response.GetNamedString(L"requestID") != CanonicalWidgetGuid(requestId) ||
            response.GetNamedNumber(L"maximumFrameBytes") != MaximumWidgetFramePayload ||
            response.GetNamedNumber(L"maximumEventBytes") != 16 * 1024 || response.GetNamedString(L"nextSequence") != L"0") {
            throw winrt::hresult_invalid_argument();
        }
    } catch (...) {
        pipe.Cancel();
        throw;
    }
}
}
