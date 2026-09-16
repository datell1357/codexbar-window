import Foundation

extension CostUsageScanner {
    static let windowsCodexReadProofVersion = 1

    static func newWindowsCodexContentGeneration() -> String? {
        #if os(Windows)
        return UUID().uuidString
        #else
        return nil
        #endif
    }

    /// Windows uses the digest of the actual parser input; it must never recertify parsed rows
    /// by reopening a potentially different source after the parser has returned.
    static func codexCommittedPrefixAnchor(
        fileURL: URL,
        indexedBytes: Int64,
        metadata: CodexFileMetadata,
        parserAnchor: CostUsageCodexTokenIndexAnchor?,
        checkCancellation: CancellationCheck?) throws -> CostUsageCodexTokenIndexAnchor?
    {
        try Task.checkCancellation()
        try checkCancellation?()
        #if os(Windows)
        guard indexedBytes >= 0, indexedBytes <= metadata.size else {
            throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
        }
        if indexedBytes == 0 { return nil }
        guard let parserAnchor, parserAnchor.windowStart == 0, parserAnchor.indexedBytes == indexedBytes else {
            throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
        }
        return parserAnchor
        #else
        return self.codexTokenIndexAnchor(
            fileURL: fileURL, indexedBytes: indexedBytes, expectedFile: metadata.readSnapshot,
            checkCancellation: checkCancellation)
        #endif
    }

    static func observeWindowsCodexContent(
        fileURL: URL,
        metadata: CodexFileMetadata,
        anchor: CostUsageCodexTokenIndexAnchor?,
        auxiliaryAnchors: [CostUsageCodexTokenIndexAnchor] = [],
        observations: CostUsagePublicationObservations?) throws
    {
        #if os(Windows)
        guard let snapshot = metadata.readSnapshot else {
            throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
        }
        if let anchor {
            try observations?.content(fileURL, snapshot: snapshot, anchor: anchor)
        } else {
            try observations?.file(fileURL, snapshot: snapshot)
        }
        for auxiliary in auxiliaryAnchors {
            try observations?.content(fileURL, snapshot: snapshot, anchor: auxiliary)
        }
        #endif
    }

    static func mergeWindowsCodexAnchors(
        _ previous: [CostUsageCodexTokenIndexAnchor]?,
        _ current: [CostUsageCodexTokenIndexAnchor]) throws -> [CostUsageCodexTokenIndexAnchor]?
    {
        var byOffset: [Int64: CostUsageCodexTokenIndexAnchor] = [:]
        for anchor in (previous ?? []) + current {
            if let existing = byOffset[anchor.indexedBytes], existing != anchor {
                throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
            }
            byOffset[anchor.indexedBytes] = anchor
        }
        return byOffset.isEmpty ? nil : byOffset.sorted { $0.key < $1.key }.map(\.value)
    }

    #if os(Windows)
    /// Native metadata is a prerequisite; it does not prove that an appended file kept its prefix.
    static func windowsCodexSourceMatches(
        _ usage: CostUsageFileUsage,
        metadata: CodexFileMetadata,
        allowAppend: Bool = false) -> Bool
    {
        guard let expected = usage.codexWindowsSource, expected.isValidWindowsObservation,
              let current = metadata.readSnapshot, current.isValidWindowsObservation,
              usage.codexWindowsContentGeneration?.isEmpty == false,
              usage.codexWindowsReadProofVersion == self.windowsCodexReadProofVersion,
              usage.codexScanFileId == expected.fileID,
              metadata.fileId == current.fileID,
              usage.size == expected.size, metadata.size == current.size
        else { return false }
        return allowAppend ? CostUsageSourcePublication.allowsAppend(current, from: expected) : current == expected
    }

    /// Validate exactly the bytes from which cached rows and resume buffers were produced.
    /// A legacy tail anchor cannot stand in for the complete committed prefix.
    static func windowsCodexPrefixMatches(
        _ usage: CostUsageFileUsage,
        metadata: CodexFileMetadata,
        checkCancellation: CancellationCheck? = nil) -> Bool
    {
        guard self.windowsCodexSourceMatches(usage, metadata: metadata, allowAppend: true) else { return false }
        let parsedBytes = usage.parsedBytes ?? usage.size
        guard parsedBytes >= 0, parsedBytes <= usage.size, parsedBytes <= metadata.size else { return false }
        if parsedBytes == 0 {
            return usage.size == 0 && usage.codexJSONLResumeState == nil
                && usage.codexRows?.isEmpty != false && usage.days.isEmpty
                && usage.codexTokenSnapshots?.isEmpty != false
                && !usage.hasBufferedCodexForkRetryLines
        }
        guard let anchor = usage.codexTokenIndexAnchor,
              anchor.indexedBytes == parsedBytes, anchor.windowStart == 0
        else { return false }
        guard let snapshot = metadata.readSnapshot else { return false }
        do {
            try WindowsCostContentRead.validate(
                [anchor] + (usage.codexWindowsAuxiliaryAnchors ?? []),
                fileURL: URL(fileURLWithPath: metadata.path), expectedFile: snapshot,
                checkCancellation: checkCancellation)
            return true
        } catch {
            return false
        }
    }
    #endif
}
