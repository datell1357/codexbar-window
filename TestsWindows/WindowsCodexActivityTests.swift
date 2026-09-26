#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarWindows

/// Pure synthetic report/cache values. No source, account, defaults, UI or network access.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsCodexActivityTests {
    private typealias Scanner = CostUsageScanner
    private typealias Builder = CostUsageCodexActivityBuilder
    private typealias Evidence = CodexModelActivityEvidence
    private typealias Input = WindowsSpendDashboardModel.ProviderInput
    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private static let now = ISO8601DateFormatter().date(from: "2026-11-04T12:00:00Z")!
    private static var range: Scanner.CostUsageDayRange {
        .init(since: Self.calendar.date(byAdding: .day, value: -29, to: Self.now)!,
            until: Self.now, calendar: Self.calendar)
    }
    private static func row(_ day: String = "2026-11-04", effort: String? = "high", tokens: Int = 100) -> Scanner.CodexUsageRow {
        .init(day: day, model: "gpt-example", input: tokens, cached: 0, output: 0, reasoningEffort: effort)
    }
    private static func usage(_ rows: [Scanner.CodexUsageRow], session: String? = "private-session",
                              migrated: Bool = true) -> CostUsageFileUsage {
        Scanner.makeFileUsage(mtimeUnixMs: 1, size: 1, days: [:], parsedBytes: 1,
            sessionId: session, codexRows: rows, codexScanComplete: true,
            codexContextMetadataVersion: migrated ? Scanner.codexContextMetadataVersion : nil)
    }
    private static func evidence(_ rows: [Scanner.CodexUsageRow], session: String? = "private-session",
                                 migrated: Bool = true, limits: Builder.Limits = .init()) -> Evidence {
        var builder = Builder(range: Self.range, limits: limits)
        builder.add(Self.usage(rows, session: session, migrated: migrated), reconciled: .init(rows: rows, unresolvedGroups: []))
        return builder.finish()
    }
    private static func report(_ evidence: Evidence?) -> CostUsageDailyReport {
        let dates = ["2026-11-04", "2026-11-03", "2026-10-28"]
        let entries = dates.map { day in
            CostUsageDailyReport.Entry(date: day, inputTokens: 100, outputTokens: 0, totalTokens: 100, costUSD: nil,
                modelsUsed: nil, modelBreakdowns: [.init(modelName: "gpt-example", costUSD: nil, totalTokens: 100)])
        }
        return .init(data: entries, summary: .init(totalInputTokens: 300, totalOutputTokens: 0,
            totalTokens: 300, totalCostUSD: nil), codexActivity: evidence)
    }
    private static func input(_ evidence: Evidence?, id: String = "private-source") -> Input {
        .init(id: id, provider: .codex, displayName: "private@example.invalid",
            snapshot: CostUsageFetcher.tokenSnapshot(from: Self.report(evidence), now: Self.now,
                calendar: Self.calendar, historyCoverageIsEstablished: true, costProvenance: .listPriceEstimate))
    }
    private static func analysis(_ inputs: [Input]) -> WindowsCodexModelAnalysis.Snapshot {
        WindowsCodexModelAnalysis.build(inputs: inputs, days: 7, now: Self.now, calendar: Self.calendar,
            preferredCurrency: "auto", currency: "USD", conversionRates: [:], collectionComplete: true)
    }
    private static var rows: [Scanner.CodexUsageRow] {
        [Self.row(), Self.row("2026-11-03", effort: "low"), Self.row("2026-10-28", effort: nil)]
    }

    @Test
    func `report local references deduplicate sessions across files without exposing identities`() throws {
        var builder = Builder(range: Self.range)
        for session in ["private-session", "private-session", "another-private-session"] {
            builder.add(Self.usage([Self.row()], session: session), reconciled: .init(rows: [Self.row()], unresolvedGroups: []))
        }
        let value = builder.finish()
        #expect(value.rowsComplete && value.rows.count == 2)
        #expect(Set(value.rows.compactMap(\.sessionReference)).count == 2)
        #expect(value.rows.reduce(0) { $0 + $1.tokens } == 300)
        let json = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        #expect(!json.contains("private-session") && !json.contains("rollout_path"))
    }

    @Test
    func `legacy and missing context remain unrecorded while explicit none survives`() {
        #expect(Self.evidence([Self.row()], migrated: false).rows.first?.effort == nil)
        #expect(Self.evidence([Self.row(effort: nil)]).rows.first?.effort == nil)
        #expect(Self.evidence([Self.row(effort: "none")]).rows.first?.effort == "none")
        #expect(Self.evidence([Self.row()], session: nil).rows.first?.sessionReference == nil)
    }

    @Test
    func `file event group caps and invalid rows cannot claim complete evidence`() {
        for limits in [Builder.Limits(files: 0), Builder.Limits(events: 1), Builder.Limits(groups: 1)] {
            #expect(!Self.evidence(Self.rows, limits: limits).rowsComplete)
        }
        #expect(!Self.evidence([Self.row(tokens: -1)]).rowsComplete)
        let overflow = [Self.row(tokens: Int.max), Self.row(tokens: 1)]
        #expect(!Self.evidence(overflow).rowsComplete)
        var builder = Builder(range: Self.range)
        builder.add(Self.usage([]), reconciled: .init(rows: [], unresolvedGroups: [.init(day: "2026-11-04", model: "gpt-example")]))
        #expect(!builder.finish().rowsComplete)
    }

    @Test
    func `public report JSON omits local activity but retained internal reports preserve it`() throws {
        let evidence = Self.evidence(Self.rows)
        let report = Self.report(evidence)
        let encoded = try JSONEncoder().encode(report)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains("codexActivity") && !text.contains("sessionReference") && !text.contains("effort"))
        #expect(try JSONDecoder().decode(CostUsageDailyReport.self, from: encoded).codexActivity == nil)
        let previous = try #require(CostUsageCodexPreviousReport(report: report, cache: CostUsageCache(),
            reportSinceKey: Self.range.sinceKey, reportUntilKey: Self.range.untilKey))
        let restored = try JSONDecoder().decode(CostUsageCodexPreviousReport.self, from: JSONEncoder().encode(previous))
        #expect(restored.report.codexActivity == evidence)
        #expect(Self.input(evidence).snapshot.codexActivity == evidence)
    }

    @Test
    func `merging another nonempty source withdraws native activity evidence`() {
        let report = Self.report(Self.evidence(Self.rows))
        let empty = CostUsageDailyReport(data: [], summary: nil)
        #expect(CostUsageDailyReport.merged([report]).codexActivity == report.codexActivity)
        #expect(CostUsageDailyReport.merged([report, empty]).codexActivity == report.codexActivity)
        #expect(CostUsageDailyReport.merged([report, Self.report(nil)]).codexActivity == nil)
    }

    @Test
    func `period analysis counts distinct sessions and uses recorded effort token totals`() throws {
        let value = Self.analysis([Self.input(Self.evidence(Self.rows))])
        let current = try #require(value.current.activity.models["gpt-example"])
        #expect(value.current.activity.complete && current.sessions.count == 1)
        #expect(current.effortTokens == ["high": 100, "low": 100])
        #expect(value.previous.activity.models["gpt-example"]?.effortTokens == ["": 100])
        let page = WindowsAppSpendProjection.codexModels(value, page: 0, hidePersonalInfo: false, stale: false,
            calendar: Self.calendar, text: { value, _ in value })
        let details = try #require(page.rows.first?.details)
        #expect(details.contains("Session refs — Current: 1 · Previous: 1 · Change: Unchanged"))
        #expect(details.contains("Unrecorded: 100") && details.contains("high: 100"))
        let multiple = Self.analysis([Self.input(Self.evidence(Self.rows), id: "one"), Self.input(Self.evidence(Self.rows), id: "two")])
        #expect(multiple.current.activity.models["gpt-example"]?.sessions.count == 2)
    }

    @Test
    func `missing mismatched duplicate and foreign timezone evidence stays unavailable`() {
        let base = Self.evidence(Self.rows)
        let mismatch = Self.evidence([Self.row(tokens: 99), Self.rows[1], Self.rows[2]])
        let duplicate = Evidence(timeZoneIdentifier: base.timeZoneIdentifier, sinceDay: base.sinceDay,
            untilDay: base.untilDay, rowsComplete: true, rows: base.rows + base.rows)
        let foreign = Evidence(timeZoneIdentifier: "Asia/Seoul", sinceDay: base.sinceDay,
            untilDay: base.untilDay, rowsComplete: true, rows: base.rows)
        for evidence in [nil, mismatch, duplicate, foreign] as [Evidence?] {
            let value = Self.analysis([Self.input(evidence)])
            #expect(!value.current.activity.complete && value.current.activity.models.isEmpty)
        }
        let missingID = Self.analysis([Self.input(Self.evidence(Self.rows, session: nil))])
        #expect(missingID.current.activity.complete)
        #expect(missingID.current.activity.models["gpt-example"]?.sessionsComplete == false)
    }

    @Test
    func `privacy hides custom effort and stale collections withhold session changes`() throws {
        let rows = [Self.row(effort: "private_project_boost"), Self.rows[1], Self.rows[2]]
        let value = Self.analysis([Self.input(Self.evidence(rows))])
        let page = WindowsAppSpendProjection.codexModels(value, page: 0, hidePersonalInfo: true, stale: true,
            calendar: Self.calendar, text: { value, _ in value })
        let json = String(decoding: try JSONEncoder().encode(page), as: UTF8.self)
        #expect(!json.contains("private_project_boost") && !json.contains("private-session") && !json.contains("private-source"))
        #expect(page.rows.first?.details.contains("Custom: ~100") == true)
        #expect(page.rows.first?.details.contains("Change: Unavailable") == true)
    }
}
#endif
