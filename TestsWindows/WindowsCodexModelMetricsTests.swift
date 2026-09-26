#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarWindows

/// In-memory reports and event rows only; no source scanning, settings, catalogs, UI or native actions.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsCodexModelMetricsTests {
    private typealias Evidence = CodexModelActivityEvidence
    private typealias Analysis = WindowsCodexModelAnalysis
    private typealias Metrics = WindowsCodexModelMetrics
    private typealias Projection = WindowsAppSpendProjection
    private static let alpha = "synthetic-alpha"
    private static let beta = "synthetic-beta"
    private static let revision = String(repeating: "a", count: 64)
    private static let now = ISO8601DateFormatter().date(from: "2026-11-04T12:00:00Z")!
    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private static func row(_ model: String = Self.alpha, tokens: Int = 100, cost: Double? = 1,
                            priced: Int? = nil, unpriced: Int = 0, reference: Int? = 0,
                            aliases: [String]? = nil, legacy: Bool = false) -> Evidence.Row {
        .init(day: "2026-11-04", model: model, effort: "high", sessionReference: reference, tokens: tokens,
            knownCostUSD: legacy ? nil : cost, pricedTokens: legacy ? nil : (priced ?? tokens),
            unpricedTokens: legacy ? nil : unpriced, rawAliases: legacy ? nil : (aliases ?? [model]),
            aliasesComplete: legacy ? nil : true)
    }
    private static func sum(_ values: [Double?]) -> Double? {
        let known = values.compactMap { $0 }
        return known.isEmpty ? nil : known.reduce(0, +)
    }
    private static func input(_ rows: [Evidence.Row], source: String = "source",
                              complete: Bool = true) -> WindowsSpendDashboardModel.ProviderInput {
        let models = Dictionary(grouping: rows, by: \.model)
        let breakdowns = models.keys.sorted().map { model -> CostUsageDailyReport.ModelBreakdown in
            let values = models[model] ?? []
            return .init(modelName: model, costUSD: Self.sum(values.map(\.knownCostUSD)),
                totalTokens: values.reduce(0) { $0 + $1.tokens })
        }
        let count = rows.reduce(0) { $0 + $1.tokens }
        let cost = Self.sum(breakdowns.map(\.costUSD))
        let evidence = Evidence(timeZoneIdentifier: Self.calendar.timeZone.identifier, sinceDay: "2026-10-06",
            untilDay: "2026-11-04", rowsComplete: complete, rows: rows)
        return .init(id: source, provider: .codex, displayName: "Synthetic",
            snapshot: .init(sessionTokens: nil, sessionCostUSD: nil, last30DaysTokens: count,
                last30DaysCostUSD: cost, historyDays: 30, historyCoverageIsEstablished: true,
                daily: [.init(date: "2026-11-04", inputTokens: count, outputTokens: 0, totalTokens: count,
                    costUSD: cost, modelsUsed: nil, modelBreakdowns: breakdowns)],
                codexActivity: evidence, updatedAt: Self.now))
    }
    private static func analysis(_ rows: [Evidence.Row], second: [Evidence.Row]? = nil,
                                 complete: Bool = true) -> Analysis.Snapshot {
        var inputs = [Self.input(rows)]
        if let second { inputs.append(Self.input(second, source: "second")) }
        return Analysis.build(inputs: inputs, days: 7, now: Self.now, calendar: Self.calendar,
            preferredCurrency: "USD", currency: "USD", conversionRates: [:], collectionComplete: complete)
    }
    private static func builder(_ aliases: [String?], limits: CostUsageCodexActivityBuilder.Limits = .init()) -> Evidence {
        typealias Scanner = CostUsageScanner
        let rows = aliases.enumerated().map { index, alias in
            Scanner.CodexUsageRow(day: "2026-11-04", model: Self.alpha, rawModel: alias, turnID: nil,
                eventIndex: index, input: 100, cached: 0, output: 0)
        }
        var builder = CostUsageCodexActivityBuilder(range: .init(since: Self.now, until: Self.now, calendar: Self.calendar),
            limits: limits)
        let usage = Scanner.makeFileUsage(mtimeUnixMs: 1, size: 1, days: [:], parsedBytes: 1,
            codexRows: rows, codexScanComplete: true)
        builder.add(usage, reconciled: .init(rows: rows, unresolvedGroups: []), resolvedCost: { _ in 1 })
        return builder.finish()
    }
    private static func csv(_ value: Analysis.Snapshot, privacy: Bool = false,
                            selection: Projection.CodexModelSelection? = nil) throws -> String {
        String(decoding: try WindowsCodexModelCSVExporter.encodedData(analysis: value,
            query: .init(days: 7, currency: "USD", codexModelsPage: 0, codexModel: selection),
            selectionRevision: Self.revision, stale: false, hidePersonalInfo: privacy, calendar: Self.calendar), as: UTF8.self)
    }

    @Test
    func `raw labels preserve recorded spelling and legacy rows do not invent canonical aliases`() throws {
        let value = Self.builder([Self.alpha, " SYNTHETIC-ALPHA ", Self.alpha])
        let row = try #require(value.rows.first)
        #expect(row.rawAliases == [" SYNTHETIC-ALPHA ", Self.alpha] && row.aliasesComplete == true)
        #expect(row.tokens == 300 && row.knownCostUSD == 3)
        let legacy = try #require(Self.builder([nil]).rows.first)
        #expect(legacy.rawAliases == [] && legacy.aliasesComplete == false && legacy.tokens == 100)
    }

    @Test
    func `alias budgets preserve known labels and all token and pricing totals`() throws {
        for limits in [CostUsageCodexActivityBuilder.Limits(aliasesPerGroup: 1),
                       CostUsageCodexActivityBuilder.Limits(aliases: 1)] {
            let value = Self.builder([Self.alpha, "SYNTHETIC-ALPHA"], limits: limits)
            let row = try #require(value.rows.first)
            #expect(value.rowsComplete && row.rawAliases?.count == 1 && row.aliasesComplete == false)
            #expect(row.tokens == 200 && row.pricedTokens == 200 && row.knownCostUSD == 2)
        }
    }

    @Test
    func `malformed or unrelated aliases do not erase reconciled usage`() {
        for aliases in [[Self.beta], [Self.alpha, Self.alpha], ["bad\nalias"],
                        [String(repeating: "x", count: 257)], Array(repeating: Self.alpha, count: 33)] {
            let value = Self.analysis([Self.row(aliases: aliases)])
            let row = value.current.activity.models[Self.alpha]
            #expect(row?.rawAliases.isEmpty == true && row?.aliasesComplete == false)
            #expect(row?.effortTokens["high"] == 100 && value.current.tokens.value == 100)
        }
    }

    @Test
    func `pricing distinguishes fully priced free partially priced unpriced and unknown models`() {
        let cases: [(Evidence.Row, Double?, String)] = [
            (Self.row(), 1, "known"), (Self.row(cost: 0), 1, "known"),
            (Self.row(priced: 40, unpriced: 60), 0.4, "partial"),
            (Self.row(cost: nil, priced: 0, unpriced: 100), 0, "unavailable"),
            (Self.row(legacy: true), nil, "unavailable"),
        ]
        for (row, coverage, status) in cases {
            let value = Self.analysis([row])
            let metric = Metrics.pricing(Self.alpha, period: value.current, collected: true)
            #expect(metric.coverage.value == coverage && metric.status == status)
            if coverage != nil { #expect(metric.countsComplete && metric.coverage.complete) }
        }
    }

    @Test
    func `legacy sources cannot turn a known pricing subtotal into full coverage`() {
        let value = Self.analysis([Self.row()], second: [Self.row(legacy: true)])
        let pricing = Metrics.pricing(Self.alpha, period: value.current, collected: true)
        #expect(pricing.priced.value == 100 && !pricing.countsComplete && pricing.coverage.value == nil)
        let aliases = Metrics.aliases(Self.alpha, period: value.current, collected: true)
        #expect(aliases.values == [Self.alpha] && !aliases.complete)
    }

    @Test
    func `shares use all models and per-model session references rather than unique sessions`() throws {
        let value = Self.analysis([Self.row(), Self.row(Self.beta, tokens: 300, cost: 3)])
        let shares = Metrics.shares(Self.alpha, period: value.current, collected: true)
        #expect(shares.tokens.value == 0.25 && shares.knownCost.value == 0.25)
        #expect(shares.sessionReferences.value == 0.5 && shares.sessionReferences.complete)
        let selection = Projection.CodexModelSelection(indices: [0], revision: Self.revision)
        let selected = Projection.codexModels(value, page: 0, hidePersonalInfo: false, stale: false,
            calendar: Self.calendar, text: { value, _ in value }, selectionRevision: Self.revision, selection: selection)
        #expect(selected.rows.count == 1 && selected.rows[0].shares.contains("scope share"))
        let csv = try Self.csv(value, selection: selection)
        #expect(csv.contains("\"token_share\",\"0.25\",\"complete\""))
        #expect(csv.contains("\"session_reference_share\",\"0.5\",\"complete\""))
    }

    @Test
    func `confirmed no usage has empty coverage and zero shares without unknown zero substitution`() {
        let value = Self.analysis([Self.row()])
        let pricing = Metrics.pricing(Self.alpha, period: value.previous, collected: true)
        #expect(pricing.status == "no_usage" && pricing.priced.value == 0 && pricing.unpriced.value == 0)
        #expect(pricing.coverage.value == 1 && pricing.coverage.complete)
        let shares = Metrics.shares(Self.alpha, period: value.previous, collected: true)
        #expect(shares.tokens.value == 0 && shares.knownCost.value == 0 && shares.sessionReferences.value == 0)
        #expect(Metrics.pricing(Self.alpha, period: value.previous, collected: false).coverage.value == nil)
    }

    @Test
    func `unknown cost and session identity stay unknown while known denominators remain partial`() {
        let value = Self.analysis([Self.row(cost: nil, priced: 0, unpriced: 100, reference: nil),
                                   Self.row(Self.beta)])
        let alpha = Metrics.shares(Self.alpha, period: value.current, collected: true)
        let beta = Metrics.shares(Self.beta, period: value.current, collected: true)
        #expect(alpha.tokens.value == 0.5 && alpha.knownCost.value == nil && alpha.sessionReferences.value == nil)
        #expect(beta.knownCost.value == 1 && !beta.knownCost.complete)
        #expect(beta.sessionReferences.value == 1 && !beta.sessionReferences.complete)
        #expect(Metrics.pricing(Self.beta, period: value.current, collected: true).status == "known")
    }

    @Test
    func `stale or incomplete captures never mark their retained percentages complete`() {
        let value = Self.analysis([Self.row()])
        let pricing = Metrics.pricing(Self.alpha, period: value.current, collected: false)
        let shares = Metrics.shares(Self.alpha, period: value.current, collected: false)
        #expect(pricing.coverage.value == 1 && !pricing.coverage.complete && pricing.status == "partial")
        #expect(shares.tokens.value == 1 && !shares.tokens.complete)
        #expect(shares.knownCost.value == 1 && !shares.knownCost.complete)
        #expect(!Metrics.aliases(Self.alpha, period: value.current, collected: false).complete)
    }

    @Test
    func `invalid ratios and unknown empty denominators never produce percentages`() {
        for (numerator, denominator) in [(Double.nan, 1.0), (1.0, Double.infinity), (-1.0, 1.0), (2.0, 1.0)] {
            #expect(Metrics.ratio(numerator, denominator, complete: true).value == nil)
        }
        #expect(Metrics.ratio(nil, 1, complete: true).value == nil)
        #expect(Metrics.ratio(0, 0, complete: false).value == nil)
        #expect(Metrics.ratio(0, 0, complete: true).value == 0)
    }

    @Test
    func `CSV carries symbolic pricing states fractions and privacy-aware raw alias associations`() throws {
        let raw = " SYNTHETIC-ALPHA "
        let value = Self.analysis([Self.row(priced: 50, unpriced: 50, aliases: [raw])])
        let csv = try Self.csv(value)
        #expect(csv.contains("\"pricing_coverage\",\"0.5\",\"complete\""))
        #expect(csv.contains("\"partial\",\"cost_status\",\"\",\"complete\""))
        #expect(csv.contains(raw) && csv.contains("\"raw_alias_association\",\"1\",\"complete\""))
        let hidden = try Self.csv(value, privacy: true)
        #expect(!hidden.contains(raw) && !hidden.contains("\"raw_alias_association\""))
        let page = Projection.codexModels(value, page: 0, hidePersonalInfo: true, stale: false,
            calendar: Self.calendar, text: { value, _ in value }, selectionRevision: Self.revision)
        #expect(page.rows.first?.aliases.contains("Hidden") == true)
        #expect(page.rows.first?.pricing.contains("coverage") == true)
        let wire = try JSONEncoder().encode(page)
        #expect(!String(decoding: wire, as: UTF8.self).contains(raw))
        #expect(try JSONDecoder().decode(Projection.CodexModelsPage.self, from: wire).rows.first?.shares == page.rows.first?.shares)
    }

    @Test
    func `legacy metadata decoding and public report JSON keep the optional alias boundary`() throws {
        let old = Self.row(legacy: true)
        let decoded = try JSONDecoder().decode(Evidence.Row.self, from: JSONEncoder().encode(old))
        #expect(decoded.rawAliases == nil && decoded.aliasesComplete == nil)
        let evidence = Self.builder([" SYNTHETIC-ALPHA "])
        #expect(try JSONDecoder().decode(Evidence.self, from: JSONEncoder().encode(evidence)) == evidence)
        let report = CostUsageDailyReport(data: [], summary: nil, codexActivity: evidence)
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        #expect(!json.contains("rawAliases") && !json.contains("SYNTHETIC-ALPHA"))
        #expect(CostUsageStore.compatiblePredecessorParserHashes.contains("619f13f23d9a5b31"))
    }

    @Test
    func `per-model alias cap remains explicit without dropping any usage`() {
        let rows = (0..<270).map { index in
            Self.row(tokens: 1, cost: 0.01, aliases: [
                String(repeating: " ", count: index / 20) + Self.alpha + String(repeating: " ", count: index % 20),
            ])
        }
        let value = Self.analysis(rows)
        let aliases = Metrics.aliases(Self.alpha, period: value.current, collected: true)
        #expect(aliases.values.count == 256 && !aliases.complete)
        #expect(value.current.tokens.value == 270)
        #expect(Metrics.pricing(Self.alpha, period: value.current, collected: true).priced.value == 270)
    }
}
#endif
