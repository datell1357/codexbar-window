#pragma once
#include <windows.h>
#include <objbase.h>
#include <vector>
#include <winrt/base.h>

namespace CodexBar::Widgets {
// Call exactly once in the dedicated native host process, after COM apartment initialization and BEFORE
// constructing any WinRT object or marshaling interfaces. A reconnect must not call this again.
// This is a process access baseline, not proof that a callback originated from the Windows Widgets host.
inline void InitializeWidgetComSecurity() {
    HANDLE rawToken = nullptr;
    winrt::check_bool(OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &rawToken));
    winrt::handle token{rawToken};
    DWORD required = 0;
    GetTokenInformation(token.get(), TokenUser, nullptr, 0, &required);
    if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || required < sizeof(TOKEN_USER) || required > 65536) {
        throw winrt::hresult_access_denied();
    }
    std::vector<unsigned char> tokenBytes(required);
    winrt::check_bool(GetTokenInformation(token.get(), TokenUser, tokenBytes.data(), required, &required));
    auto sid = reinterpret_cast<TOKEN_USER*>(tokenBytes.data())->User.Sid;
    winrt::check_bool(IsValidSid(sid));
    auto sidSize = GetLengthSid(sid);
    if (sidSize == 0 || sidSize > SECURITY_MAX_SID_SIZE) throw winrt::hresult_access_denied();
    auto aclSize = static_cast<DWORD>(sizeof(ACL) + sizeof(ACCESS_ALLOWED_ACE) - sizeof(DWORD) + sidSize);
    std::vector<unsigned char> aclBytes(aclSize);
    auto acl = reinterpret_cast<PACL>(aclBytes.data());
    winrt::check_bool(InitializeAcl(acl, aclSize, ACL_REVISION));
    winrt::check_bool(AddAccessAllowedAce(acl, ACL_REVISION, COM_RIGHTS_EXECUTE | COM_RIGHTS_EXECUTE_LOCAL, sid));
    // CoInitializeSecurity requires an absolute descriptor, not the self-relative form produced by SDDL parsing.
    SECURITY_DESCRIPTOR descriptor{};
    winrt::check_bool(InitializeSecurityDescriptor(&descriptor, SECURITY_DESCRIPTOR_REVISION));
    winrt::check_bool(SetSecurityDescriptorOwner(&descriptor, sid, FALSE));
    winrt::check_bool(SetSecurityDescriptorGroup(&descriptor, sid, FALSE));
    winrt::check_bool(SetSecurityDescriptorDacl(&descriptor, TRUE, acl, FALSE));
    winrt::check_bool(IsValidSecurityDescriptor(&descriptor));
    // Do not silently accept RPC_E_TOO_LATE: it would mean some earlier marshaling selected another policy.
    winrt::check_hresult(CoInitializeSecurity(&descriptor, -1, nullptr, nullptr,
        RPC_C_AUTHN_LEVEL_PKT_PRIVACY, RPC_C_IMP_LEVEL_IDENTIFY, nullptr, EOAC_DISABLE_AAA, nullptr));
}
}
