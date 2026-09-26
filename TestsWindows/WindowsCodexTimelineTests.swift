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

/// Synthetic captured reports and fixed signing keys only. No UI, files, settings or providers.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsCodexTimelineTests {
    private typealias Analysis = WindowsCodexModelAnalysis
    private typealias Timeline = WindowsCodexModelTimeline
    private typealias Projection = WindowsAppSpendProjection
    private typealias Entry = CostUsageDailyReport.Entry
    private typealias Row = CostUsageDailyReport.ModelBreakdown
    private typealias Input = WindowsSpendDashboardModel.ProviderInput
    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private static let now = ISO8601DateFormatter().date(from: "2026-11-04T12:00:00Z")!
    private static let key = SymmetricKey(data: Data(repeating: 1, count: 32))
    private static func row(_ model: String = "gpt-example", tokens: Int = 100, cost: Double? = 2) -> Row {
        .init(modelName: model, costUSD: cost, totalTokens: tokens)
    }
    private static func entry(_ date: String, _ rows: [Row]) -> Entry {
        .init(date: date, inputTokens: nil, outputTokens: nil,
            totalTokens: rows.reduce(0) { $0 + ($1.totalTokens ?? 0) },
            costUSD: rows.allSatisfy { $0.costUSD != nil } ? rows.reduce(0) { $0 + ($1.costUSD ?? 0) } : nil,
            modelsUsed: nil, modelBreakdowns: rows)
    }
    private static func input(_ daily: [Entry], now: Date = Self.now, calendar: Calendar = Self.calendar,
                              complete: Bool = true, activity: Bool = true) -> Input {
        let evidence = CodexModelActivityEvidence(timeZoneIdentifier: calendar.timeZone.identifier,
            sinceDay: Projection.dayKey(calendar.date(byAdding: .day, value: -29, to: now)!, calendar: calendar),
            untilDay: Projection.dayKey(now, calendar: calendar), rowsComplete: true,
            rows: daily.flatMap { day in (day.modelBreakdowns ?? []).map {
                .init(day: day.date, model: $0.modelName, effort: "high", sessionReference: 0, tokens: $0.totalTokens ?? 0)
            } })
        return .init(id: "private-source", provider: .codex, displayName: "private@example.invalid",
            snapshot: .init(sessionTokens: nil, sessionCostUSD: nil,
                last30DaysTokens: daily.reduce(0) { $0 + ($1.totalTokens ?? 0) },
                last30DaysCostUSD: daily.allSatisfy { $0.costUSD != nil } ? daily.reduce(0) { $0 + ($1.costUSD ?? 0) } : nil,
                historyDays: 30, historyCoverageIsEstablished: complete, costProvenance: .listPriceEstimate,
                daily: daily, codexActivity: activity ? evidence : nil, updatedAt: now))
    }
    private static func analysis(_ input: Input, days: Int = 7, now: Date = Self.now,
                                 calendar: Calendar = Self.calendar, preferred: String = "auto",
                                 currency: String = "USD", rates: [String: Double] = [:]) -> Analysis.Snapshot {
        Analysis.build(inputs: [input], days: days, now: now, calendar: calendar, preferredCurrency: preferred,
            currency: currency, conversionRates: rates, collectionComplete: true)
    }

    @Test
    func `daily model filtering preserves known empty days and selected currency cost`() throws {
        let input = Self.input([Self.entry("2026-11-03", [Self.row(), Self.row("gpt-other-example", tokens: 50, cost: 1)])])
        let value = Self.analysis(input, preferred: "KRW", currency: "KRW", rates: ["KRW": 1000])
        let all = Timeline.build(value, model: nil, granularity: "daily", calendar: Self.calendar)
        let selected = Timeline.build(value, model: "gpt-example", granularity: "daily", calendar: Self.calendar)
        #expect(all.count == 7 && selected.count == 7)
        #expect(all.reduce(0) { $0 + ($1.tokens ?? 0) } == 150)
        #expect(selected.reduce(0) { $0 + ($1.tokens ?? 0) } == 100)
        #expect(selected.reduce(0) { $0 + ($1.cost ?? 0) } == 2000)
        #expect(selected.last?.tokens == 0 && selected.last?.tokensComplete == true)
        #expect(selected.last?.sessionReferences == 0 && selected.last?.sessionsComplete == true)
    }

    @Test
    func `weekly and monthly references deduplicate within each model and interval`() {
        let value = Self.analysis(Self.input([
            Self.entry("2026-11-03", [Self.row(), Self.row("gpt-other-example")]),
            Self.entry("2026-11-04", [Self.row(), Self.row("gpt-other-example")])
        ]))
        let daily = Timeline.build(value, model: nil, granularity: "daily", calendar: Self.calendar)
        let weekly = Timeline.build(value, model: nil, granularity: "weekly", calendar: Self.calendar)
        let monthly = Timeline.build(value, model: "gpt-example", granularity: "monthly", calendar: Self.calendar)
        #expect(daily.compactMap(\.sessionReferences).reduce(0, +) == 4)
        #expect(weekly.last?.sessionReferences == 2 && weekly.last?.tokens == 400)
        #expect(monthly.last?.sessionReferences == 1 && monthly.last?.tokens == 200)
        #expect(weekly.last?.sessionsComplete == true)
    }

    @Test
    func `calendar grouping respects Monday weeks DST and clipped month boundaries`() throws {
        var calendar = Self.calendar
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let value = Self.analysis(Self.input([], calendar: calendar), days: 14, calendar: calendar)
        let weeks = Timeline.build(value, model: nil, granularity: "weekly", calendar: calendar)
        let full = try #require(weeks.first { !$0.clipped })
        #expect(calendar.component(.weekday, from: full.interval.start) == 2)
        #expect(full.interval.duration == 169 * 3600)
        #expect(weeks.first?.clipped == true && weeks.last?.clipped == true)
        let now = Self.calendar.date(from: .init(year: 2026, month: 2, day: 2))!
        let monthValue = Self.analysis(Self.input([], now: now), days: 4, now: now)
        let months = Timeline.build(monthValue, model: nil, granularity: "monthly", calendar: Self.calendar)
        #expect(months.count == 2 && months.allSatisfy(\.clipped))
        #expect(months.first?.interval.start == monthValue.current.interval.start)
        #expect(months.last?.interval.end == monthValue.current.interval.end)
    }

    @Test
    func `partial history unpriced usage and missing session evidence remain unknown`() {
        let daily = [Self.entry("2026-11-04", [Self.row(cost: nil)])]
        let value = Self.analysis(Self.input(daily, complete: false, activity: false))
        let samples = Timeline.build(value, model: nil, granularity: "daily", calendar: Self.calendar)
        #expect(samples.first?.tokens == nil && samples.first?.cost == nil)
        #expect(samples.last?.tokens == 100 && samples.last?.tokensComplete == false)
        #expect(samples.last?.cost == nil && samples.last?.sessionReferences == nil)
        let points = Projection.codexTimeline(value, model: nil, granularity: "daily", metric: "tokens",
            stale: false, calendar: Self.calendar, text: { value, _ in value })
        #expect(points.last?.detail.contains("Tokens: ~100") == true)
        #expect(points.last?.detail.contains("Session refs: Unknown") == true)
    }

    @Test
    func `model selectors bind model ordering and the complete display revision`() {
        let value = Self.analysis(Self.input([Self.entry("2026-11-04", [Self.row()])]))
        let first = WindowsAppSpendSelection.codexModelsRevision(analysis: value, viewRevision: "collection-a", key: Self.key)
        let rotated = WindowsAppSpendSelection.codexModelsRevision(analysis: value, viewRevision: "collection-b", key: Self.key)
        let other = Self.analysis(Self.input([Self.entry("2026-11-04", [Self.row("gpt-other-example")])]))
        let replaced = WindowsAppSpendSelection.codexModelsRevision(analysis: other, viewRevision: "collection-a", key: Self.key)
        let selection = Projection.CodexModelSelection(index: 0, revision: first)
        #expect(first.count == 64 && first != rotated && first != replaced)
        #expect(Projection.acceptsCodexModel(selection, analysis: value, revision: first))
        #expect(!Projection.acceptsCodexModel(selection, analysis: value, revision: rotated))
        #expect(!Projection.acceptsCodexModel(.init(index: 1, revision: first), analysis: value, revision: first))
        #expect(!Projection.acceptsCodexModel(selection, analysis: nil, revision: first))
    }

    @Test
    func `focused model keeps its privacy label and stale selectors never fall back to all models`() throws {
        let value = Self.analysis(Self.input([Self.entry("2026-11-04", [
            Self.row("private-alpha"), Self.row("private-beta", tokens: 50, cost: 1)
        ])]))
        let revision = WindowsAppSpendSelection.codexModelsRevision(analysis: value, viewRevision: "view", key: Self.key)
        let selection = Projection.CodexModelSelection(index: 1, revision: revision)
        let page = Projection.codexModels(value, page: 99, hidePersonalInfo: true, stale: false, calendar: Self.calendar,
            text: { value, _ in value }, selectionRevision: revision, selection: selection, granularity: "monthly", metric: "cost")
        #expect(page.totalRows == 1 && page.page == 0 && page.rows.first?.selectionIndex == 1)
        #expect(page.selectedLabel == "Model 2" && page.rows.first?.title == "Model 2")
        #expect(page.timeline.compactMap(\.value).reduce(0, +) == 1)
        let json = String(decoding: try JSONEncoder().encode(page), as: UTF8.self)
        #expect(!json.contains("private-alpha") && !json.contains("private-beta") && !json.contains("private-source"))
        let invalid = Projection.codexModels(value, page: 0, hidePersonalInfo: true, stale: false, calendar: Self.calendar,
            text: { value, _ in value }, selectionRevision: String(repeating: "0", count: 64), selection: selection)
        #expect(invalid.rows.isEmpty && invalid.timeline.isEmpty && invalid.selectedLabel == "Selection changed")
    }

    @Test
    func `wire query rejects unbounded selectors unknown intervals and hidden model options`() throws {
        let selection = Projection.CodexModelSelection(index: 0, revision: String(repeating: "a", count: 64))
        let query = Projection.Query(codexModelsPage: 0, codexModel: selection, codexGranularity: "weekly", codexMetric: "sessionReferences")
        #expect(query.isValid)
        let decoded = try JSONDecoder().decode(Projection.Query.self, from: JSONEncoder().encode(query))
        #expect(decoded.codexModel?.index == 0 && decoded.codexMetric == "sessionReferences")
        #expect(!Projection.Query(codexModel: selection).isValid)
        #expect(!Projection.Query(codexModelsPage: 0, codexGranularity: "yearly").isValid)
        #expect(!Projection.Query(codexModelsPage: 0, codexMetric: "requests").isValid)
        #expect(!Projection.CodexModelSelection(index: -1, revision: selection.revision).isValid)
        #expect(!Projection.CodexModelSelection(index: 1_000_001, revision: selection.revision).isValid)
    }

    @Test
    func `timeline stays bounded and stale display preserves known values with qualification`() {
        let value = Self.analysis(Self.input([Self.entry("2026-11-04", [Self.row()])]), days: 365)
        let points = Projection.codexTimeline(value, model: nil, granularity: "daily", metric: "tokens",
            stale: true, calendar: Self.calendar, text: { value, _ in value })
        #expect(points.count == 365 && points.last?.column == 364)
        #expect(points.last?.value == 100 && points.last?.detail.contains("Tokens: ~100") == true)
        #expect(Timeline.build(value, model: nil, granularity: "yearly", calendar: Self.calendar).isEmpty)
    }
}
#endif
