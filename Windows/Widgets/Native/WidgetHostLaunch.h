#pragma once
#include "WidgetGuid.h"
#include "WidgetActivationIdentity.h"
#include <windows.h>
#include <appmodel.h>
#include <objbase.h>
#include <sddl.h>
#include <algorithm>
#include <array>
#include <cstdint>
#include <memory>
#include <string>
#include <string_view>
#include <vector>
#include <winrt/base.h>

namespace CodexBar::Widgets {
// Externally serialized owner of one dedicated child or one authenticated OS-activated host.
// An activated peer's PID comes only from the connected kernel pipe, never from argv or a request body.
class WidgetHostLaunch final {
public:
    static std::unique_ptr<WidgetHostLaunch> Accept(DWORD timeout) {
        if (!timeout || timeout > 1000) throw winrt::hresult_invalid_argument();
        auto expected = WidgetActivationIdentity::Sibling(L"CodexBarWindows.exe", L"CodexBarWidgetHost.exe");
        auto name = WidgetActivationIdentity::PipeName();
        auto sddl = L"D:P(A;;GA;;;" + WidgetActivationIdentity::User(GetCurrentProcess()) + L")";
        PSECURITY_DESCRIPTOR descriptor = nullptr;
        winrt::check_bool(ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(), SDDL_REVISION_1,
            &descriptor, nullptr));
        struct DescriptorOwner { void* value; ~DescriptorOwner() { LocalFree(value); } } descriptorOwner{descriptor};
        SECURITY_ATTRIBUTES security{sizeof(SECURITY_ATTRIBUTES), descriptor, FALSE};
        auto raw = CreateNamedPipeW(name.c_str(), PIPE_ACCESS_OUTBOUND | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 1, 8192, 8192, 1000, &security);
        if (raw == INVALID_HANDLE_VALUE) winrt::throw_last_error();
        winrt::handle pipe{raw};
        winrt::handle completed{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
        winrt::check_bool(static_cast<bool>(completed));
        OVERLAPPED operation{};
        operation.hEvent = completed.get();
        if (!ConnectNamedPipe(pipe.get(), &operation)) {
            auto error = GetLastError();
            if (error != ERROR_PIPE_CONNECTED) {
                if (error != ERROR_IO_PENDING) winrt::throw_hresult(HRESULT_FROM_WIN32(error));
                auto waited = WaitForSingleObject(completed.get(), timeout);
                DWORD transferred = 0;
                if (waited == WAIT_TIMEOUT) {
                    CancelIoEx(pipe.get(), &operation);
                    // A connect racing the timeout may already have succeeded; keep that peer.
                    if (!GetOverlappedResult(pipe.get(), &operation, &transferred, TRUE)) {
                        auto completion = GetLastError();
                        if (completion == ERROR_OPERATION_ABORTED) return nullptr;
                        winrt::throw_hresult(HRESULT_FROM_WIN32(completion));
                    }
                } else if (waited != WAIT_OBJECT_0) {
                    auto failure = waited == WAIT_FAILED ? GetLastError() : ERROR_GEN_FAILURE;
                    CancelIoEx(pipe.get(), &operation);
                    GetOverlappedResult(pipe.get(), &operation, &transferred, TRUE);
                    winrt::throw_hresult(HRESULT_FROM_WIN32(failure));
                } else {
                    winrt::check_bool(GetOverlappedResult(pipe.get(), &operation, &transferred, FALSE));
                }
            }
        }
        ULONG clientId = 0;
        winrt::check_bool(GetNamedPipeClientProcessId(pipe.get(), &clientId));
        winrt::handle process{OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_DUP_HANDLE |
            SYNCHRONIZE | PROCESS_TERMINATE, FALSE, clientId)};
        winrt::check_bool(static_cast<bool>(process));
        auto image = WidgetActivationIdentity::PinImage(expected);
        WidgetActivationIdentity::ValidatePeer(process.get(), expected);
        ULONG currentClient = 0;
        winrt::check_bool(GetNamedPipeClientProcessId(pipe.get(), &currentClient));
        if (currentClient != GetProcessId(process.get()) || WaitForSingleObject(process.get(), 0) != WAIT_TIMEOUT) {
            throw winrt::hresult_access_denied();
        }
        // Ownership begins only after authentication. Failure above closes the channel without killing a peer.
        return std::unique_ptr<WidgetHostLaunch>(new WidgetHostLaunch(std::move(pipe), std::move(process), std::move(image)));
    }
    explicit WidgetHostLaunch(std::wstring const& hostImage) {
        auto backendImage = ImageName(GetCurrentProcess());
        auto separator = backendImage.find_last_of(L"\\/");
        if (separator == std::wstring::npos ||
            CompareStringOrdinal(backendImage.c_str() + separator + 1, -1, L"CodexBarWindows.exe", -1, TRUE) != CSTR_EQUAL) {
            throw winrt::hresult_access_denied();
        }
        auto directory = backendImage.substr(0, separator + 1);
        auto expected = directory + L"CodexBarWidgetHost.exe";
        auto supplied = hostImage;
        std::replace(supplied.begin(), supplied.end(), L'/', L'\\');
        if (hostImage.empty() || hostImage.size() > 32767 || hostImage.find(L'\0') != std::wstring::npos ||
            CompareStringOrdinal(expected.c_str(), -1, supplied.c_str(), -1, TRUE) != CSTR_EQUAL) {
            throw winrt::hresult_access_denied();
        }
        auto package = PackageName(GetCurrentProcess()); // Unpackaged launches are not supported.
        UINT32 rootSize = 0;
        if (GetCurrentPackagePath(&rootSize, nullptr) != ERROR_INSUFFICIENT_BUFFER || rootSize < 2 || rootSize > 32768) {
            throw winrt::hresult_access_denied();
        }
        std::vector<wchar_t> root(rootSize);
        winrt::check_hresult(HRESULT_FROM_WIN32(GetCurrentPackagePath(&rootSize, root.data())));
        std::wstring prefix(root.data());
        if (prefix.empty()) throw winrt::hresult_access_denied();
        if (prefix.back() != L'\\') prefix.push_back(L'\\');
        if (directory.size() < prefix.size() || CompareStringOrdinal(directory.data(), static_cast<int>(prefix.size()),
            prefix.data(), static_cast<int>(prefix.size()), TRUE) != CSTR_EQUAL) throw winrt::hresult_access_denied();

        // Pin the image against replacement from this point through child exit.
        auto image = CreateFileW(expected.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
        if (image == INVALID_HANDLE_VALUE) winrt::throw_last_error();
        image_ = winrt::handle{image};
        BY_HANDLE_FILE_INFORMATION info{};
        winrt::check_bool(GetFileInformationByHandle(image_.get(), &info));
        if (GetFileType(image_.get()) != FILE_TYPE_DISK ||
            (info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0) {
            throw winrt::hresult_access_denied();
        }
        auto client = CreateChannel();
        SECURITY_ATTRIBUTES inheritable{sizeof(SECURITY_ATTRIBUTES), nullptr, TRUE};
        winrt::handle output{CreateFileW(L"NUL", GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
            &inheritable, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr)};
        if (output.get() == INVALID_HANDLE_VALUE) winrt::throw_last_error();
        job_ = winrt::handle{CreateJobObjectW(nullptr, nullptr)};
        winrt::check_bool(static_cast<bool>(job_));
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        winrt::check_bool(SetInformationJobObject(job_.get(), JobObjectExtendedLimitInformation, &limits, sizeof(limits)));
        SIZE_T bytes = 0;
        InitializeProcThreadAttributeList(nullptr, 1, 0, &bytes);
        if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || !bytes || bytes > 65536) winrt::throw_last_error();
        std::vector<unsigned char> attributes(bytes);
        STARTUPINFOEXW startup{};
        startup.StartupInfo.cb = sizeof(startup);
        startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
        startup.StartupInfo.hStdInput = client.get();
        startup.StartupInfo.hStdOutput = output.get();
        startup.StartupInfo.hStdError = output.get();
        startup.lpAttributeList = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(attributes.data());
        winrt::check_bool(InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0, &bytes));
        struct AttributeOwner {
            LPPROC_THREAD_ATTRIBUTE_LIST value;
            ~AttributeOwner() { DeleteProcThreadAttributeList(value); }
        } attributeOwner{startup.lpAttributeList};
        HANDLE inherited[]{client.get(), output.get()};
        winrt::check_bool(UpdateProcThreadAttribute(startup.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
            inherited, sizeof(inherited), nullptr, nullptr));
        std::wstring command = L"\"" + expected + L"\" --private-bootstrap";
        auto environment = Environment();
        PROCESS_INFORMATION child{};
        winrt::check_bool(CreateProcessW(expected.c_str(), command.data(), nullptr, nullptr, TRUE,
            CREATE_SUSPENDED | EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
            environment.data(), directory.c_str(), &startup.StartupInfo, &child));
        process_ = winrt::handle{child.hProcess};
        thread_ = winrt::handle{child.hThread};
        try {
            winrt::check_bool(AssignProcessToJobObject(job_.get(), process_.get()));
            auto actual = ImageName(process_.get());
            DWORD ownSession = 0, childSession = 0;
            winrt::check_bool(ProcessIdToSessionId(GetCurrentProcessId(), &ownSession));
            winrt::check_bool(ProcessIdToSessionId(child.dwProcessId, &childSession));
            if (PackageName(process_.get()) != package || ownSession != childSession ||
                CompareStringOrdinal(actual.c_str(), -1, expected.c_str(), -1, TRUE) != CSTR_EQUAL ||
                WaitForSingleObject(process_.get(), 0) != WAIT_TIMEOUT) throw winrt::hresult_access_denied();
        } catch (...) {
            // The child has never run. A constructor failure must not leave it suspended outside its owner.
            TerminateProcess(process_.get(), ERROR_PROCESS_ABORTED);
            WaitForSingleObject(process_.get(), 5000);
            throw;
        }
    }
    WidgetHostLaunch(WidgetHostLaunch const&) = delete;
    WidgetHostLaunch& operator=(WidgetHostLaunch const&) = delete;
    HANDLE Process() const noexcept { return process_.get(); }

