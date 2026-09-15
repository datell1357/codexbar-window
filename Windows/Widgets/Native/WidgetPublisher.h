#pragma once
#include <cstdint>
#include "WidgetProvider.h"
#include <mutex>
#include <optional>
#include <set>
#include <vector>
#include <winrt/Microsoft.Windows.Widgets.Providers.h>

namespace CodexBar::Widgets {
// One instance per provider process. Account invalidation and OS writes share this lock.
class WidgetPublisher final {
public:
    struct Context {
        std::uint64_t generation;
        std::vector<winrt::hstring> withdrawalFailures;
    };
    WidgetPublisher();
    // Reads only this provider's OS inventory; custom state is deliberately not imported.
    std::vector<WidgetHostInstance> ReadInventory();
    // Call only from the authenticated OS DeleteWidget callback, never from an omitted inventory entry.
    void ConfirmDeleted(std::uint64_t generation, winrt::hstring const& widgetId);
    // Include the authenticated OS inventory on startup, so prior-process content is withdrawn too.
    Context BeginContext(std::vector<winrt::hstring> const& inventory,
                         std::optional<std::uint64_t> expectedGeneration = std::nullopt);
    std::uint64_t CurrentGeneration();
    // Thread-safe publication barrier only; call BeginContext on the COM worker to withdraw OS content.
    void InvalidateContext();
    void Publish(std::uint64_t generation, winrt::hstring const& widgetId,
                 winrt::hstring const& templateJson, winrt::hstring const& dataJson);
    void Withdraw(std::uint64_t generation, winrt::hstring const& widgetId);
private:
    void WriteBlank(winrt::hstring const& widgetId);
    static void ValidateId(winrt::hstring const& widgetId);
    std::mutex mutex_;
    std::uint64_t generation_ = 0;
    bool ready_ = false;
    std::set<winrt::hstring> known_;
    winrt::Microsoft::Windows::Widgets::Providers::WidgetManager manager_;
};
}
