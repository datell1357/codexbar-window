#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

/// Source-only Windows fixtures. These have not been compiled or executed on the Mac host.
@Suite(.serialized)
struct WindowsCostTreeInventoryTests {
    private struct Fixture {
        let root: URL
        let logs: URL
        let calendar: Calendar
        let day: Date

        init() throws {
            self.root = FileManager.default.temporaryDirectory
                .appendingPathComponent("codexbar-tree-pages-\(UUID().uuidString)", isDirectory: true)
            self.logs = self.root.appendingPathComponent("logs", isDirectory: true)
            try FileManager.default.createDirectory(at: self.logs, withIntermediateDirectories: true)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
            self.calendar = calendar
            self.day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        }

        func options(work: Int = 4096) -> CostUsageScanner.Options {
            var options = CostUsageScanner.Options(
                claudeProjectsRoots: [self.logs], cacheRoot: self.root.appendingPathComponent("cache"),
                calendar: self.calendar)
            options.maxWindowsClaudeInventoryWorkPerRefresh = work
            return options
        }

        func event(_ input: Int) throws -> Data {
            let object: [String: Any] = [
                "type": "assistant", "timestamp": "2026-08-01T12:00:00Z",
                "metadata": ["provider": "vertex"],
                "message": ["model": "synthetic-cost-tree-model", "usage": ["input_tokens": input]],
            ]
            var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            data.append(10)
            return data
        }

        func load(_ options: CostUsageScanner.Options, provider: UsageProvider = .claude,
                  checkCancellation: CostUsageScanner.CancellationCheck? = nil) throws -> CostUsageDailyReport {
            try CostUsageScanner.loadDailyReportCancellable(
                provider: provider, since: self.day, until: self.day, now: self.day,
                options: options, checkCancellation: checkCancellation)
        }

        func cache(_ provider: UsageProvider = .claude) -> CostUsageClaudeCache {
            CostUsageClaudeCacheIO.load(provider: provider, cacheRoot: self.options().cacheRoot, calendar: self.calendar)
        }

        func cleanup() {
            WindowsCostDirectoryPages.shared.reset(under: self.root)
            try? FileManager.default.removeItem(at: self.root)
        }
    }

