#if os(Windows)
import CodexBarCore
import Foundation
import WinSDK
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public struct WindowsPluginReplacementReview: Sendable {
    let token: UUID
    let instanceID: ProviderInstanceID
    let name: String
    let previousHash: String?
    let replacementHash: String
    let restoringBackup: Bool
}

public enum WindowsPluginReplacementFailure: String, Error, Sendable {
    case changed, formatMismatch, stateChangedBeforeFailure, reinstallStateChangedBeforeFailure
    case destinationExists, unavailable, busy, invalidBackup
    var localizationKey: String { "plugin_replace_" + self.rawValue }
    static func classify(_ error: Error) -> Self {
        if let failure = error as? Self { return failure }
        if let failure = error as? WindowsPluginInstallFailure, failure == .busy { return .busy }
        return .unavailable
    }
}

enum WindowsPluginReplacementOutcome: Sendable { case replaced, reinstalled, restoredBackup }

struct WindowsPluginReplacementPlan: Sendable {
    let review: WindowsPluginReplacementReview
    let destination: URL
    private let replacement: Data

    static func prepare(source: URL, installed: UserProviderPlugin) throws -> Self {
        guard source.pathExtension.lowercased() == installed.fileURL.pathExtension.lowercased() else {
            throw WindowsPluginReplacementFailure.formatMismatch
        }
        return try self.prepare(source: source, instanceID: installed.manifest.id,
            destination: installed.fileURL, previousHash: installed.sourceHash)
    }

    static func prepareReinstallation(source: URL, instanceID: ProviderInstanceID) throws -> Self {
        let destination = UserProviderPluginLoader.defaultProvidersDirectory.appendingPathComponent(source.lastPathComponent)
        return try self.prepare(source: source, instanceID: instanceID, destination: destination, previousHash: nil)
    }

    static var backupDirectory: URL {
        UserProviderPluginLoader.defaultProvidersDirectory.appendingPathComponent(".backups", isDirectory: true)
    }

