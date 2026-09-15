#pragma once
#include <string>
#include <string_view>
#include "WidgetProvider.h"
#include <winrt/Windows.Data.Json.h>

namespace CodexBar::Widgets {
// UTF-8 object payload inside the authenticated transport's bounded frame; never a command line.
inline std::string EncodeWidgetEvent(WidgetHostEvent const& event, winrt::guid const& sessionId,
                                    winrt::guid const& requestId, std::uint64_t sequence) {
    using winrt::Windows::Data::Json::JsonObject;
    using winrt::Windows::Data::Json::JsonValue;
    auto guidText = [](winrt::guid const& id) {
        auto text = winrt::to_hstring(id);
        if (text.size() == 38 && text[0] == L'{') return winrt::hstring(std::wstring_view(text).substr(1, 36));
        return text;
    };
    winrt::hstring kind;
    using Kind = WidgetHostEvent::Kind;
    switch (event.kind) {
    case Kind::Created: kind = L"created"; break;
    case Kind::Deleted: kind = L"deleted"; break;
    case Kind::Action: kind = L"action"; break;
    case Kind::ContextChanged: kind = L"contextChanged"; break;
    case Kind::Activated: kind = L"activated"; break;
    case Kind::Deactivated: kind = L"deactivated"; break;
    case Kind::CustomizationRequested: kind = L"customizationRequested"; break;
    default: throw winrt::hresult_invalid_argument();
    }
    JsonObject object;
    object.Insert(L"protocolVersion", JsonValue::CreateNumberValue(1));
    object.Insert(L"sessionID", JsonValue::CreateStringValue(guidText(sessionId)));
    object.Insert(L"requestID", JsonValue::CreateStringValue(guidText(requestId)));
    object.Insert(L"sequence", JsonValue::CreateStringValue(winrt::to_hstring(sequence)));
    object.Insert(L"kind", JsonValue::CreateStringValue(kind));
    object.Insert(L"widgetID", JsonValue::CreateStringValue(event.instance.id));
    if (event.kind != Kind::Deleted && event.kind != Kind::Deactivated) {
        winrt::hstring size;
        switch (event.instance.size) {
        case 0: size = L"small"; break;
        case 1: size = L"medium"; break;
        case 2: size = L"large"; break;
        default: throw winrt::hresult_invalid_argument();
        }
        object.Insert(L"definitionID", JsonValue::CreateStringValue(event.instance.definitionId));
        object.Insert(L"size", JsonValue::CreateStringValue(size));
    }
    if (event.kind == Kind::Action) {
        object.Insert(L"verb", JsonValue::CreateStringValue(event.verb));
        object.Insert(L"arguments", JsonValue::CreateStringValue(event.data));
    }
    auto result = winrt::to_string(object.Stringify());
    if (result.size() > 16 * 1024) throw winrt::hresult_invalid_argument();
    return result;
}
}
