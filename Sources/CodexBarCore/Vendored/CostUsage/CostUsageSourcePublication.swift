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

    struct Entry: Sendable {
        let url: URL
        let expectation: Expectation
    }

    let entries: [Entry]

    func check(checkCancellation: (() throws -> Void)? = nil) throws {
        #if os(Windows)
        for entry in self.entries {
            try Task.checkCancellation()
            try checkCancellation?()
            let current = try WindowsCostFileMetadata.atURL(entry.url)
            switch entry.expectation {
            case .missing:
                guard current == nil else { throw Failure.sourceChangedOrUnavailable }
            case let .file(expected):
                guard let current, !current.isDirectory,
                      Self.allowsAppend(CostUsageFileReadSnapshot(native: current), from: expected)
                else { throw Failure.sourceChangedOrUnavailable }
            case let .directory(expected):
                guard let current, current.isDirectory, CostUsageFileReadSnapshot(native: current) == expected else {
                    throw Failure.sourceChangedOrUnavailable
                }
            }
        }
        #endif
        try checkCancellation?()
    }

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
        let url = url.standardizedFileURL
        if let previous = self.entries[url.path]?.expectation, previous != expectation {
            guard case let .file(old) = previous, case let .file(new) = expectation,
                  CostUsageSourcePublication.allowsAppend(new, from: old)
            else { throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable }
        }
        self.entries[url.path] = .init(url: url, expectation: expectation)
    }
}
