#pragma once
#include "WidgetProvider.h"
#include "WidgetGuid.h"
#include <charconv>
#include <limits>
#include <string_view>
#include <winrt/Windows.Data.Json.h>

namespace CodexBar::Widgets {
struct WidgetHostResponse {
    bool accepted;
    bool consumed;
    std::uint64_t nextSequence;
    winrt::hstring effect;
    winrt::hstring error;
    winrt::hstring widgetId;
    winrt::hstring actionToken;
    winrt::hstring templateJson;
    winrt::hstring dataJson;
};

inline WidgetHostResponse DecodeWidgetResponse(std::string_view payload, winrt::guid const& sessionId,
    winrt::guid const& requestId, std::uint64_t sequence, WidgetHostEvent const& request) {
    using winrt::Windows::Data::Json::JsonObject;
    if (payload.size() > 256 * 1024 || sequence == (std::numeric_limits<std::uint64_t>::max)()) {
        throw winrt::hresult_invalid_argument();
    }
    auto object = JsonObject::Parse(winrt::to_hstring(payload));
    if (object.GetNamedNumber(L"protocolVersion") != 1 ||
        object.GetNamedString(L"sessionID") != CanonicalWidgetGuid(sessionId)) throw winrt::hresult_invalid_argument();
    WidgetHostResponse result{};
    result.accepted = object.GetNamedBoolean(L"accepted");
    result.consumed = object.GetNamedBoolean(L"consumed");
    auto nextText = winrt::to_string(object.GetNamedString(L"nextSequence"));
    auto parsed = std::from_chars(nextText.data(), nextText.data() + nextText.size(), result.nextSequence);
    if (parsed.ec != std::errc{} || parsed.ptr != nextText.data() + nextText.size() ||
        std::to_string(result.nextSequence) != nextText ||
        result.nextSequence != sequence + (result.consumed ? 1 : 0)) throw winrt::hresult_invalid_argument();
    if (object.HasKey(L"requestID")) {
        if (object.GetNamedString(L"requestID") != CanonicalWidgetGuid(requestId)) throw winrt::hresult_invalid_argument();
    } else if (result.accepted || result.consumed) { throw winrt::hresult_invalid_argument(); }
    if (!result.accepted) {
        result.error = object.GetNamedString(L"error");
        if (result.error != L"busy" && result.error != L"closed" && result.error != L"invalidMessage" &&
            result.error != L"staleContext" && result.error != L"settingsChanged" &&
            result.error != L"unavailable" && result.error != L"cancelled") throw winrt::hresult_invalid_argument();
        for (auto key : {L"effect", L"widgetID", L"actionToken", L"template", L"data"}) {
            if (object.HasKey(key)) throw winrt::hresult_invalid_argument();
        }
        return result;
    }
    if (!result.consumed || object.HasKey(L"error")) throw winrt::hresult_invalid_argument();
    result.effect = object.GetNamedString(L"effect");
    if (result.effect == L"removed" || result.effect == L"customization") {
        result.widgetId = object.GetNamedString(L"widgetID");
        if (result.widgetId != request.instance.id) throw winrt::hresult_invalid_argument();
        if (result.effect == L"removed" && request.kind != WidgetHostEvent::Kind::Deleted) {
            throw winrt::hresult_invalid_argument();
        }
    } else if (result.effect != L"idle" && result.effect != L"refreshRequired") {
        throw winrt::hresult_invalid_argument();
    } else if (object.HasKey(L"widgetID")) { throw winrt::hresult_invalid_argument(); }
    if (result.effect == L"customization") {
        if (request.kind != WidgetHostEvent::Kind::CustomizationRequested) throw winrt::hresult_invalid_argument();
        result.actionToken = object.GetNamedString(L"actionToken");
        if (result.actionToken.size() != 36) throw winrt::hresult_invalid_argument();
        for (std::size_t i = 0; i < 36; ++i) {
            auto ch = result.actionToken[i];
            bool separator = i == 8 || i == 13 || i == 18 || i == 23;
            if (separator ? ch != L'-' : !((ch >= L'0' && ch <= L'9') || (ch >= L'a' && ch <= L'f'))) {
                throw winrt::hresult_invalid_argument();
            }
        }
        result.templateJson = object.GetNamedString(L"template");
        result.dataJson = object.GetNamedString(L"data");
        if (winrt::to_string(result.templateJson).size() > 64 * 1024 ||
            winrt::to_string(result.dataJson).size() > 64 * 1024) throw winrt::hresult_invalid_argument();
        JsonObject::Parse(result.templateJson);
        JsonObject::Parse(result.dataJson);
    } else {
        for (auto key : {L"actionToken", L"template", L"data"}) {
            if (object.HasKey(key)) throw winrt::hresult_invalid_argument();
        }
    }
    return result;
}
}
