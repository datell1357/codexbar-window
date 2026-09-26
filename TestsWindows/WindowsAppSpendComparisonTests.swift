#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarWindows

/// Synthetic captures and injected rates only. No exchange fetch, providers, transport or UI.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsAppSpendComparisonTests {
    private typealias Model = WindowsSpendDashboardModel
    private typealias Controller = WindowsSpendDashboardController
    private typealias Projection = WindowsAppSpendProjection
    private static var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private static var day: Date { Self.calendar.date(from: .init(year: 2026, month: 11, day: 4))! }
    private static let periods = [7, 30, 90, 365]

    private static func snapshot(days: Int = 30, code: String = "USD", source: String = "private-source",
                                 cost: Double? = 10, tokens: Int? = 100, covered: Int? = nil,
                                 providers: [Model.ProviderRow]? = nil, calendar: Calendar = Self.calendar,
                                 now: Date = Self.day, stale: Bool = false, partial: Bool = false,
                                 sequence: UInt64 = 9, generation: UInt64 = 1, domainDays: Int? = nil)
        -> Controller.Snapshot {
        let start = calendar.date(byAdding: .day, value: -((domainDays ?? days) - 1), to: calendar.startOfDay(for: now))!
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let group = Model.CurrencyGroup(currencyCode: code,
            providers: providers ?? [.init(id: source, rank: 1, provider: .claude, displayName: "private@example.invalid",
                totalTokens: tokens, totalCost: cost, coveredDayCount: covered ?? days)],
            models: [], dailyPoints: [], totalTokens: tokens, totalCost: cost, coveredDayCount: covered ?? days,
            chartDomain: start...end, modelHistoryCompleteness: .incomplete, timeZone: calendar.timeZone)
        return .init(generation: generation, phase: partial ? .partial : .ready,
            model: .init(requestedDays: days, groups: [group],
                         availableSources: [.init(id: source, displayName: "Private alias")]),
            sharePayload: nil, loadedAt: now, stale: stale, failure: nil, openCodexObservation: .disabled,
            sourceFailures: partial ? [.init(sourceID: source, provider: .claude)] : [], publicationSequence: sequence)
    }
    private static func rows(_ periods: [Controller.Snapshot], current: Controller.Snapshot = Self.snapshot(),
                             currency: String? = "USD", calendar: Calendar = Self.calendar) -> [Projection.ComparisonRow] {
        Projection.comparisons(snapshot: current, periods: periods, currency: currency, calendar: calendar,
                               text: { value, _ in value })
    }
    private static func input(_ id: String, currency: String, cost: Double) -> Model.ProviderInput {
        .init(id: id, provider: .claude, displayName: "Private alias",
            snapshot: .init(sessionTokens: 10, sessionCostUSD: cost, last30DaysTokens: 10, last30DaysCostUSD: cost,
                currencyCode: currency, historyDays: 1, costProvenance: .listPriceEstimate,
                daily: [.init(date: "2026-11-04", inputTokens: 10, outputTokens: 0, totalTokens: 10,
                              costUSD: cost, modelsUsed: nil, modelBreakdowns: nil)],
                updatedAt: Self.day))
    }

    @Test
    func `rolling windows share their local end date through a DST transition`() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let day = calendar.date(from: .init(year: 2026, month: 11, day: 4))!
        let periods = Self.periods.map { Self.snapshot(days: $0, calendar: calendar, now: day) }
        let current = Self.snapshot(calendar: calendar, now: day)
        let rows = Self.rows(periods, current: current, calendar: calendar)
        #expect(rows.map(\.days) == Self.periods)
        #expect(rows[0].range == "2026-10-29 – 2026-11-04 · America/New_York")
        #expect(rows[1].range.hasPrefix("2026-10-06 – 2026-11-04"))
        #expect(rows.allSatisfy { $0.details.contains("overlap") })
        #expect(rows.allSatisfy { $0.coverage.contains("Full-period source coverage: 1 / 1") })
        #expect(rows.allSatisfy { !$0.cost.hasPrefix("~") })
    }

    @Test
    func `missing duplicate or different currency windows do not become zero`() {
        #expect(Self.rows([]).allSatisfy { $0.cost == "Unknown" && $0.tokens == "Unknown" })
        var periods = Self.periods.map { Self.snapshot(days: $0) }
        periods.append(Self.snapshot(days: 7))
        #expect(Self.rows(periods)[0].cost == "Unknown")
        #expect(Self.rows(periods)[1].cost != "Unknown")
        periods = Self.periods.map { Self.snapshot(days: $0, code: $0 == 7 ? "EUR" : "USD") }
        #expect(Self.rows(periods)[0].cost == "Unknown")
        #expect(Self.rows(periods, currency: nil).allSatisfy { $0.cost == "Unknown" })
    }

    @Test
    func `partial source and date coverage marks known subtotals`() {
        let providers: [Model.ProviderRow] = [
            .init(id: "private-source", rank: 1, provider: .claude, displayName: "Private alias",
                  totalTokens: 100, totalCost: 10, coveredDayCount: 7),
            .init(id: "unknown-source", rank: 2, provider: .codex, displayName: "Another private alias",
                  totalTokens: nil, totalCost: nil, coveredDayCount: 3)
        ]
        let current = Self.snapshot(providers: providers, stale: true, partial: true)
        let periods = Self.periods.map { Self.snapshot(days: $0, providers: providers) }
        let rows = Self.rows(periods, current: current)
        #expect(rows[0].cost.hasPrefix("~"))
        #expect(rows[0].tokens.hasPrefix("~"))
        #expect(rows[0].coverage.contains("Full-period source coverage: 1 / 2"))
        #expect(rows[1].coverage.contains("Full-period source coverage: 0 / 2"))
        #expect(rows[0].details.contains("Stale collection"))
        #expect(rows[0].details.contains("Partial collection"))
        #expect(rows[0].details.contains("missing values are not zero"))
    }

    @Test
    func `confirmed zero and unknown remain different in comparison rows`() {
        let periods = Self.periods.map { Self.snapshot(days: $0, cost: 0, tokens: 0) }
        let zero = Self.rows(periods, current: Self.snapshot(cost: 0, tokens: 0))
        #expect(zero.allSatisfy { $0.cost != "Unknown" && $0.tokens == "0" && !$0.cost.hasPrefix("~") })
        let missing = Self.periods.map { Self.snapshot(days: $0, cost: nil, tokens: nil) }
        #expect(Self.rows(missing).allSatisfy { $0.cost == "Unknown" && $0.tokens == "Unknown" })
    }

    @Test
    func `another collection source catalog or date range cannot supply a comparison`() {
        for invalid in [
            Self.snapshot(days: 7, sequence: 10),
            Self.snapshot(days: 7, generation: 2),
            Self.snapshot(days: 7, source: "another-owner"),
            Self.snapshot(days: 7, now: Self.day.addingTimeInterval(-86400)),
            Self.snapshot(days: 7, domainDays: 8),
            Self.snapshot(days: 7, providers: [])
        ] {
            #expect(Self.rows([invalid])[0].cost == "Unknown")
        }
    }

    @Test
    func `injected rates convert all sources once and unavailable rates retain original currency`() {
        let inputs = [Self.input("USD-source", currency: "USD", cost: 2),
                      Self.input("EUR-source", currency: "EUR", cost: 4)]
        for days in Self.periods {
            let converted = Model.build(inputs: inputs, requestedDays: days, now: Self.day, calendar: Self.calendar,
                preferredCurrencyCode: "KRW", conversionRates: ["EUR": 2, "KRW": 1000], includeDetails: false)
            #expect(converted.groups.count == 1)
            #expect(converted.groups[0].currencyCode == "KRW")
            #expect(converted.groups[0].totalCost == 4000)
            #expect(converted.groups[0].totalTokens == 20)
        }
        let fallback = Model.build(inputs: inputs, requestedDays: 7, now: Self.day, calendar: Self.calendar,
            preferredCurrencyCode: "KRW", conversionRates: ["KRW": 1000], includeDetails: false)
        #expect(fallback.groups.map(\.currencyCode) == ["EUR", "KRW"])
        #expect(fallback.groups[0].totalCost == 4)
        #expect(fallback.groups[1].totalCost == 2000)
        for invalid in [0.0, -1, Double.infinity, Double.nan] {
            #expect(Model.currencyMultiplier(from: "USD", to: "EUR", rates: ["EUR": invalid]) == nil)
        }
        #expect(Model.currencyMultiplier(from: "EUR", to: "KRW",
            rates: ["EUR": Double.leastNonzeroMagnitude, "KRW": Double.greatestFiniteMagnitude]) == nil)
        #expect(Model.currencyMultiplier(from: "EUR", to: "EUR", rates: [:]) == 1)
    }

    @Test
    func `summary projection preserves accounting and omits chart model session and project work`() {
        let inputs = [Self.input("source", currency: "USD", cost: 2)]
        let full = Model.build(inputs: inputs, requestedDays: 7, now: Self.day,
                               calendar: Self.calendar, conversionRates: [:])
        let summary = Model.build(inputs: inputs, requestedDays: 7, now: Self.day,
                                  calendar: Self.calendar, conversionRates: [:], includeDetails: false)
        #expect(summary.groups.first?.providers == full.groups.first?.providers)
        #expect(summary.groups.first?.totalCost == full.groups.first?.totalCost)
        #expect(summary.groups.first?.totalTokens == full.groups.first?.totalTokens)
        #expect(summary.groups.first?.coverage == full.groups.first?.coverage)
        #expect(summary.groups.first?.provenance == full.groups.first?.provenance)
        #expect(summary.groups.first?.dailyPoints.isEmpty == true)
        #expect(summary.groups.first?.models.isEmpty == true)
        #expect(summary.groups.first?.sessions.isEmpty == true)
        #expect(summary.groups.first?.projects.isEmpty == true)
        #expect(summary.tokenActivity.isEmpty)
        #expect(full.groups.first?.dailyPoints.count == 1)
    }

    private actor Counter {
        var count = 0
        func load() -> Controller.Scan {
            self.count += 1
            return .init(inputs: [], subscriptionNames: [:], capturedAt: WindowsAppSpendComparisonTests.day)
        }
    }
    @Test
    func `comparison batch neither recollects nor changes shared period options`() async {
        let counter = Counter()
        var options = Controller.Options()
        options.days = 14
        options.bucketTimeZoneIdentifier = "GMT"
        let controller = Controller(loader: { _ in await counter.load() }, options: options, publisher: { _ in })
        await controller.refresh()
        let view = await controller.appView(days: 7, comparePeriods: true, now: Self.day, conversionRates: ["EUR": 2])
        #expect(view.selected.model.requestedDays == 7)
        #expect(view.comparisons.map(\.model.requestedDays) == Self.periods)
        #expect(view.comparisons.allSatisfy { $0.publicationSequence == view.selected.publicationSequence })
        #expect(view.comparisons.allSatisfy { $0.loadedAt == view.selected.loadedAt })
        #expect(view.conversionRates == ["EUR": 2])
        let shared = await controller.snapshot(now: Self.day)
        #expect(shared.model.requestedDays == 14)
        let disabled = await controller.appView(days: 90, comparePeriods: false, now: Self.day, conversionRates: [:])
        #expect(disabled.comparisons.isEmpty)
        #expect(await counter.count == 1)
        await controller.stop()
    }

    @Test
    func `comparison wire is optional bounded and contains no source identities`() throws {
        let current = Self.snapshot()
        let periods = Self.periods.map { Self.snapshot(days: $0) }
        let query = Projection.Query(days: 30, currency: "USD", comparePeriods: true)
        let page = Projection.make(snapshot: current, query: query, hidePersonalInfo: true, calendar: Self.calendar,
            selectionRevision: String(repeating: "a", count: 64), comparisonSnapshots: periods)
        #expect(page.comparisons?.count == 4)
        var response = WindowsAppProtocol.Response(protocolVersion: 1, requestID: UUID(),
                                                   generation: UUID(), status: "ok", snapshot: nil)
        response.spend = page
        let data = try WindowsAppProtocol.response(response)
        #expect(data.count < WindowsAppProtocol.maximumResponseBytes)
        let wire = String(decoding: data, as: UTF8.self)
        #expect(!wire.contains("private-source"))
        #expect(!wire.contains("private@example.invalid"))
        #expect(!wire.contains("Private alias"))
        let decoded = try JSONDecoder().decode(WindowsAppProtocol.Response.self, from: data)
        #expect(decoded.spend?.comparisons?.map(\.days) == Self.periods)
        let queryData = try JSONEncoder().encode(query)
        #expect(try JSONDecoder().decode(Projection.Query.self, from: queryData).comparePeriods == true)
        let disabled = Projection.make(snapshot: current, query: .init(days: 30), hidePersonalInfo: true,
                                       calendar: Self.calendar, selectionRevision: String(repeating: "a", count: 64))
        #expect(disabled.comparisons == nil)
    }
}
#endif