    void Deliver(uint8_t const* bytes, uint32_t count) {
        if (started_ || stopped_) throw winrt::hresult_illegal_method_call();
        if (!bytes || count < 17 || count > 4112 || std::string_view(reinterpret_cast<char const*>(bytes), 4) != "CBL1") {
            throw winrt::hresult_invalid_argument();
        }
        uint32_t length = 0;
        for (unsigned i = 0; i < 4; ++i) length |= uint32_t(bytes[4 + i]) << (8 * i);
        if (!length || length > 4096 || count != length + 16) throw winrt::hresult_invalid_argument();
        if (!adopted_ && ResumeThread(thread_.get()) == DWORD(-1)) winrt::throw_last_error();
        thread_ = nullptr;
        started_ = true;
        auto deadline = GetTickCount64() + 5000;
        uint32_t offset = 0;
        while (offset < count) {
            auto now = GetTickCount64();
            if (now >= deadline) winrt::throw_hresult(HRESULT_FROM_WIN32(ERROR_TIMEOUT));
            winrt::handle completed{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
            winrt::check_bool(static_cast<bool>(completed));
            OVERLAPPED operation{};
            operation.hEvent = completed.get();
            DWORD written = 0;
            if (!WriteFile(pipe_.get(), bytes + offset, count - offset, &written, &operation)) {
                auto error = GetLastError();
                if (error != ERROR_IO_PENDING) winrt::throw_hresult(HRESULT_FROM_WIN32(error));
                HANDLE waits[]{completed.get(), process_.get()};
                auto waited = WaitForMultipleObjects(2, waits, FALSE, static_cast<DWORD>(deadline - now));
                if (waited != WAIT_OBJECT_0) {
                    auto failure = waited == WAIT_TIMEOUT ? ERROR_TIMEOUT :
                        (waited == WAIT_FAILED ? GetLastError() : ERROR_BROKEN_PIPE);
                    CancelIoEx(pipe_.get(), &operation);
                    GetOverlappedResult(pipe_.get(), &operation, &written, TRUE);
                    winrt::throw_hresult(HRESULT_FROM_WIN32(failure));
                }
                winrt::check_bool(GetOverlappedResult(pipe_.get(), &operation, &written, FALSE));
            }
            if (!written) winrt::throw_hresult(HRESULT_FROM_WIN32(ERROR_BROKEN_PIPE));
            offset += written;
        }
    }
    void Stop() {
        if (stopped_) return;
        pipe_ = nullptr; // EOF requests host cancellation without injecting a message into the usage channel.
        auto waited = WaitForSingleObject(process_.get(), (started_ || adopted_) ? 10000 : 0);
        if (waited == WAIT_FAILED) winrt::throw_last_error();
        if (waited == WAIT_TIMEOUT) {
            // The OS-started host has no application-created Job. Its authenticated process handle
            // is the only termination target; the backend application is never terminated here.
            if (adopted_) winrt::check_bool(TerminateProcess(process_.get(), ERROR_PROCESS_ABORTED));
            else winrt::check_bool(TerminateJobObject(job_.get(), ERROR_PROCESS_ABORTED));
            forced_ = true;
            waited = WaitForSingleObject(process_.get(), 5000);
            if (waited == WAIT_FAILED) winrt::throw_last_error();
            if (waited != WAIT_OBJECT_0) winrt::throw_hresult(HRESULT_FROM_WIN32(ERROR_TIMEOUT));
        }
        winrt::check_bool(GetExitCodeProcess(process_.get(), &exitCode_));
        stopped_ = true;
        thread_ = nullptr;
        image_ = nullptr;
    }
    void Status(uint32_t* phase, uint32_t* exitCode, uint32_t* forced) {
        auto waited = WaitForSingleObject(process_.get(), 0);
        if (waited == WAIT_FAILED) winrt::throw_last_error();
        bool exited = waited == WAIT_OBJECT_0;
        if (exited) winrt::check_bool(GetExitCodeProcess(process_.get(), &exitCode_));
        *phase = exited ? 2 : (started_ ? 1 : 0);
        *exitCode = exited ? exitCode_ : STILL_ACTIVE;
        *forced = forced_ ? 1 : 0;
    }
private:
    WidgetHostLaunch(winrt::handle pipe, winrt::handle process, winrt::handle image) noexcept
        : image_(std::move(image)), pipe_(std::move(pipe)), process_(std::move(process)), adopted_(true) {}
    static std::vector<wchar_t> Environment() {
        // Widget rendering must not inherit provider credentials, shell hooks or DLL-search overrides.
        std::vector<std::pair<std::wstring, std::wstring>> values;
        std::array<wchar_t, 32768> buffer{};
        auto length = GetWindowsDirectoryW(buffer.data(), static_cast<UINT>(buffer.size()));
        if (!length || length >= buffer.size()) throw winrt::hresult_access_denied();
        values.emplace_back(L"SystemRoot", std::wstring(buffer.data(), length));
        values.emplace_back(L"WINDIR", std::wstring(buffer.data(), length));
        length = GetSystemDirectoryW(buffer.data(), static_cast<UINT>(buffer.size()));
        if (!length || length >= buffer.size()) throw winrt::hresult_access_denied();
        values.emplace_back(L"PATH", std::wstring(buffer.data(), length));
        for (auto name : {L"TEMP", L"TMP", L"USERPROFILE", L"LOCALAPPDATA", L"APPDATA", L"ProgramData",
                          L"ProgramFiles", L"ProgramFiles(x86)", L"ProgramW6432", L"ALLUSERSPROFILE"}) {
            SetLastError(ERROR_SUCCESS);
            auto count = GetEnvironmentVariableW(name, buffer.data(), static_cast<DWORD>(buffer.size()));
            if (!count) {
                auto error = GetLastError();
                if (error != ERROR_SUCCESS && error != ERROR_ENVVAR_NOT_FOUND) winrt::throw_hresult(HRESULT_FROM_WIN32(error));
                continue;
            }
            if (count >= buffer.size()) throw winrt::hresult_invalid_argument();
            values.emplace_back(name, std::wstring(buffer.data(), count));
        }
        std::sort(values.begin(), values.end(), [](auto const& a, auto const& b) {
            return CompareStringOrdinal(a.first.c_str(), -1, b.first.c_str(), -1, TRUE) == CSTR_LESS_THAN;
        });
        std::vector<wchar_t> block;
        for (auto const& [name, value] : values) {
            if (block.size() + name.size() + value.size() + 3 > 131072) throw winrt::hresult_invalid_argument();
            block.insert(block.end(), name.begin(), name.end());
            block.push_back(L'=');
            block.insert(block.end(), value.begin(), value.end());
            block.push_back(L'\0');
        }
        block.push_back(L'\0');
        return block;
    }
    static std::wstring ImageName(HANDLE process) {
        std::vector<wchar_t> text(32768);
        DWORD count = static_cast<DWORD>(text.size());
        winrt::check_bool(QueryFullProcessImageNameW(process, 0, text.data(), &count));
        return std::wstring(text.data(), count);
    }
    static std::wstring PackageName(HANDLE process) {
        UINT32 count = 0;
        if (GetPackageFullName(process, &count, nullptr) != ERROR_INSUFFICIENT_BUFFER || count < 2 || count > 1024) {
            throw winrt::hresult_access_denied();
        }
        std::vector<wchar_t> text(count);
        winrt::check_hresult(HRESULT_FROM_WIN32(GetPackageFullName(process, &count, text.data())));
        if (count < 2 || count > text.size() || text[count - 1] != 0) throw winrt::hresult_access_denied();
        return std::wstring(text.data(), count - 1);
    }
    winrt::handle CreateChannel() {
        HANDLE rawToken = nullptr;
        winrt::check_bool(OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &rawToken));
        winrt::handle token{rawToken};
        DWORD count = 0;
        GetTokenInformation(token.get(), TokenUser, nullptr, 0, &count);
        if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || count < sizeof(TOKEN_USER) || count > 65536) {
            throw winrt::hresult_access_denied();
        }
        std::vector<unsigned char> bytes(count);
        winrt::check_bool(GetTokenInformation(token.get(), TokenUser, bytes.data(), count, &count));
        struct LocalOwner { void* value = nullptr; ~LocalOwner() { if (value) LocalFree(value); } } sid, descriptor;
        winrt::check_bool(ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(bytes.data())->User.Sid,
            reinterpret_cast<LPWSTR*>(&sid.value)));
        std::wstring sddl = L"D:P(A;;GA;;;" + std::wstring(static_cast<wchar_t*>(sid.value)) + L")";
        winrt::check_bool(ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(), SDDL_REVISION_1,
            reinterpret_cast<PSECURITY_DESCRIPTOR*>(&descriptor.value), nullptr));
        SECURITY_ATTRIBUTES security{sizeof(SECURITY_ATTRIBUTES), descriptor.value, FALSE};
        winrt::guid nonce{};
        winrt::check_hresult(CoCreateGuid(reinterpret_cast<GUID*>(&nonce)));
        auto name = LR"(\\.\pipe\CodexBar.WidgetLaunch.)" + std::wstring(CanonicalWidgetGuid(nonce));
        auto server = CreateNamedPipeW(name.c_str(), PIPE_ACCESS_OUTBOUND | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 1, 8192, 8192, 5000, &security);
        if (server == INVALID_HANDLE_VALUE) winrt::throw_last_error();
        pipe_ = winrt::handle{server};
        SECURITY_ATTRIBUTES inheritable{sizeof(SECURITY_ATTRIBUTES), nullptr, TRUE};
        auto input = CreateFileW(name.c_str(), GENERIC_READ, 0, &inheritable, OPEN_EXISTING,
            FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, nullptr);
        if (input == INVALID_HANDLE_VALUE) winrt::throw_last_error();
        winrt::handle client{input};
        // The client was opened locally before child creation. Inheritance does not change its recorded PID.
        ULONG clientId = 0;
        winrt::check_bool(GetNamedPipeClientProcessId(pipe_.get(), &clientId));
        if (clientId != GetCurrentProcessId()) throw winrt::hresult_access_denied();
        return client;
    }
    winrt::handle image_;
    winrt::handle pipe_;
    winrt::handle job_;
    winrt::handle process_;
    winrt::handle thread_;
    bool adopted_ = false;
    bool started_ = false;
    bool stopped_ = false;
    bool forced_ = false;
    DWORD exitCode_ = STILL_ACTIVE;
};
}
