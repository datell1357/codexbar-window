#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

/// Synthetic, source-only fixtures. No build or execution was performed on the Mac host.
@Suite(.serialized)
struct WindowsClaudeContentCheckpointTests {
    private struct Fixture {
        let root: URL
        let logs: URL
        let day: Date
        let calendar: Calendar

        init() throws {
            self.root = FileManager.default.temporaryDirectory
                .appendingPathComponent("codexbar-claude-content-\(UUID().uuidString)", isDirectory: true)
            self.logs = self.root.appendingPathComponent("logs", isDirectory: true)
            try FileManager.default.createDirectory(at: self.logs, withIntermediateDirectories: true)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
            self.calendar = calendar
            self.day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        }

        func options(bytes: Int64 = 8 * 1024 * 1024, files: Int = 64) -> CostUsageScanner.Options {
            var options = CostUsageScanner.Options(
                claudeProjectsRoots: [self.logs], cacheRoot: self.root.appendingPathComponent("cache"),
                calendar: self.calendar)
            options.maxWindowsClaudeParseBytesPerRefresh = bytes
            options.maxWindowsClaudeFilesPerRefresh = files
            return options
        }

        func event(_ input: Int, id: String? = nil) throws -> Data {
            var message: [String: Any] = [
                "model": "synthetic-content-model", "usage": ["input_tokens": input],
            ]
            if let id { message["id"] = id }
            var object: [String: Any] = [
                "type": "assistant", "timestamp": "2026-08-01T12:00:00Z",
                "metadata": ["provider": "vertex"], "message": message,
            ]
            if id != nil { object["requestId"] = "synthetic-request" }
            var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            data.append(10)
            return data
        }

        func append(_ data: Data, to file: URL) throws {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: data)
        }

        func load(_ options: CostUsageScanner.Options, provider: UsageProvider = .claude,
                  checkCancellation: CostUsageScanner.CancellationCheck? = nil) throws -> CostUsageDailyReport {
            try CostUsageScanner.loadDailyReportCancellable(
                provider: provider, since: self.day, until: self.day, now: self.day,
                options: options, checkCancellation: checkCancellation)
        }

        func cache(_ provider: UsageProvider = .claude) -> CostUsageClaudeCache {
            CostUsageClaudeCacheIO.load(provider: provider, cacheRoot: self.options().cacheRoot)
        }

        func finish(_ options: CostUsageScanner.Options, provider: UsageProvider = .claude) throws -> CostUsageDailyReport {
            for _ in 0..<100 {
                do { return try self.load(options, provider: provider) }
                catch CostUsageError.localInventoryPending { }
                catch CostUsageError.localContentPending { }
            }
            throw FixtureFailure.didNotComplete
        }

