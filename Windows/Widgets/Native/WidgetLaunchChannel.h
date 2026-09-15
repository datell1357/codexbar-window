#pragma once
#include "WidgetHostCancellation.h"
#include <windows.h>
#include <appmodel.h>
#include <array>
#include <atomic>
#include <cstdint>
#include <limits>
#include <string>
#include <thread>
#include <vector>
#include <winrt/base.h>

namespace CodexBar::Widgets {
// The launcher supplies one connected, overlapped, byte-mode CLIENT pipe as stdin through
// STARTUPINFOEX's handle list. No bootstrap payload, process ID or event value belongs in argv.
// Both ends must belong to the same installed package and Windows session. This process also
// requires the server's image to be the sibling CodexBarWindows.exe before reading any bytes.
class WidgetLaunchChannel final {
public:
    struct Delivery {
        std::string json;
        winrt::handle invalidation;
    };
    WidgetLaunchChannel() {
        auto input = GetStdHandle(STD_INPUT_HANDLE);
        if (!input || input == INVALID_HANDLE_VALUE) throw winrt::hresult_access_denied();
        HANDLE retained = nullptr;
        winrt::check_bool(DuplicateHandle(GetCurrentProcess(), input, GetCurrentProcess(), &retained,
            0, FALSE, DUPLICATE_SAME_ACCESS));
        pipe_ = winrt::handle{retained};
        if (GetFileType(pipe_.get()) != FILE_TYPE_PIPE) throw winrt::hresult_access_denied();
        DWORD flags = 0;
        winrt::check_bool(GetNamedPipeInfo(pipe_.get(), &flags, nullptr, nullptr, nullptr));
        if ((flags & (PIPE_SERVER_END | PIPE_TYPE_MESSAGE)) != 0) throw winrt::hresult_access_denied();
        ULONG serverId = 0;
        winrt::check_bool(GetNamedPipeServerProcessId(pipe_.get(), &serverId));
        backend_ = winrt::handle{OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, serverId)};
        winrt::check_bool(static_cast<bool>(backend_));
        DWORD ownSession = 0, serverSession = 0;
        winrt::check_bool(ProcessIdToSessionId(GetCurrentProcessId(), &ownSession));
        winrt::check_bool(ProcessIdToSessionId(serverId, &serverSession));
        if (serverSession != ownSession || PackageName(GetCurrentProcess()) != PackageName(backend_.get())) {
            throw winrt::hresult_access_denied();
        }
        auto ownImage = ImageName(GetCurrentProcess());
        auto separator = ownImage.find_last_of(L"\\/");
        if (separator == std::wstring::npos) throw winrt::hresult_access_denied();
        installedBackendImage_ = ownImage.substr(0, separator + 1) + L"CodexBarWindows.exe";
        auto serverImage = ImageName(backend_.get());
        if (CompareStringOrdinal(installedBackendImage_.c_str(), -1, serverImage.c_str(), -1, TRUE) != CSTR_EQUAL) {
            throw winrt::hresult_access_denied();
        }
        ULONG currentServer = 0;
        winrt::check_bool(GetNamedPipeServerProcessId(pipe_.get(), &currentServer));
        if (currentServer != GetProcessId(backend_.get()) || WaitForSingleObject(backend_.get(), 0) != WAIT_TIMEOUT) {
            throw winrt::hresult_access_denied();
        }
        stop_ = winrt::handle{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
        winrt::check_bool(static_cast<bool>(stop_));
    }
    WidgetLaunchChannel(WidgetLaunchChannel const&) = delete;
    WidgetLaunchChannel& operator=(WidgetLaunchChannel const&) = delete;
    ~WidgetLaunchChannel() { StopCancellation(); }

    Delivery ReadDelivery() {
        if (read_) throw winrt::hresult_illegal_method_call();
        read_ = true;
        auto deadline = GetTickCount64() + 30000;
        auto header = ReadExact(16, deadline);
        if (header.compare(0, 4, "CBL1") != 0) throw winrt::hresult_invalid_argument();
        auto length = LittleEndian(header, 4, 4);
        auto value = LittleEndian(header, 8, 8);
        if (!length || length > 4096 || !value || value >= (std::numeric_limits<std::uintptr_t>::max)()) {
            throw winrt::hresult_invalid_argument();
        }
        // Only the authenticated delivery grants ownership. The existing JSON decoder later
        // requires this independently delivered handle to equal the JSON invalidationHandle.
        winrt::handle invalidation{reinterpret_cast<HANDLE>(static_cast<std::uintptr_t>(value))};
        DWORD attributes = 0;
        winrt::check_bool(GetHandleInformation(invalidation.get(), &attributes));
        auto json = ReadExact(static_cast<std::size_t>(length), deadline);
        return {std::move(json), std::move(invalidation)};
    }

