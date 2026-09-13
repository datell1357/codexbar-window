#if os(Windows)
import Foundation

/// Manual credentials are bound to the production Zed service; editor credentials are not read.
struct WindowsZedCredentialsReader: ZedCredentialsReading, Sendable {
    static let environmentKey = "CODEXBAR_ZED_AUTHORIZATION"
    let environment: [String: String]

    func loadCredentials(serviceURL: String) throws -> ZedCredentials? {
        guard serviceURL == ZedStatusProbe.defaultKeychainServiceURL else {
            throw ZedStatusProbeError.untrustedServerConfiguration
        }
        guard let raw = CodexBarPlatformPaths.environmentValue(Self.environmentKey, environment: self.environment) else {
            throw Failure.invalidBundle
        }
        guard raw.utf8.count <= 65536 else { throw Failure.invalidBundle }
        let fields = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: false)
        guard fields.count == 2, !fields[0].isEmpty, !fields[1].isEmpty,
              fields[0].utf8.allSatisfy({ (48...57).contains($0) }),
              let userID = UInt64(fields[0]), userID > 0,
              fields[1].utf8.allSatisfy({ (0x21...0x7E).contains($0) }) else { throw Failure.invalidBundle }
        return ZedCredentials(userID: String(userID), accessToken: String(fields[1]))
    }

    enum Failure: LocalizedError {
        case invalidBundle
        var errorDescription: String? {
            "Enter the numeric Zed user ID, one space, and the access token for the same account."
        }
    }
}
#endif
