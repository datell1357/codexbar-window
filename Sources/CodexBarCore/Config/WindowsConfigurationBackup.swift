#if os(Windows)
import Foundation
import WinSDK

/// A config-file recovery archive for the current Windows profile, not a portable account export.
/// The whole archive is protected, including unknown extension fields and legacy plaintext tokens.
public enum WindowsConfigurationBackup {
    public enum Failure: Error {
        case invalidConfiguration, unsupportedVersion, invalidArchive, protectionUnavailable
    }

    public struct RestoredConfiguration: Sendable {
        public let backupID: UUID
        public let createdAt: Date
        /// Ready for private on-disk publication; recognized secrets have been protected again.
        public let storedData: Data
    }

    private struct Payload: Codable {
        let version: Int
        let scope: String
        let backupID: UUID
        let createdAt: Date
        let storedConfiguration: Data
    }

    public static let maximumConfigurationBytes = 32 * 1024 * 1024
    public static let maximumArchiveBytes = 48 * 1024 * 1024
    private static let magic = Data("CodexBar.Windows.ConfigBackup.v1\0".utf8)
    private static let scope = "config-file-only"

    public static func archive(storedConfiguration: Data) throws -> Data {
        // Apply the same recovery conversion before publishing an archive. A legacy plaintext
        // config can fit the input bound yet exceed the on-disk bound after secret protection.
        // Keep the original bytes in the archive; this conversion only checks the recovery contract.
        _ = try self.protectedConfiguration(storedConfiguration)
        let payload = Payload(version: 1, scope: self.scope, backupID: UUID(), createdAt: Date(),
                              storedConfiguration: storedConfiguration)
        let plaintext = try JSONEncoder().encode(payload)
        let encrypted = try self.transform(plaintext, protect: true)
        return self.magic + encrypted
    }

    public static func restore(_ archive: Data) throws -> RestoredConfiguration {
        guard archive.count <= self.maximumArchiveBytes, archive.count > self.magic.count,
              archive.starts(with: self.magic) else { throw Failure.invalidArchive }
        let plaintext = try self.transform(Data(archive.dropFirst(self.magic.count)), protect: false)
        guard let payload = try? JSONDecoder().decode(Payload.self, from: plaintext),
              payload.version == 1, payload.scope == self.scope,
              payload.createdAt.timeIntervalSince1970.isFinite else { throw Failure.invalidArchive }
        let protected = try self.protectedConfiguration(payload.storedConfiguration)
        return RestoredConfiguration(backupID: payload.backupID, createdAt: payload.createdAt,
                                     storedData: protected)
    }

    package static func protectedConfiguration(_ stored: Data) throws -> Data {
        let decoded = try self.decodedConfiguration(stored)
        let protected: Data
        do { protected = try WindowsProtectedTokenConfig.encode(decoded) }
        catch WindowsTokenAccountProtection.Failure.invalidInput { throw Failure.invalidConfiguration }
        catch WindowsProtectedTokenConfig.Failure.invalidFormat { throw Failure.invalidConfiguration }
        catch { throw Failure.protectionUnavailable }
        guard protected.count <= self.maximumConfigurationBytes else { throw Failure.invalidConfiguration }
        return protected
    }

    private static func decodedConfiguration(_ stored: Data) throws -> Data {
        guard !stored.isEmpty, stored.count <= self.maximumConfigurationBytes else {
            throw Failure.invalidConfiguration
        }
        // Inspect the declared version before attempting credential decoding. Do not normalize a
        // future schema to today's version or drop unknown providers/extension fields through Codable.
        guard let root = (try? JSONSerialization.jsonObject(with: stored)) as? [String: Any],
              let version = root["version"] as? NSNumber,
              String(cString: version.objCType) != "c",
              version.doubleValue == Double(CodexBarConfig.currentVersion) else {
            throw Failure.unsupportedVersion
        }
        guard let providers = root["providers"] as? [[String: Any]] else {
            throw Failure.invalidConfiguration
        }
        var providerIDs = Set<String>()
        for provider in providers {
            guard let id = provider["id"] as? String, ProviderInstanceID(rawValue: id) != nil,
                  providerIDs.insert(id).inserted else { throw Failure.invalidConfiguration }
        }
        do { return try WindowsProtectedTokenConfig.decode(stored) }
        catch WindowsTokenAccountProtection.Failure.protectionUnavailable { throw Failure.protectionUnavailable }
        catch { throw Failure.invalidConfiguration }
    }

    private static func transform(_ input: Data, protect: Bool) throws -> Data {
        try WindowsRecoveryProtection.transform(input, protect: protect, purpose: .configuration,
            maximumBytes: self.maximumArchiveBytes - self.magic.count)
    }
}
#endif
