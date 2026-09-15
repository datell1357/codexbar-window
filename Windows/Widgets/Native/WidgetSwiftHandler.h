#pragma once
#include "WidgetBackendABI.h"
#include "WidgetBackendServer.h"
#include <vector>

namespace CodexBar::Widgets {
inline WidgetBackendServer::Handler MakeWidgetSwiftHandler(void* context, CBWidgetRequestHandler callback) {
    if (!context || !callback) throw winrt::hresult_invalid_argument();
    return [context, callback](std::string_view request) -> std::string {
        if (request.empty() || request.size() > 16 * 1024) throw winrt::hresult_invalid_argument();
        std::vector<uint8_t> response(MaximumWidgetFramePayload);
        uint32_t written = 0;
        auto status = callback(context, reinterpret_cast<uint8_t const*>(request.data()),
            static_cast<uint32_t>(request.size()), response.data(), static_cast<uint32_t>(response.size()), &written);
        if (status != 0 || written == 0 || written > response.size()) {
            throw winrt::hresult_error(E_FAIL);
        }
        return std::string(reinterpret_cast<char const*>(response.data()), written);
    };
}
}
