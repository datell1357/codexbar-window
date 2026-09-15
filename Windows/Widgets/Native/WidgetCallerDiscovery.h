#pragma once
#include "WidgetCallerPackage.h"
#include <tlhelp32.h>
#include <algorithm>

namespace CodexBar::Widgets {
// Policy values must be bundled/validated installation configuration, not command or callback data.
inline std::vector<winrt::handle> DiscoverWidgetCallers(std::wstring const& packageFamily,
    std::vector<std::wstring> const& executableNames) {
    if (executableNames.empty() || executableNames.size() > 8) throw winrt::hresult_invalid_argument();
    for (auto const& name : executableNames) {
        if (name.empty() || name.size() > 255 || name.find_first_of(L"\\/:*?\"<>|") != std::wstring::npos) {
            throw winrt::hresult_invalid_argument();
        }
        for (auto ch : name) if (ch <= 32 || ch == 127) throw winrt::hresult_invalid_argument();
    }
    auto allowed = [&](std::wstring const& name) {
        return std::any_of(executableNames.begin(), executableNames.end(), [&](auto const& expected) {
            return CompareStringOrdinal(name.c_str(), -1, expected.c_str(), -1, TRUE) == CSTR_EQUAL;
        });
    };
    DWORD ownSession = 0;
    winrt::check_bool(ProcessIdToSessionId(GetCurrentProcessId(), &ownSession));
    auto raw = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (raw == INVALID_HANDLE_VALUE) winrt::throw_last_error();
    winrt::handle snapshot{raw};
    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    std::vector<winrt::handle> result;
    std::size_t inspected = 0;
    BOOL found = Process32FirstW(snapshot.get(), &entry);
    while (found) {
        if (++inspected > 16384) throw winrt::hresult_access_denied();
        if (allowed(entry.szExeFile)) {
            winrt::handle process{OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE,
                FALSE, entry.th32ProcessID)};
            if (process) {
                DWORD session = 0;
                if (ProcessIdToSessionId(GetProcessId(process.get()), &session) && session == ownSession) {
                    try {
                        RequireWidgetCallerPackage(process.get(), packageFamily);
                        std::vector<wchar_t> path(32768);
                        DWORD size = static_cast<DWORD>(path.size());
                        winrt::check_bool(QueryFullProcessImageNameW(process.get(), 0, path.data(), &size));
                        std::wstring image(path.data(), size);
                        auto separator = image.find_last_of(L"\\/");
                        auto name = image.substr(separator == std::wstring::npos ? 0 : separator + 1);
                        if (allowed(name) && WaitForSingleObject(process.get(), 0) == WAIT_TIMEOUT) {
                            if (result.size() >= 8) throw winrt::hresult_error(HRESULT_FROM_WIN32(ERROR_TOO_MANY_CMDS));
                            result.push_back(std::move(process));
                        }
                    } catch (winrt::hresult_access_denied const&) {
                        // Matching filenames from other packages are not trusted candidates.
                    }
                }
            }
        }
        found = Process32NextW(snapshot.get(), &entry);
    }
    auto error = GetLastError();
    if (error != ERROR_NO_MORE_FILES) winrt::throw_hresult(HRESULT_FROM_WIN32(error));
    if (result.empty()) throw winrt::hresult_access_denied();
    return result;
}
}
