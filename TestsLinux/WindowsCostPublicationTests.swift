#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

/// Implementation-only Windows fixtures; no filesystem or SQLite fixture was run on the Mac.
@Suite(.serialized)
struct WindowsCostPublicationTests {
    private func makeDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-cost-publication-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func observe(_ file: URL) throws -> CostUsageSourcePublication {
        let observations = CostUsagePublicationObservations()
        try observations.file(file, snapshot: #require(CostUsageFileReadSnapshot.capture(at: file)))
        return observations.freeze()
    }

    private func truncate(_ file: URL) throws {
        let writer = try FileHandle(forWritingTo: file)
        defer { try? writer.close() }
        try writer.truncate(atOffset: 0)
    }

    @Test
    func `publication accepts an appended tail but rejects a replacement`() throws {
        let root = try self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source.jsonl")
        try Data("first\n".utf8).write(to: file)
        let publication = try self.observe(file)
        let writer = try FileHandle(forWritingTo: file)
        _ = try writer.seekToEnd()
        try writer.write(contentsOf: Data("second\n".utf8))
        try writer.close()
        try publication.check()
        try FileManager.default.moveItem(at: file, to: root.appendingPathComponent("original.jsonl"))
        try Data("first\nsecond\n".utf8).write(to: file)
        #expect(throws: CostUsageSourcePublication.Failure.self) { try publication.check() }
    }

    @Test
    func `absent roots and replaced directories invalidate inventory publication`() throws {
        let root = try self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("sessions", isDirectory: true)
        let missing = CostUsagePublicationObservations()
        #expect(try WindowsCostSourceInventory.jsonlFiles(in: source, publicationObservations: missing) == nil)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        #expect(throws: CostUsageSourcePublication.Failure.self) { try missing.freeze().check() }

        let empty = CostUsagePublicationObservations()
        #expect(try WindowsCostDirectoryInventory.read(in: source, publicationObservations: empty)?.entries.isEmpty == true)
        try FileManager.default.moveItem(at: source, to: root.appendingPathComponent("original"))
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        #expect(throws: CostUsageSourcePublication.Failure.self) { try empty.freeze().check() }
    }

    @Test
    func `cache publication failure preserves the previous Claude bytes`() throws {
        let root = try self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.jsonl")
        try Data("{}\n".utf8).write(to: source)
        let publication = try self.observe(source)
        _ = try #require(CostUsageClaudeCacheIO.save(provider: .claude, cache: .init(), cacheRoot: root))
        let target = CostUsageClaudeCacheIO.cacheFileURL(provider: .claude, cacheRoot: root)
        let original = try Data(contentsOf: target)
        let originalStamp = try #require(CostUsageClaudeFileStamp.read(at: target))
        var replacement = CostUsageClaudeCache()
        replacement.usage.lastScanUnixMs = 2000
        var checks = 0
        #expect(throws: CostUsageSourcePublication.Failure.self) {
            _ = try CostUsageClaudeCacheIO.save(
                provider: .claude, cache: replacement, cacheRoot: root,
                checkCancellation: {
                    checks += 1
                    // Initial cancellation + one-entry preflight + its final cancellation have
                    // completed. Mutate when the protected writer reaches its staging callback.
                    if checks == 4 { try self.truncate(source) }
                },
                sourcePublication: publication)
        }
        #expect(checks >= 4)
        #expect(try Data(contentsOf: target) == original)
        #expect(CostUsageClaudeFileStamp.read(at: target) == originalStamp)
    }

    @Test
    func `memo publication failure preserves the old disk and memory entry`() throws {
        let root = try self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.jsonl")
        try Data("{}\n".utf8).write(to: source)
        let publication = try self.observe(source)
        let cachePath = root.appendingPathComponent("claude-cache.json").path
        let key = CostUsageClaudeReportMemoKey(
            provider: .claude, providerFilter: "all", sinceKey: "2026-08-01", untilKey: "2026-08-01",
            scanSinceKey: "2026-08-01", scanUntilKey: "2026-08-01", timeZoneIdentifier: "GMT",
            roots: [], cacheArtifactStamp: nil, pricingArtifactStamp: nil)
        let memo = CostUsageClaudeReportMemo()
        let stamp = try #require(CostUsageClaudeFileStamp.read(at: source))
        try memo.store(
            provider: .claude, canonicalCachePath: cachePath, sourceInventory: [source.path: stamp],
            reportKey: key, report: .init(data: [], summary: nil))
        let target = CostUsageClaudeReportMemo.reportMemoFileURL(cacheFileURL: URL(fileURLWithPath: cachePath))
        let original = try Data(contentsOf: target)
        var checks = 0
        #expect(throws: CostUsageSourcePublication.Failure.self) {
            try memo.store(
                provider: .claude, canonicalCachePath: cachePath, sourceInventory: [:],
                reportKey: key, report: .init(data: [], summary: nil), sourcePublication: publication,
                checkCancellation: {
                    checks += 1
                    // One-entry preflight and its final check precede the staging callback.
                    if checks == 3 { try self.truncate(source) }
                })
        }
        #expect(checks >= 3)
        #expect(try Data(contentsOf: target) == original)
        #expect(memo.entry(provider: .claude, canonicalCachePath: cachePath)?.sourceInventory == [source.path: stamp])
    }

    @Test
    func `changed and identical Codex saves roll back source failure without rebuilding`() async throws {
        let root = try self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.jsonl")
        let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var initial = CostUsageCache()
        initial.lastScanUnixMs = 1000
        initial.scanSinceKey = "2026-08-01"
        initial.scanUntilKey = "2026-08-01"
        initial.timeZoneIdentifier = calendar.timeZone.identifier
        initial.roots = ["synthetic-root": 1]
        let seed = CostUsageStoreAccess.replace(cacheRoot: cacheRoot, cache: initial, calendar: calendar)
        try #require(!seed.catchUpRequired)

        for identical in [false, true] {
            try Data("{}\n".utf8).write(to: source)
            let publication = try self.observe(source)
            let loaded = CostUsageStoreAccess.load(cacheRoot: cacheRoot, calendar: calendar)
            defer { loaded.release() }
            var candidate = loaded.cache
            candidate.lastScanUnixMs = 2000
            if !identical { candidate.roots = ["synthetic-root": 2] }
            var mutationError: (any Error)?
            var reachedCheckpoint = false
            CostUsageStore.identicalContentPreLockCheckpointForTesting = (loaded.store.databaseURL, {
                reachedCheckpoint = true
                do { try self.truncate(source) } catch { mutationError = error }
            })
            defer { CostUsageStore.identicalContentPreLockCheckpointForTesting = nil }
            let result = CostUsageStoreAccess.save(
                store: loaded.store, cache: candidate, calendar: calendar,
                requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
                skipIdenticalContent: identical, receipt: loaded.receipt, sourcePublication: publication)
            #expect(reachedCheckpoint)
            #expect(mutationError == nil)
            #expect(result.catchUpRequired)
            #expect(result.sourceValidationFailed)
            #expect(await loaded.store.rebuildCount == 0)
            let retained = CostUsageStoreAccess.read(cacheRoot: cacheRoot, calendar: calendar)
            #expect(retained.lastScanUnixMs == 1000)
            #expect(retained.roots == initial.roots)
        }
    }
}
#endif
