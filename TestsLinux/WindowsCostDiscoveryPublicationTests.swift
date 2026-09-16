#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

/// These fixtures share the serialized suite that owns the store interleaving hook.
/// Source only: no scanner, store, or Windows filesystem operation was executed on the Mac.
extension WindowsCostPublicationTests {
    private func makeDiscoveryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-discovery-publication-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test
    func `paged and full discovery reject a missing root reappearing before commit`() throws {
        for paged in [false, true] {
            let root = try self.makeDiscoveryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let sessions = root.appendingPathComponent("logs", isDirectory: true)
            let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
            let store = CostUsageStore(cacheRoot: cacheRoot)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
            let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
            let options = CostUsageScanner.Options(
                codexSessionsRoot: sessions, cacheRoot: cacheRoot,
                codexTraceDatabaseURL: root.appendingPathComponent("absent-trace.sqlite"), calendar: calendar,
                forceRescan: !paged, maxCodexScanDurationPerRefresh: paged ? 60 : nil)
            var mutationError: (any Error)?
            var reachedCheckpoint = false
            CostUsageStore.identicalContentPreLockCheckpointForTesting = (store.databaseURL, {
                reachedCheckpoint = true
                do {
                    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: false)
                } catch { mutationError = error }
            })
            defer { CostUsageStore.identicalContentPreLockCheckpointForTesting = nil }
            #expect(throws: CostUsageSourcePublication.Failure.self) {
                try CostUsageScanner.loadDailyReportCancellable(
                    provider: .codex, since: day, until: day, now: day,
                    options: options, checkCancellation: nil)
            }
            #expect(reachedCheckpoint)
            #expect(mutationError == nil)
            #expect(CostUsageStoreAccess.read(cacheRoot: cacheRoot, calendar: calendar).lastScanUnixMs == 0)
        }
    }

    @Test
    func `a newly created date partition invalidates the completed full inventory`() throws {
        let root = try self.makeDiscoveryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: false)
        let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
        let store = CostUsageStore(cacheRoot: cacheRoot)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let options = CostUsageScanner.Options(
            codexSessionsRoot: sessions, cacheRoot: cacheRoot,
            codexTraceDatabaseURL: root.appendingPathComponent("absent-trace.sqlite"),
            calendar: calendar, forceRescan: true)
        var mutationError: (any Error)?
        var reachedCheckpoint = false
        CostUsageStore.identicalContentPreLockCheckpointForTesting = (store.databaseURL, {
            reachedCheckpoint = true
            do {
                try FileManager.default.createDirectory(
                    at: sessions.appendingPathComponent("2026/08/01", isDirectory: true),
                    withIntermediateDirectories: true)
            } catch { mutationError = error }
        })
        defer { CostUsageStore.identicalContentPreLockCheckpointForTesting = nil }
        #expect(throws: CostUsageSourcePublication.Failure.self) {
            try CostUsageScanner.loadDailyReportCancellable(
                provider: .codex, since: day, until: day, now: day,
                options: options, checkCancellation: nil)
        }
        #expect(reachedCheckpoint)
        #expect(mutationError == nil)
        #expect(CostUsageStoreAccess.read(cacheRoot: cacheRoot, calendar: calendar).lastScanUnixMs == 0)
    }

    @Test
    func `cached source reuse detects same size and timestamp replacement and append`() throws {
        let root = try self.makeDiscoveryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.jsonl")
        try Data("first\n".utf8).write(to: source)
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: source.path)
        let initial = try WindowsCostFileMetadata.requiredFile(at: source)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let range = CostUsageScanner.CostUsageDayRange(since: day, until: day, calendar: calendar)
        var usage = CostUsageFileUsage(
            mtimeUnixMs: initial.mtimeUnixMs, size: initial.size,
            days: ["2026-08-01": ["synthetic-cost-model": [10, 0, 1]]])
        usage.codexScanFileId = initial.fileID
        usage.codexScanComplete = true
        var cache = CostUsageCache()
        cache.files[source.path] = usage
        let observations = CostUsagePublicationObservations()
        #expect(try !CostUsageScanner.observeCachedCodexSources(
            cache: cache, range: range, roots: [root],
            publicationObservations: observations, checkCancellation: nil).requiresRefresh)

        try FileManager.default.moveItem(at: source, to: root.appendingPathComponent("original.jsonl"))
        try Data("other\n".utf8).write(to: source)
        try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: source.path)
        #expect(throws: CostUsageSourcePublication.Failure.self) { try observations.freeze().check() }
        #expect(try CostUsageScanner.observeCachedCodexSources(
            cache: cache, range: range, roots: [root],
            publicationObservations: CostUsagePublicationObservations(), checkCancellation: nil).requiresRefresh)

        let replacement = try WindowsCostFileMetadata.requiredFile(at: source)
        cache.files[source.path]?.codexScanFileId = replacement.fileID
        let writer = try FileHandle(forWritingTo: source)
        _ = try writer.seekToEnd()
        try writer.write(contentsOf: Data("tail\n".utf8))
        try writer.close()
        #expect(try CostUsageScanner.observeCachedCodexSources(
            cache: cache, range: range, roots: [root],
            publicationObservations: CostUsagePublicationObservations(), checkCancellation: nil).requiresRefresh)
    }

    @Test
    func `cache reuse records absence and propagates wrong kind and cancellation`() throws {
        let root = try self.makeDiscoveryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("absent.jsonl")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let range = CostUsageScanner.CostUsageDayRange(since: day, until: day, calendar: calendar)
        var cache = CostUsageCache()
        cache.files[source.path] = CostUsageFileUsage(
            mtimeUnixMs: 1, size: 3, days: ["2026-08-01": ["synthetic-cost-model": [1, 0, 0]]])
        let observations = CostUsagePublicationObservations()
        #expect(try CostUsageScanner.observeCachedCodexSources(
            cache: cache, range: range, roots: [root],
            publicationObservations: observations, checkCancellation: nil).requiresRefresh)
        try observations.freeze().check()
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        #expect(throws: CostUsageSourcePublication.Failure.self) { try observations.freeze().check() }
        #expect(throws: WindowsCostSourceInventory.Failure.self) {
            try CostUsageScanner.observeCachedCodexSources(
                cache: cache, range: range, roots: [root],
                publicationObservations: CostUsagePublicationObservations(), checkCancellation: nil)
        }
        enum Cancelled: Error { case requested }
        #expect(throws: Cancelled.self) {
            try CostUsageScanner.observeCachedCodexSources(
                cache: cache, range: range, roots: [root],
                publicationObservations: CostUsagePublicationObservations(),
                checkCancellation: { throw Cancelled.requested })
        }
    }

    @Test
    func `a durable missing candidate can leave the bounded scan queue`() throws {
        for timed in [false, true] {
            let root = try self.makeDiscoveryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let sessions = root.appendingPathComponent("logs", isDirectory: true)
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: false)
            let missing = sessions.appendingPathComponent("removed.jsonl")
            let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
            let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
            let range = CostUsageScanner.CostUsageDayRange(since: day, until: day, calendar: calendar)
            let options = CostUsageScanner.Options(
                codexSessionsRoot: sessions, cacheRoot: cacheRoot,
                codexTraceDatabaseURL: root.appendingPathComponent("absent-trace.sqlite"),
                calendar: calendar, maxCodexScanDurationPerRefresh: timed ? 60 : nil)
            var cache = CostUsageCache()
            cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
            cache.scanSinceKey = range.scanSinceKey
            cache.scanUntilKey = range.scanUntilKey
            cache.timeZoneIdentifier = calendar.timeZone.identifier
            cache.codexScanCatchUpPending = true
            cache.codexActiveLookbackState = CostUsageCodexActiveLookbackState(
                scanSinceKey: range.scanSinceKey,
                rootPaths: [sessions.standardizedFileURL.path],
                pendingFilePaths: [missing.path])
            let seed = CostUsageStoreAccess.replace(cacheRoot: cacheRoot, cache: cache, calendar: calendar)
            try #require(!seed.catchUpRequired)
            _ = try CostUsageScanner.loadDailyReportCancellable(
                provider: .codex, since: day, until: day, now: day,
                options: options, checkCancellation: nil)
            let saved = CostUsageStoreAccess.read(cacheRoot: cacheRoot, calendar: calendar)
            #expect(saved.lastScanUnixMs > 0)
            #expect(saved.codexActiveLookbackState?.pendingFilePaths.contains(missing.path) != true)
            #expect(saved.files[missing.path] == nil)
        }
    }
}
#endif
