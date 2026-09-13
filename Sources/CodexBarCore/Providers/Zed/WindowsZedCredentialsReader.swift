#if os(Windows)
import Foundation

/// Manual credentials carry their service origin; editor credentials are not read.
struct WindowsZedCredentialsReader: ZedCredentialsReading, Sendable {
    static let environmentKey = "CODEXBAR_ZED_AUTHORIZATION"
    let environment: [String: String]

    private func bundle() throws -> ZedManualCredentialInput.Bundle {
        guard let raw = CodexBarPlatformPaths.environmentValue(Self.environmentKey, environment: self.environment) else {
            throw ZedManualCredentialInput.Failure.invalidBundle
        }
        return try ZedManualCredentialInput.bundle(raw)
    }

    func settings() throws -> ZedClientSettings {
        let bundle = try self.bundle()
        return ZedClientSettings(credentialsURL: bundle.serviceURL, serverURL: bundle.serviceURL)
    }

    func loadCredentials(serviceURL: String) throws -> ZedCredentials? {
        let bundle = try self.bundle()
        guard serviceURL == bundle.serviceURL else { throw ZedStatusProbeError.untrustedServerConfiguration }
        return bundle.credentials
    }
}

/// Structural validation only; does not read credentials or contact the service.
public enum ZedManualCredentialInput {
    public static func normalizedServiceOrigin(_ raw: String) throws -> String {
        try self.bundle("1 placeholder " + raw.trimmingCharacters(in: .whitespacesAndNewlines)).serviceURL
    }

    public static func validate(_ raw: String) throws {
        _ = try self.bundle(raw)
    }

    struct Bundle {
        let credentials: ZedCredentials
        let serviceURL: String
    }

    static func parse(_ raw: String) throws -> ZedCredentials { try self.bundle(raw).credentials }

    static func bundle(_ raw: String) throws -> Bundle {
        guard raw.utf8.count <= 65536 else { throw Failure.invalidBundle }
        let fields = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: false)
        guard (fields.count == 2 || fields.count == 3), !fields[0].isEmpty, !fields[1].isEmpty,
              fields[0].utf8.allSatisfy({ (48...57).contains($0) }),
              let userID = Int(fields[0]), userID > 0,
              fields[1].utf8.allSatisfy({ (0x21...0x7E).contains($0) }) else { throw Failure.invalidBundle }
        var service = ZedStatusProbe.defaultKeychainServiceURL
        if fields.count == 3 {
            guard var origin = URLComponents(string: String(fields[2])),
                  origin.scheme?.lowercased() == "https", let host = origin.host, !host.isEmpty,
                  origin.user == nil, origin.password == nil, origin.query == nil, origin.fragment == nil,
                  origin.path.isEmpty || origin.path == "/",
                  fields[2].utf8.allSatisfy({ (0x21...0x7E).contains($0) }),
                  origin.port.map({ (1...65535).contains($0) }) ?? true else { throw Failure.invalidBundle }
            origin.scheme = "https"
            origin.host = host.lowercased()
            origin.path = ""
            guard let normalized = origin.url?.absoluteString else { throw Failure.invalidBundle }
            service = normalized
        }
        return Bundle(credentials: ZedCredentials(userID: String(userID), accessToken: String(fields[1])),
            serviceURL: service)
    }

    enum Failure: LocalizedError {
        case invalidBundle
        var errorDescription: String? {
            "Enter the numeric Zed user ID and access token separated by one space, optionally followed by an HTTPS server origin."
        }
    }
}
#endif