        func cleanup() {
            WindowsCostDirectoryPages.shared.reset(under: self.root)
            try? FileManager.default.removeItem(at: self.root)
        }
    }

    private enum FixtureFailure: Error { case didNotComplete, cancelled }

    @Test(arguments: [UsageProvider.claude, .vertexai])
    func `partial body checkpoints preserve completed usage and resume streaming rows once`(provider: UsageProvider) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let file = fixture.logs.appendingPathComponent("session.jsonl")
        try fixture.event(3, id: "same-message").write(to: file)
        #expect(try fixture.load(fixture.options(), provider: provider).summary?.totalInputTokens == 3)
        let before = fixture.cache(provider)
        try fixture.append(fixture.event(17, id: "same-message") + fixture.event(5), to: file)
        let limited = fixture.options(bytes: 31)
        var lastOffset = before.usage.files[file.path]?.parsedBytes ?? 0
        var completed = false
        for _ in 0..<100 {
            do {
                let report = try fixture.load(limited, provider: provider)
                #expect(report.summary?.totalInputTokens == 22)
                completed = true
                break
            } catch let CostUsageError.localContentPending(done, total) {
                #expect(done == 0 && total == 1)
                let cache = fixture.cache(provider)
                #expect(cache.usage.files == before.usage.files)
                #expect(cache.usage.lastScanUnixMs == before.usage.lastScanUnixMs)
                #expect(cache.windowsReadProofs == before.windowsReadProofs)
                let partial = try #require(cache.windowsContent?.partial)
                #expect(partial.readBytes > lastOffset && partial.readBytes - lastOffset <= 31)
                #expect(partial.readBytes < partial.source.size)
                lastOffset = partial.readBytes
                // Drop process-local directory handles; persisted body state remains authoritative.
                WindowsCostDirectoryPages.shared.reset(under: fixture.logs)
            }
        }
        #expect(completed)
        #expect(fixture.cache(provider).windowsContent == nil)
        #expect(fixture.cache(provider).windowsInventory == nil)
    }

    @Test
    func `file visit limits retain completed staged files without publishing partial totals`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        for input in 1...3 {
            try fixture.event(input).write(to: fixture.logs.appendingPathComponent("\(input).jsonl"))
        }
        let limited = fixture.options(files: 1)
        for expected in 1...2 {
            do { _ = try fixture.load(limited); Issue.record("Expected pending body collection") }
            catch let CostUsageError.localContentPending(done, total) {
                #expect(done == expected && total == 3)
            }
            let cache = fixture.cache()
            #expect(cache.usage.files.isEmpty)
            #expect(cache.windowsContent?.nextFile == expected)
            #expect(cache.windowsContent?.cache.files.count == expected)
            #expect(cache.windowsContent?.partial == nil)
        }
        #expect(try fixture.load(limited).summary?.totalInputTokens == 6)
    }

    @Test
    func `append after a body checkpoint is deferred beyond the frozen collection boundary`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let file = fixture.logs.appendingPathComponent("growing.jsonl")
        try (fixture.event(7) + fixture.event(9)).write(to: file)
        let limited = fixture.options(bytes: 31)
        do { _ = try fixture.load(limited); Issue.record("Expected pending body collection") }
        catch CostUsageError.localContentPending { }
        let boundary = try #require(fixture.cache().windowsContent?.partial?.source.size)
        try fixture.append(fixture.event(20), to: file)
        #expect(try fixture.finish(limited).summary?.totalInputTokens == 16)
        #expect(fixture.cache().usage.files[file.path]?.size == boundary)
        #expect(try fixture.load(fixture.options()).summary?.totalInputTokens == 36)
    }

    @Test
    func `replacement discards staged rows while preserving the prior completed report`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let file = fixture.logs.appendingPathComponent("replace.jsonl")
        try fixture.event(4).write(to: file)
        _ = try fixture.load(fixture.options())
        let before = fixture.cache()
        try fixture.append(fixture.event(18), to: file)
        let limited = fixture.options(bytes: 31)
        do { _ = try fixture.load(limited); Issue.record("Expected pending body collection") }
        catch CostUsageError.localContentPending { }
        try FileManager.default.moveItem(at: file, to: fixture.root.appendingPathComponent("retained.jsonl"))
        try fixture.event(13).write(to: file)
        do { _ = try fixture.load(limited); Issue.record("Expected restarted discovery") }
        catch CostUsageError.localInventoryPending { }
        #expect(fixture.cache().windowsContent == nil)
        #expect(fixture.cache().usage.files == before.usage.files)
        #expect(try fixture.finish(limited).summary?.totalInputTokens == 13)
    }

    @Test
    func `force rescan and calendar changes do not overwrite completed data while pending`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let file = fixture.logs.appendingPathComponent("rescan.jsonl")
        try fixture.event(12).write(to: file)
        _ = try fixture.load(fixture.options())
        let before = fixture.cache()
        var limited = fixture.options(bytes: 31)
        limited.forceRescan = true
        limited.calendar.timeZone = try #require(TimeZone(secondsFromGMT: 9 * 3600))
        do { _ = try fixture.load(limited); Issue.record("Expected pending body collection") }
        catch CostUsageError.localContentPending { }
        let after = fixture.cache()
        #expect(after.usage.files == before.usage.files)
        #expect(after.usage.timeZoneIdentifier == before.usage.timeZoneIdentifier)
        #expect(after.sourceFileIDs == before.sourceFileIDs)
        #expect(after.windowsReadProofs == before.windowsReadProofs)
        #expect(try fixture.finish(limited).summary?.totalInputTokens == 12)
        #expect(fixture.cache().usage.timeZoneIdentifier == limited.calendar.timeZone.identifier)
    }

    @Test
    func `cancellation preserves the prior body checkpoint bytes`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.event(8).write(to: fixture.logs.appendingPathComponent("cancel.jsonl"))
        let limited = fixture.options(bytes: 31)
        do { _ = try fixture.load(limited); Issue.record("Expected pending body collection") }
        catch CostUsageError.localContentPending { }
        let url = CostUsageClaudeCacheIO.cacheFileURL(provider: .claude, cacheRoot: limited.cacheRoot)
        let before = try Data(contentsOf: url)
        #expect(throws: FixtureFailure.self) {
            try fixture.load(limited, checkCancellation: { throw FixtureFailure.cancelled })
        }
        #expect(try Data(contentsOf: url) == before)
    }

    @Test
    func `an incompatible optional continuation does not erase completed rows`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let file = fixture.logs.appendingPathComponent("compatible.jsonl")
        try fixture.event(14).write(to: file)
        _ = try fixture.load(fixture.options())
        let before = fixture.cache()
        let data = try JSONEncoder().encode(before)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["windowsContent"] = ["incompatible": true]
        let decoded = try JSONDecoder().decode(
            CostUsageClaudeCache.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.usage.files == before.usage.files)
        #expect(decoded.windowsReadProofs == before.windowsReadProofs)
        #expect(decoded.windowsContent == nil)
    }

    @Test
    func `body checkpoint write failure is not successful progress`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.event(6).write(to: fixture.logs.appendingPathComponent("blocked.jsonl"))
        let blocked = fixture.root.appendingPathComponent("ordinary-file")
        try Data().write(to: blocked)
        var limited = fixture.options(bytes: 31)
        limited.cacheRoot = blocked
        do { _ = try fixture.load(limited); Issue.record("Expected a checkpoint write failure") }
        catch CostUsageError.localInventoryCheckpointUnavailable { }
    }
}
#endif
