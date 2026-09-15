#if os(Windows)
import CodexBarCore
import Foundation
import WinSDK
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public struct WindowsPluginRemovalReview: Sendable {
    let token: UUID
    let instanceID: ProviderInstanceID?
    let sourceFilename: String?
    let sourceHash: String?
    let cacheCount: Int
}

public enum WindowsPluginRemovalFailure: String, Error, Sendable {
    case changed, busy, unavailable, partiallyRemoved, notFailedFile, fileRemovalIncomplete
    var localizationKey: String { "plugin_remove_" + self.rawValue }

    static func classify(_ error: Error) -> Self {
        if let failure = error as? Self { return failure }
        if let failure = error as? WindowsPluginInstallFailure, failure == .busy { return .busy }
        return .unavailable
    }
}

enum WindowsPluginRemovalOutcome: Sendable { case providerRemoved, failedFileRemoved }

struct WindowsPluginRemovalPlan: Sendable {
    private struct Artifact: Sendable {
        let url: URL
        let hash: String
        let byteLimit: Int
    }

    let review: WindowsPluginRemovalReview
    private let source: Artifact?
    private let caches: [Artifact]

    static func prepare(instanceID: ProviderInstanceID, installed: UserProviderPlugin?) throws -> Self {
        guard instanceID.firstPartyProvider == nil else { throw WindowsPluginRemovalFailure.changed }
        return try WindowsPluginInstaller.withInstallationLock {
            guard let installed else {
                guard !UserProviderPluginLoader().discover().contains(where: { $0.instanceID == instanceID }) else {
                    throw WindowsPluginRemovalFailure.changed
                }
                return Self(review: WindowsPluginRemovalReview(token: UUID(), instanceID: instanceID,
                    sourceFilename: nil, sourceHash: nil, cacheCount: 0), source: nil, caches: [])
            }
            guard installed.manifest.id == instanceID,
                  installed.fileURL.deletingLastPathComponent().standardizedFileURL ==
                    UserProviderPluginLoader.defaultProvidersDirectory.standardizedFileURL else {
                throw WindowsPluginRemovalFailure.changed
            }
            let source = try self.describe(installed.fileURL, byteLimit: UserProviderPlugin.maximumSourceBytes)
            guard source.hash == installed.sourceHash else { throw WindowsPluginRemovalFailure.changed }
            let caches = try self.cacheURLs(for: source.url).map { try self.describe($0, byteLimit: 8 * 1024 * 1024) }
            return Self(review: WindowsPluginRemovalReview(token: UUID(), instanceID: instanceID,
                sourceFilename: source.url.lastPathComponent, sourceHash: source.hash, cacheCount: caches.count),
                source: source, caches: caches)
        }
    }

    static func prepareFailedFile(sourceURL: URL) throws -> Self {
        let sourceURL = sourceURL.standardizedFileURL
        guard sourceURL.isFileURL, !sourceURL.path.contains("\0"),
              ["js", "ts"].contains(sourceURL.pathExtension.lowercased()),
              sourceURL.deletingLastPathComponent() == UserProviderPluginLoader.defaultProvidersDirectory.standardizedFileURL else {
            throw WindowsPluginRemovalFailure.notFailedFile
        }
        return try WindowsPluginInstaller.withInstallationLock {
            let source = try self.describeFailedSource(sourceURL, expectedHash: nil)
            // A failed load has no trustworthy provider identity. Match the original's
            // file-only deletion contract; never infer config or cache ownership by filename.
            return Self(review: WindowsPluginRemovalReview(token: UUID(), instanceID: nil,
                sourceFilename: sourceURL.lastPathComponent, sourceHash: source.hash, cacheCount: 0),
                source: source, caches: [])
        }
    }

    private static func describeFailedSource(_ url: URL, expectedHash: String?) throws -> Artifact {
        let byteLimit = 64 * 1024 * 1024
        let file = try PinnedFile(url, byteLimit: byteLimit, deleting: false, expectedHash: expectedHash)
        return try withExtendedLifetime(file) {
            guard let result = UserProviderPluginLoader().discover().first(where: {
                $0.fileURL.standardizedFileURL == url.standardizedFileURL
            }), result.plugin == nil, result.error != nil else {
                throw WindowsPluginRemovalFailure.notFailedFile
            }
            return Artifact(url: url, hash: file.hash, byteLimit: byteLimit)
        }
    }

