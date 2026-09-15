#pragma once
#include "WidgetCardRefresh.h"
#include "WidgetEffectApplier.h"
#include "WidgetEventQueue.h"
#include "WidgetSystemTheme.h"
#include <atomic>
#include <chrono>
#include <exception>

namespace CodexBar::Widgets {
// Own Run on a dedicated COM-initialized thread. All collaborators must outlive that thread.
// Use a fresh authenticated backend session; do not run WidgetEventPump on the same client.
class WidgetHostWorker final {
public:
    using Theme = std::function<bool()>;
    using Report = WidgetEffectApplier::Report;
    WidgetHostWorker(WidgetEventQueue& queue, WidgetBackendClient& client, WidgetPublisher& publisher,
                     Theme darkTheme, Report report)
        : queue_(queue), client_(client), publisher_(publisher), cards_(publisher, client),
          theme_(std::move(darkTheme)), report_(std::move(report)),
          effects_(publisher, [this](std::uint64_t generation, std::vector<WidgetHostInstance> const& inventory) {
              Refresh(generation, inventory);
          }, report_) {
        if (!report_) throw winrt::hresult_invalid_argument();
    }
    // Default desktop behavior follows Windows system colors. Tests/custom hosts may inject Theme above.
    WidgetHostWorker(WidgetEventQueue& queue, WidgetBackendClient& client, WidgetPublisher& publisher, Report report)
        : WidgetHostWorker(queue, client, publisher, Theme{}, std::move(report)) {}
    struct ExitStatus {
        HRESULT operation = S_OK;
        HRESULT withdrawal = S_OK;
        HRESULT producerShutdown = S_OK;
    };
    // Read only after joining the owner thread; an OS withdrawal failure requires host attention.
    ExitStatus StatusAfterJoin() const noexcept { return exitStatus_; }
    // stopProducers must stop/join external invalidation producers before terminal OS withdrawal.
    void Run(std::function<void()> stopProducers = {}) {
        if (started_.exchange(true)) throw winrt::hresult_illegal_method_call();
        std::exception_ptr operationFailure;
        std::shared_ptr<WidgetSystemTheme> systemTheme;
        try {
            if (!theme_) {
                systemTheme = std::make_shared<WidgetSystemTheme>(queue_);
                theme_ = [systemTheme] { return systemTheme->Dark(); };
            }
            RunLoop();
        }
        catch (...) {
            operationFailure = std::current_exception();
            exitStatus_.operation = winrt::to_hresult();
        }
        if (systemTheme) {
            systemTheme->Close();
            theme_ = {};
            systemTheme.reset(); // Release UISettings on the worker apartment before Run returns.
        }
        Cancel();
        if (stopProducers) {
            try { stopProducers(); }
            catch (...) { exitStatus_.producerShutdown = winrt::to_hresult(); }
        }
        // Run cleanup on the same COM apartment, after no further event/card writes are possible.
        try {
            auto context = publisher_.BeginContext({}, publisher_.CurrentGeneration());
            if (!context.withdrawalFailures.empty()) throw winrt::hresult_error(E_FAIL);
        } catch (...) {
            exitStatus_.withdrawal = winrt::to_hresult();
        }
        if (FAILED(exitStatus_.withdrawal)) throw winrt::hresult_error(exitStatus_.withdrawal);
        if (FAILED(exitStatus_.producerShutdown)) throw winrt::hresult_error(exitStatus_.producerShutdown);
        if (operationFailure) std::rethrow_exception(operationFailure);
    }
    // Call after updating the thread-safe theme source, or for a same-account manual refresh.
    // Account invalidation needs the backend/native context protocol, not just this wake-up.
    void RequestRefresh() { queue_.RequestRefresh(); }
    // Authenticated backend invalidation receiver may call this from another thread.
    // It must outlive the call, and the owner must stop/join the receiver before destroying this worker.
    void InvalidateContext() {
        if (cancelled_) return;
        publisher_.InvalidateContext();
        queue_.RequestWithdrawal();
    }
    void Cancel() {
        cancelled_ = true;
        queue_.Cancel();
        client_.Cancel();
    }
private:
    void RunLoop() {
        auto inventory = publisher_.ReadInventory();
        std::vector<winrt::hstring> ids;
        for (auto const& instance : inventory) ids.push_back(instance.id);
        // Backend hello performs internal initial invalidation without signaling our event.
        // This withdrawal MUST precede registration replay and the first card request on every fresh session.
        auto context = publisher_.BeginContext(ids);
        if (!context.withdrawalFailures.empty()) throw winrt::hresult_error(E_FAIL);
        // Restore existing OS widgets through idempotent registration before the first full snapshot.
        // Registration preserves saved settings and rejects definition changes.
        for (auto const& instance : inventory) {
            if (cancelled_) throw winrt::hresult_error(HRESULT_FROM_WIN32(ERROR_CANCELLED));
            WidgetHostEvent event{WidgetHostEvent::Kind::Created, instance, {}, {}};
            auto response = client_.Dispatch(event);
            if (!response.accepted) {
                report_(response.error);
                throw winrt::hresult_error(E_FAIL);
            }
            if (response.effect != L"refreshRequired") throw winrt::hresult_invalid_argument();
        }
        Refresh(context.generation, inventory);
        while (!cancelled_) {
            auto wake = queue_.WaitUntil(deadline_);
            if (wake.kind == WidgetEventQueue::Wake::Kind::Cancelled) break;
            if (wake.kind == WidgetEventQueue::Wake::Kind::Invalidation) {
                auto generation = publisher_.CurrentGeneration();
                auto current = publisher_.ReadInventory();
                std::vector<winrt::hstring> currentIds;
                for (auto const& instance : current) currentIds.push_back(instance.id);
                auto replacement = publisher_.BeginContext(currentIds, generation);
                if (!replacement.withdrawalFailures.empty()) throw winrt::hresult_error(E_FAIL);
                Refresh(replacement.generation, current);
                continue;
            }
            if (wake.kind == WidgetEventQueue::Wake::Kind::Deadline ||
                wake.kind == WidgetEventQueue::Wake::Kind::Refresh) {
                Refresh(publisher_.CurrentGeneration(), publisher_.ReadInventory());
                continue;
            }
            auto generation = publisher_.CurrentGeneration();
            auto response = client_.Dispatch(*wake.event);
            // RefreshRequired is handled synchronously, including its final acknowledgement.
            // No queued callback can interleave an event between prepare/card/acknowledge.
            effects_.Apply(generation, *wake.event, response);
            if (!response.accepted && !WidgetEffectApplier::CanRefreshAfterRejection(*wake.event, response)) {
                throw winrt::hresult_error(E_FAIL);
            }
        }
    }
    void Refresh(std::uint64_t generation, std::vector<WidgetHostInstance> const& inventory) {
        if (cancelled_) throw winrt::hresult_error(HRESULT_FROM_WIN32(ERROR_CANCELLED));
        auto result = cards_.Refresh(generation, inventory, theme_());
        // Convert a server wall-clock timestamp once to a bounded monotonic delay.
        // Account/settings changes take precedence through the event queue, independent of this timer.
        double delay = result.retryRequired ? 60.0 : 1800.0;
        if (result.nextRefreshEpochSeconds) {
            auto now = std::chrono::duration<double>(std::chrono::system_clock::now().time_since_epoch()).count();
            auto candidate = *result.nextRefreshEpochSeconds - now;
            if (candidate < delay) delay = candidate;
        }
        if (delay < 1.0) delay = 1.0;
        deadline_ = std::chrono::steady_clock::now() +
            std::chrono::duration_cast<std::chrono::steady_clock::duration>(std::chrono::duration<double>(delay));
    }
    WidgetEventQueue& queue_;
    WidgetBackendClient& client_;
    WidgetPublisher& publisher_;
    WidgetCardRefresh cards_;
    Theme theme_;
    Report report_;
    WidgetEffectApplier effects_;
    std::optional<std::chrono::steady_clock::time_point> deadline_;
    ExitStatus exitStatus_;
    std::atomic_bool started_{false};
    std::atomic_bool cancelled_{false};
};
}
