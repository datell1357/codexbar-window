#if os(Windows)
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Accumulates the exact Data passed to the JSONL parser. Hash state may move between
/// exclusive in-process continuations; only immutable digests and opaque tokens are persisted.
final class WindowsCostContentRead {
    enum Failure: Error { case digestMismatch }
    private var digest = SHA256()
    private var committedDigest = SHA256()
    private var readOffset: Int64 = 0
    private var committedOffset: Int64 = 0

    struct SeedProgress {
        let bytesRead: Int64
        let isComplete: Bool
    }

    init() {}

    /// Recreate a lost in-memory prefix state in bounded slices. A live state is merely
    /// staging evidence: the final publication still verifies the full consumed prefix.
    func seed(
        file: FileHandle,
        startOffset: Int64,
        committedOffset: Int64,
        expectedPrefix: CostUsageCodexTokenIndexAnchor?,
        expectedCommitted: CostUsageCodexTokenIndexAnchor?,
        readGuard: WindowsCostFileReadGuard,
        maxBytes: Int64?,
        checkCancellation: (() throws -> Void)?) throws -> SeedProgress
    {
        try Task.checkCancellation()
        try checkCancellation?()
        guard startOffset >= 0, committedOffset >= 0, committedOffset <= startOffset,
              startOffset <= readGuard.snapshot.size, self.readOffset <= startOffset,
              self.committedOffset <= committedOffset else { throw Self.failure }
        let initialOffset = self.readOffset
        let allowance = max(0, maxBytes ?? (startOffset - initialOffset))
        try file.seek(toOffset: UInt64(initialOffset))
        while self.readOffset < startOffset, self.readOffset - initialOffset < allowance {
            try Task.checkCancellation()
            try checkCancellation?()
            try readGuard.check()
            let count = Int(min(64 * 1024, min(startOffset - self.readOffset,
                                              allowance - (self.readOffset - initialOffset))))
            guard let chunk = try file.read(upToCount: count), !chunk.isEmpty else { throw Self.failure }
            try self.append(chunk, committedThrough: min(committedOffset, self.readOffset + Int64(chunk.count)))
        }
        try readGuard.check()
        guard self.readOffset == startOffset else {
            return SeedProgress(bytesRead: self.readOffset - initialOffset, isComplete: false)
        }
        guard self.committedOffset == committedOffset else { throw Self.failure }
        if let expectedPrefix {
            guard expectedPrefix.windowStart == 0, expectedPrefix.indexedBytes == startOffset,
                  try self.anchor(at: startOffset) == expectedPrefix else { throw Self.failure }
        }
        if let expectedCommitted {
            guard expectedCommitted.windowStart == 0, expectedCommitted.indexedBytes == committedOffset,
                  try self.anchor(at: committedOffset) == expectedCommitted else { throw Self.failure }
        }
        return SeedProgress(bytesRead: self.readOffset - initialOffset, isComplete: true)
    }

    /// The scanner supplies its last complete line boundary after consuming this same chunk.
    func append(_ chunk: Data, committedThrough boundary: Int64) throws {
        try Task.checkCancellation()
        let end = self.readOffset + Int64(chunk.count)
        guard boundary >= self.committedOffset, boundary <= end else { throw Self.failure }
        if boundary > self.committedOffset {
            guard boundary >= self.readOffset else { throw Self.failure }
            var checkpoint = self.digest
            checkpoint.update(data: chunk.prefix(Int(boundary - self.readOffset)))
            self.committedDigest = checkpoint
            self.committedOffset = boundary
        }
        self.digest.update(data: chunk)
        self.readOffset = end
    }

    func anchor(at offset: Int64) throws -> CostUsageCodexTokenIndexAnchor? {
        try Task.checkCancellation()
        guard offset >= 0 else { throw Self.failure }
        if offset == 0 { return nil }
        let state: SHA256
        if offset == self.readOffset {
            state = self.digest
        } else if offset == self.committedOffset {
            state = self.committedDigest
        } else {
            throw Self.failure
        }
        return Self.anchor(state: state, offset: offset)
    }

    /// Multiple observations of one file are checked in one sequential pass. Each requested
    /// prefix retains its own digest so a later, longer read cannot overwrite earlier evidence.
    static func validate(
        _ anchors: [CostUsageCodexTokenIndexAnchor],
        fileURL: URL,
        expectedFile: CostUsageFileReadSnapshot,
        checkCancellation: (() throws -> Void)?) throws
    {
        guard !anchors.isEmpty else { return }
        let sorted = anchors.sorted { $0.indexedBytes < $1.indexedBytes }
        guard sorted.allSatisfy({ $0.windowStart == 0 && $0.indexedBytes > 0
            && $0.indexedBytes <= expectedFile.size }) else { throw Self.failure }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let readGuard = try WindowsCostFileReadGuard(file: handle, url: fileURL, expected: expectedFile)
        var digest = SHA256()
        var offset: Int64 = 0
        for anchor in sorted {
            while offset < anchor.indexedBytes {
                try Task.checkCancellation()
                try checkCancellation?()
                try readGuard.check()
                let count = Int(min(64 * 1024, anchor.indexedBytes - offset))
                guard let data = try handle.read(upToCount: count), !data.isEmpty else { throw Self.failure }
                digest.update(data: data)
                offset += Int64(data.count)
            }
            guard Self.anchor(state: digest, offset: offset) == anchor else { throw Failure.digestMismatch }
        }
        try Task.checkCancellation()
        try checkCancellation?()
        try readGuard.check()
    }

    private static var failure: CostUsageSourcePublication.Failure { .sourceChangedOrUnavailable }

    private static func anchor(state: SHA256, offset: Int64) -> CostUsageCodexTokenIndexAnchor {
        var copy = state
        return CostUsageCodexTokenIndexAnchor(
            indexedBytes: offset, windowStart: 0,
            sha256: copy.finalize().map { String(format: "%02x", $0) }.joined())
    }
}
#endif
