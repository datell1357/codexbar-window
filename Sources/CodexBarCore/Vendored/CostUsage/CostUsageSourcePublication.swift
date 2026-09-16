import Foundation

/// Immutable observations passed from the scan queue to a cache publication boundary.
/// Checks apply to recorded sources, not to a whole filesystem snapshot.
struct CostUsageSourcePublication: Sendable {
    enum Failure: Error { case sourceChangedOrUnavailable }

    enum Expectation: Equatable, Sendable {
        case file(CostUsageFileReadSnapshot)
        case directory(CostUsageFileReadSnapshot)
        case missing
    }

    struct Entry: Equatable, Sendable {
        let url: URL
        let expectation: Expectation
        var contentAnchors: [CostUsageCodexTokenIndexAnchor] = []
    }

    let entries: [Entry]
    #if os(Windows)
    var windowsVerifier: WindowsCostPublicationVerifier? = nil
    #endif

    /// Only staged, non-report checkpoints may defer byte verification. Final cache/memo
    /// publication must retain the original ledger and all of its consumed-prefix anchors.
    func metadataOnly() -> Self {
        Self(entries: self.entries.map { Entry(url: $0.url, expectation: $0.expectation) })
    }

    func check(checkCancellation: (() throws -> Void)? = nil) throws {
        #if os(Windows)
        if let windowsVerifier,
           try windowsVerifier.canReuse(entries: self.entries, checkCancellation: checkCancellation) { return }
        for entry in self.entries {
            try Task.checkCancellation()
            try checkCancellation?()
            if let current = try Self.checkMetadata(entry) {
                do {
                    try WindowsCostContentRead.validate(
                        entry.contentAnchors, fileURL: entry.url,
                        expectedFile: current, checkCancellation: checkCancellation)
                } catch WindowsCostContentRead.Failure.digestMismatch {
                    throw Failure.sourceChangedOrUnavailable
                }
            }
        }
        #endif
        try checkCancellation?()
    }

    #if os(Windows)
    static func checkMetadata(_ entry: Entry) throws -> CostUsageFileReadSnapshot? {
        let current = try WindowsCostFileMetadata.atURL(entry.url)
        switch entry.expectation {
        case .missing:
            guard current == nil else { throw Failure.sourceChangedOrUnavailable }
        case let .file(expected):
            guard let current, !current.isDirectory,
                  Self.allowsAppend(CostUsageFileReadSnapshot(native: current), from: expected)
            else { throw Failure.sourceChangedOrUnavailable }
            return CostUsageFileReadSnapshot(native: current)
        case let .directory(expected):
            guard let current, current.isDirectory, CostUsageFileReadSnapshot(native: current) == expected else {
                throw Failure.sourceChangedOrUnavailable
            }
        }
        return nil
    }
    #endif

    var isCurrent: Bool {
        do { try self.check(); return true } catch { return false }
    }

    static func allowsAppend(_ current: CostUsageFileReadSnapshot, from expected: CostUsageFileReadSnapshot) -> Bool {
        current.fileID == expected.fileID && current.size >= expected.size
            && (current.size > expected.size || current == expected)
    }
}

/// A scan and its parent-discovery work share this ledger. Freeze before crossing into the
/// store actor; no mutable collector or cancellation closure is sent to the actor.
final class CostUsagePublicationObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: CostUsageSourcePublication.Entry] = [:]

    static func forCurrentPlatform() -> CostUsagePublicationObservations? {
        #if os(Windows)
        return CostUsagePublicationObservations()
        #else
        return nil
        #endif
    }

    func file(_ url: URL, snapshot: CostUsageFileReadSnapshot) throws {
        try self.record(url, expectation: .file(snapshot))
    }

    func content(
        _ url: URL,
        snapshot: CostUsageFileReadSnapshot,
        anchor: CostUsageCodexTokenIndexAnchor) throws
    {
        guard anchor.windowStart == 0, anchor.indexedBytes > 0, anchor.indexedBytes <= snapshot.size else {
            throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        let url = url.standardizedFileURL
        try self.recordLocked(url, expectation: .file(snapshot))
        guard var entry = self.entries[url.path] else {
            throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
        }
        if let previous = entry.contentAnchors.first(where: { $0.indexedBytes == anchor.indexedBytes }) {
            guard previous == anchor else { throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable }
        } else {
            entry.contentAnchors.append(anchor)
            entry.contentAnchors.sort { $0.indexedBytes < $1.indexedBytes }
        }
        self.entries[url.path] = entry
    }

    func directory(_ url: URL, snapshot: CostUsageFileReadSnapshot) throws {
        try self.record(url, expectation: .directory(snapshot))
    }

    func missing(_ url: URL) throws {
        try self.record(url, expectation: .missing)
    }

    func freeze() -> CostUsageSourcePublication {
        self.lock.lock()
        defer { self.lock.unlock() }
        return CostUsageSourcePublication(entries: self.entries.sorted { $0.key < $1.key }.map(\.value))
    }

    private func record(_ url: URL, expectation: CostUsageSourcePublication.Expectation) throws {
        self.lock.lock()
        defer { self.lock.unlock() }
        try self.recordLocked(url.standardizedFileURL, expectation: expectation)
    }

    private func recordLocked(_ url: URL, expectation: CostUsageSourcePublication.Expectation) throws {
        if let previous = self.entries[url.path]?.expectation, previous != expectation {
            guard case let .file(old) = previous, case let .file(new) = expectation,
                  CostUsageSourcePublication.allowsAppend(new, from: old)
            else { throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable }
        }
        self.entries[url.path] = .init(
            url: url, expectation: expectation, contentAnchors: self.entries[url.path]?.contentAnchors ?? [])
    }
}
