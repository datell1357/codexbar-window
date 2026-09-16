#if os(Windows)
import Foundation

/// Native traversal follows directory links once per volume/file ID. Aliases remain in the
/// observation ledger even when their contents have already been enumerated through another path.
enum WindowsCostSourceInventory {
    enum Failure: Error {
        case unreadableDirectory
        case sourceChanged
    }

    /// nil means the root was absent before enumeration; an existing empty root returns [:].
    /// Zero-byte logs remain in this inventory so callers can distinguish truncation from absence.
    static func jsonlFiles(
        in root: URL,
        descendIntoDirectory: ((URL) -> Bool)? = nil,
        checkCancellation: (() throws -> Void)? = nil,
        publicationObservations: CostUsagePublicationObservations? = nil) throws -> [URL: CostUsageClaudeFileStamp]?
    {
        try self.checkCancellation(checkCancellation)
        guard let rootSnapshot = try WindowsCostFileMetadata.atURL(root) else {
            try publicationObservations?.missing(root)
            return nil
        }
        guard rootSnapshot.isDirectory else { throw Failure.unreadableDirectory }
        var pending: [(URL, WindowsCostFileMetadata.Snapshot)] = [(root, rootSnapshot)]
        var nextDirectory = 0
        var visitedDirectories: [String: WindowsCostFileMetadata.Snapshot] = [:]
        var directories: [URL: WindowsCostFileMetadata.Snapshot] = [:]
        var observedFiles: [URL: CostUsageClaudeFileStamp] = [:]
        var fileOwners: [String: URL] = [:]
        var files: [URL: CostUsageClaudeFileStamp] = [:]
        while nextDirectory < pending.count {
            try self.checkCancellation(checkCancellation)
            let (directory, expected) = pending[nextDirectory]
            nextDirectory += 1
            guard try WindowsCostFileMetadata.atURL(directory) == expected else { throw Failure.sourceChanged }
            directories[directory] = expected
            if let visited = visitedDirectories[expected.fileID] {
                guard visited == expected else { throw Failure.sourceChanged }
                continue
            }
            guard directory == root || descendIntoDirectory?(directory) != false else { continue }
            guard let listing = try WindowsCostDirectoryInventory.read(
                in: directory, checkCancellation: checkCancellation,
                publicationObservations: publicationObservations), listing.directorySnapshot == expected
            else { throw Failure.sourceChanged }
            visitedDirectories[expected.fileID] = expected
            // Native enumeration order is unspecified. Keep the first representative stable
            // across calls, without folding case-sensitive Windows directory names.
            for entry in listing.entries.sorted(by: { $0.url.path < $1.url.path }) {
                try self.checkCancellation(checkCancellation)
                if entry.snapshot.isDirectory {
                    pending.append((entry.url, entry.snapshot))
                } else {
                    let snapshot = entry.snapshot
                    let stamp = CostUsageClaudeFileStamp(
                        fileID: snapshot.fileID, size: snapshot.size,
                        modifiedSeconds: snapshot.modifiedSeconds, modifiedNanoseconds: snapshot.modifiedNanoseconds)
                    observedFiles[entry.url] = stamp
                    if let owner = fileOwners[stamp.fileID] {
                        guard files[owner] == stamp else { throw Failure.sourceChanged }
                    } else {
                        fileOwners[stamp.fileID] = entry.url
                        files[entry.url] = stamp
                    }
                }
            }
        }
        // Re-observation is a change detector, not an atomic filesystem snapshot. Do not accept
        // a root/subdirectory disappearing, an observed file changing, or an enumeration error.
        for (url, expected) in directories {
            try self.checkCancellation(checkCancellation)
            guard try WindowsCostFileMetadata.atURL(url) == expected else { throw Failure.sourceChanged }
            try publicationObservations?.directory(url, snapshot: .init(native: expected))
        }
        for (url, expected) in observedFiles {
            try self.checkCancellation(checkCancellation)
            try self.requireUnchangedFile(at: url, stamp: expected)
            try publicationObservations?.file(url, snapshot: .init(claude: expected))
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
