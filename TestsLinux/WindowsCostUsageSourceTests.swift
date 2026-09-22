#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

/// Source-only fixtures. This suite has not been executed on the macOS implementation host.
extension WindowsCostPublicationTests {
    private func withUsageSource(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-usage-source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root, root.appendingPathComponent("source.jsonl"))
    }

    private func usageSource(_ file: URL) throws -> CostUsageFileUsage {
        let metadata = try CostUsageScanner.requiredCodexFileMetadata(fileURL: file)
        var usage = CostUsageFileUsage(mtimeUnixMs: metadata.mtimeUnixMs, size: metadata.size, days: [:])
        usage.parsedBytes = metadata.size
        usage.codexScanFileId = metadata.fileId
        usage.codexScanComplete = true
        usage.codexWindowsSource = metadata.readSnapshot
        usage.codexWindowsContentGeneration = UUID().uuidString
        usage.codexWindowsReadProofVersion = CostUsageScanner.windowsCodexReadProofVersion
        usage.codexTokenIndexAnchor = CostUsageScanner.codexTokenIndexAnchor(
            fileURL: file, indexedBytes: metadata.size, expectedFile: metadata.readSnapshot)
        return usage
    }

    @Test
    func `native freshness retains submillisecond write times`() throws {
        let first = WindowsCostFileMetadata.Snapshot(
            fileID: "win128:synthetic:identity", size: 20, modifiedSeconds: 100,
            modifiedNanoseconds: 100, isDirectory: false)
        let second = WindowsCostFileMetadata.Snapshot(
            fileID: first.fileID, size: first.size, modifiedSeconds: first.modifiedSeconds,
            modifiedNanoseconds: 200, isDirectory: false)
        var usage = CostUsageFileUsage(mtimeUnixMs: first.mtimeUnixMs, size: first.size, days: [:])
        usage.codexWindowsSource = CostUsageFileReadSnapshot(native: first)
        usage.codexScanFileId = first.fileID
        usage.codexWindowsContentGeneration = "synthetic-generation"
        usage.codexWindowsReadProofVersion = CostUsageScanner.windowsCodexReadProofVersion
        let metadata = CostUsageScanner.CodexFileMetadata(
            path: "unused.jsonl", mtimeUnixMs: second.mtimeUnixMs, size: second.size, fileId: second.fileID,
            readSnapshot: CostUsageFileReadSnapshot(native: second))
        #expect(first.mtimeUnixMs == second.mtimeUnixMs)
        #expect(!CostUsageScanner.windowsCodexSourceMatches(usage, metadata: metadata))
        #expect(!CostUsageScanner.windowsCodexSourceMatches(usage, metadata: metadata, allowAppend: true))
    }

    @Test
    func `full prefix rejects a rewritten head outside the old tail anchor`() throws {
        try self.withUsageSource { _, file in
            try Data(repeating: 65, count: 160 * 1024).write(to: file)
            let time = Date(timeIntervalSince1970: 1_700_000_000)
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
            let usage = try self.usageSource(file)
            #expect(usage.codexTokenIndexAnchor?.windowStart == 0)
            let writer = try FileHandle(forWritingTo: file)
            try writer.write(contentsOf: Data([66]))
            try writer.close()
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
            let metadata = try CostUsageScanner.requiredCodexFileMetadata(fileURL: file)
            #expect(CostUsageScanner.windowsCodexSourceMatches(usage, metadata: metadata))
            #expect(!CostUsageScanner.windowsCodexPrefixMatches(usage, metadata: metadata))
        }
    }

    @Test
    func `append reuse requires an unchanged complete prefix`() throws {
        try self.withUsageSource { _, file in
            try Data(repeating: 65, count: 160 * 1024).write(to: file)
            let usage = try self.usageSource(file)
            let writer = try FileHandle(forWritingTo: file)
            _ = try writer.seekToEnd()
            try writer.write(contentsOf: Data("tail".utf8))
            try writer.close()
            var metadata = try CostUsageScanner.requiredCodexFileMetadata(fileURL: file)
            #expect(CostUsageScanner.windowsCodexPrefixMatches(usage, metadata: metadata))
            let rewriter = try FileHandle(forWritingTo: file)
            try rewriter.write(contentsOf: Data([66]))
            try rewriter.close()
            metadata = try CostUsageScanner.requiredCodexFileMetadata(fileURL: file)
            #expect(CostUsageScanner.windowsCodexSourceMatches(usage, metadata: metadata, allowAppend: true))
            #expect(!CostUsageScanner.windowsCodexPrefixMatches(usage, metadata: metadata))
        }
    }

    @Test
    func `legacy identity and tail anchors require reparsing`() throws {
        try self.withUsageSource { _, file in
            try Data(repeating: 65, count: 160 * 1024).write(to: file)
            let usage = try self.usageSource(file)
            let metadata = try CostUsageScanner.requiredCodexFileMetadata(fileURL: file)
            var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(usage))
                as? [String: Any])
            object.removeValue(forKey: "codexWindowsSource")
            object.removeValue(forKey: "codexWindowsContentGeneration")
            object.removeValue(forKey: "codexWindowsReadProofVersion")
            let legacy = try JSONDecoder().decode(
                CostUsageFileUsage.self, from: JSONSerialization.data(withJSONObject: object))
            #expect(!CostUsageScanner.windowsCodexSourceMatches(legacy, metadata: metadata))
            var tailOnly = usage
            tailOnly.codexTokenIndexAnchor?.windowStart = usage.size - 64 * 1024
            #expect(!CostUsageScanner.windowsCodexPrefixMatches(tailOnly, metadata: metadata))
        }
    }

    @Test
    func `prefix hashing can stop between bounded chunks`() throws {
        enum Stop: Error { case requested }
        try self.withUsageSource { _, file in
            try Data(repeating: 65, count: 160 * 1024).write(to: file)
            let usage = try self.usageSource(file)
            let metadata = try CostUsageScanner.requiredCodexFileMetadata(fileURL: file)
            var calls = 0
            #expect(!CostUsageScanner.windowsCodexPrefixMatches(usage, metadata: metadata, checkCancellation: {
                calls += 1
                if calls == 2 { throw Stop.requested }
            }))
            #expect(calls == 2)
        }
    }

    @Test
    func `new content generation replaces equal count rows and token snapshots in SQLite`() throws {
        try self.withUsageSource { root, file in
            try Data("synthetic fixture\n".utf8).write(to: file)
            let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
            var usage = try self.usageSource(file)
            usage.sessionId = "synthetic-session"
            usage.codexWindowsAuxiliaryAnchors = usage.codexTokenIndexAnchor.map { [$0] }
            usage.days = ["2026-08-01": ["synthetic-cost-model": [10, 0, 0]]]
            usage.codexRows = [.init(day: "2026-08-01", model: "synthetic-cost-model",
                                    turnID: nil, eventIndex: 0, input: 10, cached: 0, output: 0)]
            usage.codexTokenSnapshots = [.init(timestamp: "2026-08-01T12:00:00Z", last: nil,
                                               total: .init(input: 10, cached: 0, output: 0), endOffset: usage.size)]
            var cache = CostUsageCache()
            cache.scanSinceKey = "2026-08-01"
            cache.scanUntilKey = "2026-08-01"
            cache.timeZoneIdentifier = calendar.timeZone.identifier
            cache.files[file.path] = usage
            cache.days = usage.days
            _ = CostUsageStoreAccess.replace(cacheRoot: cacheRoot, cache: cache, calendar: calendar)
            let loaded = CostUsageStoreAccess.read(cacheRoot: cacheRoot, calendar: calendar)
            let persisted = try #require(loaded.files[file.path])
            #expect(persisted.codexWindowsSource == usage.codexWindowsSource)
            #expect(persisted.codexWindowsReadProofVersion == usage.codexWindowsReadProofVersion)
            #expect(persisted.codexWindowsAuxiliaryAnchors == usage.codexWindowsAuxiliaryAnchors)
            #expect(persisted.codexWindowsContentGeneration == usage.codexWindowsContentGeneration)
            #expect(persisted.codexRows?.first?.input == 10)

            var replacement = persisted
            replacement.codexWindowsContentGeneration = UUID().uuidString
            replacement.days = ["2026-08-01": ["synthetic-cost-model": [20, 0, 0]]]
            replacement.codexRows = [.init(day: "2026-08-01", model: "synthetic-cost-model",
                                          turnID: nil, eventIndex: 0, input: 20, cached: 0, output: 0)]
            replacement.codexTokenSnapshots = [.init(timestamp: "2026-08-01T12:00:00Z", last: nil,
                                                     total: .init(input: 20, cached: 0, output: 0),
                                                     endOffset: usage.size)]
            var changed = loaded
            changed.files[file.path] = replacement
            changed.days = replacement.days
            _ = CostUsageStoreAccess.replace(cacheRoot: cacheRoot, cache: changed, calendar: calendar)
            let reloaded = try #require(CostUsageStoreAccess.read(cacheRoot: cacheRoot, calendar: calendar)
                .files[file.path])
            #expect(reloaded.codexRows?.first?.input == 20)
            #expect(reloaded.codexTokenSnapshots?.first?.total?.input == 20)
            #expect(reloaded.codexWindowsContentGeneration == replacement.codexWindowsContentGeneration)
        }
    }

    @Test
    func `same length rewrite does not retain the previous session or historical days`() throws {
        try self.withUsageSource { root, _ in
            let sessions = root.appendingPathComponent("logs", isDirectory: true)
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: false)
            let file = sessions.appendingPathComponent("source.jsonl")
            let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
            let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
            func source(_ id: String, input: Int) throws -> Data {
                let lines: [[String: Any]] = [
                    ["type": "session_meta", "timestamp": "2026-08-01T12:00:00Z",
                     "payload": ["id": id, "cwd": "C:/\(id)"]],
                    ["type": "turn_context", "timestamp": "2026-08-01T12:00:00Z",
                     "payload": ["model": "synthetic-cost-model"]],
                    ["type": "event_msg", "timestamp": "2026-08-01T12:00:01Z",
                     "payload": ["type": "token_count", "info": ["total_token_usage": [
                        "input_tokens": input, "cached_input_tokens": 0, "output_tokens": 0]]]],
                ]
                var data = Data()
                for line in lines {
                    data.append(try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]))
                    data.append(10)
                }
                return data
            }
            let before = try source("before", input: 10)
            let after = try source("after!", input: 90)
            #expect(before.count == after.count)
            try before.write(to: file)
            let time = Date(timeIntervalSince1970: 1_700_000_000)
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
            let options = CostUsageScanner.Options(
                codexSessionsRoot: sessions, cacheRoot: cacheRoot,
                codexTraceDatabaseURL: root.appendingPathComponent("absent-trace.sqlite"),
                calendar: calendar, forceRescan: true)
            _ = try CostUsageScanner.loadDailyReportCancellable(
                provider: .codex, since: day, until: day, now: day, options: options, checkCancellation: nil)
            var cached = CostUsageStoreAccess.read(cacheRoot: cacheRoot, calendar: calendar)
            var old = try #require(cached.files[file.path])
            let oldGeneration = old.codexWindowsContentGeneration
            old.days["2026-07-31"] = ["synthetic-cost-model": [99, 0, 0]]
            cached.files[file.path] = old
            cached.days["2026-07-31"] = old.days["2026-07-31"]
            _ = CostUsageStoreAccess.replace(cacheRoot: cacheRoot, cache: cached, calendar: calendar)
            let writer = try FileHandle(forWritingTo: file)
            try writer.write(contentsOf: after)
            try writer.close()
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
            let report = try CostUsageScanner.loadDailyReportCancellable(
                provider: .codex, since: day, until: day, now: day.addingTimeInterval(1),
                options: options, checkCancellation: nil)
            #expect(report.summary?.totalInputTokens == 90)
            let current = try #require(CostUsageStoreAccess.read(cacheRoot: cacheRoot, calendar: calendar)
                .files[file.path])
            #expect(current.sessionId == "after!")
            #expect(current.projectPath == "C:/after!")
            #expect(current.days["2026-07-31"] == nil)
            #expect(current.codexWindowsContentGeneration != oldGeneration)
        }
    }

    @Test
    func `codex report publication check resumes through sliced verification`() throws {
        try self.withUsageSource { root, _ in
            let sessions = root.appendingPathComponent("logs", isDirectory: true)
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: false)
            func source(_ id: String, input: Int) throws -> Data {
                let lines: [[String: Any]] = [
                    ["type": "session_meta", "timestamp": "2026-08-01T12:00:00Z",
                     "payload": ["id": id, "cwd": "C:/\(id)"]],
                    ["type": "turn_context", "timestamp": "2026-08-01T12:00:00Z",
                     "payload": ["model": "synthetic-cost-model"]],
                    ["type": "event_msg", "timestamp": "2026-08-01T12:00:01Z",
                     "payload": ["type": "token_count", "info": ["total_token_usage": [
                        "input_tokens": input, "cached_input_tokens": 0, "output_tokens": 0]]]],
                ]
                var data = Data()
                for line in lines {
                    data.append(try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]))
                    data.append(10)
                }
                return data
            }
            let time = Date(timeIntervalSince1970: 1_700_000_000)
            // Beyond the verifier's 64-lease capacity so the report boundary must use the
            // per-entry fallback check sliced by the process-local resume cursor.
            for index in 0..<65 {
                let file = sessions.appendingPathComponent("session-\(index).jsonl")
                try source("s\(index)", input: 10).write(to: file)
                try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
            }
            let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
            let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
            var options = CostUsageScanner.Options(
                codexSessionsRoot: sessions, cacheRoot: cacheRoot,
                codexTraceDatabaseURL: root.appendingPathComponent("absent-trace.sqlite"),
                calendar: calendar)
            options.refreshMinIntervalSeconds = 3600
            options.maxWindowsCodexVerificationEntriesPerRefresh = 1
            var verificationPendings = 0
            var report: CostUsageDailyReport?
            for _ in 0..<160 {
                if report != nil { break }
                do {
                    report = try CostUsageScanner.loadDailyReportCancellable(
                        provider: .codex, since: day, until: day, now: day,
                        options: options, checkCancellation: nil)
                } catch let error as CostUsageError {
                    switch error {
                    case .localInventoryPending, .localContentPending:
                        continue
                    case .localContentVerificationPending:
                        verificationPendings += 1
                    default:
                        throw error
                    }
                }
            }
            // Finishing within the bound proves resume: restarting each pass at entry zero
            // would pend forever with one entry checked per refresh.
            #expect(verificationPendings >= 1)
            let final = try #require(report)
            #expect(final.summary?.totalInputTokens == 650)
        }
    }
}
#endif