    /// Opens every reviewed artifact before changing settings. Handles deny writes and renames
    /// until deletion, so a path replacement cannot redirect a confirmed removal to new bytes.
    func commit(beforeRemoval: () throws -> Void) throws {
        try WindowsPluginInstaller.withInstallationLock {
            if let source = self.source, self.review.instanceID == nil {
                _ = try Self.describeFailedSource(source.url, expectedHash: source.hash)
            } else if let source = self.source {
                guard try Self.cacheURLs(for: source.url) == self.caches.map(\.url) else {
                    throw WindowsPluginRemovalFailure.changed
                }
            } else {
                guard let instanceID = self.review.instanceID,
                      !UserProviderPluginLoader().discover().contains(where: { $0.instanceID == instanceID }) else {
                    throw WindowsPluginRemovalFailure.changed
                }
            }
            var files: [PinnedFile] = []
            for artifact in self.source.map({ [$0] }) ?? [] {
                files.append(try PinnedFile(artifact.url, byteLimit: artifact.byteLimit, deleting: true,
                    expectedHash: artifact.hash))
            }
            for artifact in self.caches {
                files.append(try PinnedFile(artifact.url, byteLimit: artifact.byteLimit, deleting: true,
                    expectedHash: artifact.hash))
            }
            // Conditional approval revocation and protected config removal happen first.
            try beforeRemoval()
            for file in files { try file.remove() }
        }
    }

    private static func describe(_ url: URL, byteLimit: Int) throws -> Artifact {
        let file = try PinnedFile(url, byteLimit: byteLimit, deleting: false, expectedHash: nil)
        return Artifact(url: url, hash: file.hash, byteLimit: byteLimit)
    }

    private static func cacheURLs(for source: URL) throws -> [URL] {
        let directory = UserProviderPluginLoader.defaultCacheDirectory
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        let prefix = source.deletingPathExtension().lastPathComponent + "-"
        let matches = urls.filter { url in
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix) else { return false }
            // An exact hash/version suffix avoids deleting another plugin whose name shares a prefix.
            let suffix = String(name.dropFirst(prefix.count))
            return suffix.range(of: "^[0-9a-f]{64}-sucrase-[0-9]+\\.[0-9]+\\.[0-9]+\\.js$",
                options: .regularExpression) != nil
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard matches.count <= 512 else { throw WindowsPluginRemovalFailure.unavailable }
        return matches
    }

    private final class PinnedFile {
        let handle: HANDLE
        let hash: String

        init(_ url: URL, byteLimit: Int, deleting: Bool, expectedHash: String?) throws {
            let opened = url.path.withCString(encodedAs: UTF16.self) {
                CreateFileW($0, DWORD(GENERIC_READ) | (deleting ? DWORD(DELETE) : 0), DWORD(FILE_SHARE_READ),
                    nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT), nil)
            }
            guard let handle = opened, handle != INVALID_HANDLE_VALUE else {
                let code = GetLastError()
                if code == ERROR_SHARING_VIOLATION || code == ERROR_LOCK_VIOLATION {
                    throw WindowsPluginRemovalFailure.busy
                }
                throw WindowsPluginRemovalFailure.changed
            }
            var retained = false
            defer { if !retained { CloseHandle(handle) } }
            var info = BY_HANDLE_FILE_INFORMATION()
            guard GetFileType(handle) == DWORD(FILE_TYPE_DISK), GetFileInformationByHandle(handle, &info) != 0,
                  info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) == 0 else {
                throw WindowsPluginRemovalFailure.unavailable
            }
            var digest = SHA256()
            var total = 0
            var bytes = [UInt8](repeating: 0, count: 65536)
            while true {
                var read: DWORD = 0
                let success = bytes.withUnsafeMutableBytes {
                    ReadFile(handle, $0.baseAddress, DWORD($0.count), &read, nil)
                }
                guard success != 0 else { throw WindowsPluginRemovalFailure.unavailable }
                if read == 0 { break }
                total += Int(read)
                guard total <= byteLimit else { throw WindowsPluginRemovalFailure.changed }
                digest.update(data: Data(bytes.prefix(Int(read))))
            }
            let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
            if let expectedHash, hash != expectedHash { throw WindowsPluginRemovalFailure.changed }
            self.handle = handle
            self.hash = hash
            retained = true
        }

        func remove() throws {
            var disposition = FILE_DISPOSITION_INFO()
            disposition.DeleteFile = 1
            guard SetFileInformationByHandle(self.handle, FileDispositionInfo, &disposition,
                DWORD(MemoryLayout<FILE_DISPOSITION_INFO>.size)) != 0 else {
                throw WindowsPluginRemovalFailure.partiallyRemoved
            }
        }

        deinit { CloseHandle(self.handle) }
    }
}
#endif
