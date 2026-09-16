import Foundation

extension CostUsageScanner {
    static func codexLogicalTargetHasUnconsumedTail(
        metadata: CodexFileMetadata,
        cached: CostUsageFileUsage) -> Bool
    {
        let parsedBytes = cached.parsedBytes ?? cached.size
        let targetSize = cached.codexScanTargetSize ?? cached.size
        return parsedBytes < metadata.size || targetSize < metadata.size
    }

    static func codexResumableScanTargetSize(
        metadata: CodexFileMetadata,
        cached: CostUsageFileUsage) -> Int64?
    {
        let startOffset = cached.parsedBytes ?? cached.size
        let targetSize = cached.codexScanTargetSize ?? cached.size
        let hasMatchingResumeOffset = cached.codexJSONLResumeState?.offset == nil
            || cached.codexJSONLResumeState?.offset == startOffset
        guard cached.codexScanComplete == false,
              cached.codexScanFileId != nil,
              cached.codexScanFileId == metadata.fileId,
              startOffset > 0,
              startOffset <= targetSize,
              targetSize <= metadata.size,
              startOffset < targetSize || cached.codexJSONLResumeState != nil,
              cached.codexTokenIndexAnchor?.indexedBytes == startOffset,
              hasMatchingResumeOffset
        else { return nil }
        #if os(Windows)
        guard Self.windowsCodexPrefixMatches(cached, metadata: metadata) else { return nil }
        #else
        guard cached.codexTokenIndexAnchor.map({
            Self.codexTokenIndexAnchorMatches(
                $0, fileURL: URL(fileURLWithPath: metadata.path), metadata: metadata)
        }) == true else { return nil }
        #endif
        return targetSize
    }

    static func isValidatedCodexFrozenTargetTail(
        metadata: CodexFileMetadata,
        cached: CostUsageFileUsage) -> Bool
    {
        let startOffset = cached.parsedBytes ?? cached.size
        guard cached.codexJSONLResumeState == nil,
              cached.codexScanFileId != nil,
              cached.codexScanFileId == metadata.fileId,
              let targetSize = cached.codexScanTargetSize,
              targetSize > 0,
              startOffset == targetSize,
              targetSize < metadata.size,
              cached.codexTokenIndexAnchor?.indexedBytes == startOffset
        else { return false }
        #if os(Windows)
        return Self.windowsCodexPrefixMatches(cached, metadata: metadata)
        #else
        return cached.codexTokenIndexAnchor.map {
            Self.codexTokenIndexAnchorMatches(
                $0,
                fileURL: URL(fileURLWithPath: metadata.path),
                metadata: metadata)
        } == true
        #endif
    }
}
