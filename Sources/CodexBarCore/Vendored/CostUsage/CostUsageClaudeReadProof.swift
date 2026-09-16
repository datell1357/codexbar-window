import Foundation

/// Proofs travel with Claude/Vertex rows and report memos. Both boundaries come from the
/// parser's actual input: the complete prefix owns rows; the read prefix also covers a partial tail.
struct CostUsageClaudeReadProof: Codable, Equatable, Sendable {
    var version: Int = 1
    let source: CostUsageFileReadSnapshot
    let parsedBytes: Int64
    let readAnchor: CostUsageCodexTokenIndexAnchor?
    let committedAnchor: CostUsageCodexTokenIndexAnchor?

    #if os(Windows)
    func isUsable(for stamp: CostUsageClaudeFileStamp, allowAppend: Bool) -> Bool {
        let current = CostUsageFileReadSnapshot(claude: stamp)
        guard self.version == 1, self.source.isValidWindowsObservation,
              self.parsedBytes >= 0, self.parsedBytes <= self.source.size,
              (allowAppend ? CostUsageSourcePublication.allowsAppend(current, from: self.source)
                  : current == self.source)
        else { return false }
        return Self.hasBoundary(self.readAnchor, offset: self.source.size)
            && Self.hasBoundary(self.committedAnchor, offset: self.parsedBytes)
    }

    private static func hasBoundary(_ anchor: CostUsageCodexTokenIndexAnchor?, offset: Int64) -> Bool {
        if offset == 0 { return anchor == nil }
        guard let anchor else { return false }
        return anchor.windowStart == 0 && anchor.indexedBytes == offset
    }

    /// Only a content mismatch is a cache miss. Access failures, concurrent source changes
    /// detected by the handle guard, and either kind of cancellation still fail the refresh.
    func matchesContent(
        at url: URL,
        stamp: CostUsageClaudeFileStamp,
        checkCancellation: CostUsageScanner.CancellationCheck?) throws -> Bool
    {
        do {
            try WindowsCostContentRead.validate(
                [self.committedAnchor, self.readAnchor].compactMap { $0 },
                fileURL: url, expectedFile: CostUsageFileReadSnapshot(claude: stamp),
                checkCancellation: checkCancellation)
            return true
        } catch WindowsCostContentRead.Failure.digestMismatch {
            return false
        }
    }

    func observe(
        at url: URL,
        stamp: CostUsageClaudeFileStamp,
        in observations: CostUsagePublicationObservations?) throws
    {
        let snapshot = CostUsageFileReadSnapshot(claude: stamp)
        try observations?.file(url, snapshot: snapshot)
        for anchor in [self.committedAnchor, self.readAnchor].compactMap({ $0 }) {
            try observations?.content(url, snapshot: snapshot, anchor: anchor)
        }
    }
    #endif
}
