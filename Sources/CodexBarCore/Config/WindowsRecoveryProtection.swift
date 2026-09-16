#if os(Windows)
import Foundation
import WinSDK

/// Domain-separated Windows-profile protection shared by the two recovery formats.
package enum WindowsRecoveryProtection {
    package enum Purpose: String {
        case configuration = "CodexBar.Windows.ConfigurationRecovery.v1"
        case localSettings = "CodexBar.Windows.LocalSettingsRecovery.v1"
        case historyManifest = "CodexBar.Windows.UsageHistoryManifest.v1"
        case historyFile = "CodexBar.Windows.UsageHistoryFile.v1"
    }
    private typealias Failure = WindowsConfigurationBackup.Failure

    package static func transform(_ input: Data, protect: Bool, purpose: Purpose, maximumBytes: Int) throws -> Data {
        let limit = maximumBytes
        guard limit > 0, limit <= 64 * 1024 * 1024,
              !input.isEmpty, input.count <= limit else { throw Failure.invalidArchive }
        // Separate purpose from provider tokens, credential caches and account-removal journals.
        let entropy = Data(purpose.rawValue.utf8)
        return try input.withUnsafeBytes { inputBytes in
            try entropy.withUnsafeBytes { entropyBytes in
                var source = DATA_BLOB()
                source.cbData = DWORD(inputBytes.count)
                source.pbData = UnsafeMutablePointer(mutating: inputBytes.bindMemory(to: BYTE.self).baseAddress)
                var binding = DATA_BLOB()
                binding.cbData = DWORD(entropyBytes.count)
                binding.pbData = UnsafeMutablePointer(mutating: entropyBytes.bindMemory(to: BYTE.self).baseAddress)
                var output = DATA_BLOB()
                let succeeded = protect
                    ? CryptProtectData(&source, nil, &binding, nil, nil, DWORD(CRYPTPROTECT_UI_FORBIDDEN), &output)
                    : CryptUnprotectData(&source, nil, &binding, nil, nil, DWORD(CRYPTPROTECT_UI_FORBIDDEN), &output)
                defer {
                    if let bytes = output.pbData {
                        // DPAPI's unprotected allocation must not outlive this copy.
                        if !protect { bytes.initialize(repeating: 0, count: Int(output.cbData)) }
                        LocalFree(HLOCAL(bytes))
                    }
                }
                guard succeeded != 0 else { throw Failure.protectionUnavailable }
                guard let bytes = output.pbData, output.cbData > 0, output.cbData <= DWORD(limit) else {
                    throw Failure.invalidArchive
                }
                return Data(bytes: bytes, count: Int(output.cbData))
            }
        }
    }
}
#endif
