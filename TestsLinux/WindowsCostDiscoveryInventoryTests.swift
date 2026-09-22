#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

/// Unexecuted Windows source fixtures, sharing the serialized publication-hook suite.
extension WindowsCostPublicationTests {
    private struct DiscoveryFixture {
        let root: URL
        let logs: URL
        let dayDirectory: URL
        let options: CostUsageScanner.Options
        let range: CostUsageScanner.CostUsageDayRange
        let day: Date
        let fixedTime = Date(timeIntervalSince1970: 1_700_000_000)

        init() throws {
            self.root = FileManager.default.temporaryDirectory
                .appendingPathComponent("codexbar-main-discovery-\(UUID().uuidString)", isDirectory: true)
            self.logs = self.root.appendingPathComponent("logs", isDirectory: true)
            self.dayDirectory = self.logs.appendingPathComponent("2026/08/01", isDirectory: true)
            try FileManager.default.createDirectory(at: self.dayDirectory, withIntermediateDirectories: true)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
            self.day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
            self.range = CostUsageScanner.CostUsageDayRange(since: self.day, until: self.day, calendar: calendar)
            var options = CostUsageScanner.Options(
                codexSessionsRoot: self.logs, cacheRoot: self.root.appendingPathComponent("cache"),
                codexTraceDatabaseURL: self.root.appendingPathComponent("absent-trace.sqlite"), calendar: calendar)
            options.refreshMinIntervalSeconds = 3600
            self.options = options
        }

        var rootPaths: [String] { [self.logs.resolvingSymlinksInPath().standardizedFileURL.path] }

        func setTime(_ url: URL) throws {
            try FileManager.default.setAttributes([.modificationDate: self.fixedTime], ofItemAtPath: url.path)
        }

        func inventory() throws -> CostUsageWindowsDiscoveryInventory {
            let observations = CostUsagePublicationObservations()
            _ = try CostUsageScanner.codexDirectoryExists(directoryURL: self.logs, publicationObservations: observations)
            _ = try WindowsCostDirectoryInventory.read(in: self.dayDirectory, publicationObservations: observations)
            return try CostUsageWindowsDiscoveryInventory.capture(
                roots: [self.logs], range: self.range, publication: observations.freeze())
        }

        func reconcile(
            _ cache: inout CostUsageCache,
            observations: CostUsagePublicationObservations = CostUsagePublicationObservations(),
            checkCancellation: CostUsageScanner.CancellationCheck? = nil) throws -> Bool
        {
            try CostUsageScanner.reconcileWindowsCodexDiscovery(
                cache: &cache, roots: [self.logs], resolvedRootPaths: self.rootPaths, range: self.range,
                options: self.options, publicationObservations: observations, checkCancellation: checkCancellation)
        }

