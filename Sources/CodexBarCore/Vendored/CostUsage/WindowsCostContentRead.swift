#if os(Windows)
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Accumulates the exact Data passed to the JSONL parser. Hash state is local to one read;
/// only immutable digest/offset pairs cross into persisted cache and publication checks.
final class WindowsCostContentRead {
    private var digest = SHA256()
    private var committedDigest = SHA256()
    private var readOffset: Int64 = 0
    private var committedOffset: Int64 = 0

    init(
        file: FileHandle,
        startOffset: Int64,
        committedOffset: Int64,
        expectedPrefix: CostUsageCodexTokenIndexAnchor?,
        readGuard: WindowsCostFileReadGuard,
        checkCancellation: (() throws -> Void)?) throws
    {
        try Task.checkCancellation()
        try checkCancellation?()
        guard startOffset >= 0, committedOffset >= 0, committedOffset <= startOffset,
              startOffset <= readGuard.snapshot.size else { throw Self.failure }
        try file.seek(toOffset: 0)
        while self.readOffset < startOffset {
            try Task.checkCancellation()
            try checkCancellation?()
            try readGuard.check()
            let count = Int(min(64 * 1024, startOffset - self.readOffset))
            guard let chunk = try file.read(upToCount: count), !chunk.isEmpty else { throw Self.failure }
            try self.append(chunk, committedThrough: min(committedOffset, self.readOffset + Int64(chunk.count)))
        }
        try readGuard.check()
        if let expectedPrefix {
            guard expectedPrefix.windowStart == 0, expectedPrefix.indexedBytes == startOffset,
                  try self.anchor(at: startOffset) == expectedPrefix else { throw Self.failure }
        }
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
            guard Self.anchor(state: digest, offset: offset) == anchor else { throw Self.failure }
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
