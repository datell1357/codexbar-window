import Foundation

/// Native directory observations outlive the active lookback queue. Completion of a queue
/// must not discard the evidence that allowed earlier date partitions to be skipped.
struct CostUsageWindowsDiscoveryInventory: Codable, Equatable, Sendable {
    enum Observation: Codable, Equatable, Sendable {
        case directory(CostUsageFileReadSnapshot)
        case missing
    }

    var version: Int = 1
    let rootPaths: [String]
    let scanSinceKey: String
    let scanUntilKey: String
    let timeZoneIdentifier: String
    let observations: [String: Observation]
    /// Durable cursor for the bounded membership revalidation pass, counted in leading keys of
    /// the sorted observation order. nil means no pass is mid-flight; a completed pass wraps
    /// to nil so the next refresh starts a fresh cycle. Persisted with the inventory.
    var matchCheckedCount: Int? = nil

    #if os(Windows)
    static func capture(
        roots: [URL],
        range: CostUsageScanner.CostUsageDayRange,
        publication: CostUsageSourcePublication,
        checkCancellation: CostUsageScanner.CancellationCheck? = nil) throws -> Self
    {
        var observations: [String: Observation] = [:]
        for entry in publication.entries {
            try Task.checkCancellation()
            try checkCancellation?()
            let path = entry.url.standardizedFileURL.path
            switch entry.expectation {
            case let .directory(snapshot): observations[path] = .directory(snapshot)
            case .missing: observations[path] = .missing
            case .file: break
            }
        }
        let rootPaths = roots.map { $0.standardizedFileURL.path }.sorted()
        guard rootPaths.allSatisfy({ observations[$0] != nil }) else {
            throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
        }
        return Self(
            rootPaths: rootPaths, scanSinceKey: range.scanSinceKey, scanUntilKey: range.scanUntilKey,
            timeZoneIdentifier: range.calendar.timeZone.identifier, observations: observations)
    }

    /// Bounded membership revalidation: verifies up to maxEntries observations per call,
    /// rotating through the sorted key order across refreshes. A mismatch in any checked entry
    /// fails immediately; a partial pass still returns true, and the publication ledger the
    /// caller registers afterwards keeps every entry covered before a report is served.
    mutating func matches(
        roots: [URL],
        range: CostUsageScanner.CostUsageDayRange,
        maxEntries: Int,
        checkCancellation: CostUsageScanner.CancellationCheck?) throws -> Bool
    {
        guard self.version == 1,
              self.rootPaths == roots.map({ $0.standardizedFileURL.path }).sorted(),
              self.scanSinceKey == range.scanSinceKey, self.scanUntilKey == range.scanUntilKey,
              self.timeZoneIdentifier == range.calendar.timeZone.identifier,
              self.rootPaths.allSatisfy({ self.observations[$0] != nil })
        else { return false }
        let keys = self.observations.keys.sorted()
        var index = min(self.matchCheckedCount ?? 0, keys.count)
        var visits = max(1, maxEntries)
        while index < keys.count, visits > 0 {
            try Task.checkCancellation()
            try checkCancellation?()
            let path = keys[index]
            let current = try WindowsCostFileMetadata.atURL(URL(fileURLWithPath: path))
            switch self.observations[path] {
            case let .some(.directory(expected)):
                guard expected.isValidWindowsObservation else { return false }
                if let current, !current.isDirectory {
                    throw WindowsCostSourceInventory.Failure.unreadableDirectory
                }
                guard current.map({ CostUsageFileReadSnapshot(native: $0) }) == expected else { return false }
            case .some(.missing):
                guard current == nil else { return false }
            case nil: return false
            }
            index += 1
            visits -= 1
        }
        self.matchCheckedCount = index < keys.count ? index : nil
        return true
    }

    /// Register only after the entire retained inventory matches. A changed generation
    /// restarts discovery without mixing its old directory stamps with new observations.
    func observe(
        in publication: CostUsagePublicationObservations?,
        checkCancellation: CostUsageScanner.CancellationCheck?) throws
    {
        for path in self.observations.keys.sorted() {
            try Task.checkCancellation()
            try checkCancellation?()
            let url = URL(fileURLWithPath: path)
            switch self.observations[path] {
            case let .some(.directory(snapshot)): try publication?.directory(url, snapshot: snapshot)
            case .some(.missing): try publication?.missing(url)
            case nil: break
            }
        }
    }
    #endif
}

extension CostUsageScanner {
    /// True means the next scan must restart discovery. Previously queued and cached files
    /// stay available; only the directory cursors/completion claims lose their authority.
    static func reconcileWindowsCodexDiscovery(
        cache: inout CostUsageCache,
        roots: [URL],
        resolvedRootPaths: [String],
        range: CostUsageDayRange,
        options: Options,
        publicationObservations: CostUsagePublicationObservations?,
        checkCancellation: CancellationCheck?) throws -> Bool
    {
        #if os(Windows)
        try Task.checkCancellation()
        try checkCancellation?()
        if var inventory = cache.codexWindowsDiscoveryInventory,
           try inventory.matches(
               roots: roots, range: range,
               maxEntries: max(1, options.maxWindowsCodexVerificationEntriesPerRefresh),
               checkCancellation: checkCancellation)
        {
            cache.codexWindowsDiscoveryInventory = inventory
            try inventory.observe(in: publicationObservations, checkCancellation: checkCancellation)
            return false
        }
        let prior = cache.codexActiveLookbackState
        let candidates = (prior?.pendingFilePaths ?? []) + cache.files.keys.sorted()
        var seen: Set<String> = []
        let pending = try candidates.filter {
            try Task.checkCancellation()
            try checkCancellation?()
            return Self.isWithinCodexRoots(fileURL: URL(fileURLWithPath: $0), roots: roots) && seen.insert($0).inserted
        }
        cache.codexActiveLookbackState = CostUsageCodexActiveLookbackState(
            scanSinceKey: range.scanSinceKey, rootPaths: resolvedRootPaths,
            pendingFilePaths: pending, legacyRecursivePendingRootPaths: resolvedRootPaths,
            cacheWideMigrationQueueActive: prior?.cacheWideMigrationQueueActive)
        cache.codexWindowsDiscoveryInventory = nil
        cache.codexScanInventoryPaths = nil
        cache.codexScanCatchUpPending = true
        return true
        #else
        return false
        #endif
    }
}