        func writeSession(name: String, input: Int) throws {
            let events: [[String: Any]] = [
                ["type": "session_meta", "timestamp": "2026-08-01T12:00:00Z", "payload": ["id": name]],
                ["type": "turn_context", "timestamp": "2026-08-01T12:00:00Z",
                 "payload": ["model": "synthetic-discovery-model"]],
                ["type": "event_msg", "timestamp": "2026-08-01T12:00:01Z",
                 "payload": ["type": "token_count", "info": ["total_token_usage": [
                    "input_tokens": input, "cached_input_tokens": 0, "output_tokens": 0]]]],
            ]
            var data = Data()
            for event in events {
                data.append(try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]))
                data.append(10)
            }
            try data.write(to: self.dayDirectory.appendingPathComponent("\(name).jsonl"))
        }

        func load() throws -> CostUsageDailyReport {
            try CostUsageScanner.loadDailyReportCancellable(
                provider: .codex, since: self.day, until: self.day, now: self.day,
                options: self.options, checkCancellation: nil)
        }

        func cleanup() {
            CostUsageScanner.resetCodexDirectoryCursorsForTesting(under: self.logs)
            try? FileManager.default.removeItem(at: self.root)
        }
    }

    @Test
    func `replaced completed directory resets discovery while retaining pending files`() throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.cleanup() }
        try fixture.setTime(fixture.logs)
        try fixture.setTime(fixture.dayDirectory)
        let old = try fixture.inventory()
        let pending = fixture.dayDirectory.appendingPathComponent("pending.jsonl").path
        let cached = fixture.dayDirectory.appendingPathComponent("cached.jsonl").path
        var cache = CostUsageCache()
        cache.codexWindowsDiscoveryInventory = try JSONDecoder().decode(
            CostUsageWindowsDiscoveryInventory.self, from: JSONEncoder().encode(old))
        cache.files[cached] = CostUsageFileUsage(mtimeUnixMs: 0, size: 0, days: [:])
        cache.codexActiveLookbackState = CostUsageCodexActiveLookbackState(
            scanSinceKey: fixture.range.scanSinceKey, rootPaths: fixture.rootPaths,
            nextDayKeyByRoot: [fixture.rootPaths[0]: "2026-07-31"],
            nextDirectoryOffsetByRoot: [fixture.rootPaths[0]: 22], completedRootPaths: fixture.rootPaths,
            pendingFilePaths: [pending], completedCurrentWindowRootPaths: fixture.rootPaths,
            completedCurrentWindowFlatRootPaths: fixture.rootPaths, cacheWideMigrationQueueActive: true)
        try FileManager.default.moveItem(
            at: fixture.dayDirectory, to: fixture.root.appendingPathComponent("retained-day"))
        try FileManager.default.createDirectory(at: fixture.dayDirectory, withIntermediateDirectories: false)
        try fixture.setTime(fixture.logs)
        try fixture.setTime(fixture.dayDirectory)
        #expect(try fixture.reconcile(&cache))
        let state = try #require(cache.codexActiveLookbackState)
        #expect(state.pendingFilePaths == [pending, cached])
        #expect(state.completedRootPaths.isEmpty)
        #expect(state.completedCurrentWindowRootPaths == nil)
        #expect(state.nextDayKeyByRoot.isEmpty)
        #expect(state.nextDirectoryOffsetByRoot == nil)
        #expect(state.legacyRecursivePendingRootPaths == fixture.rootPaths)
        #expect(state.cacheWideMigrationQueueActive == true)
        #expect(cache.codexWindowsDiscoveryInventory == nil)
        #expect(cache.codexScanCatchUpPending == true)
        #expect(cache.files[cached] != nil)
    }

    @Test
    func `legacy completed state cannot skip directories without native observations`() throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.cleanup() }
        var cache = CostUsageCache()
        cache.codexActiveLookbackState = CostUsageCodexActiveLookbackState(
            scanSinceKey: fixture.range.scanSinceKey, rootPaths: fixture.rootPaths,
            completedRootPaths: fixture.rootPaths, completedCurrentWindowRootPaths: fixture.rootPaths,
            completedCurrentWindowFlatRootPaths: fixture.rootPaths)
        #expect(try fixture.reconcile(&cache))
        #expect(cache.codexActiveLookbackState?.completedRootPaths.isEmpty == true)
        let legacy = try JSONDecoder().decode(CostUsageCache.self, from: JSONEncoder().encode(CostUsageCache()))
        #expect(legacy.codexWindowsDiscoveryInventory == nil)
    }

    @Test
    func `membership revalidation rotates through a durable cursor`() throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.cleanup() }
        try fixture.setTime(fixture.logs)
        try fixture.setTime(fixture.dayDirectory)
        var inventory = try fixture.inventory()
        let count = inventory.observations.count
        #expect(count >= 2)
        var cursors: [Int?] = []
        for _ in 0...count {
            #expect(try inventory.matches(
                roots: [fixture.logs], range: fixture.range, maxEntries: 1, checkCancellation: nil))
            cursors.append(inventory.matchCheckedCount)
        }
        // One entry per call: the cursor walks the sorted key order, wraps to nil when the
        // pass completes, and starts the next cycle at the first entry again.
        #expect(cursors == (1..<count).map { $0 } + [nil, 1])
        // A replaced directory is caught when the rotating pass reaches its entry.
        try FileManager.default.moveItem(
            at: fixture.dayDirectory, to: fixture.root.appendingPathComponent("retained-day"))
        try FileManager.default.createDirectory(at: fixture.dayDirectory, withIntermediateDirectories: false)
        try fixture.setTime(fixture.dayDirectory)
        var detected = false
        for _ in 0..<count where !detected {
            if try inventory.matches(
                roots: [fixture.logs], range: fixture.range, maxEntries: 1,
                checkCancellation: nil) == false
            {
                detected = true
            }
        }
        #expect(detected)
    }

    @Test
    func `restored earlier directory observations survive another partial refresh and final publication`() throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.cleanup() }
        var cache = CostUsageCache()
        cache.codexWindowsDiscoveryInventory = try fixture.inventory()
        let state = CostUsageCodexActiveLookbackState(
            scanSinceKey: fixture.range.scanSinceKey, rootPaths: fixture.rootPaths,
            currentWindowNextDayKeyByRoot: [fixture.rootPaths[0]: "2026-07-31"])
        cache.codexActiveLookbackState = state
        let observations = CostUsagePublicationObservations()
        #expect(try !fixture.reconcile(&cache, observations: observations))
        #expect(cache.codexActiveLookbackState == state)
        let next = try CostUsageWindowsDiscoveryInventory.capture(
            roots: [fixture.logs], range: fixture.range, publication: observations.freeze())
        #expect(next == cache.codexWindowsDiscoveryInventory)
        try FileManager.default.moveItem(
            at: fixture.dayDirectory, to: fixture.root.appendingPathComponent("retained-day"))
        try FileManager.default.createDirectory(at: fixture.dayDirectory, withIntermediateDirectories: false)
        #expect(throws: CostUsageSourcePublication.Failure.self) { try observations.freeze().check() }
    }

    @Test
    func `SQLite preserves directory inventory after the lookback queue is removed`() throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.cleanup() }
        var cache = CostUsageCache()
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: fixture.options)
        cache.scanSinceKey = fixture.range.scanSinceKey
        cache.scanUntilKey = fixture.range.scanUntilKey
        cache.codexWindowsDiscoveryInventory = try fixture.inventory()
        cache.codexActiveLookbackState = nil
        _ = CostUsageStoreAccess.replace(cacheRoot: fixture.options.cacheRoot, cache: cache, calendar: fixture.range.calendar)
        let restored = CostUsageStoreAccess.read(cacheRoot: fixture.options.cacheRoot, calendar: fixture.range.calendar)
        #expect(restored.codexActiveLookbackState == nil)
        #expect(restored.codexWindowsDiscoveryInventory == cache.codexWindowsDiscoveryInventory)
    }

    @Test
    func `new files in a completed date partition bypass a still fresh report`() throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.cleanup() }
        try fixture.writeSession(name: "first", input: 10)
        try fixture.setTime(fixture.logs)
        try fixture.setTime(fixture.dayDirectory)
        #expect(try fixture.load().summary?.totalInputTokens == 10)
        let originalRoot = try #require(WindowsCostFileMetadata.atURL(fixture.logs))
        let persisted = CostUsageStoreAccess.read(cacheRoot: fixture.options.cacheRoot, calendar: fixture.range.calendar)
        #expect(persisted.codexWindowsDiscoveryInventory != nil)
        try fixture.writeSession(name: "second", input: 20)
        try fixture.setTime(fixture.logs)
        #expect(try WindowsCostFileMetadata.atURL(fixture.logs) == originalRoot)
        #expect(try fixture.load().summary?.totalInputTokens == 30)
    }

    @Test
    func `first paged refresh retains the absent second root after its visit budget is exhausted`() throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.cleanup() }
        let sessions = fixture.root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: false)
        for index in 0..<520 {
            try Data().write(to: sessions.appendingPathComponent("ignored-\(index).txt"))
        }
        var options = fixture.options
        options.codexSessionsRoot = sessions
        options.maxCodexScanDurationPerRefresh = 60
        defer { CostUsageScanner.resetCodexDirectoryCursorsForTesting(under: sessions) }
        _ = try CostUsageScanner.loadDailyReportCancellable(
            provider: .codex, since: fixture.day, until: fixture.day, now: fixture.day,
            options: options, checkCancellation: nil)
        let cache = CostUsageStoreAccess.read(cacheRoot: options.cacheRoot, calendar: fixture.range.calendar)
        let inventory = try #require(cache.codexWindowsDiscoveryInventory)
        let archived = fixture.root.appendingPathComponent("archived_sessions", isDirectory: true)
        #expect(inventory.observations[archived.path] == .missing)
        #expect(inventory.observations[sessions.path] != nil)
        #expect(cache.codexActiveLookbackState != nil)
    }

    @Test
    func `absent partition reappearance invalidates retained inventory`() throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.cleanup() }
        let absent = fixture.logs.appendingPathComponent("2026/07/31", isDirectory: true)
        let observations = CostUsagePublicationObservations()
        _ = try CostUsageScanner.codexDirectoryExists(directoryURL: fixture.logs, publicationObservations: observations)
        #expect(try !CostUsageScanner.codexDirectoryExists(directoryURL: absent, publicationObservations: observations))
        var cache = CostUsageCache()
        cache.codexWindowsDiscoveryInventory = try CostUsageWindowsDiscoveryInventory.capture(
            roots: [fixture.logs], range: fixture.range, publication: observations.freeze())
        try FileManager.default.createDirectory(at: absent, withIntermediateDirectories: true)
        #expect(try fixture.reconcile(&cache))
    }

    @Test
    func `directory validation does not turn wrong kind or cancellation into a completed scan`() throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.cleanup() }
        try fixture.setTime(fixture.logs)
        var cache = CostUsageCache()
        cache.codexWindowsDiscoveryInventory = try fixture.inventory()
        let previous = cache
        enum Stopped: Error { case requested }
        #expect(throws: Stopped.self) {
            try fixture.reconcile(&cache, checkCancellation: { throw Stopped.requested })
        }
        #expect(cache == previous)
        try FileManager.default.moveItem(
            at: fixture.dayDirectory, to: fixture.root.appendingPathComponent("retained-day"))
        try Data("not a directory".utf8).write(to: fixture.dayDirectory)
        try fixture.setTime(fixture.logs)
        #expect(throws: WindowsCostSourceInventory.Failure.self) { try fixture.reconcile(&cache) }
        #expect(cache == previous)
    }
}
#endif
