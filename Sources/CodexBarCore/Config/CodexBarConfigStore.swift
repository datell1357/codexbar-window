import Foundation

public enum CodexBarConfigStoreError: LocalizedError {
    case invalidURL
    case decodeFailed(String)
    case encodeFailed(String)
    case protectedTokenUnavailable
    case protectedTokenUnsupported
    case protectedTokenMalformed
    case protectedTokenWriteFailed

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid CodexBar config path."
        case let .decodeFailed(details):
            "Failed to decode CodexBar config: \(details)"
        case let .encodeFailed(details):
            "Failed to encode CodexBar config: \(details)"
        case .protectedTokenUnavailable:
            "Could not restore Windows-protected credentials. Keep the original configuration and use the Windows user profile that saved it; if it is damaged, restore a compatible backup."
        case .protectedTokenUnsupported:
            "This configuration contains Windows-protected credentials and cannot be opened on this platform."
        case .protectedTokenMalformed:
            "The Windows-protected configuration has an invalid or unsupported format. Keep the file unchanged and restore a compatible backup or use the version that saved it."
        case .protectedTokenWriteFailed:
            "Windows could not protect the configuration credentials. The existing configuration was not replaced. Check the current Windows user profile and retry."
        }
    }
}

public struct CodexBarConfigStore: @unchecked Sendable {
    public static let pathEnvironmentKey = "CODEXBAR_CONFIG"
    public static let xdgConfigHomeEnvironmentKey = "XDG_CONFIG_HOME"

    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL = Self.defaultURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> CodexBarConfig? {
        #if os(Windows)
        let storedData: Data
        do {
            guard let loaded = try WindowsBoundedFileReader.readIfPresent(at: self.fileURL, maximumBytes: 32 * 1024 * 1024)
            else { return nil }
            storedData = loaded
        } catch WindowsBoundedFileReader.Failure.tooLarge {
            throw CodexBarConfigStoreError.decodeFailed("The Windows configuration exceeds the 32 MiB size limit.")
        }
        #else
        guard self.fileManager.fileExists(atPath: self.fileURL.path) else { return nil }
        let storedData = try Data(contentsOf: self.fileURL)
        #endif
        let data: Data
        #if os(Windows)
        do { data = try WindowsProtectedTokenConfig.decode(storedData) }
        catch WindowsTokenAccountProtection.Failure.protectionUnavailable {
            throw CodexBarConfigStoreError.protectedTokenUnavailable
        } catch WindowsProtectedTokenConfig.Failure.invalidFormat {
            throw CodexBarConfigStoreError.protectedTokenMalformed
        } catch WindowsTokenAccountProtection.Failure.invalidProtectedData {
            throw CodexBarConfigStoreError.protectedTokenMalformed
        } catch WindowsTokenAccountProtection.Failure.invalidInput {
            throw CodexBarConfigStoreError.protectedTokenMalformed
        } catch {
            // JSON parser diagnostics can include credential-bearing input fragments.
            throw CodexBarConfigStoreError.decodeFailed("Invalid configuration JSON or credential payload.")
        }
        #else
        if let root = try? JSONSerialization.jsonObject(with: storedData) as? [String: Any],
           root["windowsTokenProtectionVersion"] != nil {
            throw CodexBarConfigStoreError.protectedTokenUnsupported
        }
        data = storedData
        #endif
        let decoder = JSONDecoder()
        do {
            let decoded = try decoder.decode(CodexBarConfig.self, from: data)
            return decoded.normalized()
        } catch {
            #if os(Windows)
            // Model decoding can also include decrypted values in error descriptions.
            throw CodexBarConfigStoreError.decodeFailed("Invalid Windows configuration fields.")
            #else
            throw CodexBarConfigStoreError.decodeFailed(error.localizedDescription)
            #endif
        }
    }

