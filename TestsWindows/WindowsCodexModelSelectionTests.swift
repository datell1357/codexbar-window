#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarWindows

/// Synthetic captured reports only; no accounts, settings, files, providers or native UI.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsCodexModelSelectionTests {
    private typealias Projection = WindowsAppSpendProjection
    private typealias Selection = Projection.CodexModelSelection
    private static let revision = String(repeating: "a", count: 64)
    private static let now = ISO8601DateFormatter().date(from: "2026-11-04T12:00:00Z")!
    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private static func analysis(count: Int = 3) -> WindowsCodexModelAnalysis.Snapshot {
        let names = (0..<count).map { "private-model-" + String(format: "%03d", $0) }
        let rows = names.map { CostUsageDailyReport.ModelBreakdown(modelName: $0, costUSD: 1, totalTokens: 100) }
        let entry = CostUsageDailyReport.Entry(date: "2026-11-04", inputTokens: nil, outputTokens: nil,
            totalTokens: count * 100, costUSD: Double(count), modelsUsed: nil, modelBreakdowns: rows)
        let evidence = CodexModelActivityEvidence(timeZoneIdentifier: Self.calendar.timeZone.identifier,
            sinceDay: "2026-10-06", untilDay: "2026-11-04", rowsComplete: true,
            rows: names.map { .init(day: "2026-11-04", model: $0, effort: "high", sessionReference: 0, tokens: 100) })
        let input = WindowsSpendDashboardModel.ProviderInput(id: "private-source", provider: .codex,
            displayName: "private@example.invalid", snapshot: .init(sessionTokens: nil, sessionCostUSD: nil,
                last30DaysTokens: count * 100, last30DaysCostUSD: Double(count), historyDays: 30,
                daily: [entry], codexActivity: evidence, updatedAt: Self.now))
        return WindowsCodexModelAnalysis.build(inputs: [input], days: 7, now: Self.now, calendar: Self.calendar,
            preferredCurrency: "auto", currency: "USD", conversionRates: [:], collectionComplete: true)
    }
    private static func page(_ selection: Selection?, count: Int = 3, page: Int = 0, catalog: Int = 0) -> Projection.CodexModelsPage {
        Projection.codexModels(Self.analysis(count: count), page: page, hidePersonalInfo: true, stale: false,
            calendar: Self.calendar, text: { value, _ in value }, selectionRevision: Self.revision,
            selection: selection, granularity: "monthly", metric: "tokens", catalogPage: catalog)
    }

    @Test
    func `included models drive both the filtered table and combined timeline`() {
        let value = Self.page(.init(indices: [0, 2], revision: Self.revision))
        #expect(value.rows.map(\.selectionIndex) == [0, 2])
        #expect(value.rows.map(\.title) == ["Model 1", "Model 3"])
        #expect(value.selectedLabel == "2 models selected")
        #expect(value.timeline.compactMap(\.value).reduce(0, +) == 200)
        #expect(value.choices.map(\.selected) == [true, false, true])
    }

    @Test
    func `exclusions preserve all other models without encoding their identifiers`() throws {
        let selection = Selection(indices: [1], revision: Self.revision, mode: "exclude")
        let value = Self.page(selection)
        #expect(value.rows.map(\.selectionIndex) == [0, 2])
        #expect(value.timeline.compactMap(\.value).reduce(0, +) == 200)
        let bytes = try JSONEncoder().encode(value)
        let json = String(decoding: bytes, as: UTF8.self)
        #expect(!json.contains("private-model") && !json.contains("private-source") && !json.contains("private@example"))
        let restored = try JSONDecoder().decode(Projection.CodexModelsPage.self, from: bytes)
        #expect(restored.modelSelection?.indices == [1] && restored.modelSelection?.mode == "exclude")
    }

    @Test
    func `no models is an explicit empty view and differs from all models`() {
        let empty = Self.page(.init(indices: [], revision: Self.revision))
        #expect(empty.rows.isEmpty && empty.timeline.isEmpty && empty.totalRows == 0)
        #expect(empty.selectedLabel == "No models selected" && empty.choices.allSatisfy { !$0.selected })
        #expect(Self.page(nil).totalRows == 3)
        #expect(Self.page(.init(indices: [], revision: Self.revision, mode: "exclude")).totalRows == 3)
        let excluded = Self.page(.init(indices: [0, 1, 2], revision: Self.revision, mode: "exclude"))
        #expect(excluded.rows.isEmpty && excluded.timeline.isEmpty)
    }

    @Test
    func `catalog paging is independent of filtered rows and keeps original anonymous indices`() {
        let value = Self.page(.init(indices: [1, 41, 81], revision: Self.revision), count: 85, page: 99, catalog: 99)
        #expect(value.page == 0 && value.totalRows == 3 && value.pageCount == 1)
        #expect(value.catalogPage == 2 && value.catalogPageCount == 3 && value.catalogTotal == 85)
        #expect(value.choices.map(\.index) == [80, 81, 82, 83, 84])
        #expect(value.choices.map(\.selected) == [false, true, false, false, false])
        #expect(value.rows.map(\.title) == ["Model 2", "Model 42", "Model 82"])
        let excluded = Self.page(.init(indices: [1, 41, 81], revision: Self.revision, mode: "exclude"),
            count: 85, page: 2, catalog: 2)
        #expect(excluded.totalRows == 82 && excluded.rows.map(\.selectionIndex) == [83, 84])
    }

    @Test
    func `combined timeline keeps per model session reference semantics`() throws {
        let value = Self.analysis()
        let keys: Set<String> = [value.modelKeys[0], value.modelKeys[2]]
        let samples = WindowsCodexModelTimeline.build(value, models: keys, granularity: "monthly", calendar: Self.calendar)
        let current = try #require(samples.last)
        #expect(current.tokens == 200 && current.cost == 2 && current.sessionReferences == 2)
        #expect(current.sessionsComplete)
        #expect(WindowsCodexModelTimeline.build(value, models: [], granularity: "daily", calendar: Self.calendar).isEmpty)
    }

    @Test
    func `legacy single selectors decode while ambiguous and malformed selector shapes are rejected`() throws {
        let legacy = Data("{\"index\":2,\"revision\":\"\(Self.revision)\"}".utf8)
        let decoded = try JSONDecoder().decode(Selection.self, from: legacy)
        #expect(decoded.isValid && decoded.indices == [2] && decoded.mode == "include" && decoded.index == 2)
        let ambiguous = Data("{\"index\":2,\"indices\":[1],\"revision\":\"\(Self.revision)\"}".utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Selection.self, from: ambiguous) }
        for values in [[0, 0], [2, 1], [-1], [1_000_001], Array(0...256)] {
            #expect(!Selection(indices: values, revision: Self.revision).isValid)
        }
        #expect(!Selection(indices: [], revision: Self.revision, mode: "replace").isValid)
    }

    @Test
    func `maximum selector fits the wire budget and catalog options require an active model view`() throws {
        let selection = Selection(indices: Array(999_745...1_000_000), revision: Self.revision, mode: "exclude")
        let query = Projection.Query(days: 365, currency: "USD", section: "models", chart: "tokens",
            detail: .init(kind: "session", index: 0, day: nil, revision: Self.revision),
            comparePeriods: true, codexModelsPage: 100000, codexModel: selection,
            codexGranularity: "monthly", codexMetric: "sessionReferences", codexCatalogPage: 100000)
        #expect(query.isValid)
        let request = WindowsAppProtocol.Request(protocolVersion: 1, requestID: UUID(), generation: UUID(),
            method: "spend", mutation: nil, spendQuery: query)
        let bytes = try JSONEncoder().encode(request)
        #expect(bytes.count <= WindowsAppProtocol.maximumRequestBytes)
        #expect(try WindowsAppProtocol.request(bytes).spendQuery?.codexModel?.indices.count == 256)
        #expect(!Projection.Query(codexCatalogPage: 0).isValid)
        #expect(!Projection.Query(codexModelsPage: 0, codexCatalogPage: -1).isValid)
        #expect(!Projection.Query(codexModelsPage: 0, codexCatalogPage: 100001).isValid)
    }

    @Test
    func `stale and out of range multi selectors do not fall back to the full collection`() {
        let value = Self.analysis()
        for selection in [Selection(indices: [0, 2], revision: String(repeating: "b", count: 64)),
                          Selection(indices: [0, 3], revision: Self.revision),
                          Selection(indices: [3], revision: Self.revision, mode: "exclude")] {
            #expect(!Projection.acceptsCodexModel(selection, analysis: value, revision: Self.revision))
            let page = Self.page(selection)
            #expect(page.rows.isEmpty && page.timeline.isEmpty && page.selectedLabel == "Selection changed")
        }
    }
}
#endif
