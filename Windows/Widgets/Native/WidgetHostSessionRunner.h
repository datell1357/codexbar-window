#pragma once
#include "WidgetClassFactory.h"
#include "WidgetInvalidationReceiver.h"
#include <memory>

namespace CodexBar::Widgets {
struct WidgetHostSessionResult {
    HRESULT operation = S_OK;
    HRESULT registrationCleanup = S_OK;
    HRESULT receiverCleanup = S_OK;
    WidgetHostWorker::ExitStatus worker{};
    WidgetInvalidationReceiver::Status receiver{WidgetInvalidationReceiver::Status::Phase::Created, S_OK};
};

// Runs on the caller's dedicated MTA after process COM security initialization.
// The launcher owns authentication, supplies local session handles, and retains them until this function returns.
// To cancel externally, cancel BOTH the shared queue and pipe, then join the thread executing this function.
// authenticateCaller must synchronously authenticate the original COM callback caller and throw on failure.
inline WidgetHostSessionResult RunWidgetHostSession(
    std::shared_ptr<WidgetEventQueue> const& queue,
    std::shared_ptr<WidgetPipeExchange> const& authenticatedPipe,
    winrt::guid const& sessionID, HANDLE invalidationEvent, HANDLE trustedBackendProcess,
    std::function<void()> authenticateCaller, WidgetHostWorker::Report report) {
    if (!queue || !authenticatedPipe || !authenticateCaller || !report) throw winrt::hresult_invalid_argument();
    WidgetHostSessionResult result;
    // Create the publisher before handshake so a failed backend negotiation still has a withdrawal path.
    // WidgetManager construction itself can fail and remains a process-level startup error.
    WidgetPublisher publisher;
    try {
        WidgetBackendClient client(authenticatedPipe, sessionID);
        WidgetHostWorker worker(*queue, client, publisher, report);
        WidgetInvalidationReceiver receiver(worker, invalidationEvent, trustedBackendProcess);
        auto factory = winrt::make_self<WidgetClassFactory>(
            [queue, authenticate = std::move(authenticateCaller)](WidgetHostEvent event) {
                authenticate(); // Caller identity must be checked before crossing to the consumer thread.
                queue->Push(std::move(event));
            });
        std::unique_ptr<WidgetClassRegistration> registration;
        try {
            receiver.Start();
            registration = std::make_unique<WidgetClassRegistration>(factory);
            worker.Run([&receiver, &result] {
                try { receiver.StopAndJoin(); }
                catch (...) { result.receiverCleanup = winrt::to_hresult(); throw; }
            });
        } catch (...) { result.operation = winrt::to_hresult(); }
        // Retained COM interfaces capture the shared cancelled queue, never a stack frame or worker pointer.
        worker.Cancel();
        if (registration) {
            try { registration->Revoke(); }
            catch (...) { result.registrationCleanup = winrt::to_hresult(); }
            registration.reset();
        }
        try { receiver.StopAndJoin(); }
        catch (...) { result.receiverCleanup = winrt::to_hresult(); }
        result.receiver = receiver.CurrentStatus();
        result.worker = worker.StatusAfterJoin();
    } catch (...) {
        // Covers handshake/worker/receiver/factory construction before the inner run cleanup exists.
        if (SUCCEEDED(result.operation)) result.operation = winrt::to_hresult();
    }
    queue->Cancel();
    authenticatedPipe->Cancel();
    // If negotiation or collaborator construction failed before Run, terminal withdrawal never ran.
    // Reconcile OS inventory here as well so previous-process contents are not left behind on startup failure.
    if (FAILED(result.operation)) {
        try {
            auto inventory = publisher.ReadInventory();
            std::vector<winrt::hstring> ids;
            for (auto const& instance : inventory) ids.push_back(instance.id);
            auto context = publisher.BeginContext(ids);
            if (!context.withdrawalFailures.empty()) throw winrt::hresult_error(E_FAIL);
        } catch (...) {
            if (SUCCEEDED(result.worker.withdrawal)) result.worker.withdrawal = winrt::to_hresult();
        }
    }
    return result;
}
}
