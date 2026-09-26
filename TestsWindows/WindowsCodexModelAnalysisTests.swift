#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarWindows

/// Synthetic daily reports, captured collections and injected FX only. No providers, files or UI.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsCodexModelAnalysisTests {
    private typealias Model = WindowsSpendDashboardModel
    private typealias Analysis = WindowsCodexModelAnalysis
    private typealias Projection = WindowsAppSpendProjection
    private typealias Controller = WindowsSpendDashboardController
    private typealias Entry = CostUsageDailyReport.Entry
    private typealias Row = CostUsageDailyReport.ModelBreakdown
    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private static var day: Date { Self.calendar.date(from: .init(year: 2026, month: 11, day: 4))! }
    private static func row(_ name: String = "gpt-example", tokens: Int = 100, cost: Double? = 2) -> Row {
        .init(modelName: name, costUSD: cost, totalTokens: tokens, requestCount: 7,
            inputTokens: tokens, outputTokens: 0, cacheReadTokens: 0, reasoningTokens: 0,
            standardCostUSD: cost, priorityCostUSD: cost == nil ? nil : 0,
            standardTokens: tokens, priorityTokens: 0)
    }
    private static func entry(_ date: String, _ rows: [Row]) -> Entry {
        .init(date: date, inputTokens: nil, outputTokens: nil,
            totalTokens: rows.allSatisfy { $0.totalTokens != nil } ? rows.reduce(0) { $0 + ($1.totalTokens ?? 0) } : nil,
            costUSD: rows.allSatisfy { $0.costUSD != nil } ? rows.reduce(0) { $0 + ($1.costUSD ?? 0) } : nil,
            modelsUsed: nil, modelBreakdowns: rows)
    }
    private static func input(_ daily: [Entry], id: String = "private-source", currency: String = "USD",
                              historyDays: Int = 30, established: Bool = true, authoritative: Bool = true,
                              now: Date = Self.day, provider: UsageProvider = .codex,
                              kind: Model.SourceKind = .native) -> Model.ProviderInput {
        .init(id: id, provider: provider, displayName: "private@example.invalid",
            snapshot: .init(sessionTokens: nil, sessionCostUSD: nil,
                last30DaysTokens: authoritative && daily.allSatisfy { $0.totalTokens != nil }
                    ? daily.reduce(0) { $0 + ($1.totalTokens ?? 0) } : nil,
                last30DaysCostUSD: authoritative && daily.allSatisfy { $0.costUSD != nil }
                    ? daily.reduce(0) { $0 + ($1.costUSD ?? 0) } : nil,
                currencyCode: currency, historyDays: historyDays, historyCoverageIsEstablished: established,
                costProvenance: .listPriceEstimate, daily: daily, updatedAt: now), sourceKind: kind)
    }
    private static func analysis(_ inputs: [Model.ProviderInput], days: Int = 7,
                                 calendar: Calendar = Self.calendar, now: Date = Self.day,
                                 preferred: String = "auto", currency: String? = "USD",
                                 rates: [String: Double] = [:], complete: Bool = true) -> Analysis.Snapshot {
        Analysis.build(inputs: inputs, days: days, now: now, calendar: calendar,
            preferredCurrency: preferred, currency: currency, conversionRates: rates, collectionComplete: complete)
    }
    private static func page(_ value: Analysis.Snapshot, page: Int = 0, privacy: Bool = false,
                             stale: Bool = false, calendar: Calendar = Self.calendar) -> Projection.CodexModelsPage {
        Projection.codexModels(value, page: page, hidePersonalInfo: privacy, stale: stale,
            calendar: calendar, text: { value, _ in value }, selectionRevision: String(repeating: "b", count: 64))
    }

    @Test
    func `adjacent complete periods distinguish new ended unchanged and percent changes`() throws {
        let input = Self.input([
            Self.entry("2026-11-04", [Self.row("gpt-example-growing", tokens: 200, cost: 4),
                Self.row("gpt-example-new"), Self.row("gpt-example-same")]),
            Self.entry("2026-10-28", [Self.row("gpt-example-growing"),
                Self.row("gpt-example-ended"), Self.row("gpt-example-same")])
        ])
        let value = Self.analysis([input])
        #expect(value.current.tokensComplete && value.previous.tokensComplete)
        #expect(value.current.costComplete && value.previous.costComplete)
        #expect(value.current.interval.duration == value.previous.interval.duration)
        #expect(value.previous.interval.end == value.current.interval.start)
        let rows = Self.page(value).rows
        let growing = try #require(rows.first { $0.title == "gpt-example-growing" })
        #expect(growing.currentTokens == "200" && growing.previousTokens == "100")
        #expect(growing.tokenChange.hasPrefix("+100") && growing.costChange.hasPrefix("+100"))
        #expect(rows.first { $0.title == "gpt-example-new" }?.tokenChange == "New")
        #expect(rows.first { $0.title == "gpt-example-ended" }?.costChange == "Ended")
        #expect(rows.first { $0.title == "gpt-example-same" }?.tokenChange == "Unchanged")
        #expect(growing.details.contains("Current standard: 200 tokens"))
        #expect(growing.details.contains("Current priority: 0 tokens"))
        #expect(!growing.details.contains("7 sessions"))
    }

    @Test
    func `unpriced models preserve token comparisons without fabricating cost or tiers`() throws {
        let missing = Row(modelName: "gpt-example", costUSD: nil, totalTokens: 100)
        let value = Self.analysis([Self.input([
            Self.entry("2026-11-04", [missing]), Self.entry("2026-10-28", [Self.row()])
        ])])
        let row = try #require(Self.page(value).rows.first)
        #expect(row.currentTokens == "100" && row.tokenChange == "Unchanged")
        #expect(row.currentCost == "Unknown" && row.costChange == "Unavailable")
        #expect(row.details.contains("Current standard: Unknown tokens"))
        #expect(row.details.contains("Current priority: Unknown tokens"))
        #expect(row.details.contains("Reasoning: Unknown"))
    }

    @Test
    func `incomplete history does not turn absent models into a new or ended state`() {
        let daily = [Self.entry("2026-11-04", [Self.row()])]
        for input in [
            Self.input(daily, historyDays: 7),
            Self.input(daily, authoritative: false),
            Self.input(daily, established: false)
        ] {
            let page = Self.page(Self.analysis([input]))
            #expect(page.rows.allSatisfy { $0.tokenChange == "Unavailable" && $0.costChange == "Unavailable" })
            #expect(page.rows.allSatisfy { $0.previousTokens == "Unknown" && $0.previousCost == "Unknown" })
        }
        let annual = Self.analysis([Self.input(daily, historyDays: 365)], days: 365)
        #expect(annual.current.fullSources == 1 && annual.previous.fullSources == 0)
        #expect(Self.page(annual).rows.first?.tokenChange == "Unavailable")
    }

    @Test
    func `confirmed empty history is zero while an unknown empty history stays unknown`() {
        let zero = Self.analysis([Self.input([])])
        #expect(zero.current.tokens.value == 0 && zero.current.tokensComplete)
        #expect(zero.previous.cost.value == 0 && zero.previous.costComplete)
        let unknown = Self.analysis([Self.input([], authoritative: false)])
        #expect(unknown.current.tokens.value == nil && !unknown.current.tokensComplete)
        #expect(unknown.previous.cost.value == nil && !unknown.previous.costComplete)
        #expect(Self.page(unknown).rows.isEmpty)
    }

    @Test
    func `tier mismatches and partial tiers are unknown instead of inferred zeros`() {
        for row in [
            Row(modelName: "gpt-example", costUSD: 2, totalTokens: 100,
                standardCostUSD: 2, standardTokens: 100),
            Row(modelName: "gpt-example", costUSD: 2, totalTokens: 100,
                standardCostUSD: 2, priorityCostUSD: 1, standardTokens: 100, priorityTokens: 1),
            Row(modelName: "gpt-example", costUSD: 2, totalTokens: 100,
                standardCostUSD: -1, priorityCostUSD: 3, standardTokens: -1, priorityTokens: 101)
        ] {
            let value = Self.analysis([Self.input([Self.entry("2026-11-04", [row])])])
            #expect(value.current.models["gpt-example"]?.standardTokens.value == nil)
            #expect(value.current.models["gpt-example"]?.priorityCost.value == nil)
        }
    }

    @Test
    func `duplicate days mismatched totals and invalid dates cannot supply complete changes`() {
        let good = Self.entry("2026-11-04", [Self.row()])
        let mismatched = Entry(date: "2026-11-04", inputTokens: nil, outputTokens: nil,
            totalTokens: 101, costUSD: 3, modelsUsed: nil, modelBreakdowns: [Self.row()])
        for daily in [[good, good], [mismatched], [good, Self.entry("2026-02-30", [Self.row()])]] {
            let value = Self.analysis([Self.input(daily)])
            #expect(!value.current.tokensComplete && !value.current.costComplete)
            #expect(Self.page(value).rows.allSatisfy { $0.tokenChange == "Unavailable" && $0.costChange == "Unavailable" })
        }
        let duplicates = Self.analysis([Self.input([good, good])])
        #expect(duplicates.current.models.isEmpty)
        #expect(duplicates.current.tokens.value == nil)
    }

    @Test
    func `overflow and nonfinite inputs never become plausible lower totals`() {
        var count = Analysis.Count()
        count.add(Int.max); count.add(1); count.add(0)
        #expect(count.value == nil && !count.complete)
        var amount = Analysis.Amount()
        amount.add(Double.greatestFiniteMagnitude); amount.add(Double.greatestFiniteMagnitude); amount.add(0)
        #expect(amount.value == nil && !amount.complete)
        var partial = Analysis.Amount()
        partial.add(2); partial.add(.nan); partial.add(-1)
        #expect(partial.value == 2 && !partial.complete)
    }

    @Test
    func `equal elapsed DST windows keep partial daily boundaries unavailable`() {
        var calendar = Self.calendar
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        for (month, day, key) in [(3, 8, "2026-03-08"), (11, 1, "2026-11-01")] {
            let now = calendar.date(from: .init(year: 2026, month: month, day: day))!
            let value = Self.analysis([Self.input([Self.entry(key, [Self.row()])], now: now)],
                days: 1, calendar: calendar, now: now)
            #expect(value.current.interval.duration == value.previous.interval.duration)
            #expect(!value.previous.boundaryAligned && !value.previous.tokensComplete)
            let page = Self.page(value, calendar: calendar)
            #expect(page.context.contains("time-zone offset change"))
            #expect(page.rows.first?.tokenChange == "Unavailable")
        }
    }

    @Test
    func `currency groups use one injected conversion and exclude other provider sources`() {
        let daily = [Self.entry("2026-11-04", [Self.row()])]
        let inputs = [Self.input(daily, id: "usd"),
                      Self.input(daily, id: "eur", currency: "EUR"),
                      Self.input(daily, id: "claude", provider: .claude),
                      Self.input(daily, id: Model.openCodexSourceID, kind: .openCodex)]
        let converted = Self.analysis(inputs, preferred: "KRW", currency: "KRW", rates: ["EUR": 2, "KRW": 1000])
        #expect(converted.sourceCount == 2)
        #expect(converted.current.cost.value == 3000 && converted.current.tokens.value == 200)
        let fallback = Self.analysis(inputs, preferred: "KRW", currency: "EUR", rates: ["KRW": 1000])
        #expect(fallback.sourceCount == 1 && fallback.current.cost.value == 2)
        let absent = Self.analysis(inputs, currency: "JPY")
        #expect(absent.sourceCount == 0 && absent.current.tokens.value == nil)
        #expect(Self.page(absent).context.contains("No included native Codex source"))
    }

    @Test
    func `stale or incomplete collection suppresses changes without deleting known rows`() {
        let input = Self.input([Self.entry("2026-11-04", [Self.row()])])
        for page in [Self.page(Self.analysis([input], complete: false)),
                     Self.page(Self.analysis([input]), stale: true)] {
            #expect(page.rows.first?.currentTokens == "~100")
            #expect(page.rows.first?.previousTokens == "Unknown")
            #expect(page.rows.first?.tokenChange == "Unavailable")
            #expect(page.context.contains("stale or incomplete"))
        }
    }

    private actor Counter {
        var count = 0
        let inputs: [Model.ProviderInput]
        init(_ inputs: [Model.ProviderInput]) { self.inputs = inputs }
        func load() -> Controller.Scan {
            self.count += 1
            return .init(inputs: self.inputs, subscriptionNames: [:], capturedAt: WindowsCodexModelAnalysisTests.day)
        }
    }

    @Test
    func `app projection respects source filters and does not recollect or change shared options`() async throws {
        let daily = [Self.entry("2026-11-04", [Self.row()])]
        let counter = Counter([Self.input(daily, id: "visible"), Self.input(daily, id: "hidden"),
            Self.input(daily, id: Model.openCodexSourceID, kind: .openCodex)])
        var options = Controller.Options()
        options.days = 14; options.bucketTimeZoneIdentifier = "GMT"; options.hiddenSourceIDs = ["hidden"]
        let controller = Controller(loader: { _ in await counter.load() }, options: options, publisher: { _ in })
        await controller.refresh()
        let view = await controller.appView(days: 7, comparePeriods: true, now: Self.day,
            conversionRates: [:], codexModels: true, currency: "USD")
        #expect(view.codexModels?.sourceCount == 1 && view.codexModels?.current.tokens.value == 100)
        #expect(view.comparisons.count == 4)
        let shared = await controller.snapshot(now: Self.day)
        #expect(shared.model.requestedDays == 14)
        let absent = await controller.appView(days: 7, comparePeriods: false, now: Self.day,
            conversionRates: [:], codexModels: true, currency: "JPY")
        #expect(absent.codexModels?.sourceCount == 0)
        options.hideNativeCodexWhenOpenCodexPresent = true
        _ = await controller.setOptions(options)
        let hidden = await controller.appView(days: 7, comparePeriods: false, now: Self.day,
            conversionRates: [:], codexModels: true)
        #expect(hidden.codexModels?.sourceCount == 0)
        let disabled = await controller.appView(days: 7, comparePeriods: false, now: Self.day, conversionRates: [:])
        #expect(disabled.codexModels == nil)
        #expect(await counter.count == 1)
        await controller.stop()
    }

    @Test
    func `model paging and privacy share the enclosing response byte budget`() throws {
        let rows = (0..<85).map { Self.row("private-model-\($0)-" + String(repeating: "한\u{0301}", count: 600)) }
        let inputs = [Self.input([Self.entry("2026-11-04", rows)], historyDays: 365)]
        let analysis = Self.analysis(inputs, days: 365)
        let first = Self.page(analysis, privacy: true)
        let last = Self.page(analysis, page: 100000, privacy: true)
        #expect(first.rows.count == 40 && last.rows.count == 5)
        #expect(first.pageCount == 3 && last.page == 2 && last.totalRows == 85)
        #expect(first.rows.first?.title == "Model 1" && last.rows.last?.title == "Model 85")
        let model = Model.build(inputs: inputs, requestedDays: 365, now: Self.day, calendar: Self.calendar,
            conversionRates: [:])
        let snapshot = Controller.Snapshot(generation: 1, phase: .ready, model: model,
            sharePayload: nil, loadedAt: Self.day, stale: false, failure: nil,
            openCodexObservation: .disabled, sourceFailures: [])
        let query = Projection.Query(days: 365, currency: "USD", section: "models", comparePeriods: true, codexModelsPage: 0)
        let page = Projection.make(snapshot: snapshot, query: query, hidePersonalInfo: true, calendar: Self.calendar,
            selectionRevision: String(repeating: "a", count: 64), comparisonSnapshots: [], codexModels: analysis,
            codexModelsRevision: String(repeating: "b", count: 64))
        var response = WindowsAppProtocol.Response(protocolVersion: 1, requestID: UUID(), generation: UUID(), status: "ok", snapshot: nil)
        response.spend = page
        let bytes = try WindowsAppProtocol.response(response)
        #expect(bytes.count < WindowsAppProtocol.maximumResponseBytes)
        let wire = String(decoding: bytes, as: UTF8.self)
        #expect(!wire.contains("private-model") && !wire.contains("private-source") && !wire.contains("private@example"))
        let decoded = try JSONDecoder().decode(WindowsAppProtocol.Response.self, from: bytes)
        #expect(decoded.spend?.codexModels?.totalRows == 85)
        #expect(decoded.spend?.codexModels?.selectionRevision.count == 64)
        #expect(decoded.spend?.codexModels?.timeline.count == 365)
        #expect(decoded.spend?.rows.first?.title == "Model 1")
        let publicPage = Projection.make(snapshot: snapshot, query: query, hidePersonalInfo: false, calendar: Self.calendar,
            selectionRevision: String(repeating: "a", count: 64), codexModels: analysis,
            codexModelsRevision: String(repeating: "b", count: 64))
        #expect(publicPage.truncated)
        #expect(try JSONEncoder().encode(publicPage).count < WindowsAppProtocol.maximumResponseBytes)
        #expect(Projection.Query(codexModelsPage: 100000).isValid)
        #expect(!Projection.Query(codexModelsPage: -1).isValid)
        #expect(!Projection.Query(codexModelsPage: 100001).isValid)
        let queryBytes = try JSONEncoder().encode(query)
        #expect(try JSONDecoder().decode(Projection.Query.self, from: queryBytes).codexModelsPage == 0)
    }
}
#endif
