#if os(Windows)
import Foundation
import WinSDK

/// User-scoped DPAPI codec. This type does not access files, mutate config or migrate legacy tokens.
public enum WindowsTokenAccountProtection {
    public enum Failure: Error {
        case invalidInput
        case protectionUnavailable
        case invalidProtectedData
    }
    private struct Payload: Codable {
        let version: Int
        let providerID: String
        let accountID: UUID
        let token: String
    }
    private static let maximumTokenBytes = 65_536
    private static let maximumEnvelopeBytes = 524_288

    public static func protect(token: String, providerID: ProviderInstanceID, accountID: UUID) throws -> Data {
        guard !token.isEmpty, token.utf8.count <= Self.maximumTokenBytes, !token.contains("\0") else {
            throw Failure.invalidInput
        }
        let payload = Payload(version: 1, providerID: providerID.rawValue, accountID: accountID, token: token)
        let input = try JSONEncoder().encode(payload)
        return try Self.transform(input, providerID: providerID, accountID: accountID, protect: true)
    }

    public static func unprotect(_ encrypted: Data, providerID: ProviderInstanceID, accountID: UUID) throws -> String {
        let plaintext = try Self.transform(encrypted, providerID: providerID, accountID: accountID, protect: false)
        guard let payload = try? JSONDecoder().decode(Payload.self, from: plaintext),
              payload.version == 1, payload.providerID == providerID.rawValue, payload.accountID == accountID,
              !payload.token.isEmpty, payload.token.utf8.count <= Self.maximumTokenBytes,
              !payload.token.contains("\0") else { throw Failure.invalidProtectedData }
        return payload.token
    }

    /// Separate DPAPI purpose for already-confirmed account-removal recovery records.
    public static func removalRecoveryPayload(_ data: Data, accountID: UUID, protect: Bool) throws -> Data {
        try Self.transform(data, providerID: UsageProvider.antigravity.instanceID, accountID: accountID,
                           protect: protect, purpose: "AccountRemovalRecovery.v1")
    }

    static func providerFields(_ data: Data, providerID: ProviderInstanceID, protect: Bool) throws -> Data {
        // A separate purpose prevents a provider bundle from being substituted for an account token.
        let scopeID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        return try Self.transform(data, providerID: providerID, accountID: scopeID,
                                  protect: protect, purpose: "ProviderSecrets.v1")
    }

    private static func transform(_ input: Data, providerID: ProviderInstanceID, accountID: UUID,
                                  protect: Bool, purpose: String = "TokenAccount.v1") throws -> Data {
        guard !input.isEmpty, input.count <= Self.maximumEnvelopeBytes,
              !providerID.rawValue.isEmpty, providerID.rawValue.utf8.count <= 512,
              !providerID.rawValue.contains("\0") else { throw Failure.invalidInput }
        // Domain separation only: entropy is not a secret and must be reproduced exactly.
        let entropy = Data(("CodexBar.Windows." + purpose + "\0" + providerID.rawValue + "\0" +
                            accountID.uuidString.lowercased()).utf8)
        return try input.withUnsafeBytes { inputBytes in
            try entropy.withUnsafeBytes { entropyBytes in
                var source = DATA_BLOB()
                source.cbData = DWORD(inputBytes.count)
                source.pbData = UnsafeMutablePointer(mutating: inputBytes.bindMemory(to: BYTE.self).baseAddress)
                var binding = DATA_BLOB()
                binding.cbData = DWORD(entropyBytes.count)
                binding.pbData = UnsafeMutablePointer(mutating: entropyBytes.bindMemory(to: BYTE.self).baseAddress)
                var output = DATA_BLOB()
                // No machine-wide flag and no UI prompts. Failures never fall back to plaintext.
                let succeeded = protect
                    ? CryptProtectData(&source, nil, &binding, nil, nil, DWORD(CRYPTPROTECT_UI_FORBIDDEN), &output)
                    : CryptUnprotectData(&source, nil, &binding, nil, nil, DWORD(CRYPTPROTECT_UI_FORBIDDEN), &output)
                defer { if let bytes = output.pbData { LocalFree(HLOCAL(bytes)) } }
                guard succeeded != 0 else { throw Failure.protectionUnavailable }
                guard let bytes = output.pbData, output.cbData > 0,
                      output.cbData <= DWORD(Self.maximumEnvelopeBytes) else { throw Failure.invalidProtectedData }
                return Data(bytes: bytes, count: Int(output.cbData))
            }
        }
    }
}
#endif
