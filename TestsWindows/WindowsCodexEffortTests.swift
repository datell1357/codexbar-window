#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

/// Synthetic rollout/cache fixtures only. These fixtures have not been executed on the Mac host.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsCodexEffortTests {
    private typealias Scanner = CostUsageScanner
    private typealias Effort = CostUsageCodexEffortContext
    private static let model = "gpt-example"
    private static let day = ISO8601DateFormatter().date(from: "2026-09-09T12:00:00Z")!
    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private static var range: Scanner.CostUsageDayRange {
        .init(since: Self.day, until: Self.day, calendar: Self.calendar)
    }
    private static func stamp(_ seconds: Int) -> String { "2026-09-09T12:00:" + String(format: "%02d", seconds) + "Z" }
    private static func context(_ effort: Any?, at seconds: Int = 0, turn: String? = nil) -> [String: Any] {
        var payload: [String: Any] = ["model": Self.model]
        if let effort { payload["effort"] = effort }
        if let turn { payload["turn_id"] = turn }
        return ["type": "turn_context", "timestamp": Self.stamp(seconds), "payload": payload]
    }
    private static func started(_ turn: String, at seconds: Int) -> [String: Any] {
        ["type": "event_msg", "timestamp": Self.stamp(seconds), "payload": ["type": "task_started", "turn_id": turn]]
    }
    private static func usage(_ total: Int, at seconds: Int, turn: String? = nil) -> [String: Any] {
        var payload: [String: Any] = ["type": "token_count", "info": [
            "model": Self.model, "total_token_usage": [
                "input_tokens": total, "cached_input_tokens": 0, "output_tokens": 0, "reasoning_output_tokens": 0
            ]
        ]]
        if let turn { payload["turn_id"] = turn }
        return ["type": "event_msg", "timestamp": Self.stamp(seconds), "payload": payload]
    }
    private static func jsonl(_ objects: [[String: Any]], fallback: Bool = false) throws -> Data {
        let lines = try objects.map { object in
            var line = String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
            if fallback { line = line.replacingOccurrences(of: #""type""#, with: #""t\u0079pe""#) }
            return line
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
    private func withRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codexbar-effort-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
    private func parse(_ data: Data) throws -> Scanner.CodexParseResult {
        var result: Scanner.CodexParseResult?
        try self.withRoot { root in
            let file = root.appendingPathComponent("synthetic.jsonl")
            try data.write(to: file)
            result = try Scanner.parseCodexFileCancellable(fileURL: file, range: Self.range)
        }
        return try #require(result)
    }
    private static func eventRow(effort: String?) -> Scanner.CodexUsageRow {
        .init(day: "2026-09-09", model: Self.model, turnID: "turn-a", eventIndex: 0,
            timestampUnixMs: Int64(Self.day.timeIntervalSince1970 * 1000) + 1000,
            input: 100, cached: 0, output: 0, reasoningEffort: effort)
    }

    @Test
    func `recorded labels are bounded and context must match model turn and timestamp`() throws {
        for label in ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra", "persistent", "vendor_boost-2"] {
            #expect(Effort.normalizedEffort(label) == label)
        }
        #expect(Effort.normalizedEffort(" HIGH ") == "high")
        for label in ["", " ", "high\nsecret", "https://example.invalid", "private@example.invalid", String(repeating: "x", count: 65)] {
            #expect(Effort.normalizedEffort(label) == nil)
        }
        let context = try #require(Effort(effort: "high", model: Self.model, turnID: "a", timestampUnixMs: 1000))
        #expect(context.value(model: Self.model, turnID: "a", timestampUnixMs: 1000) == "high")
        #expect(context.value(model: "gpt-other-example", turnID: "a", timestampUnixMs: 1001) == nil)
        #expect(context.value(model: Self.model, turnID: "b", timestampUnixMs: 1001) == nil)
        #expect(context.value(model: Self.model, turnID: nil, timestampUnixMs: 1001) == nil)
        #expect(context.value(model: Self.model, turnID: "a", timestampUnixMs: 999) == nil)
        #expect(context.value(model: Self.model, turnID: "a", timestampUnixMs: 1001, reportedModel: "gpt-other-example") == nil)
        #expect(Effort(effort: "high", model: nil, turnID: nil, timestampUnixMs: 1000) == nil)
    }

    @Test
    func `fast and fallback parsing record effort changes without changing token deltas`() throws {
        let lines = [Self.started("a", at: 0), Self.context("low", at: 0, turn: "a"),
                     Self.usage(100, at: 1, turn: "a"), Self.context("high", at: 2, turn: "a"),
                     Self.usage(200, at: 3, turn: "a"), Self.context("none", at: 4, turn: "a"),
                     Self.usage(300, at: 5, turn: "a")]
        for fallback in [false, true] {
            let result = try self.parse(Self.jsonl(lines, fallback: fallback))
            #expect(result.rows.map(\.reasoningEffort) == ["low", "high", "none"])
            #expect(result.rows.map(\.input) == [100, 100, 100])
            #expect(result.lastCodexEffortContext?.effort == "none")
        }
    }

    @Test
    func `missing null invalid and nested effort clear earlier evidence`() throws {
        let efforts: [Any?] = [nil, NSNull(), 3, ["effort": "high"], ""]
        for effort in efforts {
            let lines = [Self.context("low"), Self.usage(100, at: 1),
                         Self.context(effort, at: 2), Self.usage(200, at: 3)]
            let result = try self.parse(Self.jsonl(lines))
            #expect(result.rows.map(\.reasoningEffort) == ["low", nil])
        }
        var nested = Self.context(nil, at: 2)
        nested["payload"] = ["model": Self.model, "info": ["effort": "high"],
                             "collaboration_mode": ["settings": ["reasoning_effort": "high"]]]
        let result = try self.parse(Self.jsonl([Self.context("low"), Self.usage(100, at: 1), nested, Self.usage(200, at: 3)]))
        #expect(result.rows.map(\.reasoningEffort) == ["low", nil])
    }

    @Test
    func `a new task cannot inherit an earlier turns effort`() throws {
        let result = try self.parse(Self.jsonl([
            Self.started("a", at: 0), Self.context("high", at: 0, turn: "a"), Self.usage(100, at: 1),
            Self.started("b", at: 2), Self.usage(200, at: 3),
            Self.context("low", at: 4, turn: "b"), Self.usage(300, at: 5)
        ]))
        #expect(result.rows.map(\.reasoningEffort) == ["high", nil, "low"])
        #expect(result.rows.map(\.turnID) == ["a", "b", "b"])
    }

    @Test
    func `invalid or truncated contexts cannot carry forward an old effort`() throws {
        var invalid = Self.context("high", at: 2)
        invalid["timestamp"] = "invalid"
        var invalidTask = Self.started("b", at: 2)
        invalidTask["timestamp"] = "invalid"
        for object in [invalid, invalidTask] {
            for fallback in [false, true] {
                let first = try self.parse(Self.jsonl([Self.context("low"), Self.usage(100, at: 1), object, Self.usage(200, at: 3)], fallback: fallback))
                #expect(first.rows.map(\.reasoningEffort) == ["low", nil])
            }
        }
        let prefix = try Self.jsonl([Self.context("low"), Self.usage(100, at: 1)])
        let long = #"{"type":"turn_context","timestamp":"2026-09-09T12:00:02Z","payload":{"model":"gpt-example","effort":"high","prompt":""#
            + String(repeating: "x", count: 300 * 1024) + "\"}}\n"
        let result = try self.parse(prefix + Data(long.utf8) + Self.jsonl([Self.usage(200, at: 3)]))
        #expect(result.rows.map(\.reasoningEffort) == ["low", nil])
    }

    @Test
    func `incremental resume retains the recorded context and then clears it on a new turn`() throws {
        try self.withRoot { root in
            let prefix = try Self.jsonl([Self.started("a", at: 0), Self.context("high", at: 0, turn: "a"), Self.usage(100, at: 1)])
            let suffix = try Self.jsonl([Self.usage(200, at: 2), Self.started("b", at: 3), Self.usage(300, at: 4)])
            let file = root.appendingPathComponent("resume.jsonl")
            try (prefix + suffix).write(to: file)
            let first = try Scanner.parseCodexFileCancellable(fileURL: file, range: Self.range, scanTargetSize: Int64(prefix.count))
            let context = try JSONDecoder().decode(Effort.self, from: JSONEncoder().encode(try #require(first.lastCodexEffortContext)))
            let next = try Scanner.parseCodexFileCancellable(fileURL: file, range: Self.range,
                startOffset: first.parsedBytes, initialModel: first.lastModel,
                initialTotals: first.lastCountedTotals, initialRawTotalsBaseline: first.lastRawTotalsBaseline,
                initialRawTotalsWatermark: first.lastRawTotalsWatermark, initialSeenRawTotals: first.seenRawTotals,
                initialHasDivergentTotals: first.hasDivergentTotals, initialHasInterleavedTotals: first.hasInterleavedTotals,
                initialCodexTurnID: first.lastCodexTurnID, initialCodexEffortContext: context,
                initialCodexUsageRowIndex: first.rows.count, initialJSONLResumeState: first.jsonlResumeState,
                expectedPrefixAnchor: first.windowsReadAnchor)
            #expect(next.rows.map(\.input) == [100, 100])
            #expect(next.rows.map(\.reasoningEffort) == ["high", nil])
            #expect(next.lastCodexEffortContext == nil)
        }
    }

    @Test
    func `bare usage is annotated only with the matching recorded context`() throws {
        let bare: [String: Any] = ["timestamp": Self.stamp(1), "model": Self.model,
            "usage": ["input_tokens": 100, "output_tokens": 0]]
        let result = try self.parse(Self.jsonl([Self.context("medium"), bare]))
        #expect(result.rows.first?.reasoningEffort == "medium")
        #expect(result.rows.first?.input == 100)
    }

    @Test
    func `legacy row and buffer payloads decode without inventing effort`() throws {
        let row = Self.eventRow(effort: "high")
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any])
        object.removeValue(forKey: "reasoningEffort")
        let legacy = try JSONDecoder().decode(Scanner.CodexUsageRow.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.reasoningEffort == nil && legacy.input == row.input)
        let metadata = Scanner.CodexTurnContextMetadata(timestamp: Self.stamp(0), model: Self.model, cwd: nil, title: nil)
        let buffered = Scanner.CodexBufferedFastLine(lineIndex: 0, ordinal: nil, line: .turnContext(metadata))
        let restored = try JSONDecoder().decode(Scanner.CodexBufferedFastLine.self, from: JSONEncoder().encode(buffered))
        #expect(restored == buffered)
    }

    @Test
    func `pricing and workspace fingerprints preserve effort migration evidence`() throws {
        let row = Self.eventRow(effort: "high")
        let repriced = Scanner.codexRowsWithPricingMetadata([row], priorityTurns: [:])
        #expect(repriced.first?.reasoningEffort == "high")
        var usage = Scanner.makeFileUsage(mtimeUnixMs: 1, size: 1, days: ["2026-09-09": [Self.model: [100, 0, 0]]],
            parsedBytes: 1, codexRows: [row])
        #expect(usage.hasCurrentCodexParserMetadata)
        let current = CodexWorkspaceUsageFingerprint.make(for: usage)
        usage.codexContextMetadataVersion = nil
        #expect(!usage.hasCurrentCodexParserMetadata)
        #expect(CodexWorkspaceUsageFingerprint.make(for: usage) != current)
        let fragment = CodexModelsUsageFragment(workspaceID: "synthetic-project", sessionID: "synthetic-session",
            day: Self.day, rawModelID: Self.model, inputTokens: 100, cachedInputTokens: 0, outputTokens: 0,
            costNanos: nil, reasoningEffort: repriced.first?.reasoningEffort)
        #expect(fragment.reasoningEffort == "high" && fragment.sessionID == "synthetic-session")
    }

    @Test
    func `store replaces same-size legacy rows and restores incremental effort state`() throws {
        try self.withRoot { root in
            let context = try #require(Effort(effort: "high", model: Self.model, turnID: "turn-a", timestampUnixMs: 1000))
            let path = root.appendingPathComponent("synthetic.jsonl").path
            var cache = CostUsageCache()
            cache.scanSinceKey = "2026-09-09"; cache.scanUntilKey = "2026-09-09"
            cache.timeZoneIdentifier = Self.calendar.timeZone.identifier
            cache.files[path] = Scanner.makeFileUsage(mtimeUnixMs: 1, size: 100, days: ["2026-09-09": [Self.model: [100, 0, 0]]],
                parsedBytes: 100, sessionId: "synthetic-session", codexRows: [Self.eventRow(effort: nil)],
                codexScanComplete: false, codexContextMetadataVersion: nil)
            cache.days = cache.files[path]!.days
            _ = CostUsageStoreAccess.replace(cacheRoot: root, cache: cache, calendar: Self.calendar)
            cache.files[path]?.codexContextMetadataVersion = Scanner.codexContextMetadataVersion
            cache.files[path]?.lastCodexEffortContext = context
            cache.files[path]?.codexRows = [Self.eventRow(effort: "high")]
            _ = CostUsageStoreAccess.replace(cacheRoot: root, cache: cache, calendar: Self.calendar)
            let loaded = CostUsageStoreAccess.read(cacheRoot: root, calendar: Self.calendar)
            #expect(loaded.files[path]?.codexRows?.first?.reasoningEffort == "high")
            #expect(loaded.files[path]?.lastCodexEffortContext == context)
            #expect(loaded.files[path]?.hasCurrentCodexParserMetadata == true)
        }
    }

    @Test
    func `sidecar round trip retains event effort independently of current catalog settings`() throws {
        try self.withRoot { root in
            let path = root.appendingPathComponent("synthetic.jsonl").path
            var cache = CostUsageCache()
            cache.files[path] = Scanner.makeFileUsage(mtimeUnixMs: 1, size: 100, days: ["2026-09-09": [Self.model: [100, 0, 0]]],
                parsedBytes: 100, sessionId: "synthetic-session", codexRows: [Self.eventRow(effort: "high")])
            let sidecar = CodexWorkspaceUsageSidecar(cacheRoot: root)
            try sidecar.synchronizeSources(cache: cache, catalog: .empty)
            let loaded = try sidecar.usageCache(roots: [:])
            #expect(loaded.files[path]?.codexRows?.first?.reasoningEffort == "high")
            #expect(loaded.files[path]?.codexRows?.first?.input == 100)
        }
    }

    #if canImport(SQLite3) || canImport(CSQLite3)
    @Test
    func `sidecar v5 migration preserves rows and rolls back on a conflicting schema`() throws {
        for alreadyHasColumn in [false, true] {
            var db: OpaquePointer?
            #expect(sqlite3_open(":memory:", &db) == SQLITE_OK)
            defer { sqlite3_close(db) }
            let extra = alreadyHasColumn ? ", reasoning_effort TEXT" : ""
            #expect(sqlite3_exec(db, "CREATE TABLE usage_events (event_index INTEGER, input_tokens INTEGER\(extra)); INSERT INTO usage_events (event_index, input_tokens) VALUES (1, 100); PRAGMA user_version = 5", nil, nil, nil) == SQLITE_OK)
            if alreadyHasColumn {
                #expect(throws: (any Error).self) { try CodexWorkspaceUsageSidecar.ensureSchema(db) }
            } else {
                try CodexWorkspaceUsageSidecar.ensureSchema(db)
                try CodexWorkspaceUsageSidecar.ensureSchema(db)
            }
            var statement: OpaquePointer?
            #expect(sqlite3_prepare_v2(db, "SELECT event_index, input_tokens, reasoning_effort FROM usage_events", -1, &statement, nil) == SQLITE_OK)
            #expect(sqlite3_step(statement) == SQLITE_ROW)
            #expect(sqlite3_column_int(statement, 0) == 1 && sqlite3_column_int(statement, 1) == 100)
            #expect(sqlite3_column_type(statement, 2) == SQLITE_NULL)
            sqlite3_finalize(statement)
            statement = nil
            #expect(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK)
            #expect(sqlite3_step(statement) == SQLITE_ROW)
            #expect(sqlite3_column_int(statement, 0) == (alreadyHasColumn ? 5 : 6))
            sqlite3_finalize(statement)
        }
    }
    #endif
}
#endif
