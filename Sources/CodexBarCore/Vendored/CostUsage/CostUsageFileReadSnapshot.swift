import Foundation

/// Observation used to bind a cost scan to a file and a fixed physical read boundary.
/// It is deliberately separate from the persisted cache's millisecond freshness hint.
struct CostUsageFileReadSnapshot: Equatable, Sendable {
    let fileID: String
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64

    static func capture(at url: URL) throws -> Self? {
        #if os(Windows)
        return Self(native: try WindowsCostFileMetadata.requiredFile(at: url))
        #else
        return nil
        #endif
    }

    #if os(Windows)
    init(native: WindowsCostFileMetadata.Snapshot) {
        self.fileID = native.fileID
        self.size = native.size
        self.modifiedSeconds = native.modifiedSeconds
        self.modifiedNanoseconds = native.modifiedNanoseconds
    }

    init(claude: CostUsageClaudeFileStamp) {
        self.fileID = claude.fileID
        self.size = claude.size
        self.modifiedSeconds = claude.modifiedSeconds
        self.modifiedNanoseconds = claude.modifiedNanoseconds
    }
    #endif
}

#if os(Windows)
/// Detects observed replacement/truncation while allowing append-only growth beyond the frozen
/// read boundary. This is not an immutable filesystem snapshot or a content-integrity proof.
final class WindowsCostFileReadGuard {
    enum Failure: Error { case sourceChanged, invalidOffset }

    let snapshot: CostUsageFileReadSnapshot
    private let file: FileHandle
    private let url: URL
    private var lastObserved: CostUsageFileReadSnapshot

    init(file: FileHandle, url: URL, expected: CostUsageFileReadSnapshot) throws {
        guard expected.size >= 0 else { throw Failure.invalidOffset }
        self.file = file
        self.url = url
        self.snapshot = expected
        self.lastObserved = expected
        try self.check()
    }

    func remainingBytes(from offset: Int64) throws -> Int64 {
        guard offset >= 0, offset <= self.snapshot.size else { throw Failure.invalidOffset }
        return self.snapshot.size - offset
    }

    func check() throws {
        try self.observe(CostUsageFileReadSnapshot(native: WindowsCostFileMetadata.opened(self.file)))
        try self.observe(CostUsageFileReadSnapshot(native: WindowsCostFileMetadata.requiredFile(at: self.url)))
    }

    private func observe(_ current: CostUsageFileReadSnapshot) throws {
        guard current.fileID == self.snapshot.fileID, current.size >= self.lastObserved.size else {
            throw Failure.sourceChanged
        }
        if current.size == self.lastObserved.size {
            guard current.modifiedSeconds == self.lastObserved.modifiedSeconds,
                  current.modifiedNanoseconds == self.lastObserved.modifiedNanoseconds
            else { throw Failure.sourceChanged }
        }
        self.lastObserved = current
    }
}
#endif
