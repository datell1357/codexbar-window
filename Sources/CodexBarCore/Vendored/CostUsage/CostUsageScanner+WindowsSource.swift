import Foundation

extension CostUsageScanner {
    static func newWindowsCodexContentGeneration() -> String? {
        #if os(Windows)
        return UUID().uuidString
        #else
        return nil
        #endif
    }

    /// A Windows parse cannot publish a resumable prefix whose digest could not be captured.
    static func codexCommittedPrefixAnchor(
        fileURL: URL,
        indexedBytes: Int64,
        metadata: CodexFileMetadata,
        checkCancellation: CancellationCheck?) throws -> CostUsageCodexTokenIndexAnchor?
    {
        try Task.checkCancellation()
        try checkCancellation?()
        #if os(Windows)
        guard indexedBytes >= 0, indexedBytes <= metadata.size else {
            throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
        }
        if indexedBytes == 0 { return nil }
        #endif
        let anchor = self.codexTokenIndexAnchor(
            fileURL: fileURL, indexedBytes: indexedBytes, expectedFile: metadata.readSnapshot,
            checkCancellation: checkCancellation)
        #if os(Windows)
        guard anchor != nil else {
            try Task.checkCancellation()
            try checkCancellation?()
            throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
        }
        #endif
        return anchor
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
        return self.codexTokenIndexAnchorMatches(
            anchor, fileURL: URL(fileURLWithPath: metadata.path), metadata: metadata,
            checkCancellation: checkCancellation)
    }
    #endif
}
