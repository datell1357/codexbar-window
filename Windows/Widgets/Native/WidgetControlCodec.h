#pragma once
#include "WidgetResponseCodec.h"

namespace CodexBar::Widgets {
struct WidgetControlResponse {
    bool accepted;
    bool consumed;
    std::uint64_t nextSequence;
    winrt::hstring error;
    winrt::Windows::Data::Json::JsonObject payload{nullptr};
};
inline WidgetControlResponse DecodeWidgetControl(std::string_view bytes, winrt::guid const& sessionId,
    winrt::guid const& requestId, std::uint64_t sequence) {
    using winrt::Windows::Data::Json::JsonObject;
    if (bytes.size() > 256 * 1024 || sequence == (std::numeric_limits<std::uint64_t>::max)()) {
        throw winrt::hresult_invalid_argument();
    }
    auto object = JsonObject::Parse(winrt::to_hstring(bytes));
    if (!object.GetNamedBoolean(L"accepted")) {
        // Reuse the same bounded error/correlation contract. No event effect is accepted on this path.
        WidgetHostEvent unused{WidgetHostEvent::Kind::Deactivated, {}, {}, {}};
        auto error = DecodeWidgetResponse(bytes, sessionId, requestId, sequence, unused);
        if (object.HasKey(L"payload")) throw winrt::hresult_invalid_argument();
        return {false, error.consumed, error.nextSequence, error.error, nullptr};
    }
    if (object.GetNamedNumber(L"protocolVersion") != 1 ||
        object.GetNamedString(L"sessionID") != CanonicalWidgetGuid(sessionId) ||
        object.GetNamedString(L"requestID") != CanonicalWidgetGuid(requestId) ||
        !object.GetNamedBoolean(L"consumed") || object.GetNamedString(L"nextSequence") != winrt::to_hstring(sequence + 1)) {
        throw winrt::hresult_invalid_argument();
    }
    for (auto key : {L"error", L"effect", L"widgetID", L"template", L"data", L"actionToken"}) {
        if (object.HasKey(key)) throw winrt::hresult_invalid_argument();
    }
    return {true, true, sequence + 1, {}, object.GetNamedObject(L"payload")};
}
}
