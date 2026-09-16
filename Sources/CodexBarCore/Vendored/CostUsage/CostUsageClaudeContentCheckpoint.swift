import Foundation

/// Separate from the last completed report. A checkpoint may contain incomplete files, but
/// those rows never become usage-cache authority until the complete collection is published.
struct CostUsageClaudeContentCheckpoint: Codable {
    struct Key: Codable, Equatable {
        let configuration: CostUsageClaudeReportMemoKey.ScanConfiguration
        let since: String
        let until: String
        let scanSince: String
        let scanUntil: String
        let pricing: CostUsageClaudeFileStamp?
        let forceRescan: Bool
        let semantics: Int

        init(report: CostUsageClaudeReportMemoKey, forceRescan: Bool) {
            self.configuration = report.scanConfiguration
            self.since = report.sinceKey
            self.until = report.untilKey
            self.scanSince = report.scanSinceKey
            self.scanUntil = report.scanUntilKey
            self.pricing = report.pricingArtifactStamp
            self.forceRescan = forceRescan
            self.semantics = CostUsageClaudeReportMemo.reportSemanticsVersion
        }
    }

    struct File: Codable {
        let path: String
        let source: CostUsageClaudeFileStamp
        let rows: [CostUsageScanner.ClaudeUsageRow]
        let parsedBytes: Int64
        let readBytes: Int64
        let resume: CostUsageJsonl.ResumeState?
        let readAnchor: CostUsageCodexTokenIndexAnchor?
        let committedAnchor: CostUsageCodexTokenIndexAnchor?
        var contentContinuation: UUID? = nil

        #if os(Windows)
        func isUsable(path: String, stamp: CostUsageClaudeFileStamp) -> Bool {
            guard self.path == path, self.source == stamp,
                  CostUsageFileReadSnapshot(claude: stamp).isValidWindowsObservation,
                  self.parsedBytes >= 0, self.readBytes > 0, self.parsedBytes <= self.readBytes,
                  self.readBytes < stamp.size,
                  Self.hasBoundary(self.readAnchor, offset: self.readBytes),
                  Self.hasBoundary(self.committedAnchor, offset: self.parsedBytes)
            else { return false }
            if let resume {
                return resume.isValidContinuation(
                    committedOffset: self.parsedBytes, readOffset: self.readBytes, limit: 512 * 1024)
            }
            return self.parsedBytes == self.readBytes
        }

        func observe(in observations: CostUsagePublicationObservations?) throws {
            let url = URL(fileURLWithPath: self.path)
            let snapshot = CostUsageFileReadSnapshot(claude: self.source)
            try observations?.file(url, snapshot: snapshot)
            for anchor in [self.readAnchor, self.committedAnchor].compactMap({ $0 }) {
                try observations?.content(url, snapshot: snapshot, anchor: anchor)
            }
        }

        private static func hasBoundary(_ anchor: CostUsageCodexTokenIndexAnchor?, offset: Int64) -> Bool {
            if offset == 0 { return anchor == nil }
            return anchor?.windowStart == 0 && anchor?.indexedBytes == offset
        }
        #endif
    }

    var version = 1
    let key: Key
    let sourceInventory: [String: CostUsageClaudeFileStamp]
    var cache: CostUsageCache
    var sourceFileIDs: [String: String]
    var proofs: [String: CostUsageClaudeReadProof]
    var nextFile = 0
    var partial: File?
    var verificationToken: UUID? = nil
}