    static func prepareBackupRestoration(source: URL) throws -> Self {
        guard source.isFileURL else { throw WindowsPluginReplacementFailure.invalidBackup }
        let source = source.standardizedFileURL
        let generation = source.deletingLastPathComponent()
        guard !source.path.contains("\0"), UUID(uuidString: generation.lastPathComponent) != nil,
              generation.deletingLastPathComponent() == self.backupDirectory.standardizedFileURL else {
            throw WindowsPluginReplacementFailure.invalidBackup
        }
        // Only direct source files in one of our backup generations; do not follow junctions or links.
        for (url, isDirectory) in [(self.backupDirectory, true), (generation, true), (source, false)] {
            let attributes = url.path.withCString(encodedAs: UTF16.self) { GetFileAttributesW($0) }
            guard attributes != DWORD(INVALID_FILE_ATTRIBUTES),
                  attributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) == 0,
                  (attributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0) == isDirectory else {
                throw WindowsPluginReplacementFailure.invalidBackup
            }
        }
        return try self.withCandidate(source: source) { candidate, bytes in
            let installed = UserProviderPluginLoader().discover().compactMap(\.plugin)
                .first { $0.manifest.id == candidate.manifest.id }
            if let installed, source.pathExtension.lowercased() != installed.fileURL.pathExtension.lowercased() {
                throw WindowsPluginReplacementFailure.formatMismatch
            }
            let destination = installed?.fileURL ?? UserProviderPluginLoader.defaultProvidersDirectory
                .appendingPathComponent(source.lastPathComponent)
            return try self.makePlan(candidate: candidate, bytes: bytes, destination: destination,
                previousHash: installed?.sourceHash, restoringBackup: true)
        }
    }

    private static func prepare(source: URL, instanceID: ProviderInstanceID,
                                destination: URL, previousHash: String?) throws -> Self {
        try self.withCandidate(source: source) { candidate, bytes in
            guard candidate.manifest.id == instanceID else { throw WindowsPluginReplacementFailure.changed }
            return try self.makePlan(candidate: candidate, bytes: bytes, destination: destination,
                previousHash: previousHash, restoringBackup: false)
        }
    }

    /// The same private staged bytes supply the manifest, review hash and eventual installed source.
    private static func withCandidate<T>(source: URL, body: (UserProviderPlugin, Data) throws -> T) throws -> T {
        let bytes = try WindowsPluginInstaller.readSource(source)
        return try WindowsPluginInstaller.withInstallationLock {
            let temporary = UserProviderPluginLoader.defaultProvidersDirectory
                .appendingPathComponent(".review-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let staged = temporary.appendingPathComponent("replacement." + source.pathExtension.lowercased())
            try WindowsCredentialFileWriter.writePrivate(bytes, to: staged)
            let candidate = try UserProviderPluginLoader(cacheDirectory: temporary.appendingPathComponent("cache", isDirectory: true))
                .load(fileURL: staged)
            guard candidate.sourceHash == self.hash(bytes) else { throw WindowsPluginReplacementFailure.changed }
            return try body(candidate, bytes)
        }
    }

    /// Must run under the installation lock, after loading the frozen candidate.
    private static func makePlan(candidate: UserProviderPlugin, bytes: Data, destination: URL,
                                 previousHash: String?, restoringBackup: Bool) throws -> Self {
        let directory = UserProviderPluginLoader.defaultProvidersDirectory.standardizedFileURL
        guard candidate.manifest.id.firstPartyProvider == nil,
              destination.deletingLastPathComponent().standardizedFileURL == directory else {
            throw WindowsPluginReplacementFailure.changed
        }
        if let previousHash {
            let current = try WindowsPluginInstaller.readSource(destination)
            guard self.hash(current) == previousHash else { throw WindowsPluginReplacementFailure.changed }
        } else {
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw WindowsPluginReplacementFailure.destinationExists
            }
            guard !UserProviderPluginLoader().discover().contains(where: { $0.instanceID == candidate.manifest.id }) else {
                throw WindowsPluginReplacementFailure.changed
            }
        }
        let review = WindowsPluginReplacementReview(token: UUID(), instanceID: candidate.manifest.id,
            name: candidate.manifest.name, previousHash: previousHash, replacementHash: candidate.sourceHash,
            restoringBackup: restoringBackup)
        return Self(review: review, destination: destination, replacement: bytes)
    }

    /// Called only after explicit review acceptance. beforePublish disables usage and revokes permissions.
    /// A present source is backed up; absent destinations are published with a non-replacing move.
    func commit(beforePublish: () throws -> Void) throws -> URL? {
        try WindowsPluginInstaller.withInstallationLock {
            guard Self.hash(self.replacement) == self.review.replacementHash else {
                throw WindowsPluginReplacementFailure.changed
            }
            if let previousHash = self.review.previousHash {
                let current = try WindowsPluginInstaller.readSource(self.destination)
                guard Self.hash(current) == previousHash else { throw WindowsPluginReplacementFailure.changed }
                let backup = Self.backupDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    .appendingPathComponent(self.destination.lastPathComponent)
                try WindowsCredentialFileWriter.writePrivate(current, to: backup)
                try beforePublish()
                try WindowsCredentialFileWriter.writePrivate(self.replacement, to: self.destination, beforePublish: { _ in
                    let latest = try WindowsPluginInstaller.readSource(self.destination)
                    guard Self.hash(latest) == previousHash else { throw WindowsPluginReplacementFailure.changed }
                })
                return backup
            }
            let fm = FileManager.default
            guard !fm.fileExists(atPath: self.destination.path) else { throw WindowsPluginReplacementFailure.destinationExists }
            guard !UserProviderPluginLoader().discover().contains(where: { $0.instanceID == self.review.instanceID }) else {
                throw WindowsPluginReplacementFailure.changed
            }
            let temporary = self.destination.deletingLastPathComponent()
                .appendingPathComponent(".reinstall-" + UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: temporary, withIntermediateDirectories: false)
            defer { try? fm.removeItem(at: temporary) }
            let staged = temporary.appendingPathComponent(self.destination.lastPathComponent)
            try WindowsCredentialFileWriter.writePrivate(self.replacement, to: staged)
            try beforePublish()
            try fm.moveItem(at: staged, to: self.destination)
            return nil
        }
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