    @Test
    func `recursive pages bound visits and metadata work through final validation`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var expected: Set<URL> = []
        for folder in 0..<4 {
            let directory = fixture.logs.appendingPathComponent("project-\(folder)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            for index in 0..<7 {
                let file = directory.appendingPathComponent("\(index).jsonl")
                try Data().write(to: file)
                expected.insert(file)
            }
            try Data().write(to: directory.appendingPathComponent("ignored.txt"))
        }
        let absent = fixture.root.appendingPathComponent("absent", isDirectory: true)
        var state = CostUsageWindowsTreeInventory(roots: [fixture.logs, absent])
        var complete = false
        var phases: Set<String> = []
        for _ in 0..<100 {
            let progress = try WindowsCostTreeInventory.advance(&state, maxWork: 3)
            #expect(progress.work <= 3)
            phases.insert(state.phase.rawValue)
            if progress.isComplete { complete = true; break }
            state = try JSONDecoder().decode(
                CostUsageWindowsTreeInventory.self, from: JSONEncoder().encode(state))
        }
        #expect(complete)
        #expect(phases.contains("files"))
        #expect(state.missingRoots == [absent.path])
        #expect(Set(try WindowsCostTreeInventory.representatives(state).keys) == expected)
        let observations = CostUsagePublicationObservations()
        try WindowsCostTreeInventory.observe(state, in: observations)
        try observations.freeze().check()
    }

    @Test
    func `completed directories survive process loss while the active directory is replayed`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let nested = fixture.logs.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        for index in 0..<18 { try Data().write(to: nested.appendingPathComponent("\(index).jsonl")) }
        var state = CostUsageWindowsTreeInventory(roots: [fixture.logs])
        for _ in 0..<30 {
            _ = try WindowsCostTreeInventory.advance(&state, maxWork: 2)
            if state.nextDirectory == 1, state.page != nil { break }
        }
        let checkpoint = try #require(state.page)
        #expect(state.nextDirectory == 1)
        state = try JSONDecoder().decode(CostUsageWindowsTreeInventory.self, from: JSONEncoder().encode(state))
        WindowsCostDirectoryPages.shared.reset(under: fixture.logs)
        _ = try WindowsCostTreeInventory.advance(&state, maxWork: 2)
        #expect(state.nextDirectory == 1)
        #expect(state.page?.cursorID != checkpoint.cursorID)
        var completed = false
        for _ in 0..<60 {
            if try WindowsCostTreeInventory.advance(&state, maxWork: 2).isComplete { completed = true; break }
        }
        #expect(completed)
        #expect(try WindowsCostTreeInventory.representatives(state).count == 18)
    }

    @Test
    func `appending an observed file between pages does not restart the directory tree`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let file = fixture.logs.appendingPathComponent("growing.jsonl")
        try Data("{}\n".utf8).write(to: file)
        for index in 0..<12 { try Data().write(to: fixture.logs.appendingPathComponent("ignored-\(index).txt")) }
        var state = CostUsageWindowsTreeInventory(roots: [fixture.logs])
        var completed = false
        for _ in 0..<80 {
            if state.files[file.path] != nil {
                let writer = try FileHandle(forWritingTo: file)
                _ = try writer.seekToEnd()
                try writer.write(contentsOf: Data("{}\n".utf8))
                try writer.close()
            }
            if try WindowsCostTreeInventory.advance(&state, maxWork: 1).isComplete { completed = true; break }
        }
        #expect(completed)
        let observed = try #require(WindowsCostTreeInventory.representatives(state)[file])
        #expect(observed.size > 3)
        let observations = CostUsagePublicationObservations()
        try WindowsCostTreeInventory.observe(state, in: observations)
        try observations.freeze().check()
    }

    @Test
    func `old page observations remain part of the final publication`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let file = fixture.logs.appendingPathComponent("file.jsonl")
        try Data().write(to: file)
        var state = CostUsageWindowsTreeInventory(roots: [fixture.logs])
        for _ in 0..<30 {
            if try WindowsCostTreeInventory.advance(&state, maxWork: 1).isComplete { break }
        }
        let observations = CostUsagePublicationObservations()
        try WindowsCostTreeInventory.observe(state, in: observations)
        try FileManager.default.moveItem(at: file, to: fixture.root.appendingPathComponent("retained.jsonl"))
        try Data().write(to: file)
        #expect(throws: CostUsageSourcePublication.Failure.self) { try observations.freeze().check() }
    }

    @Test(arguments: [UsageProvider.claude, .vertexai])
    func `pending inventory preserves completed usage and resumes into a complete report`(provider: UsageProvider) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let first = fixture.logs.appendingPathComponent("first.jsonl")
        try fixture.event(10).write(to: first)
        #expect(try fixture.load(fixture.options(), provider: provider).summary?.totalInputTokens == 10)
        let before = fixture.cache(provider)
        try fixture.event(20).write(to: fixture.logs.appendingPathComponent("second.jsonl"))
        for index in 0..<18 { try Data().write(to: fixture.logs.appendingPathComponent("ignored-\(index).txt")) }
        let limited = fixture.options(work: 3)
        do {
            _ = try fixture.load(limited, provider: provider)
            Issue.record("Partial inventory must not publish a report")
        } catch CostUsageError.localInventoryPending { }
        let partial = fixture.cache(provider)
        #expect(partial.windowsInventory != nil)
        #expect(partial.usage.lastScanUnixMs == before.usage.lastScanUnixMs)
        #expect(partial.usage.files[first.path]?.claudeRows == before.usage.files[first.path]?.claudeRows)
        #expect(partial.windowsReadProofs == before.windowsReadProofs)
        var completed = false
        for _ in 0..<50 {
            do {
                let report = try fixture.load(limited, provider: provider)
                #expect(report.summary?.totalInputTokens == 30)
                completed = true
                break
            } catch CostUsageError.localInventoryPending { }
        }
        #expect(completed)
        #expect(fixture.cache(provider).windowsInventory == nil)
    }

    @Test
    func `changed directories restart candidate discovery without erasing the prior cost report`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let file = fixture.logs.appendingPathComponent("original.jsonl")
        try fixture.event(7).write(to: file)
        #expect(try fixture.load(fixture.options()).summary?.totalInputTokens == 7)
        for index in 0..<8 { try Data().write(to: fixture.logs.appendingPathComponent("ignored-\(index).txt")) }
        let limited = fixture.options(work: 2)
        do { _ = try fixture.load(limited); Issue.record("Expected pending discovery") }
        catch CostUsageError.localInventoryPending { }
        try FileManager.default.moveItem(at: fixture.logs, to: fixture.root.appendingPathComponent("retained-logs"))
        try FileManager.default.createDirectory(at: fixture.logs, withIntermediateDirectories: false)
        try fixture.event(19).write(to: fixture.logs.appendingPathComponent("replacement.jsonl"))
        do { _ = try fixture.load(limited); Issue.record("Expected restarted discovery") }
        catch CostUsageError.localInventoryPending { }
        #expect(fixture.cache().usage.files[file.path] != nil)
        var completed = false
        for _ in 0..<30 {
            do {
                #expect(try fixture.load(limited).summary?.totalInputTokens == 19)
                completed = true
                break
            } catch CostUsageError.localInventoryPending { }
        }
        #expect(completed)
        #expect(fixture.cache().usage.files[file.path] == nil)
    }

    @Test
    func `calendar changes preserve the prior usage calendar until discovery completes`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let file = fixture.logs.appendingPathComponent("first.jsonl")
        try fixture.event(5).write(to: file)
        _ = try fixture.load(fixture.options())
        let before = fixture.cache()
        var options = fixture.options(work: 1)
        options.calendar.timeZone = try #require(TimeZone(secondsFromGMT: 9 * 3600))
        do { _ = try fixture.load(options); Issue.record("Expected pending discovery") }
        catch CostUsageError.localInventoryPending { }
        let partial = CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: options.cacheRoot)
        #expect(partial.usage.timeZoneIdentifier == before.usage.timeZoneIdentifier)
        #expect(partial.windowsScanConfiguration == before.windowsScanConfiguration)
        #expect(partial.usage.files[file.path] == before.usage.files[file.path])
        #expect(partial.windowsInventory != nil)
    }

    @Test
    func `cancellation does not publish a new checkpoint or report`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.event(5).write(to: fixture.logs.appendingPathComponent("first.jsonl"))
        _ = try fixture.load(fixture.options())
        let cacheURL = CostUsageClaudeCacheIO.cacheFileURL(provider: .claude, cacheRoot: fixture.options().cacheRoot)
        let before = try Data(contentsOf: cacheURL)
        enum Stop: Error { case requested }
        #expect(throws: Stop.self) {
            try fixture.load(fixture.options(work: 1), checkCancellation: { throw Stop.requested })
        }
        #expect(try Data(contentsOf: cacheURL) == before)
    }

    @Test
    func `checkpoint persistence failure is not reported as successful progress`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let blocked = fixture.root.appendingPathComponent("ordinary-file")
        try Data().write(to: blocked)
        var options = fixture.options(work: 1)
        options.cacheRoot = blocked
        do {
            _ = try fixture.load(options)
            Issue.record("Expected a checkpoint write failure")
        } catch CostUsageError.localInventoryCheckpointUnavailable { }
    }
}
#endif
