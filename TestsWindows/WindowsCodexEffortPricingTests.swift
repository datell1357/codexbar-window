#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarWindows

/// Synthetic event prices/reports only. No pricing catalog files, accounts, defaults, UI or network.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsCodexEffortPricingTests {
    private typealias Scanner = CostUsageScanner
    private typealias Evidence = CodexModelActivityEvidence
    private static let now = ISO8601DateFormatter().date(from: "2026-11-04T12:00:00Z")!
    private static let model = "private-example-model"
    private static var calendar: Calendar {
        var result = Calendar(identifier: .gregorian); result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private static func price(_ effort: String? = "high", tokens: Int = 100, cost: Double? = 3,
                              priced: Int? = 100, unpriced: Int? = 0) -> Evidence.Row {
        .init(day: "2026-11-04", model: Self.model, effort: effort, sessionReference: 0,
            tokens: tokens, knownCostUSD: cost, pricedTokens: priced, unpricedTokens: unpriced)
    }
    private static func evidence(_ rows: [Evidence.Row], complete: Bool = true) -> Evidence {
        .init(timeZoneIdentifier: Self.calendar.timeZone.identifier, sinceDay: "2026-10-06",
            untilDay: "2026-11-04", rowsComplete: complete, rows: rows)
    }
    private static func input(_ rows: [Evidence.Row], cost: Double? = 3, id: String = "private-source",
                              complete: Bool = true) -> WindowsSpendDashboardModel.ProviderInput {
        let tokens = rows.reduce(0) { $0 + $1.tokens }
        let entry = CostUsageDailyReport.Entry(date: "2026-11-04", inputTokens: tokens, outputTokens: 0,
            totalTokens: tokens, costUSD: cost, modelsUsed: nil,
            modelBreakdowns: [.init(modelName: Self.model, costUSD: cost, totalTokens: tokens)])
        return .init(id: id, provider: .codex, displayName: "private@example.invalid",
            snapshot: .init(sessionTokens: nil, sessionCostUSD: nil, last30DaysTokens: tokens,
                last30DaysCostUSD: cost, historyDays: 30, historyCoverageIsEstablished: true,
                daily: [entry], codexActivity: Self.evidence(rows, complete: complete), updatedAt: Self.now))
    }
    private static func analysis(_ inputs: [WindowsSpendDashboardModel.ProviderInput],
                                 currency: String = "USD", rates: [String: Double] = [:]) -> WindowsCodexModelAnalysis.Snapshot {
        WindowsCodexModelAnalysis.build(inputs: inputs, days: 7, now: Self.now, calendar: Self.calendar,
            preferredCurrency: currency, currency: currency, conversionRates: rates, collectionComplete: true)
    }
    private static func event(_ effort: String = "high", index: Int? = 0, tokens: Int = 100,
                              unpriced: Int? = nil, known: Int64? = nil) -> Scanner.CodexUsageRow {
        .init(day: "2026-11-04", model: Self.model, turnID: nil, eventIndex: index,
            input: tokens, cached: 0, output: 0, knownCostNanos: known, unpricedTokens: unpriced,
            reasoningEffort: effort)
    }
    private static func build(_ rows: [Scanner.CodexUsageRow],
                              price: (Scanner.CodexUsageRow) -> Double?) -> Evidence {
        let range = Scanner.CostUsageDayRange(since: Self.calendar.date(byAdding: .day, value: -29, to: Self.now)!,
            until: Self.now, calendar: Self.calendar)
        var builder = CostUsageCodexActivityBuilder(range: range)
        let usage = Scanner.makeFileUsage(mtimeUnixMs: 1, size: 1, days: [:], parsedBytes: 1,
            sessionId: "private-session", codexRows: rows, codexScanComplete: true,
            codexContextMetadataVersion: Scanner.codexContextMetadataVersion)
        builder.add(usage, reconciled: .init(rows: rows, unresolvedGroups: []), resolvedCost: price)
        return builder.finish()
    }
    private static func csv(_ value: WindowsCodexModelAnalysis.Snapshot, privacy: Bool = true, stale: Bool = false) throws -> String {
        let data = try WindowsCodexModelCSVExporter.encodedData(analysis: value,
            query: .init(days: 7, currency: value.currency, codexModelsPage: 0),
            selectionRevision: String(repeating: "a", count: 64), stale: stale,
            hidePersonalInfo: privacy, calendar: Self.calendar)
        return String(decoding: data, as: UTF8.self)
    }

    @Test
    func `builder retains distinct event prices instead of allocating by token share`() throws {
        let rows = [Self.event("high", index: 0, known: 2_000_000_000),
                    Self.event("low", index: 1, known: 1_000_000_000)]
        let catalog = ModelsDevCatalog(providers: [:])
        let evidence = Self.build(rows) { row in
            Scanner.codexResolvedCostUSD(for: row, modelsDevCatalog: catalog, modelsDevCacheRoot: nil,
                customPricing: .empty, pricingResolver: CostUsagePricing.CodexResolver(catalog: catalog))
        }
        let high = try #require(evidence.rows.first { $0.effort == "high" })
        let low = try #require(evidence.rows.first { $0.effort == "low" })
        #expect(high.tokens == low.tokens && high.knownCostUSD == 2 && low.knownCostUSD == 1)
        #expect(high.pricedTokens == 100 && high.unpricedTokens == 0 && evidence.rowsComplete)
    }

    @Test
    func `zero price absent price and unstable event identity stay distinct`() {
        let free = Self.build([Self.event()]) { _ in 0 }.rows.first
        #expect(free?.knownCostUSD == 0 && free?.pricedTokens == 100 && free?.unpricedTokens == 0)
        let unknown = Self.build([Self.event()]) { _ in nil }.rows.first
        #expect(unknown?.knownCostUSD == nil && unknown?.pricedTokens == 0 && unknown?.unpricedTokens == 100)
        let unstable = Self.build([Self.event(index: nil)]) { _ in 3 }.rows.first
        #expect(unstable?.tokens == 100 && unstable?.knownCostUSD == nil && unstable?.pricedTokens == nil)
        let partial = Self.build([Self.event(unpriced: 40)]) { _ in 3 }.rows.first
        #expect(partial?.knownCostUSD == 3 && partial?.pricedTokens == 60 && partial?.unpricedTokens == 40)
    }

    @Test
    func `invalid partitions and nonfinite or overflowing prices withdraw only pricing evidence`() {
        for cost in [-1.0, Double.infinity, Double.nan] {
            let row = Self.build([Self.event()]) { _ in cost }.rows.first
            #expect(row?.tokens == 100 && row?.knownCostUSD == nil && row?.pricedTokens == nil)
        }
        let invalid = Self.build([Self.event(unpriced: 101)]) { _ in 1 }.rows.first
        #expect(invalid?.knownCostUSD == nil && invalid?.pricedTokens == nil)
        let overflow = Self.build([Self.event(), Self.event(index: 1)]) { _ in Double.greatestFiniteMagnitude }.rows.first
        #expect(overflow?.tokens == 200 && overflow?.knownCostUSD == nil && overflow?.unpricedTokens == nil)
    }

    @Test
    func `optional pricing fields preserve legacy decoding and internal report round trips`() throws {
        let legacy = Evidence.Row(day: "2026-11-04", model: Self.model, effort: nil, sessionReference: nil, tokens: 100)
        let old = try JSONDecoder().decode(Evidence.Row.self, from: JSONEncoder().encode(legacy))
        #expect(old.knownCostUSD == nil && old.pricedTokens == nil && old.unpricedTokens == nil)
        let evidence = Self.evidence([Self.price()])
        #expect(try JSONDecoder().decode(Evidence.self, from: JSONEncoder().encode(evidence)) == evidence)
        let report = CostUsageDailyReport(data: [], summary: nil, codexActivity: evidence)
        #expect(!String(decoding: try JSONEncoder().encode(report), as: UTF8.self).contains("knownCostUSD"))
        #expect(CostUsageStore.compatiblePredecessorParserHashes.contains("01c995aae18025bc"))
    }

    @Test
    func `day model reconciliation applies the same selected currency multiplier to effort costs`() throws {
        let rows = [Self.price("high", tokens: 60, cost: 2, priced: 60),
                    Self.price("low", tokens: 40, cost: 1, priced: 40)]
        let value = Self.analysis([Self.input(rows)], currency: "KRW", rates: ["KRW": 1000])
        let high = try #require(value.current.activity.models[Self.model]?.effortPricing["high"])
        let low = try #require(value.current.activity.models[Self.model]?.effortPricing["low"])
        #expect(high.cost.value == 2000 && low.cost.value == 1000 && high.costComplete && low.costComplete)
        #expect(high.pricedTokens.value == 60 && low.pricedTokens.value == 40)
        #expect(value.current.models[Self.model]?.cost.value == 3000)
    }

    @Test
    func `contradictory costs or partitions do not erase valid effort tokens or fabricate an allocation`() {
        for row in [Self.price(cost: 4), Self.price(priced: 101), Self.price(cost: -1),
                    Self.price(cost: 3, priced: nil, unpriced: nil)] {
            let value = Self.analysis([Self.input([row])])
            let model = value.current.activity.models[Self.model]
            #expect(model?.effortTokens["high"] == 100 && model?.sessions.count == 1)
            #expect(model?.effortPricing["high"]?.cost.value == nil)
            #expect(model?.effortPricing["high"]?.pricedTokens.value == nil)
        }
    }

    @Test
    func `known partial effort prices and entirely unpriced usage retain their separate token coverage`() throws {
        let value = Self.analysis([Self.input([Self.price(priced: 60, unpriced: 40)])])
        let price = try #require(value.current.activity.models[Self.model]?.effortPricing["high"])
        #expect(price.cost.value == 3 && !price.costComplete && price.pricedTokens.value == 60 && price.unpricedTokens.value == 40)
        let text = try Self.csv(value)
        #expect(text.contains("\"high\",\"estimated_cost\",\"3.0\",\"partial\""))
        #expect(text.contains("\"high\",\"unpriced_tokens\",\"40\",\"complete\""))
        let unknown = Self.analysis([Self.input([Self.price(cost: nil, priced: 0, unpriced: 100)], cost: nil)])
        #expect(unknown.current.activity.models[Self.model]?.effortPricing["high"]?.unpricedTokens.value == 100)
        #expect(unknown.current.activity.models[Self.model]?.effortPricing["high"]?.cost.value == nil)
    }

    @Test
    func `legacy sources keep known costs partial and privacy aggregates custom effort without leaking labels`() throws {
        let known = Self.input([Self.price()], id: "one")
        let legacy = Self.input([Self.price(cost: nil, priced: nil, unpriced: nil)], id: "two")
        let combined = Self.analysis([known, legacy])
        let price = try #require(combined.current.activity.models[Self.model]?.effortPricing["high"])
        #expect(price.cost.value == 3 && !price.costComplete && !price.pricedTokens.complete)
        let custom = Self.analysis([Self.input([
            Self.price("private-effort-a", tokens: 60, cost: 2, priced: 60),
            Self.price("private-effort-b", tokens: 40, cost: 1, priced: 40)
        ])])
        let hidden = try Self.csv(custom)
        #expect(!hidden.contains("private-effort") && !hidden.contains(Self.model))
        #expect(hidden.contains("\"Custom\",\"estimated_cost\",\"3.0\",\"complete\""))
        #expect(hidden.contains("\"Custom\",\"priced_tokens\",\"100\",\"complete\""))
        #expect(try Self.csv(custom, privacy: false).contains("private-effort-a"))
    }

    @Test
    func `stale and bounded collection evidence keep effort costs explicitly incomplete in UI and CSV`() throws {
        let value = Self.analysis([Self.input([Self.price()], complete: false)])
        let page = WindowsAppSpendProjection.codexModels(value, page: 0, hidePersonalInfo: true, stale: true,
            calendar: Self.calendar, text: { value, _ in value })
        let details = try #require(page.rows.first?.details)
        #expect(details.contains("high: ~100 tokens") && details.contains("priced ~100 / unpriced ~0 tokens"))
        let text = try Self.csv(value, stale: true)
        #expect(text.contains("\"high\",\"estimated_cost\",\"3.0\",\"partial\"") && text.contains("\"stale\""))
    }

    @Test
    func `missing or invalid conversion multipliers do not fall back to unconverted costs`() {
        let input = Self.input([Self.price()])
        let interval = Self.analysis([input]).current.interval
        for multipliers in [[], [Double.nan], [-1.0], [Double.infinity]] {
            let result = WindowsCodexActivityAnalysis.build(inputs: [input], interval: interval,
                calendar: Self.calendar, costMultipliers: multipliers)
            #expect(result.models[Self.model]?.effortTokens["high"] == 100)
            #expect(result.models[Self.model]?.effortPricing.isEmpty == true)
        }
    }
}
#endif
