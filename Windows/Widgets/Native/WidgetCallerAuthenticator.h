#pragma once
#include "WidgetCallerPackage.h"
#include <windows.h>
#include <rpc.h>
#include <rpcasync.h>
#include <winrt/base.h>
#include <cstdint>
#include <functional>
#include <limits>
#include <memory>
#include <vector>

#pragma comment(lib, "Rpcrt4.lib")

namespace CodexBar::Widgets {
// These handles must come from independent launcher package/image trust checks, never callback data.
// Retaining an alive process object prevents accepting a recycled PID as the trusted process.
class WidgetCallerAuthenticator final {
public:
    explicit WidgetCallerAuthenticator(std::vector<HANDLE> const& trustedCallers) {
        if (trustedCallers.empty() || trustedCallers.size() > 8) throw winrt::hresult_invalid_argument();
        DWORD ownSession = 0;
        winrt::check_bool(ProcessIdToSessionId(GetCurrentProcessId(), &ownSession));
        for (auto source : trustedCallers) {
            if (!source || source == INVALID_HANDLE_VALUE) throw winrt::hresult_invalid_argument();
            HANDLE raw = nullptr;
            winrt::check_bool(DuplicateHandle(GetCurrentProcess(), source, GetCurrentProcess(), &raw,
                PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, 0));
            winrt::handle process{raw};
            auto pid = GetProcessId(process.get());
            DWORD session = 0;
            if (!pid || !ProcessIdToSessionId(pid, &session) || session != ownSession ||
                WaitForSingleObject(process.get(), 0) != WAIT_TIMEOUT) throw winrt::hresult_access_denied();
            for (auto const& entry : callers_) {
                if (entry.pid == pid) throw winrt::hresult_invalid_argument();
            }
            callers_.push_back({std::move(process), pid});
        }
    }

    void ValidateInstalledPackages(std::wstring const& expectedFamily) const {
        for (auto const& entry : callers_) RequireWidgetCallerPackage(entry.process.get(), expectedFamily);
    }

    // Must execute synchronously on the original COM callback thread before queueing copied event data.
    // No RPC context, unknown locality, unsupported transport, or departed caller always rejects.
    void Authenticate() const {
        RPC_CALL_ATTRIBUTES_V2_W attributes{};
        attributes.Version = 2;
        attributes.Flags = RPC_QUERY_CLIENT_PID;
        auto status = RpcServerInqCallAttributesW(nullptr, &attributes);
        if (status != RPC_S_OK) winrt::throw_hresult(HRESULT_FROM_WIN32(status));
        if (attributes.IsClientLocal != rcclLocal || attributes.NullSession || attributes.KernelModeCaller ||
            attributes.AuthenticationLevel < RPC_C_AUTHN_LEVEL_PKT_PRIVACY) throw winrt::hresult_access_denied();
        // ClientPID is an integer encoded in HANDLE, not an owned handle; never CloseHandle it.
        auto value = reinterpret_cast<std::uintptr_t>(attributes.ClientPID);
        if (!value || value > (std::numeric_limits<DWORD>::max)()) throw winrt::hresult_access_denied();
        for (auto const& entry : callers_) {
            if (entry.pid == static_cast<DWORD>(value) &&
                WaitForSingleObject(entry.process.get(), 0) == WAIT_TIMEOUT) return;
        }
        throw winrt::hresult_access_denied();
    }

private:
    struct Caller { winrt::handle process; DWORD pid; };
    std::vector<Caller> callers_;
};

inline std::function<void()> MakeWidgetCallerAuthentication(std::vector<HANDLE> const& trustedCallers) {
    auto authenticator = std::make_shared<WidgetCallerAuthenticator>(trustedCallers);
    return [authenticator] { authenticator->Authenticate(); };
}
}
