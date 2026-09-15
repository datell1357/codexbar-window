#pragma once
#include <string>
#include <winrt/base.h>

namespace CodexBar::Widgets {
inline winrt::hstring CanonicalWidgetGuid(winrt::guid const& id) {
    auto value = winrt::to_hstring(id);
    std::wstring text(value.c_str(), value.size());
    if (text.size() == 38 && text.front() == L'{') text = text.substr(1, 36);
    for (auto& ch : text) if (ch >= L'A' && ch <= L'F') ch += L'a' - L'A';
    return winrt::hstring(text);
}

}
