#if os(Windows) && DEBUG
import Foundation
import Testing
@testable import CodexBarCore

/// Implementation-only fixtures. All input, cache and pricing paths belong to a temporary tree.
@Suite(.serialized)
struct WindowsCostClaudeContentTests {
    private struct Fixture {
        let root: URL
        let file: URL
        let options: CostUsageScanner.Options
        let day: Date
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        init() throws {
            self.root = FileManager.default.temporaryDirectory
                .appendingPathComponent("codexbar-claude-content-\(UUID().uuidString)", isDirectory: true)
            let logs = self.root.appendingPathComponent("logs", isDirectory: true)
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            self.file = logs.appendingPathComponent("session.jsonl")
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
            self.day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
            var options = CostUsageScanner.Options(
                claudeProjectsRoots: [logs], cacheRoot: self.root.appendingPathComponent("cache"), calendar: calendar)
            options.refreshMinIntervalSeconds = 3600
            self.options = options
        }

        func event(input: Int, id: String = "first") throws -> Data {
            let object: [String: Any] = [
                "type": "assistant", "timestamp": "2026-08-01T12:00:00Z", "requestId": "request-\(id)",
                "metadata": ["provider": "vertex"],
                "message": ["id": id, "model": "synthetic-claude-cost-model",
                            "usage": ["input_tokens": input, "output_tokens": 0]],
            ]
            var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            data.append(10)
            return data
        }

        func write(_ data: Data) throws {
            try data.write(to: self.file)
            try FileManager.default.setAttributes([.modificationDate: self.timestamp], ofItemAtPath: self.file.path)
        }

        func rewrite(_ data: Data) throws {
            let writer = try FileHandle(forWritingTo: self.file)
            try writer.write(contentsOf: data)
            try writer.truncate(atOffset: UInt64(data.count))
            try writer.close()
            try FileManager.default.setAttributes([.modificationDate: self.timestamp], ofItemAtPath: self.file.path)
        }

        func append(_ data: Data) throws {
            let writer = try FileHandle(forWritingTo: self.file)
            _ = try writer.seekToEnd()
            try writer.write(contentsOf: data)
            try writer.close()
        }

        func load(
            provider: UsageProvider = .claude,
            checkCancellation: CostUsageScanner.CancellationCheck? = nil) throws -> CostUsageDailyReport
        {
            try CostUsageScanner.loadDailyReportCancellable(
                provider: provider, since: self.day, until: self.day, now: self.day,
                options: self.options, checkCancellation: checkCancellation)
        }

        func cacheURL(provider: UsageProvider = .claude) -> URL {
            CostUsageClaudeCacheIO.cacheFileURL(provider: provider, cacheRoot: self.options.cacheRoot)
        }

        func evict(provider: UsageProvider = .claude) {
            CostUsageScanner.evictClaudeReportMemoForTesting(provider: provider, cacheRoot: self.options.cacheRoot)
        }

        func cleanup() {
            self.evict()
            self.evict(provider: .vertexai)
            try? FileManager.default.removeItem(at: self.root)
        }
    }

    @Test(arguments: [UsageProvider.claude, .vertexai], [false, true])
    func `same native stamp rewrite invalidates warm and persisted reports`(
        provider: UsageProvider, cold: Bool) throws
    {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.write(fixture.event(input: 10))
        #expect(try fixture.load(provider: provider).summary?.totalInputTokens == 10)
        let stamp = try CostUsageClaudeFileStamp.readRequired(at: fixture.file)
        try fixture.rewrite(fixture.event(input: 90))
        #expect(try CostUsageClaudeFileStamp.readRequired(at: fixture.file) == stamp)
        if cold { fixture.evict(provider: provider) }
        let work = CostUsageScanner.ClaudeScanWorkRecorder()
        let report = try CostUsageScanner.withClaudeScanWorkRecorderForTesting(work) {
            try fixture.load(provider: provider)
        }
        #expect(report.summary?.totalInputTokens == 90)
        #expect(work.snapshot().transcriptParses == 1)
        #expect(work.snapshot().incrementalTranscriptParses == 0)
    }