    public func loadOrCreateDefault() throws -> CodexBarConfig {
        if let existing = try self.load() {
            return existing
        }
        let config = CodexBarConfig.makeDefault()
        try self.save(config)
        return config
    }

    public func save(_ config: CodexBarConfig) throws {
        let data = try self.encodedData(for: config)
        try self.saveEncodedData(data)
    }

    public func encodedData(for config: CodexBarConfig) throws -> Data {
        let normalized = config.normalized()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(normalized)
        } catch {
            throw CodexBarConfigStoreError.encodeFailed(error.localizedDescription)
        }
    }

    public func saveEncodedData(_ data: Data) throws {
        let storedData: Data
        #if os(Windows)
        // Finish every encryption before creating directories or replacing the original file.
        do {
            storedData = try WindowsProtectedTokenConfig.encode(data)
            // Encryption/base64 expansion must not publish a file the reader cannot reopen.
            guard storedData.count <= 32 * 1024 * 1024 else { throw CodexBarConfigStoreError.protectedTokenWriteFailed }
        } catch { throw CodexBarConfigStoreError.protectedTokenWriteFailed }
        #else
        let candidateRoot = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if candidateRoot?["windowsTokenProtectionVersion"] != nil {
            throw CodexBarConfigStoreError.protectedTokenUnsupported
        }
        if self.fileManager.fileExists(atPath: self.fileURL.path) {
            let existing = try Data(contentsOf: self.fileURL)
            if let root = try? JSONSerialization.jsonObject(with: existing) as? [String: Any],
               root["windowsTokenProtectionVersion"] != nil {
                throw CodexBarConfigStoreError.protectedTokenUnsupported
            }
        }
        storedData = data
        #endif
        let directory = self.fileURL.deletingLastPathComponent()
        if !self.fileManager.fileExists(atPath: directory.path) {
            try self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        #if os(Windows)
        // Encrypt first, then stage with a protected current-user DACL before writing bytes.
        try WindowsCredentialFileWriter.writePrivate(storedData, to: self.fileURL)
        #else
        try storedData.write(to: self.fileURL, options: [.atomic])
        try self.applySecurePermissionsIfNeeded()
        #endif
    }

    public func deleteIfPresent() throws {
        guard self.fileManager.fileExists(atPath: self.fileURL.path) else { return }
        try self.fileManager.removeItem(at: self.fileURL)
    }

    public static func defaultURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default) -> URL
    {
        if let override = CodexBarPlatformPaths.environmentValue(pathEnvironmentKey, environment: environment)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }

        if let xdgConfigHome = CodexBarPlatformPaths.environmentValue(xdgConfigHomeEnvironmentKey, environment: environment)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !xdgConfigHome.isEmpty
        {
            let expanded = (xdgConfigHome as NSString).expandingTildeInPath
            if (expanded as NSString).isAbsolutePath {
                return URL(fileURLWithPath: expanded, isDirectory: true)
                    .appendingPathComponent("codexbar", isDirectory: true)
                    .appendingPathComponent("config.json")
            }
        }

        #if os(Windows)
        return CodexBarPlatformPaths.codexBarDataDirectory(home: home, environment: environment)
            .appendingPathComponent("config.json")
        #else

        let xdgDefault = home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("codexbar", isDirectory: true)
            .appendingPathComponent("config.json")
        if fileManager.fileExists(atPath: xdgDefault.path) {
            return xdgDefault
        }

        let legacy = home
            .appendingPathComponent(".codexbar", isDirectory: true)
            .appendingPathComponent("config.json")
        if fileManager.fileExists(atPath: legacy.path) {
            return legacy
        }

        return xdgDefault
        #endif
    }

    private func applySecurePermissionsIfNeeded() throws {
        #if os(macOS) || os(Linux)
        try self.fileManager.setAttributes([
            .posixPermissions: NSNumber(value: Int16(0o600)),
        ], ofItemAtPath: self.fileURL.path)
        #endif
    }
}
