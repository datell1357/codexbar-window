#if os(Windows)
import Foundation

/// Preserve Foundation's hidden-file/package traversal policy, but never publish a partial
/// source inventory as proof that previously cached sources were removed.
enum WindowsCostSourceInventory {
    enum Failure: Error {
        case unreadableDirectory
        case sourceChanged
    }

    private final class EnumerationFailure: @unchecked Sendable {
        private let lock = NSLock()
        private var failed = false

        func record() {
            self.lock.lock()
            defer { self.lock.unlock() }
            self.failed = true
        }

        func check() throws {
            self.lock.lock()
            defer { self.lock.unlock() }
            if self.failed { throw Failure.unreadableDirectory }
        }
    }

    /// nil means the root was absent before enumeration; an existing empty root returns [:].
    /// Zero-byte logs remain in this inventory so callers can distinguish truncation from absence.
    static func jsonlFiles(
        in root: URL,
        descendIntoDirectory: ((URL) -> Bool)? = nil,
        checkCancellation: (() throws -> Void)? = nil) throws -> [URL: CostUsageClaudeFileStamp]?
    {
        try self.checkCancellation(checkCancellation)
        guard let rootSnapshot = try WindowsCostFileMetadata.atURL(root) else { return nil }
        guard rootSnapshot.isDirectory else { throw Failure.unreadableDirectory }
        let failure = EnumerationFailure()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in
                failure.record()
                return false
            }) else { throw Failure.unreadableDirectory }

        var directories: [URL: WindowsCostFileMetadata.Snapshot] = [root: rootSnapshot]
        var files: [URL: CostUsageClaudeFileStamp] = [:]
        for case let url as URL in enumerator {
            try self.checkCancellation(checkCancellation)
            try failure.check()
            let values = try url.resourceValues(forKeys: keys)
            guard let isDirectory = values.isDirectory else { throw Failure.unreadableDirectory }
            if isDirectory {
                if descendIntoDirectory?(url) == false {
                    enumerator.skipDescendants()
                    continue
                }
                guard let snapshot = try WindowsCostFileMetadata.atURL(url), snapshot.isDirectory else {
                    throw Failure.sourceChanged
                }
                directories[url] = snapshot
                // Keep linked directory traversal explicit and finite, matching ordinary
                // DirectoryEnumerator symbolic-link behavior instead of following cycles.
                if values.isSymbolicLink == true { enumerator.skipDescendants() }
            } else if url.pathExtension.lowercased() == "jsonl" {
                files[url] = try CostUsageClaudeFileStamp.readRequired(at: url)
            }
        }
        try failure.check()
        // Re-observation is a change detector, not an atomic filesystem snapshot. Do not accept
        // a root/subdirectory disappearing, an observed file changing, or an enumeration error.
        for (url, expected) in directories {
            try self.checkCancellation(checkCancellation)
            guard try WindowsCostFileMetadata.atURL(url) == expected else { throw Failure.sourceChanged }
        }
        for (url, expected) in files {
            try self.checkCancellation(checkCancellation)
            try self.requireUnchangedFile(at: url, stamp: expected)
        }
        try self.checkCancellation(checkCancellation)
        return files
    }

    static func requireUnchangedFile(at url: URL, stamp: CostUsageClaudeFileStamp) throws {
        guard try CostUsageClaudeFileStamp.readRequired(at: url) == stamp else { throw Failure.sourceChanged }
    }

    /// The parser reads only the observed prefix. An append schedules another refresh because
    /// the cache keeps the original stamp/size, rather than claiming to have consumed new bytes.
    static func requireCompatibleFileAfterRead(at url: URL, stamp: CostUsageClaudeFileStamp) throws {
        let current = try CostUsageClaudeFileStamp.readRequired(at: url)
        guard current.fileID == stamp.fileID, current.size >= stamp.size,
              current.size > stamp.size || current == stamp else { throw Failure.sourceChanged }
    }

    private static func checkCancellation(_ check: (() throws -> Void)?) throws {
        try Task.checkCancellation()
        try check?()
    }
}
#endif
