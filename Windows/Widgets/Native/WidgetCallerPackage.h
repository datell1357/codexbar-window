#pragma once
#include <windows.h>
#include <appmodel.h>
#include <string>
#include <vector>
#include <winrt/base.h>
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Management.Deployment.h>
#include <winrt/Windows.Storage.h>

namespace CodexBar::Widgets {
// expectedFamily is installed policy, never a value received from the callback or bootstrap peer.
// Run after COM security initialization on the host owner apartment, before registering the provider.
inline void RequireWidgetCallerPackage(HANDLE process, std::wstring const& expectedFamily) {
    if (expectedFamily.empty() || expectedFamily.size() > 255) throw winrt::hresult_invalid_argument();
    for (auto ch : expectedFamily) {
        if (ch <= 32 || ch == 127) throw winrt::hresult_invalid_argument();
    }
    if (WaitForSingleObject(process, 0) != WAIT_TIMEOUT) throw winrt::hresult_access_denied();
    UINT32 size = 0;
    auto status = GetPackageFullName(process, &size, nullptr);
    if (status != ERROR_INSUFFICIENT_BUFFER || size < 2 || size > 512) throw winrt::hresult_access_denied();
    std::vector<wchar_t> buffer(size);
    status = GetPackageFullName(process, &size, buffer.data());
    if (status != ERROR_SUCCESS || size < 2 || size > buffer.size() || buffer[size - 1] != 0) {
        throw winrt::hresult_access_denied();
    }
    std::wstring fullName(buffer.data(), size - 1);
    if (fullName.find(L'\0') != std::wstring::npos) throw winrt::hresult_access_denied();
    std::vector<wchar_t> image(32768);
    DWORD imageSize = static_cast<DWORD>(image.size());
    winrt::check_bool(QueryFullProcessImageNameW(process, 0, image.data(), &imageSize));
    using winrt::Windows::ApplicationModel::PackageSignatureKind;
    winrt::Windows::Management::Deployment::PackageManager manager;
    std::size_t inspected = 0;
    for (auto const& package : manager.FindPackagesForUser(L"", expectedFamily)) {
        if (++inspected > 32) throw winrt::hresult_access_denied();
        auto id = package.Id();
        if (id.FullName() != fullName || id.FamilyName() != expectedFamily) continue;
        auto kind = package.SignatureKind();
        if (package.IsDevelopmentMode() ||
            (kind != PackageSignatureKind::Store && kind != PackageSignatureKind::System)) {
            throw winrt::hresult_access_denied();
        }
        auto location = package.InstalledLocation().Path();
        std::wstring prefix(location.c_str(), location.size());
        if (prefix.empty() || prefix.size() >= 32767) throw winrt::hresult_access_denied();
        if (prefix.back() != L'\\') prefix.push_back(L'\\');
        if (imageSize <= prefix.size() || CompareStringOrdinal(image.data(), static_cast<int>(prefix.size()),
            prefix.data(), static_cast<int>(prefix.size()), TRUE) != CSTR_EQUAL ||
            WaitForSingleObject(process, 0) != WAIT_TIMEOUT) throw winrt::hresult_access_denied();
        return;
    }
    throw winrt::hresult_access_denied();
}
}
