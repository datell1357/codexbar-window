#pragma once
#include "WidgetPipeExchange.h"
#include <memory>
#include <string_view>
#include <vector>

namespace CodexBar::Widgets {
// trustedBackendProcess must originate from the application's launcher or authenticated discovery.
// A PID/path read from the pipe itself is not an acceptable trust anchor.
inline std::shared_ptr<WidgetPipeExchange> ConnectWidgetBackend(std::wstring const& pipeName,
    HANDLE trustedBackendProcess, std::wstring const& expectedImagePath) {
    constexpr std::wstring_view prefix = LR"(\\.\pipe\CodexBar.Widgets.)";
    if (pipeName.size() <= prefix.size() || pipeName.size() > 256 ||
        pipeName.compare(0, prefix.size(), prefix) != 0 || !trustedBackendProcess ||
        trustedBackendProcess == INVALID_HANDLE_VALUE || expectedImagePath.empty() ||
        expectedImagePath.size() > 32767 || expectedImagePath.find(L'\0') != std::wstring::npos) {
        throw winrt::hresult_invalid_argument();
    }
    for (std::size_t i = prefix.size(); i < pipeName.size(); ++i) {
        auto ch = pipeName[i];
        if (!((ch >= L'0' && ch <= L'9') || (ch >= L'a' && ch <= L'f') || ch == L'-')) {
            throw winrt::hresult_invalid_argument();
        }
    }
    if (WaitForSingleObject(trustedBackendProcess, 0) != WAIT_TIMEOUT) throw winrt::hresult_access_denied();
    auto expectedPid = GetProcessId(trustedBackendProcess);
    if (expectedPid == 0) winrt::throw_last_error();
    FILETIME expectedCreated{}, exited{}, kernel{}, user{};
    winrt::check_bool(GetProcessTimes(trustedBackendProcess, &expectedCreated, &exited, &kernel, &user));
    // Identification permits identity checks without granting the server impersonation of this client.
    winrt::handle pipe{CreateFileW(pipeName.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
        OPEN_EXISTING, FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, nullptr)};
    if (pipe.get() == INVALID_HANDLE_VALUE) winrt::throw_last_error();
    ULONG serverPid = 0;
    winrt::check_bool(GetNamedPipeServerProcessId(pipe.get(), &serverPid));
    if (serverPid != expectedPid) throw winrt::hresult_access_denied();
    winrt::handle server{OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, serverPid)};
    winrt::check_bool(static_cast<bool>(server));
    FILETIME actualCreated{};
    winrt::check_bool(GetProcessTimes(server.get(), &actualCreated, &exited, &kernel, &user));
    if (CompareFileTime(&expectedCreated, &actualCreated) != 0) throw winrt::hresult_access_denied();
    DWORD serverSession = 0, ownSession = 0;
    winrt::check_bool(ProcessIdToSessionId(serverPid, &serverSession));
    winrt::check_bool(ProcessIdToSessionId(GetCurrentProcessId(), &ownSession));
    if (serverSession != ownSession) throw winrt::hresult_access_denied();
    std::vector<wchar_t> image(32768);
    DWORD length = static_cast<DWORD>(image.size());
    winrt::check_bool(QueryFullProcessImageNameW(server.get(), 0, image.data(), &length));
    if (CompareStringOrdinal(image.data(), static_cast<int>(length), expectedImagePath.data(),
        static_cast<int>(expectedImagePath.size()), TRUE) != CSTR_EQUAL) throw winrt::hresult_access_denied();
    ULONG checkedPid = 0;
    winrt::check_bool(GetNamedPipeServerProcessId(pipe.get(), &checkedPid));
    if (checkedPid != expectedPid || WaitForSingleObject(server.get(), 0) != WAIT_TIMEOUT ||
        WaitForSingleObject(trustedBackendProcess, 0) != WAIT_TIMEOUT) throw winrt::hresult_access_denied();
    return std::make_shared<WidgetPipeExchange>(std::move(pipe));
}
}
