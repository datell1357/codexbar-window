#if os(Windows)
import Foundation
import Testing
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
@testable import CodexBarCore
@testable import CodexBarWindows

/// In-memory reports and signing keys only; no clipboard, files, dialogs, defaults or providers.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsCodexModelCSVTests {
    private typealias Export = WindowsCodexModelCSVExporter
    private typealias Query = WindowsAppSpendProjection.Query
    private static let revision = String(repeating: "a", count: 64)
    private static let now = ISO8601DateFormatter().date(from: "2026-11-04T12:00:00Z")!
    private static let key = SymmetricKey(data: Data(repeating: 1, count: 32))
    private static var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private static func analysis(count: Int = 3, priced: Bool = true, complete: Bool = true,
                                 activity: Bool = true, effort: String = "high") -> WindowsCodexModelAnalysis.Snapshot {
        let names = (0..<count).map { "private-model-" + String(format: "%03d", $0) }
        let rows = names.map { CostUsageDailyReport.ModelBreakdown(modelName: $0,
            costUSD: priced ? 1 : nil, totalTokens: 100) }
        let entry = CostUsageDailyReport.Entry(date: "2026-11-04", inputTokens: nil, outputTokens: nil,
            totalTokens: count * 100, costUSD: priced ? Double(count) : nil, modelsUsed: nil, modelBreakdowns: rows)
        let evidence = CodexModelActivityEvidence(timeZoneIdentifier: Self.calendar.timeZone.identifier,
            sinceDay: "2026-10-06", untilDay: "2026-11-04", rowsComplete: true,
            rows: names.map { .init(day: "2026-11-04", model: $0, effort: effort, sessionReference: 0, tokens: 100) })
        let input = WindowsSpendDashboardModel.ProviderInput(id: "private-source", provider: .codex,
            displayName: "private@example.invalid", snapshot: .init(sessionTokens: nil, sessionCostUSD: nil,
                last30DaysTokens: count * 100, last30DaysCostUSD: priced ? Double(count) : nil,
                historyDays: 30, historyCoverageIsEstablished: complete, daily: [entry],
                codexActivity: activity ? evidence : nil, updatedAt: Self.now))
        return WindowsCodexModelAnalysis.build(inputs: [input], days: 7, now: Self.now, calendar: Self.calendar,
            preferredCurrency: "auto", currency: "USD", conversionRates: [:], collectionComplete: true)
    }
    private static func query(_ indices: [Int]? = nil, mode: String = "include",
                              metric: String = "tokens", granularity: String = "monthly") -> Query {
        Query(days: 7, currency: "USD", codexModelsPage: 0,
            codexModel: indices.map { .init(indices: $0, revision: Self.revision, mode: mode) },
            codexGranularity: granularity, codexMetric: metric, codexCatalogPage: 0)
    }
    private static func data(_ query: Query = Self.query(), count: Int = 3, privacy: Bool = true,
                             stale: Bool = false, priced: Bool = true, complete: Bool = true,
                             activity: Bool = true, effort: String = "high") throws -> Data {
        try Export.encodedData(analysis: Self.analysis(count: count, priced: priced, complete: complete, activity: activity, effort: effort),
            query: query, selectionRevision: Self.revision, stale: stale, hidePersonalInfo: privacy, calendar: Self.calendar)
    }
    private static func records(_ data: Data) -> [[String: String]] {
        // A small independent CSV reader for quoted CRLF output, including quoted line breaks and doubled quotes.
        let characters = Array(String(decoding: data, as: UTF8.self))
        var rows: [[String]] = [], row: [String] = []
        var cell = "", quoted = false, cursor = 0
        while cursor < characters.count {
            let value = characters[cursor]
            if value == "\"" {
                if quoted, cursor + 1 < characters.count, characters[cursor + 1] == "\"" {
                    cell.append("\""); cursor += 1
                } else { quoted.toggle() }
            } else if !quoted && value == "," { row.append(cell); cell = "" }
            else if !quoted && (value == "\r\n" || value == "\n" || value == "\r") {
                row.append(cell); rows.append(row); cell = ""; row = []
            } else { cell.append(value) }
            cursor += 1
        }
        guard let header = rows.first else { return [] }
        return rows.dropFirst().map { Dictionary(uniqueKeysWithValues: zip(header, $0)) }
    }

    @Test
    func `export includes selected rows beyond the current page and the same combined timeline`() throws {
        var query = Self.query([1, 41, 81])
        query.codexModelsPage = 99; query.codexCatalogPage = 99
        let bytes = try Self.data(query, count: 85)
        let records = Self.records(bytes)
        let models = records.filter { $0["record_kind"] == "model" && $0["period"] == "current" && $0["metric"] == "tokens" }
        #expect(models.map { $0["model_index"] } == ["1", "41", "81"])
        #expect(models.map { $0["model"] } == ["Model 2", "Model 42", "Model 82"])
        #expect(models.allSatisfy { $0["value"] == "100" && $0["value_status"] == "complete" })
        let timeline = records.filter { $0["record_kind"] == "timeline" }
        #expect(timeline.compactMap { Int($0["value"] ?? "") }.reduce(0, +) == 300)
        #expect(records.allSatisfy { $0["selected_model_count"] == "3" && $0["currency"] == "USD" })
        #expect(!String(decoding: bytes, as: UTF8.self).contains("private-"))
        #expect(records.allSatisfy { $0.count == Export.header.count })
    }

    @Test
    func `all none and exclude preserve distinct export scopes`() throws {
        let all = Self.records(try Self.data())
        let none = Self.records(try Self.data(Self.query([])))
        let excluded = Self.records(try Self.data(Self.query([1], mode: "exclude")))
        #expect(Set(all.filter { $0["record_kind"] == "model" }.compactMap { $0["model_index"] }) == ["0", "1", "2"])
        #expect(none.count == 2 && none.allSatisfy { $0["record_kind"] == "scope" && $0["selected_model_count"] == "0" })
        #expect(Set(excluded.filter { $0["record_kind"] == "model" }.compactMap { $0["model_index"] }) == ["0", "2"])
    }

    @Test
    func `private models and custom effort obey privacy while source and session identifiers stay absent`() throws {
        let hidden = String(decoding: try Self.data(effort: "private-custom"), as: UTF8.self)
        let visible = String(decoding: try Self.data(privacy: false, effort: "private-custom"), as: UTF8.self)
        #expect(!hidden.contains("private-model") && !hidden.contains("private-custom") && hidden.contains("\"Custom\""))
        #expect(visible.contains("private-model-000") && visible.contains("private-custom"))
        for value in [hidden, visible] {
            #expect(!value.contains("private-source") && !value.contains("private@example") && !value.contains("sessionReference"))
        }
    }

    @Test
    func `unpriced and incomplete evidence is blank or partial rather than fabricated zero`() throws {
        let records = Self.records(try Self.data(priced: false, complete: false, activity: false))
        let costs = records.filter { $0["record_kind"] == "model" && $0["metric"] == "estimated_cost" }
        #expect(costs.allSatisfy { $0["value"] == "" && $0["value_status"] == "unknown" })
        let current = records.filter { $0["record_kind"] == "model" && $0["period"] == "current" && $0["metric"] == "tokens" }
        #expect(current.allSatisfy { $0["value"] == "100" && $0["value_status"] == "partial" })
        #expect(records.filter { $0["record_kind"] == "comparison" }.allSatisfy { $0["comparison_state"] == "unavailable" })
        #expect(records.filter { $0["metric"] == "session_references" && $0["record_kind"] == "model" }
            .allSatisfy { $0["value"] == "" && $0["value_status"] == "unknown" })
    }

    @Test
    func `stale exports carry stale status and withdraw complete comparisons`() throws {
        let records = Self.records(try Self.data(stale: true))
        #expect(records.allSatisfy { $0["collection_status"] == "stale" && $0["value_status"] != "complete" })
        #expect(records.filter { $0["record_kind"] == "comparison" }.allSatisfy { $0["comparison_state"] == "unavailable" })
        let fresh = Self.records(try Self.data())
        #expect(fresh.filter { $0["record_kind"] == "comparison" }.allSatisfy { $0["comparison_state"] == "new" })
        #expect(fresh.filter { $0["record_kind"] == "model" && $0["period"] == "previous" }
            .allSatisfy { $0["value"] == "0" || $0["value"] == "0.0" })
    }

    @Test
    func `timeline metric retains per-model references and calendar boundaries`() throws {
        let references = Self.records(try Self.data(Self.query([0, 2], metric: "sessionReferences")))
            .filter { $0["record_kind"] == "timeline" }
        #expect(references.last?["value"] == "2" && references.last?["metric"] == "session_references")
        #expect(references.allSatisfy { $0["selected_metric"] == "sessionReferences" && $0["granularity"] == "monthly" })
        #expect(references.first?["interval_start"] == "2026-10-29T00:00:00Z")
        #expect(references.last?["interval_end_exclusive"] == "2026-11-05T00:00:00Z")
        let costs = Self.records(try Self.data(Self.query([0, 2], metric: "cost")))
            .filter { $0["record_kind"] == "timeline" }
        #expect(costs.compactMap { Double($0["value"] ?? "") }.reduce(0, +) == 2)
    }

    @Test
    func `CSV escaping preserves quotes and Unicode while treating formula text as literal`() throws {
        #expect(try Export.cell("한글,\"quoted\"\r\nline", text: true) == "\"한글,\"\"quoted\"\"\r\nline\"")
        for value in ["=1+1", "+example", "-example", "@example", "\t =1+1", "\r\n@value"] {
            #expect(try Export.cell(value, text: true).hasPrefix("\"'"))
        }
        #expect(try Export.cell("-0.5", text: false) == "\"-0.5\"")
        #expect(try Export.cell("a\0b", text: true) == "\"ab\"")
        #expect(throws: Export.Failure.tooLarge) { try Export.cell(String(repeating: "x", count: 16385), text: true) }
    }

    @Test
    func `oversized exports fail without returning a truncated artifact and large copies suggest saving`() throws {
        #expect(throws: Export.Failure.tooLarge) {
            try Export.encodedData(analysis: Self.analysis(), query: Self.query(), selectionRevision: Self.revision,
                stale: false, hidePersonalInfo: true, calendar: Self.calendar, maximumBytes: 128)
        }
        let analysis = Self.analysis(count: 50)
        let copied = Export.make(analysis: analysis, query: Self.query(), selectionRevision: Self.revision,
            stale: false, hidePersonalInfo: true, calendar: Self.calendar, copy: true)
        guard case let .unavailable(message) = copied else { Issue.record("Oversized copy unexpectedly produced an artifact"); return }
        #expect(message.contains("Save model CSV"))
        let saved = Export.make(analysis: analysis, query: Self.query(), selectionRevision: Self.revision,
            stale: false, hidePersonalInfo: true, calendar: Self.calendar, copy: false)
        guard case let .csv(data, filename, copy) = saved else { Issue.record("Bounded save artifact missing"); return }
        #expect(!copy && data.count > 65536 && data.count <= Export.maximumBytes)
        #expect(filename == "codexbar-models-last-7-days-USD.csv")
    }

    @Test
    func `export revision binds model set metric and interval but ignores presentation pages`() {
        let base = Self.query([0, 2])
        func revision(_ query: Query, models: String = Self.revision) -> String {
            WindowsAppSpendSelection.codexExportRevision(modelsRevision: models, query: query, key: Self.key)
        }
        var page = base; page.page = 99; page.codexModelsPage = 99; page.codexCatalogPage = 99
        #expect(revision(base) == revision(page))
        #expect(revision(base) != revision(Self.query([0])))
        #expect(revision(base) != revision(Self.query([0, 2], mode: "exclude")))
        #expect(revision(base) != revision(Self.query([0, 2], metric: "cost")))
        #expect(revision(base) != revision(Self.query([0, 2], granularity: "weekly")))
        #expect(revision(base) != revision(base, models: String(repeating: "b", count: 64)))
        #expect(revision(Self.query()) != revision(Self.query([])))
    }

    @Test
    func `actions require the matching query shape and stale selections never export all models`() throws {
        let action = WindowsAppSpendExport.Action(kind: "saveModelsCSV", expectedRevision: Self.revision)
        #expect(action.isCodexCSV && action.accepts(Self.query()))
        #expect(!action.accepts(Query(days: 7, currency: "USD")))
        #expect(!WindowsAppSpendExport.Action(kind: "saveJSON", expectedRevision: Self.revision).accepts(Self.query()))
        var bad = Self.query([0]); bad.codexModel = .init(indices: [0], revision: String(repeating: "b", count: 64))
        #expect(throws: Export.Failure.unavailable) { try Self.data(bad) }
        #expect(throws: Export.Failure.unavailable) { try Self.data(Self.query([3])) }
        var wrongCurrency = Self.query(); wrongCurrency.currency = "EUR"
        #expect(throws: Export.Failure.unavailable) { try Self.data(wrongCurrency) }
        var wrongPeriod = Self.query(); wrongPeriod.days = 30
        #expect(throws: Export.Failure.unavailable) { try Self.data(wrongPeriod) }
        var largest = Self.query(Array(999_745...1_000_000), mode: "exclude")
        largest.page = 100000; largest.codexModelsPage = 100000; largest.codexCatalogPage = 100000
        let request = WindowsAppProtocol.Request(protocolVersion: 1, requestID: UUID(), generation: UUID(),
            method: "spendAction", mutation: nil, spendQuery: largest, spendAction: action)
        let bytes = try JSONEncoder().encode(request)
        #expect(bytes.count <= WindowsAppProtocol.maximumRequestBytes)
        #expect(try WindowsAppProtocol.request(bytes).spendAction?.kind == "saveModelsCSV")
    }
}
#endif
