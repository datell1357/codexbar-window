#include "WidgetBackendABI.h"
#include "WidgetPipeListener.h"
#include "WidgetSwiftHandler.h"
#include <thread>

namespace CodexBar::Widgets {
class ServerOwner final {
public:
    ServerOwner(void* context, CBWidgetRequestHandler handler) : handler_(MakeWidgetSwiftHandler(context, handler)),
        cancellation_(CreateEventW(nullptr, TRUE, FALSE, nullptr)) {
        winrt::check_bool(static_cast<bool>(cancellation_));
    }
    ~ServerOwner() { Cancel(); Join(); }
    std::wstring const& Name() const { return listener_.Name(); }
    void Start(HANDLE trustedClient) {
        if (started_) throw winrt::hresult_illegal_method_call();
        if (!trustedClient || trustedClient == INVALID_HANDLE_VALUE) throw winrt::hresult_invalid_argument();
        HANDLE raw = nullptr;
        winrt::check_bool(DuplicateHandle(GetCurrentProcess(), trustedClient, GetCurrentProcess(), &raw,
            PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, 0));
        winrt::handle client{raw};
        started_ = true;
        phase_.store(1);
        try {
            worker_ = std::thread([this, client = std::move(client)] {
                bool apartment = false;
                HRESULT outcome = S_OK;
                try {
                    winrt::init_apartment(winrt::apartment_type::multi_threaded); apartment = true;
                    auto pipe = listener_.Accept(client.get(), cancellation_.get());
                    auto server = std::make_shared<WidgetBackendServer>(pipe, handler_);
                    {
                        std::scoped_lock lock(mutex_);
                        server_ = server;
                        if (cancelled_.load()) server->Cancel();
                    }
                    server->Run();
                } catch (...) {
                    outcome = cancelled_.load() ? S_OK : winrt::to_hresult();
                }
                { std::scoped_lock lock(mutex_); server_.reset(); }
                client = nullptr;
                if (apartment) winrt::uninit_apartment();
                // Terminal means handler/server/COM cleanup has completed. Join is still required
                // before releasing the callback context or unloading the DLL containing this thread.
                result_.store(outcome);
                phase_.store(FAILED(outcome) ? 3 : 2);
            });
        } catch (...) {
            result_.store(winrt::to_hresult()); phase_.store(3);
            throw;
        }
    }
    void Cancel() {
        cancelled_.store(true);
        SetEvent(cancellation_.get());
        std::scoped_lock lock(mutex_);
        if (server_) server_->Cancel();
    }
    void Join() {
        if (worker_.joinable()) {
            if (worker_.get_id() == std::this_thread::get_id()) throw winrt::hresult_illegal_method_call();
            worker_.join();
        }
    }
    void Status(uint32_t* phase, int32_t* result) {
        // Read phase first; a terminal phase is stored only after its result has been recorded.
        *phase = phase_.load(); *result = result_.load();
    }
private:
    WidgetBackendServer::Handler handler_;
    WidgetPipeListener listener_;
    winrt::handle cancellation_;
    std::thread worker_;
    std::mutex mutex_;
    std::shared_ptr<WidgetBackendServer> server_;
    bool started_ = false;
    std::atomic_bool cancelled_{false};
    std::atomic<uint32_t> phase_{0}; // 0 created, 1 waiting/running, 2 stopped, 3 failed
    std::atomic<int32_t> result_{S_OK};
};
}
using CodexBar::Widgets::ServerOwner;

extern "C" uint32_t CBWidgetBackendABIVersion(void) { return 1; }

extern "C" int32_t CBWidgetServerCreate(void* context, CBWidgetRequestHandler handler, void** server) {
    if (!server) return E_POINTER;
    *server = nullptr;
    try { *server = new ServerOwner(context, handler); return S_OK; } catch (...) { return winrt::to_hresult(); }
}
extern "C" int32_t CBWidgetServerName(void* server, uint16_t* buffer, uint32_t capacity, uint32_t* required) {
    if (!server || !required) return E_POINTER;
    try {
        auto const& name = static_cast<ServerOwner*>(server)->Name();
        *required = static_cast<uint32_t>(name.size() + 1);
        if (!buffer || capacity < *required) return HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER);
        for (std::size_t i = 0; i < name.size(); ++i) buffer[i] = static_cast<uint16_t>(name[i]);
        buffer[name.size()] = 0;
        return S_OK;
    } catch (...) { return winrt::to_hresult(); }
}
extern "C" int32_t CBWidgetServerStart(void* server, void* client) {
    if (!server) return E_POINTER;
    try { static_cast<ServerOwner*>(server)->Start(client); return S_OK; } catch (...) { return winrt::to_hresult(); }
}
extern "C" int32_t CBWidgetServerCancel(void* server) {
    if (!server) return E_POINTER;
    try { static_cast<ServerOwner*>(server)->Cancel(); return S_OK; } catch (...) { return winrt::to_hresult(); }
}
extern "C" int32_t CBWidgetServerJoin(void* server) {
    if (!server) return E_POINTER;
    try { static_cast<ServerOwner*>(server)->Join(); return S_OK; } catch (...) { return winrt::to_hresult(); }
}
extern "C" int32_t CBWidgetServerStatus(void* server, uint32_t* phase, int32_t* result) {
    if (!server || !phase || !result) return E_POINTER;
    static_cast<ServerOwner*>(server)->Status(phase, result); return S_OK;
}
extern "C" int32_t CBWidgetServerDestroy(void* server) {
    if (!server) return S_OK;
    try {
        auto owner = static_cast<ServerOwner*>(server);
        owner->Cancel(); owner->Join(); delete owner; return S_OK;
    } catch (...) { return winrt::to_hresult(); }
}
