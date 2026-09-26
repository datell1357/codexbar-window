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

/// Captured synthetic report references only. No sessions files, providers, accounts, settings or native UI.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsCodexSessionNavigationTests {
    private typealias Projection = WindowsAppSpendProjection
    private typealias Evidence = CodexModelActivityEvidence
    private typealias Analysis = WindowsCodexModelAnalysis
    private static let revision = String(repeating: "a", count: 64)
    private static let now = ISO8601DateFormatter().date(from: "2026-11-04T12:00:00Z")!
    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private static func row(_ model: String = "private-alpha", day: String = "2026-11-04",
                            reference: Int? = 0, tokens: Int = 100, effort: String = "high",
                            priced: Bool = true) -> Evidence.Row {
        .init(day: day, model: model, effort: effort, sessionReference: reference, tokens: tokens,
            knownCostUSD: priced ? Double(tokens) / 100 : nil, pricedTokens: priced ? tokens : nil,
            unpricedTokens: priced ? 0 : nil)
    }
    private static var rows: [Evidence.Row] {
        [Self.row(), Self.row("private-beta", tokens: 50),
         Self.row(day: "2026-11-03", reference: 1, tokens: 40, effort: "low"),
         Self.row(day: "2026-10-28")]
    }
    private static func input(_ rows: [Evidence.Row], id: String = "private-owner",
                              complete: Bool = true) -> WindowsSpendDashboardModel.ProviderInput {
        let grouped = Dictionary(grouping: rows, by: \.day)
        let daily = grouped.keys.sorted().map { day -> CostUsageDailyReport.Entry in
            let models = Dictionary(grouping: grouped[day] ?? [], by: \.model)
            let entries = models.keys.sorted().map { model -> CostUsageDailyReport.ModelBreakdown in
                let values = models[model] ?? []
                return .init(modelName: model,
                    costUSD: values.allSatisfy { $0.knownCostUSD != nil } ? values.reduce(0) { $0 + ($1.knownCostUSD ?? 0) } : nil,
                    totalTokens: values.reduce(0) { $0 + $1.tokens })
            }
            return .init(date: day, inputTokens: nil, outputTokens: nil,
                totalTokens: entries.reduce(0) { $0 + ($1.totalTokens ?? 0) },
                costUSD: entries.allSatisfy { $0.costUSD != nil } ? entries.reduce(0) { $0 + ($1.costUSD ?? 0) } : nil,
                modelsUsed: nil, modelBreakdowns: entries)
        }
        let evidence = Evidence(timeZoneIdentifier: Self.calendar.timeZone.identifier,
            sinceDay: "2026-10-06", untilDay: "2026-11-04", rowsComplete: complete, rows: rows)
        return .init(id: id, provider: .codex, displayName: "private@example.invalid",
            snapshot: .init(sessionTokens: nil, sessionCostUSD: nil,
                last30DaysTokens: daily.reduce(0) { $0 + ($1.totalTokens ?? 0) },
                last30DaysCostUSD: daily.allSatisfy { $0.costUSD != nil } ? daily.reduce(0) { $0 + ($1.costUSD ?? 0) } : nil,
                historyDays: 30, daily: daily, codexActivity: evidence, updatedAt: Self.now))
    }
    private static func analysis(_ inputs: [WindowsSpendDashboardModel.ProviderInput]) -> Analysis.Snapshot {
        Analysis.build(inputs: inputs, days: 7, now: Self.now, calendar: Self.calendar,
            preferredCurrency: "auto", currency: "USD", conversionRates: [:], collectionComplete: true)
    }
    private static func query(model: Int = 0, period: String = "current", reference: Int? = nil, page: Int = 0) -> Projection.CodexSessionQuery {
        .init(modelIndex: model, period: period, revision: Self.revision, referenceIndex: reference, page: page)
    }
    private static func page(_ analysis: Analysis.Snapshot, _ query: Projection.CodexSessionQuery = Self.query(),
                             stale: Bool = false) -> Projection.DetailPage? {
        Projection.codexSessionsDetail(analysis, query: query, revision: Self.revision,
            stale: stale, hidePersonalInfo: true, calendar: Self.calendar, text: { value, _ in value })
    }

    @Test
    func `model session lists deduplicate within each source and isolate adjacent periods`() throws {
        let value = Self.analysis([Self.input(Self.rows)])
        let current = try #require(Self.page(value))
        let previous = try #require(Self.page(value, Self.query(period: "previous")))
        #expect(current.kind == "codexSessions" && current.totalRows == 2 && current.rows.map(\.tokens) == ["100", "40"])
        #expect(previous.totalRows == 1 && previous.rows.first?.tokens == "100")
        #expect(current.rows.map(\.selectionIndex) == [0, 1])
        let multiple = Self.analysis([Self.input(Self.rows, id: "one"), Self.input(Self.rows, id: "two")])
        #expect(Self.page(multiple)?.totalRows == 4)
        #expect(multiple.current.activity.sessions.count == 4)
    }

    @Test
    func `session detail shows other models and daily tokens only within the selected interval`() throws {
        let value = Self.analysis([Self.input(Self.rows)])
        let detail = try #require(Self.page(value, Self.query(reference: 0)))
        #expect(detail.kind == "codexSession" && detail.totalRows == 2)
        #expect(detail.rows.map(\.title) == ["Model 1", "Model 2"])
        #expect(detail.rows.map(\.tokens) == ["100", "50"] && detail.rows.allSatisfy { $0.selectionIndex == nil })
        #expect(detail.points.count == 7 && detail.points.compactMap(\.value).reduce(0, +) == 150)
        #expect(detail.points.first?.dayKey == "2026-10-29" && detail.points.last?.dayKey == "2026-11-04")
        #expect(detail.context.contains("not the full lifetime"))
        #expect(value.current.activity.models["private-alpha"]?.effortPricing["high"]?.cost.value == 1)
        #expect(value.current.activity.models["private-alpha"]?.effortPricing["low"]?.cost.value == 0.4)
    }

    @Test
    func `missing session identities remain unlinked without discarding their model tokens`() throws {
        let value = Self.analysis([Self.input([Self.row(reference: nil), Self.row(reference: 1, tokens: 40)])])
        let list = try #require(Self.page(value))
        #expect(list.totalRows == 1 && list.rows.first?.tokens == "40")
        #expect(value.current.activity.models["private-alpha"]?.effortTokens["high"] == 140)
        #expect(list.context.contains("incomplete") && list.context.contains("Missing session identity"))
        #expect(value.current.activity.sessions.count == 1)
    }

    @Test
    func `session lists and per-session models paginate independently with original privacy labels`() throws {
        let rows = (0..<45).map { Self.row(reference: $0, tokens: 1) }
        let value = Self.analysis([Self.input(rows)])
        let list = try #require(Self.page(value, Self.query(page: 999)))
        #expect(list.page == 1 && list.pageCount == 2 && list.totalRows == 45)
        #expect(list.rows.map(\.selectionIndex) == [40, 41, 42, 43, 44])
        #expect(Self.page(value, Self.query(reference: 44, page: 999))?.page == 0)
        let manyModels = (0..<45).map { Self.row("private-" + String(format: "%03d", $0), tokens: 1) }
        let modelDetail = try #require(Self.page(Self.analysis([Self.input(manyModels)]), Self.query(reference: 0, page: 1)))
        #expect(modelDetail.totalRows == 45 && modelDetail.rows.first?.title == "Model 41")
    }

    @Test
    func `session detail privacy hides source model and effort identifiers`() throws {
        let value = Self.analysis([Self.input([Self.row(effort: "private_effort")])])
        let detail = try #require(Self.page(value, Self.query(reference: 0)))
        let json = String(decoding: try JSONEncoder().encode(detail), as: UTF8.self)
        #expect(!json.contains("private") && !json.contains("sessionReference") && !json.contains("\"source\":"))
        #expect(detail.rows.first?.details.contains("Custom: 100") == true)
        let decoded = try JSONDecoder().decode(Projection.DetailPage.self, from: JSONEncoder().encode(detail))
        #expect(decoded.kind == "codexSession" && decoded.rows.count == 1)
    }

    @Test
    func `stale and legacy price evidence cannot produce complete session cost claims`() throws {
        let value = Self.analysis([Self.input([Self.row(priced: false)], complete: false)])
        let detail = try #require(Self.page(value, Self.query(reference: 0), stale: true))
        #expect(detail.rows.first?.tokens == "~100" && detail.rows.first?.cost == "Unknown")
        #expect(detail.points.first?.value == nil && detail.points.last?.value == 100)
        #expect(detail.context.contains("incomplete"))
    }

    @Test
    func `session ordering and model membership participate in the model selection revision`() {
        let key = SymmetricKey(data: Data(repeating: 1, count: 32))
        func revision(_ rows: [Evidence.Row]) -> String {
            WindowsAppSpendSelection.codexModelsRevision(analysis: Self.analysis([Self.input(rows)]),
                viewRevision: "same-capture", key: key)
        }
        #expect(revision([Self.row()]) != revision([Self.row(reference: 7)]))
        #expect(revision([Self.row(), Self.row("private-beta", reference: 0)])
            != revision([Self.row(), Self.row("private-beta", reference: 1)]))
        let value = Self.analysis([Self.input(Self.rows)])
        #expect(!Projection.acceptsCodexSessions(Self.query(), analysis: value, revision: String(repeating: "b", count: 64)))
        #expect(!Projection.acceptsCodexSessions(Self.query(model: 2), analysis: value, revision: Self.revision))
        #expect(!Projection.acceptsCodexSessions(Self.query(reference: 2), analysis: value, revision: Self.revision))
        #expect(!Projection.acceptsCodexSessions(Self.query(), analysis: nil, revision: Self.revision))
    }

    @Test
    func `bounded queries reject conflicting details and exports strip session navigation`() throws {
        for query in [Self.query(model: -1), Self.query(period: "lifetime"), Self.query(reference: -1),
                      Self.query(page: 100001)] { #expect(!query.isValid) }
        #expect(!Projection.Query(codexSessions: Self.query()).isValid)
        #expect(!Projection.Query(detail: .init(kind: "session", index: 0, day: nil, revision: Self.revision),
            codexModelsPage: 0, codexSessions: Self.query()).isValid)
        let query = Projection.Query(days: 7, currency: "USD", codexModelsPage: 100000,
            codexModel: .init(indices: Array(999_745...1_000_000), revision: Self.revision, mode: "exclude"),
            codexCatalogPage: 100000, codexSessions: Self.query(model: 1000000, reference: 1000000, page: 100000))
        #expect(query.isValid)
        let request = WindowsAppProtocol.Request(protocolVersion: 1, requestID: UUID(), generation: UUID(),
            method: "spend", mutation: nil, spendQuery: query)
        let data = try JSONEncoder().encode(request)
        #expect(data.count <= WindowsAppProtocol.maximumRequestBytes)
        #expect(try WindowsAppProtocol.request(data).spendQuery?.codexSessions?.referenceIndex == 1000000)
        #expect(!WindowsAppSpendExport.Action(kind: "saveModelsCSV", expectedRevision: Self.revision).accepts(query))
    }
}
#endif
