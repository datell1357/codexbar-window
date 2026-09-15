#pragma once
#include "WidgetFrame.h"
#include <atomic>
#include <functional>
#include <mutex>
#include <windows.h>

namespace CodexBar::Widgets {
// Adopts an already authenticated, connected, byte-mode pipe opened with FILE_FLAG_OVERLAPPED.
// The owner must Cancel and join callers before destruction. This class never opens an arbitrary pipe path.
class WidgetPipeExchange final {
public:
    explicit WidgetPipeExchange(winrt::handle pipe) : pipe_(std::move(pipe)) {
        if (!pipe_ || GetFileType(pipe_.get()) != FILE_TYPE_PIPE) throw winrt::hresult_invalid_argument();
        DWORD flags = 0;
        winrt::check_bool(GetNamedPipeInfo(pipe_.get(), &flags, nullptr, nullptr, nullptr));
        if ((flags & PIPE_TYPE_MESSAGE) != 0) throw winrt::hresult_invalid_argument();
        serverEnd_ = (flags & PIPE_SERVER_END) != 0;
    }
    void Cancel() noexcept {
        cancelled_.store(true);
        CancelIoEx(pipe_.get(), nullptr);
    }
    // No automatic retry: a lost response may follow a successfully committed setting change.
    std::string Exchange(std::string_view request) {
        std::scoped_lock lock(exchangeMutex_);
        if (cancelled_.load() || serverEnd_) throw winrt::hresult_illegal_method_call();
        try {
            auto deadline = GetTickCount64() + 30000;
            auto framed = EncodeWidgetFrame(request);
            WriteAll(framed, deadline);
            auto header = ReadExact(8, deadline);
            if (header.substr(0, 4) != "CBW1") throw winrt::hresult_invalid_argument();
            std::uint32_t count = 0;
            for (unsigned i = 0; i < 4; ++i) count |= std::uint32_t(static_cast<unsigned char>(header[4 + i])) << (8 * i);
            if (count == 0 || count > MaximumWidgetFramePayload) throw winrt::hresult_invalid_argument();
            return ReadExact(count, deadline);
        } catch (...) {
            Cancel();
            throw;
        }
    }
    // Dedicated server worker only. Handler must complete/cancel its Swift operation before returning.
    // There is no idle timeout; a partial frame gets a 30-second I/O deadline after its first byte.
    void ReceiveAndReply(std::function<std::string(std::string_view)> const& handler) {
        std::scoped_lock lock(exchangeMutex_);
        if (!handler || cancelled_.load() || !serverEnd_) throw winrt::hresult_illegal_method_call();
        try {
            auto header = ReadExact(1, 0);
            auto deadline = GetTickCount64() + 30000;
            header += ReadExact(7, deadline);
            if (header.substr(0, 4) != "CBW1") throw winrt::hresult_invalid_argument();
            std::uint32_t count = 0;
            for (unsigned i = 0; i < 4; ++i) count |= std::uint32_t(static_cast<unsigned char>(header[4 + i])) << (8 * i);
            if (count == 0 || count > 16 * 1024) throw winrt::hresult_invalid_argument();
            auto request = ReadExact(count, deadline);
            auto response = handler(request);
            auto framed = EncodeWidgetFrame(response);
            WriteAll(framed, deadline);
        } catch (...) {
            Cancel();
            throw;
        }
    }
private:
    DWORD Transfer(bool write, char* bytes, DWORD count, ULONGLONG deadline) {
        if (cancelled_.load()) throw winrt::hresult_error(HRESULT_FROM_WIN32(ERROR_OPERATION_ABORTED));
        if (deadline != 0 && GetTickCount64() >= deadline) throw winrt::hresult_error(HRESULT_FROM_WIN32(ERROR_TIMEOUT));
        winrt::handle event{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
        winrt::check_bool(static_cast<bool>(event));
        OVERLAPPED operation{};
        operation.hEvent = event.get();
        DWORD transferred = 0;
        BOOL completed = write
            ? WriteFile(pipe_.get(), bytes, count, &transferred, &operation)
            : ReadFile(pipe_.get(), bytes, count, &transferred, &operation);
        if (!completed) {
            DWORD error = GetLastError();
            if (error != ERROR_IO_PENDING) throw winrt::hresult_error(HRESULT_FROM_WIN32(error));
            auto now = GetTickCount64();
            DWORD wait = cancelled_.load() || (deadline != 0 && now >= deadline) ? WAIT_TIMEOUT
                : WaitForSingleObject(event.get(), deadline == 0 ? INFINITE : static_cast<DWORD>(deadline - now));
            if (wait != WAIT_OBJECT_0) {
                DWORD reason = cancelled_.load() ? ERROR_OPERATION_ABORTED
                    : wait == WAIT_TIMEOUT ? ERROR_TIMEOUT : GetLastError();
                CancelIoEx(pipe_.get(), &operation);
                // Cancellation is only a request. Keep OVERLAPPED and its buffers alive until completion.
                DWORD ignored = 0;
                GetOverlappedResult(pipe_.get(), &operation, &ignored, TRUE);
                throw winrt::hresult_error(HRESULT_FROM_WIN32(reason));
            }
            winrt::check_bool(GetOverlappedResult(pipe_.get(), &operation, &transferred, FALSE));
        }
        if (cancelled_.load()) throw winrt::hresult_error(HRESULT_FROM_WIN32(ERROR_OPERATION_ABORTED));
        if (transferred == 0 || transferred > count) throw winrt::hresult_error(HRESULT_FROM_WIN32(ERROR_BROKEN_PIPE));
        return transferred;
    }
    void WriteAll(std::string& bytes, ULONGLONG deadline) {
        std::size_t offset = 0;
        while (offset < bytes.size()) {
            offset += Transfer(true, bytes.data() + offset, static_cast<DWORD>(bytes.size() - offset), deadline);
        }
    }
    std::string ReadExact(std::size_t count, ULONGLONG deadline) {
        std::string bytes(count, '\0');
        std::size_t offset = 0;
        while (offset < count) {
            offset += Transfer(false, bytes.data() + offset, static_cast<DWORD>(count - offset), deadline);
        }
        return bytes;
    }
    winrt::handle pipe_;
    bool serverEnd_ = false;
    std::atomic_bool cancelled_{false};
    std::mutex exchangeMutex_;
};
}