    @Test
    func `persisted memo and row cache retain parser proofs and reuse unchanged content`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.write(fixture.event(input: 10))
        let initial = try fixture.load()
        let artifact = CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: fixture.options.cacheRoot)
        let proof = try #require(artifact.windowsReadProofs[fixture.file.path])
        #expect(proof.parsedBytes == artifact.usage.files[fixture.file.path]?.parsedBytes)
        let path = fixture.cacheURL().standardizedFileURL.resolvingSymlinksInPath().path
        let diskEntry = try #require(CostUsageClaudeReportMemo().entry(provider: .claude, canonicalCachePath: path))
        #expect(diskEntry.windowsReadProofs == artifact.windowsReadProofs)
        #expect(artifact.windowsScanConfiguration == diskEntry.reportKey.scanConfiguration)
        let before = try CostUsageClaudeFileStamp.readRequired(at: fixture.cacheURL())
        fixture.evict()
        let work = CostUsageScanner.ClaudeScanWorkRecorder()
        let reused = try CostUsageScanner.withClaudeScanWorkRecorderForTesting(work) { try fixture.load() }
        #expect(reused.data == initial.data)
        #expect(reused.summary == initial.summary)
        #expect(work.snapshot() == CostUsageScanner.ClaudeScanWorkMetrics())
        #expect(try CostUsageClaudeFileStamp.readRequired(at: fixture.cacheURL()) == before)
    }

    @Test
    func `legacy memo and row cache without byte proofs are rebuilt within the refresh interval`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.write(fixture.event(input: 10))
        _ = try fixture.load()
        let cacheURL = fixture.cacheURL()
        let memoURL = CostUsageClaudeReportMemo.reportMemoFileURL(cacheFileURL: cacheURL)
        for url in [cacheURL, memoURL] {
            var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            object["windowsReadProofs"] = nil
            try JSONSerialization.data(withJSONObject: object).write(to: url)
        }
        fixture.evict()
        #expect(CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: fixture.options.cacheRoot)
            .windowsReadProofs.isEmpty)
        try fixture.rewrite(fixture.event(input: 90))
        let work = CostUsageScanner.ClaudeScanWorkRecorder()
        let report = try CostUsageScanner.withClaudeScanWorkRecorderForTesting(work) { try fixture.load() }
        #expect(report.summary?.totalInputTokens == 90)
        #expect(work.snapshot().transcriptParses == 1)
        #expect(work.snapshot().incrementalTranscriptParses == 0)
        #expect(CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: fixture.options.cacheRoot)
            .windowsReadProofs[fixture.file.path] != nil)
    }

    @Test
    func `legacy report memo cannot bypass row proof checks when artifact stamps still match`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.write(fixture.event(input: 10))
        _ = try fixture.load()
        let memoURL = CostUsageClaudeReportMemo.reportMemoFileURL(cacheFileURL: fixture.cacheURL())
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: memoURL)) as? [String: Any])
        object["windowsReadProofs"] = nil
        try JSONSerialization.data(withJSONObject: object).write(to: memoURL)
        fixture.evict()
        let work = CostUsageScanner.ClaudeScanWorkRecorder()
        let report = try CostUsageScanner.withClaudeScanWorkRecorderForTesting(work) { try fixture.load() }
        #expect(report.summary?.totalInputTokens == 10)
        #expect(work.snapshot().cacheDecodes == 1)
        #expect(work.snapshot().transcriptParses == 0)
    }

    @Test
    func `filter changes reparse the row cache without a report memo`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.write(fixture.event(input: 10))
        #expect(try fixture.load().summary?.totalInputTokens == 10)
        fixture.evict()
        let memoURL = CostUsageClaudeReportMemo.reportMemoFileURL(cacheFileURL: fixture.cacheURL())
        try FileManager.default.moveItem(at: memoURL, to: fixture.root.appendingPathComponent("retained-memo.json"))
        var options = fixture.options
        options.claudeLogProviderFilter = .excludeVertexAI
        let work = CostUsageScanner.ClaudeScanWorkRecorder()
        let report = try CostUsageScanner.withClaudeScanWorkRecorderForTesting(work) {
            try CostUsageScanner.loadDailyReportCancellable(
                provider: .claude, since: fixture.day, until: fixture.day, now: fixture.day,
                options: options, checkCancellation: nil)
        }
        #expect((report.summary?.totalInputTokens ?? 0) == 0)
        #expect(work.snapshot().transcriptParses == 1)
        #expect(work.snapshot().incrementalTranscriptParses == 0)
        let artifact = CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: options.cacheRoot)
        #expect(artifact.windowsScanConfiguration?.providerFilter == "exclude-vertex-ai")
    }

    @Test
    func `append resumes at the complete boundary and reparses an unfinished row`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let first = try fixture.event(input: 10)
        let second = try fixture.event(input: 20, id: "second")
        let split = second.count / 2
        var prefix = first
        prefix.append(second.prefix(split))
        try fixture.write(prefix)
        #expect(try fixture.load().summary?.totalInputTokens == 10)
        let old = try #require(CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: fixture.options.cacheRoot)
            .windowsReadProofs[fixture.file.path])
        #expect(old.parsedBytes == Int64(first.count))
        #expect(old.committedAnchor?.indexedBytes == Int64(first.count))
        #expect(old.readAnchor?.indexedBytes == Int64(prefix.count))
        try fixture.append(Data(second.dropFirst(split)))
        let work = CostUsageScanner.ClaudeScanWorkRecorder()
        let report = try CostUsageScanner.withClaudeScanWorkRecorderForTesting(work) { try fixture.load() }
        #expect(report.summary?.totalInputTokens == 30)
        #expect(work.snapshot().incrementalTranscriptParses == 1)
        let current = try #require(CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: fixture.options.cacheRoot)
            .windowsReadProofs[fixture.file.path])
        #expect(current.committedAnchor == current.readAnchor)
    }

    @Test
    func `changed inherited prefix discards old rows before an append`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.write(fixture.event(input: 10))
        _ = try fixture.load()
        try fixture.rewrite(fixture.event(input: 90))
        try fixture.append(fixture.event(input: 20, id: "second"))
        let work = CostUsageScanner.ClaudeScanWorkRecorder()
        let report = try CostUsageScanner.withClaudeScanWorkRecorderForTesting(work) { try fixture.load() }
        #expect(report.summary?.totalInputTokens == 110)
        #expect(work.snapshot().incrementalTranscriptParses == 0)
        #expect(work.snapshot().transcriptParses == 1)
    }

    @Test(arguments: [false, true])
    func `same stamp mutation at cache or memo staging rejects report publication`(atMemo: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.write(fixture.event(input: 10))
        _ = try fixture.load()
        let cacheURL = fixture.cacheURL()
        let memoURL = CostUsageClaudeReportMemo.reportMemoFileURL(cacheFileURL: cacheURL)
        let beforeCache = try Data(contentsOf: cacheURL)
        let beforeMemo = try Data(contentsOf: memoURL)
        let cachePath = cacheURL.standardizedFileURL.resolvingSymlinksInPath().path
        let memo = CostUsageClaudeReportMemo.shared
        let beforeEntry = try #require(memo.entry(provider: .claude, canonicalCachePath: cachePath))
        let target = atMemo ? memoURL : cacheURL
        try fixture.rewrite(fixture.event(input: 20))
        let expected = try CostUsageClaudeFileStamp.readRequired(at: fixture.file)
        var changed = false
        #expect(throws: CostUsageSourcePublication.Failure.self) {
            _ = try fixture.load(checkCancellation: {
                guard !changed else { return }
                let files = try FileManager.default.contentsOfDirectory(atPath: cacheURL.deletingLastPathComponent().path)
                guard files.contains(where: { $0.hasPrefix(".\(target.lastPathComponent).codexbar-staged-") })
                else { return }
                changed = true
                try fixture.rewrite(fixture.event(input: 90))
            })
        }
        #expect(changed)
        #expect(try CostUsageClaudeFileStamp.readRequired(at: fixture.file) == expected)
        if atMemo {
            // Cache and memo are distinct publications. A successful earlier cache write is
            // retained with its own proof; the next load must reject it against the new source.
            #expect(try Data(contentsOf: cacheURL) != beforeCache)
            #expect(CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: fixture.options.cacheRoot)
                .usage.files[fixture.file.path]?.claudeRows?.first?.input == 20)
        } else {
            #expect(try Data(contentsOf: cacheURL) == beforeCache)
        }
        #expect(try Data(contentsOf: memoURL) == beforeMemo)
        #expect(memo.entry(provider: .claude, canonicalCachePath: cachePath)?.windowsReadProofs
            == beforeEntry.windowsReadProofs)
        #expect(try fixture.load().summary?.totalInputTokens == 90)
    }

    @Test
    func `proof validation preserves cancellation and access errors`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.write(fixture.event(input: 10))
        _ = try fixture.load()
        let proof = try #require(CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: fixture.options.cacheRoot)
            .windowsReadProofs[fixture.file.path])
        let stamp = try CostUsageClaudeFileStamp.readRequired(at: fixture.file)
        enum Stopped: Error { case requested }
        #expect(throws: Stopped.self) {
            try proof.matchesContent(at: fixture.file, stamp: stamp, checkCancellation: { throw Stopped.requested })
        }
        try FileManager.default.moveItem(at: fixture.file, to: fixture.root.appendingPathComponent("retained.jsonl"))
        #expect(throws: (any Error).self) {
            try proof.matchesContent(at: fixture.file, stamp: stamp, checkCancellation: nil)
        }
    }

    @Test
    func `bounded memo verification resumes across refreshes without reparsing or rewriting the cache`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.write(fixture.event(input: 10))
        let second = fixture.root.appendingPathComponent("logs/session-b.jsonl")
        try fixture.event(input: 20, id: "second").write(to: second)
        try FileManager.default.setAttributes([.modificationDate: fixture.timestamp], ofItemAtPath: second.path)
        #expect(try fixture.load().summary?.totalInputTokens == 30)
        var bounded = fixture.options
        bounded.maxWindowsClaudeVerificationEntriesPerRefresh = 1
        let cacheStamp = try CostUsageClaudeFileStamp.readRequired(at: fixture.cacheURL())
        let work = CostUsageScanner.ClaudeScanWorkRecorder()
        var pendings = 0
        var report: CostUsageDailyReport?
        try CostUsageScanner.withClaudeScanWorkRecorderForTesting(work) {
            for _ in 0..<16 {
                if report != nil { break }
                do {
                    report = try CostUsageScanner.loadDailyReportCancellable(
                        provider: .claude, since: fixture.day, until: fixture.day, now: fixture.day,
                        options: bounded, checkCancellation: nil)
                } catch let error as CostUsageError {
                    guard case .localContentVerificationPending = error else { throw error }
                    pendings += 1
                }
            }
        }
        // With one entry per refresh and several observed paths, finishing at all proves the
        // memo-owned resume token carried the verifier forward instead of restarting each pass.
        #expect(pendings >= 1)
        let final = try #require(report)
        #expect(final.summary?.totalInputTokens == 30)
        #expect(work.snapshot().transcriptParses == 0)
        #expect(work.snapshot().incrementalTranscriptParses == 0)
        // A pending verification must not rewrite the cache artifact: a new stamp would break the
        // reportKey match that the next refresh depends on.
        #expect(try CostUsageClaudeFileStamp.readRequired(at: fixture.cacheURL()) == cacheStamp)
    }

    @Test
    func `fallback memo verification beyond lease capacity resumes by entry count`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        // More than the verifier's 64-lease capacity, so memo verification must use the
        // per-file fallback check sliced by entry count rather than native leases.
        for index in 0..<65 {
            let url = fixture.root.appendingPathComponent("logs/session-\(index).jsonl")
            try fixture.event(input: 10, id: "f\(index)").write(to: url)
            try FileManager.default.setAttributes([.modificationDate: fixture.timestamp], ofItemAtPath: url.path)
        }
        // The default file budget publishes 65 files over two collection refreshes, so the
        // first report must tolerate pending slices instead of a single load call.
        var initial: CostUsageDailyReport?
        for _ in 0..<8 {
            if initial != nil { break }
            do {
                initial = try fixture.load()
            } catch let error as CostUsageError {
                switch error {
                case .localInventoryPending, .localContentPending, .localContentVerificationPending:
                    break
                default:
                    throw error
                }
            }
        }
        #expect(initial?.summary?.totalInputTokens == 650)
        var bounded = fixture.options
        bounded.maxWindowsClaudeVerificationEntriesPerRefresh = 1
        let work = CostUsageScanner.ClaudeScanWorkRecorder()
        var pendings = 0
        var report: CostUsageDailyReport?
        try CostUsageScanner.withClaudeScanWorkRecorderForTesting(work) {
            for _ in 0..<80 {
                if report != nil { break }
                do {
                    report = try CostUsageScanner.loadDailyReportCancellable(
                        provider: .claude, since: fixture.day, until: fixture.day, now: fixture.day,
                        options: bounded, checkCancellation: nil)
                } catch let error as CostUsageError {
                    guard case .localContentVerificationPending = error else { throw error }
                    pendings += 1
                }
            }
        }
        // Finishing within the iteration bound proves the fallback cursor resumed: a restart
        // from zero would pend forever with one entry checked per refresh.
        #expect(pendings >= 1)
        let final = try #require(report)
        #expect(final.summary?.totalInputTokens == 650)
        #expect(work.snapshot().transcriptParses == 0)
        #expect(work.snapshot().incrementalTranscriptParses == 0)
    }

    @Test
    func `collection fallback verification resumes through the durable checkpoint cursor`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        // Beyond the verifier's 64-lease capacity, so the completed collection's final check
        // uses the per-entry fallback sliced by the persisted checkpoint cursor.
        for index in 0..<65 {
            let url = fixture.root.appendingPathComponent("logs/session-\(index).jsonl")
            try fixture.event(input: 10, id: "f\(index)").write(to: url)
            try FileManager.default.setAttributes([.modificationDate: fixture.timestamp], ofItemAtPath: url.path)
        }
        var bounded = fixture.options
        bounded.maxWindowsClaudeVerificationEntriesPerRefresh = 1
        let work = CostUsageScanner.ClaudeScanWorkRecorder()
        var pendings = 0
        var report: CostUsageDailyReport?
        try CostUsageScanner.withClaudeScanWorkRecorderForTesting(work) {
            for _ in 0..<160 {
                if report != nil { break }
                do {
                    report = try CostUsageScanner.loadDailyReportCancellable(
                        provider: .claude, since: fixture.day, until: fixture.day, now: fixture.day,
                        options: bounded, checkCancellation: nil)
                } catch let error as CostUsageError {
                    switch error {
                    case .localInventoryPending, .localContentPending, .localContentVerificationPending:
                        pendings += 1
                    default:
                        throw error
                    }
                }
            }
        }
        // Finishing within the bound proves the persisted cursor resumed: without it every
        // refresh would re-check only the first entry and pend forever.
        #expect(pendings >= 1)
        let final = try #require(report)
        #expect(final.summary?.totalInputTokens == 650)
        // Parsing happened once per file during collection; verification retries reparse none.
        #expect(work.snapshot().transcriptParses == 65)
        #expect(work.snapshot().incrementalTranscriptParses == 0)
    }

    @Test
    func `inventory revalidation rotates through a durable cursor`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        for index in 0..<4 {
            let url = fixture.root.appendingPathComponent("logs/session-\(index).jsonl")
            try fixture.event(input: 10, id: "f\(index)").write(to: url)
            try FileManager.default.setAttributes([.modificationDate: fixture.timestamp], ofItemAtPath: url.path)
        }
        var bounded = fixture.options
        bounded.maxWindowsClaudeInventoryWorkPerRefresh = 1
        bounded.maxWindowsClaudeFilesPerRefresh = 1
        var cursors: [Int] = []
        var report: CostUsageDailyReport?
        for _ in 0..<96 {
            if report != nil { break }
            do {
                report = try CostUsageScanner.loadDailyReportCancellable(
                    provider: .claude, since: fixture.day, until: fixture.day, now: fixture.day,
                    options: bounded, checkCancellation: nil)
            } catch let error as CostUsageError {
                switch error {
                case .localInventoryPending, .localContentVerificationPending:
                    break
                case .localContentPending:
                    if let cursor = CostUsageClaudeCacheIO.load(
                        provider: .claude, cacheRoot: bounded.cacheRoot
                    ).windowsInventory?.publicationCheckedCount {
                        cursors.append(cursor)
                    }
                default:
                    throw error
                }
            }
        }
        // The durable cursor must advance through the canonical entry order across collection
        // pendings; a reset would pin it at the first entry forever.
        #expect(cursors == [1, 2, 3, 4])
        let final = try #require(report)
        #expect(final.summary?.totalInputTokens == 40)
    }

    @Test
    func `lease-less memo boundary resumes through the sliced ledger pass`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        // Beyond the verifier's 64-lease capacity, so memo verification stays lease-less and
        // the report boundary must slice the ledger check through its process-local cursor.
        for index in 0..<65 {
            let url = fixture.root.appendingPathComponent("logs/session-\(index).jsonl")
            try fixture.event(input: 10, id: "f\(index)").write(to: url)
            try FileManager.default.setAttributes([.modificationDate: fixture.timestamp], ofItemAtPath: url.path)
        }
        // The default file budget publishes 65 files over two collection refreshes, so the
        // first report must tolerate pending slices instead of a single load call.
        var initial: CostUsageDailyReport?
        for _ in 0..<8 {
            if initial != nil { break }
            do {
                initial = try fixture.load()
            } catch let error as CostUsageError {
                switch error {
                case .localInventoryPending, .localContentPending, .localContentVerificationPending:
                    break
                default:
                    throw error
                }
            }
        }
        #expect(initial?.summary?.totalInputTokens == 650)
        var bounded = fixture.options
        bounded.maxWindowsClaudeVerificationEntriesPerRefresh = 1
        let work = CostUsageScanner.ClaudeScanWorkRecorder()
        var pendings = 0
        var report: CostUsageDailyReport?
        try CostUsageScanner.withClaudeScanWorkRecorderForTesting(work) {
            for _ in 0..<200 {
                if report != nil { break }
                do {
                    report = try CostUsageScanner.loadDailyReportCancellable(
                        provider: .claude, since: fixture.day, until: fixture.day, now: fixture.day,
                        options: bounded, checkCancellation: nil)
                } catch let error as CostUsageError {
                    switch error {
                    case .localInventoryPending, .localContentPending, .localContentVerificationPending:
                        pendings += 1
                    default:
                        throw error
                    }
                }
            }
        }
        // Finishing within the bound proves the completed content pass stayed valid while
        // boundary slices resumed: restarting the digest pass each pending would never finish.
        #expect(pendings >= 1)
        let final = try #require(report)
        #expect(final.summary?.totalInputTokens == 650)
        #expect(work.snapshot().transcriptParses == 0)
        #expect(work.snapshot().incrementalTranscriptParses == 0)
    }

    @Test
    func `leased memo boundary resumes through verifier slices`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        for index in 0..<3 {
            let url = fixture.root.appendingPathComponent("logs/session-\(index).jsonl")
            try fixture.event(input: 10, id: "f\(index)").write(to: url)
            try FileManager.default.setAttributes([.modificationDate: fixture.timestamp], ofItemAtPath: url.path)
        }
        #expect(try fixture.load().summary?.totalInputTokens == 30)
        var bounded = fixture.options
        bounded.maxWindowsClaudeVerificationEntriesPerRefresh = 1
        let work = CostUsageScanner.ClaudeScanWorkRecorder()
        var pendings = 0
        var report: CostUsageDailyReport?
        try CostUsageScanner.withClaudeScanWorkRecorderForTesting(work) {
            for _ in 0..<48 {
                if report != nil { break }
                do {
                    report = try CostUsageScanner.loadDailyReportCancellable(
                        provider: .claude, since: fixture.day, until: fixture.day, now: fixture.day,
                        options: bounded, checkCancellation: nil)
                } catch let error as CostUsageError {
                    switch error {
                    case .localInventoryPending, .localContentPending, .localContentVerificationPending:
                        pendings += 1
                    default:
                        throw error
                    }
                }
            }
        }
        // Finishing within the bound proves the parked verifier resumed its metadata cursor:
        // a cursor that reset each refresh would re-check only the first entry and pend forever.
        #expect(pendings >= 1)
        let final = try #require(report)
        #expect(final.summary?.totalInputTokens == 30)
        #expect(work.snapshot().transcriptParses == 0)
        #expect(work.snapshot().incrementalTranscriptParses == 0)
    }
}
#endif
