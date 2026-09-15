#pragma once
#include <cstdint>
#include <string>
#include "WidgetResponseCodec.h"

namespace CodexBar::Widgets {
struct WidgetBootstrap {
    winrt::guid sessionId;
    std::wstring pipeName;
    std::uintptr_t invalidationHandle;
};
// Input must come from a private authenticated launcher channel. Parsing does not authenticate the sender.
// This function does not adopt/close the handle: only trust-checked bootstrap delivery may grant ownership.
inline WidgetBootstrap DecodeWidgetBootstrap(std::string_view bytes) {
    if (bytes.empty() || bytes.size() > 4096) throw winrt::hresult_invalid_argument();
    auto object = winrt::Windows::Data::Json::JsonObject::Parse(winrt::to_hstring(bytes));
    if (object.Size() != 4 || object.GetNamedNumber(L"protocolVersion") != 1) {
        throw winrt::hresult_invalid_argument();
    }
    auto sessionText = object.GetNamedString(L"sessionID");
    winrt::guid session{sessionText.c_str()};
    if (CanonicalWidgetGuid(session) != sessionText) throw winrt::hresult_invalid_argument();
    auto name = object.GetNamedString(L"pipeName");
    std::wstring pipe{name.c_str(), name.size()};
    constexpr std::wstring_view prefix = LR"(\\.\pipe\CodexBar.Widgets.)";
    if (pipe.size() <= prefix.size() || pipe.size() > 256 || pipe.compare(0, prefix.size(), prefix) != 0) {
        throw winrt::hresult_invalid_argument();
    }
    auto suffix = pipe.substr(prefix.size());
    if (suffix.size() != 36) throw winrt::hresult_invalid_argument();
    winrt::guid nonce{suffix.c_str()};
    if (CanonicalWidgetGuid(nonce) != winrt::hstring(suffix)) throw winrt::hresult_invalid_argument();
    auto raw = winrt::to_string(object.GetNamedString(L"invalidationHandle"));
    if (raw.empty() || raw.size() > 20 || raw.front() == '0') throw winrt::hresult_invalid_argument();
    std::uintptr_t value = 0;
    auto parsed = std::from_chars(raw.data(), raw.data() + raw.size(), value);
    if (parsed.ec != std::errc{} || parsed.ptr != raw.data() + raw.size() || value == 0 ||
        value == (std::numeric_limits<std::uintptr_t>::max)() || std::to_string(value) != raw) {
        throw winrt::hresult_invalid_argument();
    }
    return {session, std::move(pipe), value};
}
}
