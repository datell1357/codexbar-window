#if os(Windows)
import Foundation
import WinSDK

/// Reads only the exact generic credential used by the Zed editor; never enumerates the vault.
/// Upstream: gpui_windows/src/util.rs and platform.rs (windows_credentials_target_name/read_credentials).
struct WindowsZedEditorCredentialsReader: ZedCredentialsReading, Sendable {
    func loadCredentials(serviceURL: String) throws -> ZedCredentials? {
        try Task.checkCancellation()
        let scope = try ZedManualCredentialInput.bundle("1 placeholder " + serviceURL)
        guard scope.serviceURL == serviceURL else { throw ZedStatusProbeError.untrustedServerConfiguration }
        let target = Array(("zed:url=" + serviceURL).utf16) + [0]
        var credential: UnsafeMutablePointer<CREDENTIALW>?
        let read = target.withUnsafeBufferPointer {
            CredReadW($0.baseAddress, DWORD(CRED_TYPE_GENERIC), 0, &credential)
        }
        guard read != 0 else {
            if GetLastError() == DWORD(ERROR_NOT_FOUND) { return nil }
            throw Failure.unavailable
        }
        guard let credential else { throw Failure.unavailable }
        defer { CredFree(UnsafeMutableRawPointer(credential)) }
        try Task.checkCancellation()
        let value = credential.pointee
        guard value.Type == DWORD(CRED_TYPE_GENERIC),
              let username = value.UserName, let blob = value.CredentialBlob,
              value.CredentialBlobSize > 0, value.CredentialBlobSize <= 65536 else { throw Failure.invalid }
        var units: [UInt16] = []
        var terminated = false
        for index in 0..<513 {
            let unit = username[index]
            if unit == 0 { terminated = true; break }
            units.append(unit)
        }
        guard terminated, !units.isEmpty,
              let token = String(data: Data(bytes: blob, count: Int(value.CredentialBlobSize)), encoding: .utf8)
        else { throw Failure.invalid }
        let userID = String(decoding: units, as: UTF16.self)
        let parsed = try ZedManualCredentialInput.bundle(userID + " " + token + " " + serviceURL)
        try Task.checkCancellation()
        return parsed.credentials
    }

    enum Failure: LocalizedError {
        case unavailable, invalid
        var errorDescription: String? {
            switch self {
            case .unavailable: "The Zed editor credential could not be read from Windows Credential Manager."
            case .invalid: "The stored Zed editor credential has an unsupported format. Sign in to Zed again."
            }
        }
    }
}
#endif
