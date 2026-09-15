#pragma once
#include "WidgetGuid.h"
#include "WidgetPipeExchange.h"
#include <memory>
#include <objbase.h>
#include <sddl.h>

namespace CodexBar::Widgets {
// One private endpoint per launched widget process. Reconnect creates a fresh endpoint/session.
class WidgetPipeListener final {
public:
    WidgetPipeListener() {
        HANDLE rawToken = nullptr;
        winrt::check_bool(OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &rawToken));
        winrt::handle token{rawToken};
        DWORD needed = 0;
        GetTokenInformation(token.get(), TokenUser, nullptr, 0, &needed);
        if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || needed < sizeof(TOKEN_USER) || needed > 65536) {
            throw winrt::hresult_access_denied();
        }
        std::vector<unsigned char> bytes(needed);
        winrt::check_bool(GetTokenInformation(token.get(), TokenUser, bytes.data(), needed, &needed));
        auto user = reinterpret_cast<TOKEN_USER*>(bytes.data());
        struct LocalAllocation { void* value = nullptr; ~LocalAllocation() { if (value) LocalFree(value); } } sid, descriptor;
        winrt::check_bool(ConvertSidToStringSidW(user->User.Sid, reinterpret_cast<LPWSTR*>(&sid.value)));
        std::wstring sddl = L"D:P(A;;GA;;;" + std::wstring(static_cast<wchar_t*>(sid.value)) + L")";
        winrt::check_bool(ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(), SDDL_REVISION_1,
            reinterpret_cast<PSECURITY_DESCRIPTOR*>(&descriptor.value), nullptr));
        SECURITY_ATTRIBUTES security{sizeof(SECURITY_ATTRIBUTES), descriptor.value, FALSE};
        winrt::guid nonce{};
        winrt::check_hresult(CoCreateGuid(reinterpret_cast<GUID*>(&nonce)));
        name_ = LR"(\\.\pipe\CodexBar.Widgets.)" + std::wstring(CanonicalWidgetGuid(nonce));
        auto raw = CreateNamedPipeW(name_.c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
            1, 65536, 65536, 30000, &security);
        if (raw == INVALID_HANDLE_VALUE) winrt::throw_last_error();
        pipe_ = winrt::handle{raw};
    }
    std::wstring const& Name() const noexcept { return name_; }
    // Use the process handle returned when launching the expected native widget provider.
    // This method runs on one worker; cancellationEvent remains alive through completion.
    std::shared_ptr<WidgetPipeExchange> Accept(HANDLE trustedClient, HANDLE cancellationEvent) {
        if (attempted_ || !trustedClient || trustedClient == INVALID_HANDLE_VALUE || !cancellationEvent) {
            throw winrt::hresult_invalid_argument();
        }
        attempted_ = true;
        try {
            if (WaitForSingleObject(trustedClient, 0) != WAIT_TIMEOUT) throw winrt::hresult_access_denied();
            auto expectedPid = GetProcessId(trustedClient);
            if (!expectedPid) winrt::throw_last_error();
            winrt::handle event{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
            winrt::check_bool(static_cast<bool>(event));
            OVERLAPPED operation{}; operation.hEvent = event.get();
            if (!ConnectNamedPipe(pipe_.get(), &operation)) {
                auto error = GetLastError();
                if (error == ERROR_IO_PENDING) {
                    HANDLE waits[]{event.get(), cancellationEvent};
                    auto wait = WaitForMultipleObjects(2, waits, FALSE, 30000);
                    if (wait != WAIT_OBJECT_0) {
                        auto reason = wait == WAIT_OBJECT_0 + 1 ? ERROR_OPERATION_ABORTED
                            : wait == WAIT_TIMEOUT ? ERROR_TIMEOUT : GetLastError();
                        CancelIoEx(pipe_.get(), &operation);
                        DWORD ignored = 0;
                        GetOverlappedResult(pipe_.get(), &operation, &ignored, TRUE);
                        throw winrt::hresult_error(HRESULT_FROM_WIN32(reason));
                    }
                    DWORD ignored = 0;
                    winrt::check_bool(GetOverlappedResult(pipe_.get(), &operation, &ignored, FALSE));
                } else if (error != ERROR_PIPE_CONNECTED) { throw winrt::hresult_error(HRESULT_FROM_WIN32(error)); }
            }
            if (WaitForSingleObject(cancellationEvent, 0) != WAIT_TIMEOUT) {
                throw winrt::hresult_error(HRESULT_FROM_WIN32(ERROR_OPERATION_ABORTED));
            }
            ULONG actualPid = 0;
            winrt::check_bool(GetNamedPipeClientProcessId(pipe_.get(), &actualPid));
            if (actualPid != expectedPid) throw winrt::hresult_access_denied();
            winrt::handle actual{OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, actualPid)};
            winrt::check_bool(static_cast<bool>(actual));
            FILETIME expectedCreated{}, actualCreated{}, exit{}, kernel{}, user{};
            winrt::check_bool(GetProcessTimes(trustedClient, &expectedCreated, &exit, &kernel, &user));
            winrt::check_bool(GetProcessTimes(actual.get(), &actualCreated, &exit, &kernel, &user));
            DWORD ownSession = 0, peerSession = 0;
            winrt::check_bool(ProcessIdToSessionId(GetCurrentProcessId(), &ownSession));
            winrt::check_bool(ProcessIdToSessionId(actualPid, &peerSession));
            if (CompareFileTime(&expectedCreated, &actualCreated) != 0 || ownSession != peerSession ||
                WaitForSingleObject(actual.get(), 0) != WAIT_TIMEOUT ||
                WaitForSingleObject(trustedClient, 0) != WAIT_TIMEOUT) throw winrt::hresult_access_denied();
            return std::make_shared<WidgetPipeExchange>(std::move(pipe_));
        } catch (...) {
            pipe_ = nullptr;
            throw;
        }
    }
private:
    winrt::handle pipe_;
    std::wstring name_;
    bool attempted_ = false;
};
}