    void StartCancellation(std::shared_ptr<WidgetHostCancellation> cancellation) {
        if (!read_ || monitor_.joinable() || !cancellation) throw winrt::hresult_illegal_method_call();
        monitor_ = std::thread([this, cancellation = std::move(cancellation)] {
            try {
                char byte = 0;
                auto count = Read(&byte, 1, 0);
                // EOF is the launcher's shutdown request. No further messages are defined.
                if (count != 0) monitorStatus_.store(HRESULT_FROM_WIN32(ERROR_INVALID_DATA));
            } catch (...) {
                auto error = winrt::to_hresult();
                if (error != HRESULT_FROM_WIN32(ERROR_OPERATION_ABORTED) &&
                    error != HRESULT_FROM_WIN32(ERROR_BROKEN_PIPE)) monitorStatus_.store(error);
            }
            try { cancellation->Cancel(); }
            catch (...) { monitorStatus_.store(winrt::to_hresult()); }
        });
    }
    void StopCancellation() noexcept {
        if (!monitor_.joinable()) return;
        SetEvent(stop_.get());
        monitor_.join();
    }
    HRESULT MonitorStatusAfterJoin() const noexcept { return monitorStatus_.load(); }
    HANDLE Backend() const noexcept { return backend_.get(); }
    std::wstring const& BackendImage() const noexcept { return installedBackendImage_; }

private:
    static std::wstring PackageName(HANDLE process) {
        UINT32 count = 0;
        if (GetPackageFullName(process, &count, nullptr) != ERROR_INSUFFICIENT_BUFFER || count < 2 || count > 1024) {
            throw winrt::hresult_access_denied();
        }
        std::vector<wchar_t> text(count);
        if (GetPackageFullName(process, &count, text.data()) != ERROR_SUCCESS || count < 2 ||
            count > text.size() || text[count - 1] != 0) throw winrt::hresult_access_denied();
        return std::wstring(text.data(), count - 1);
    }
    static std::wstring ImageName(HANDLE process) {
        std::vector<wchar_t> text(32768);
        DWORD count = static_cast<DWORD>(text.size());
        winrt::check_bool(QueryFullProcessImageNameW(process, 0, text.data(), &count));
        if (!count || count >= text.size()) throw winrt::hresult_access_denied();
        return std::wstring(text.data(), count);
    }
    static std::uint64_t LittleEndian(std::string const& bytes, std::size_t offset, unsigned count) {
        std::uint64_t value = 0;
        for (unsigned i = 0; i < count; ++i) value |= std::uint64_t(static_cast<unsigned char>(bytes[offset + i])) << (8 * i);
        return value;
    }
    std::string ReadExact(std::size_t count, ULONGLONG deadline) {
        std::string result(count, '\0');
        std::size_t offset = 0;
        while (offset < count) {
            auto read = Read(result.data() + offset, static_cast<DWORD>(count - offset), deadline);
            if (!read) throw winrt::hresult_error(HRESULT_FROM_WIN32(ERROR_BROKEN_PIPE));
            offset += read;
        }
        return result;
    }
    DWORD Read(char* buffer, DWORD count, ULONGLONG deadline) {
        auto now = GetTickCount64();
        if (deadline && now >= deadline) throw winrt::hresult_error(HRESULT_FROM_WIN32(ERROR_TIMEOUT));
        winrt::handle completed{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
        winrt::check_bool(static_cast<bool>(completed));
        OVERLAPPED operation{};
        operation.hEvent = completed.get();
        DWORD received = 0;
        if (ReadFile(pipe_.get(), buffer, count, &received, &operation)) return received;
        auto error = GetLastError();
        if (error == ERROR_BROKEN_PIPE) return 0;
        if (error != ERROR_IO_PENDING) winrt::throw_hresult(HRESULT_FROM_WIN32(error));
        HANDLE waits[]{completed.get(), stop_.get(), backend_.get()};
        now = GetTickCount64();
        DWORD remaining = !deadline ? INFINITE : (now >= deadline ? 0 : static_cast<DWORD>(deadline - now));
        auto waited = WaitForMultipleObjects(3, waits, FALSE, remaining);
        if (waited != WAIT_OBJECT_0) {
            auto failure = waited == WAIT_TIMEOUT ? ERROR_TIMEOUT :
                (waited == WAIT_FAILED ? GetLastError() : ERROR_OPERATION_ABORTED);
            CancelIoEx(pipe_.get(), &operation);
            // Drain the exact operation before destroying its OVERLAPPED, buffer or event.
            GetOverlappedResult(pipe_.get(), &operation, &received, TRUE);
            winrt::throw_hresult(HRESULT_FROM_WIN32(failure));
        }
        if (!GetOverlappedResult(pipe_.get(), &operation, &received, FALSE)) {
            error = GetLastError();
            if (error == ERROR_BROKEN_PIPE) return 0;
            winrt::throw_hresult(HRESULT_FROM_WIN32(error));
        }
        return received;
    }
    winrt::handle pipe_;
    winrt::handle backend_;
    winrt::handle stop_;
    std::wstring installedBackendImage_;
    std::thread monitor_;
    std::atomic<HRESULT> monitorStatus_{S_OK};
    bool read_ = false;
};
}
