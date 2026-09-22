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
        var state = CostUsageWindowsTreeInventory(roots: [root])
        defer { WindowsCostDirectoryPages.shared.discard(state.page) }
        while try !WindowsCostTreeInventory.advance(
            &state, maxWork: 1024, descendIntoDirectory: descendIntoDirectory,
            checkCancellation: checkCancellation).isComplete {}
        let observations = publicationObservations ?? CostUsagePublicationObservations()
        try WindowsCostTreeInventory.observe(state, in: observations, checkCancellation: checkCancellation)
        // Standalone callers have no later publication boundary; this synchronous pass is
        // their only ledger validation, so it stays unsliced. Callers sharing an observations
        // ledger get an early fail-fast here plus the final boundary re-check downstream.
        try observations.freeze().check(checkCancellation: checkCancellation)
        if state.missingRoots.contains(root.standardizedFileURL.path) { return nil }
        return try WindowsCostTreeInventory.representatives(state, checkCancellation: checkCancellation)
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
