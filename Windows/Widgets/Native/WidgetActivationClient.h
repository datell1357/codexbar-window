#pragma once
#include "WidgetActivationIdentity.h"
#include <userenv.h>

namespace CodexBar::Widgets {
// Runs before COM initialization. No WinRT object is created while locating the private backend channel.
struct WidgetActivationClient {
    static winrt::handle Connect() {
        auto backend = WidgetActivationIdentity::Sibling(L"CodexBarWidgetHost.exe", L"CodexBarWindows.exe");
        auto name = WidgetActivationIdentity::PipeName();
        auto deadline = GetTickCount64() + 20000;
        StartedBackend started;
        bool attemptedStart = false;
        while (GetTickCount64() < deadline) {
            auto raw = CreateFileW(name.c_str(), GENERIC_READ, 0, nullptr, OPEN_EXISTING,
                FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, nullptr);
            if (raw != INVALID_HANDLE_VALUE) return winrt::handle{raw};
            auto error = GetLastError();
            if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND && error != ERROR_PIPE_BUSY) {
                winrt::throw_hresult(HRESULT_FROM_WIN32(error));
            }
            if (!attemptedStart && error != ERROR_PIPE_BUSY) {
                attemptedStart = true;
                started = StartBackend(backend);
            }
            if (started.process) {
                auto state = WaitForSingleObject(started.process.get(), 0);
                if (state == WAIT_FAILED) winrt::throw_last_error();
                if (state == WAIT_OBJECT_0) {
                    DWORD exitCode = 0;
                    winrt::check_bool(GetExitCodeProcess(started.process.get(), &exitCode));
                    // Occupied startup storage is not IPC success. Wait for the real authenticated peer.
                    if (exitCode != ERROR_ALREADY_EXISTS) {
                        winrt::throw_hresult(HRESULT_FROM_WIN32(exitCode ? exitCode : ERROR_PROCESS_ABORTED));
                    }
                    started.process = nullptr;
                    started.image = nullptr;
                }
            }
            Sleep(50); // Bounded discovery; bootstrap reads use the existing overlapped channel.
        }
        winrt::throw_hresult(HRESULT_FROM_WIN32(ERROR_TIMEOUT));
    }
private:
    struct StartedBackend {
        winrt::handle process;
        winrt::handle image;
    };
    static StartedBackend StartBackend(std::wstring const& executable) {
        auto image = WidgetActivationIdentity::PinImage(executable);
        HANDLE rawToken = nullptr;
        winrt::check_bool(OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY | TOKEN_DUPLICATE, &rawToken));
        winrt::handle token{rawToken};
        // Restore the user's Windows environment instead of forwarding the host's filtered environment.
        // No bootstrap data, credentials, inherited handles or shell command are sent to the app.
        void* environment = nullptr;
        winrt::check_bool(CreateEnvironmentBlock(&environment, token.get(), FALSE));
        struct EnvironmentOwner { void* value; ~EnvironmentOwner() { DestroyEnvironmentBlock(value); } } owner{environment};
        auto directory = executable.substr(0, executable.find_last_of(L"\\/"));
        std::wstring command = L"\"" + executable + L"\"";
        STARTUPINFOW startup{};
        startup.cb = sizeof(startup);
        PROCESS_INFORMATION child{};
        winrt::check_bool(CreateProcessW(executable.c_str(), command.data(), nullptr, nullptr, FALSE,
            CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW, environment, directory.c_str(), &startup, &child));
        winrt::handle thread{child.hThread};
        // WidgetLaunchChannel authenticates the real server before reading bootstrap.
        // A discovery failure never terminates the application we may have started.
        return {winrt::handle{child.hProcess}, std::move(image)};
    }
};
}
