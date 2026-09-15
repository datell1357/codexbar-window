#pragma once
#include <windows.h>
#include <appmodel.h>
#include <bcrypt.h>
#include <sddl.h>
#include <array>
#include <string>
#include <vector>
#include <winrt/base.h>

namespace CodexBar::Widgets {
// Name discovery is not authentication. Every peer must also pass ValidatePeer on a retained handle.
struct WidgetActivationIdentity {
    static std::wstring Image(HANDLE process) {
        std::vector<wchar_t> text(32768);
        DWORD count = static_cast<DWORD>(text.size());
        winrt::check_bool(QueryFullProcessImageNameW(process, 0, text.data(), &count));
        if (!count || count >= text.size()) throw winrt::hresult_access_denied();
        return std::wstring(text.data(), count);
    }
    static std::wstring Package(HANDLE process) {
        UINT32 count = 0;
        if (GetPackageFullName(process, &count, nullptr) != ERROR_INSUFFICIENT_BUFFER || count < 2 || count > 1024) {
            throw winrt::hresult_access_denied();
        }
        std::vector<wchar_t> text(count);
        winrt::check_hresult(HRESULT_FROM_WIN32(GetPackageFullName(process, &count, text.data())));
        if (count < 2 || count > text.size() || text[count - 1] != 0) throw winrt::hresult_access_denied();
        return std::wstring(text.data(), count - 1);
    }
    static std::wstring User(HANDLE process) {
        HANDLE raw = nullptr;
        winrt::check_bool(OpenProcessToken(process, TOKEN_QUERY, &raw));
        winrt::handle token{raw};
        DWORD count = 0;
        GetTokenInformation(token.get(), TokenUser, nullptr, 0, &count);
        if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || count < sizeof(TOKEN_USER) || count > 65536) {
            throw winrt::hresult_access_denied();
        }
        std::vector<unsigned char> bytes(count);
        winrt::check_bool(GetTokenInformation(token.get(), TokenUser, bytes.data(), count, &count));
        if (count < sizeof(TOKEN_USER) || count > bytes.size()) throw winrt::hresult_access_denied();
        auto sid = reinterpret_cast<TOKEN_USER*>(bytes.data())->User.Sid;
        winrt::check_bool(IsValidSid(sid));
        LPWSTR text = nullptr;
        winrt::check_bool(ConvertSidToStringSidW(sid, &text));
        struct Owner { LPWSTR value; ~Owner() { LocalFree(value); } } owner{text};
        return text;
    }
    static DWORD Session(HANDLE process) {
        DWORD session = 0;
        winrt::check_bool(ProcessIdToSessionId(GetProcessId(process), &session));
        return session;
    }
    static std::wstring Sibling(wchar_t const* ownName, wchar_t const* siblingName) {
        auto own = Image(GetCurrentProcess());
        auto separator = own.find_last_of(L"\\/");
        if (separator == std::wstring::npos ||
            CompareStringOrdinal(own.c_str() + separator + 1, -1, ownName, -1, TRUE) != CSTR_EQUAL) {
            throw winrt::hresult_access_denied();
        }
        (void)Package(GetCurrentProcess());
        UINT32 count = 0;
        if (GetCurrentPackagePath(&count, nullptr) != ERROR_INSUFFICIENT_BUFFER || count < 2 || count > 32768) {
            throw winrt::hresult_access_denied();
        }
        std::vector<wchar_t> root(count);
        winrt::check_hresult(HRESULT_FROM_WIN32(GetCurrentPackagePath(&count, root.data())));
        if (count < 2 || count > root.size() || root[count - 1] != 0) throw winrt::hresult_access_denied();
        auto prefix = std::wstring(root.data(), count - 1);
        if (prefix.back() != L'\\') prefix.push_back(L'\\');
        auto directory = own.substr(0, separator + 1);
        if (directory.size() < prefix.size() || CompareStringOrdinal(directory.data(), static_cast<int>(prefix.size()),
            prefix.data(), static_cast<int>(prefix.size()), TRUE) != CSTR_EQUAL) throw winrt::hresult_access_denied();
        return directory + siblingName;
    }
    static void ValidatePeer(HANDLE peer, std::wstring const& expectedImage) {
        if (WaitForSingleObject(peer, 0) != WAIT_TIMEOUT || Package(peer) != Package(GetCurrentProcess()) ||
            User(peer) != User(GetCurrentProcess()) || Session(peer) != Session(GetCurrentProcess())) {
            throw winrt::hresult_access_denied();
        }
        auto actual = Image(peer);
        if (CompareStringOrdinal(expectedImage.c_str(), -1, actual.c_str(), -1, TRUE) != CSTR_EQUAL ||
            WaitForSingleObject(peer, 0) != WAIT_TIMEOUT) throw winrt::hresult_access_denied();
    }
    static winrt::handle PinImage(std::wstring const& path) {
        auto raw = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
        if (raw == INVALID_HANDLE_VALUE) winrt::throw_last_error();
        winrt::handle image{raw};
        BY_HANDLE_FILE_INFORMATION info{};
        winrt::check_bool(GetFileInformationByHandle(image.get(), &info));
        if (GetFileType(image.get()) != FILE_TYPE_DISK ||
            (info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))) {
            throw winrt::hresult_access_denied();
        }
        return image;
    }
    static std::wstring PipeName() {
        // Fixed encoding and separators; package/SID cannot contain newlines. SHA-256 bounds the name length.
        auto identity = Package(GetCurrentProcess()) + L"\n" + User(GetCurrentProcess()) + L"\n" +
            std::to_wstring(Session(GetCurrentProcess()));
        std::array<unsigned char, 32> digest{};
        auto status = BCryptHash(BCRYPT_SHA256_ALG_HANDLE, nullptr, 0,
            reinterpret_cast<PUCHAR>(identity.data()), static_cast<ULONG>(identity.size() * sizeof(wchar_t)),
            digest.data(), static_cast<ULONG>(digest.size()));
        if (status < 0) winrt::throw_hresult(HRESULT_FROM_NT(status));
        std::wstring name = LR"(\\.\pipe\CodexBar.WidgetActivation.v1.)";
        constexpr wchar_t hex[] = L"0123456789abcdef";
        for (auto byte : digest) { name.push_back(hex[byte >> 4]); name.push_back(hex[byte & 15]); }
        return name;
    }
};
}
