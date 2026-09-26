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

/// Synthetic captures only. No scanning, files, defaults, clipboard, process or window operations.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsCodexSessionActionsTests {
    private typealias Evidence = CodexModelActivityEvidence
    private typealias Projection = WindowsAppSpendProjection
    private typealias Analysis = WindowsCodexModelAnalysis
    private typealias Actions = WindowsCodexSessionActions
    private static let id = "11111111-2222-4333-8444-555555555555"
    private static let otherID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    private static let revision = String(repeating: "a", count: 64)
    private static let model = "synthetic-model"
    private static let now = ISO8601DateFormatter().date(from: "2026-11-04T12:00:00Z")!
    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private static func evidence(_ identities: [Evidence.SessionIdentity]?) -> Evidence {
        .init(timeZoneIdentifier: Self.calendar.timeZone.identifier, sinceDay: "2026-10-06",
            untilDay: "2026-11-04", rowsComplete: true,
            rows: [.init(day: "2026-11-04", model: Self.model, effort: "high", sessionReference: 0,
                tokens: 100, knownCostUSD: 1, pricedTokens: 100, unpricedTokens: 0)],
            sessionIdentities: identities)
    }
    private static func input(_ identities: [Evidence.SessionIdentity]?, source: String = "source") -> WindowsSpendDashboardModel.ProviderInput {
        .init(id: source, provider: .codex, displayName: "Synthetic source",
            snapshot: .init(sessionTokens: nil, sessionCostUSD: nil, last30DaysTokens: 100, last30DaysCostUSD: 1,
                historyDays: 30, historyCoverageIsEstablished: true,
                daily: [.init(date: "2026-11-04", inputTokens: 100, outputTokens: 0, totalTokens: 100,
                    costUSD: 1, modelsUsed: nil, modelBreakdowns: [.init(modelName: Self.model, costUSD: 1, totalTokens: 100)])],
                codexActivity: Self.evidence(identities), updatedAt: Self.now))
    }
    private static func analysis(_ ids: [String?] = [Self.id]) -> Analysis.Snapshot {
        Analysis.build(inputs: ids.enumerated().map { index, id in
            Self.input(id.map { [.init(reference: 0, sessionID: $0)] }, source: "source-\(index)")
        }, days: 7, now: Self.now, calendar: Self.calendar,
            preferredCurrency: "USD", currency: "USD", conversionRates: [:], collectionComplete: true)
    }
    private static func query(reference: Int? = 0) -> Projection.CodexSessionQuery {
        .init(modelIndex: 0, period: "current", revision: Self.revision, referenceIndex: reference)
    }
    private static func session(_ id: String?) -> WindowsCodexActivityAnalysis.Session {
        .init(sessionID: id)
    }
    private static func process(_ id: String = "pid:42:100", provider: AgentSession.Provider = .codex,
                                pid: Int32? = 42) -> AgentSession {
        .init(id: id, provider: provider, source: .cli, state: .active, pid: pid, cwd: nil, projectName: nil,
            startedAt: nil, lastActivityAt: nil, transcriptPath: nil, host: "synthetic")
    }

    @Test
    func `builder keeps original identity once and excludes unused file identities`() {
        typealias Scanner = CostUsageScanner
        let range = Scanner.CostUsageDayRange(since: Self.now, until: Self.now, calendar: Self.calendar)
        var builder = CostUsageCodexActivityBuilder(range: range)
        let row = Scanner.CodexUsageRow(day: "2026-11-04", model: Self.model, turnID: nil,
            eventIndex: 0, input: 100, cached: 0, output: 0)
        for id in [Self.otherID.uppercased(), Self.otherID] {
            let usage = Scanner.makeFileUsage(mtimeUnixMs: 1, size: 1, days: [:], parsedBytes: 1,
                sessionId: id, codexRows: [row], codexScanComplete: true)
            builder.add(usage, reconciled: .init(rows: [row], unresolvedGroups: []), resolvedCost: { _ in 1 })
        }
        let empty = Scanner.makeFileUsage(mtimeUnixMs: 1, size: 1, days: [:], parsedBytes: 1,
            sessionId: Self.id, codexRows: [], codexScanComplete: true)
        builder.add(empty, reconciled: .init(rows: [], unresolvedGroups: []))
        let value = builder.finish()
        #expect(value.resolvedSessionIdentities == [0: Self.otherID])
        #expect(value.rows.count == 1 && value.rows.first?.tokens == 200)
    }

    @Test
    func `legacy reports decode without identity and public reports omit the private table`() throws {
        let legacy = Self.evidence(nil)
        let old = try JSONDecoder().decode(Evidence.self, from: JSONEncoder().encode(legacy))
        #expect(old.sessionIdentities == nil && old.resolvedSessionIdentities.isEmpty)
        let value = Self.evidence([.init(reference: 0, sessionID: Self.id)])
        #expect(try JSONDecoder().decode(Evidence.self, from: JSONEncoder().encode(value)) == value)
        let report = CostUsageDailyReport(data: [], summary: nil, codexActivity: value)
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        #expect(!json.contains(Self.id) && !json.contains("sessionIdentities"))
        #expect(CostUsageStore.compatiblePredecessorParserHashes.contains("d1e8a14e0226cccd"))
    }

    @Test
    func `ambiguous and malformed identity tables withdraw links but preserve token evidence`() {
        let invalid: [[Evidence.SessionIdentity]] = [
            [.init(reference: 0, sessionID: Self.id), .init(reference: 0, sessionID: Self.otherID)],
            [.init(reference: 0, sessionID: Self.otherID), .init(reference: 1, sessionID: Self.otherID.uppercased())],
            [.init(reference: -1, sessionID: Self.id)], [.init(reference: 4096, sessionID: Self.id)],
            [.init(reference: 0, sessionID: "bad\nidentity")], [.init(reference: 0, sessionID: String(repeating: "a", count: 513))],
            (0...4096).map { .init(reference: $0, sessionID: "synthetic-\($0)") },
        ]
        for identities in invalid {
            #expect(Self.evidence(identities).resolvedSessionIdentities.isEmpty)
            let value = WindowsCodexActivityAnalysis.build(inputs: [Self.input(identities)],
                interval: DateInterval(start: Self.calendar.startOfDay(for: Self.now),
                    end: Self.calendar.date(byAdding: .day, value: 1, to: Self.calendar.startOfDay(for: Self.now))!),
                calendar: Self.calendar)
            #expect(value.models[Self.model]?.effortTokens["high"] == 100)
            #expect(value.sessions.values.first?.sessionID == nil)
        }
    }

    @Test
    func `reference lookup stays bound to its source and selected period`() throws {
        let value = Self.analysis([Self.id, Self.otherID])
        let first = try #require(Projection.selectedCodexSession(value, query: Self.query(), revision: Self.revision))
        let second = try #require(Projection.selectedCodexSession(value, query: Self.query(reference: 1), revision: Self.revision))
        #expect(first.sessionID == Self.id && second.sessionID == Self.otherID)
        let previous = Projection.CodexSessionQuery(modelIndex: 0, period: "previous",
            revision: Self.revision, referenceIndex: 0)
        #expect(Projection.selectedCodexSession(value, query: previous, revision: Self.revision) == nil)
    }

    @Test
    func `privacy hides identifiers and copying while focus uses backend identity only`() throws {
        let value = Self.analysis()
        let hidden = try #require(Projection.codexSessionsDetail(value, query: Self.query(), revision: Self.revision,
            stale: false, hidePersonalInfo: true, calendar: Self.calendar, text: { text, _ in text }))
        #expect(hidden.sessionActions?.canCopyID == false && hidden.sessionActions?.canCopyResume == false)
        #expect(hidden.sessionActions?.canFocus == true)
        #expect(!String(decoding: try JSONEncoder().encode(hidden), as: UTF8.self).contains(Self.id))
        let visible = try #require(Projection.codexSessionsDetail(value, query: Self.query(), revision: Self.revision,
            stale: false, hidePersonalInfo: false, calendar: Self.calendar, text: { text, _ in text }))
        #expect(visible.context.contains(Self.id) && visible.sessionActions?.canCopyID == true)
        #expect(!String(decoding: try JSONEncoder().encode(Self.query()), as: UTF8.self).contains(Self.id))
    }

    @Test
    func `resume commands require UUIDs and stale hidden or missing identities cannot be copied`() {
        #expect(Actions.clipboard(kind: "copyCodexResume", session: Self.session(Self.id), stale: false,
            hidePersonalInfo: false) == "codex resume " + Self.id)
        #expect(Actions.clipboard(kind: "copyCodexSessionID", session: Self.session("synthetic-id"), stale: false,
            hidePersonalInfo: false) == "synthetic-id")
        for id in ["synthetic-id", "x & echo injected", "\";bad", "bad\nid"] {
            #expect(Actions.clipboard(kind: "copyCodexResume", session: Self.session(id), stale: false,
                hidePersonalInfo: false) == nil)
        }
        for kind in ["copyCodexSessionID", "copyCodexResume"] {
            #expect(Actions.clipboard(kind: kind, session: Self.session(Self.id), stale: true, hidePersonalInfo: false) == nil)
            #expect(Actions.clipboard(kind: kind, session: Self.session(Self.id), stale: false, hidePersonalInfo: true) == nil)
            #expect(Actions.clipboard(kind: kind, session: Self.session(nil), stale: false, hidePersonalInfo: false) == nil)
        }
        #expect(!Actions.availability(Self.session(Self.id), stale: true, hidePersonalInfo: false).canFocus)
    }

    @Test
    func `identity changes invalidate an otherwise identical model reference revision`() {
        let key = SymmetricKey(data: Data(repeating: 1, count: 32))
        let first = WindowsAppSpendSelection.codexModelsRevision(analysis: Self.analysis(), viewRevision: "capture", key: key)
        for id in [Self.otherID, nil] {
            let changed = WindowsAppSpendSelection.codexModelsRevision(analysis: Self.analysis([id]), viewRevision: "capture", key: key)
            #expect(first != changed)
        }
    }

    @Test
    func `focus matching needs exactly one live Codex process with an explicit matching UUID`() {
        let target = Self.process()
        #expect(Actions.matchingProcess(sessionID: Self.id, sessions: [target],
            explicitSessionIDs: [target.id: Self.id])?.id == target.id)
        #expect(Actions.matchingProcess(sessionID: Self.id, sessions: [target], explicitSessionIDs: [:]) == nil)
        #expect(Actions.matchingProcess(sessionID: Self.id, sessions: [target],
            explicitSessionIDs: [target.id: Self.otherID]) == nil)
        let second = Self.process("pid:43:101", pid: 43)
        #expect(Actions.matchingProcess(sessionID: Self.id, sessions: [target, second],
            explicitSessionIDs: [target.id: Self.id, second.id: Self.id]) == nil)
        for process in [Self.process(provider: .claude), Self.process(pid: nil)] {
            #expect(Actions.matchingProcess(sessionID: Self.id, sessions: [process],
                explicitSessionIDs: [process.id: Self.id]) == nil)
        }
    }

    @Test
    func `only the resume subcommand contributes a requested UUID and prompt words cannot replace it`() {
        func requested(_ arguments: [String]) -> String? {
            WindowsSessionLaunchHints.parse(provider: .codex, arguments: arguments).requestedSessionID
        }
        #expect(requested(["resume", Self.id]) == Self.id)
        #expect(requested(["exec", "resume", Self.id]) == Self.id)
        #expect(requested(["resume", Self.id, "resume", Self.otherID]) == Self.id)
        #expect(requested(["resume", "--all", "resume", Self.id]) == nil)
        #expect(requested(["resume", Self.id, "--last"]) == nil)
        #expect(requested(["fork", Self.id]) == nil)
        #expect(requested(["--", "resume", Self.id]) == nil)
    }

    @Test
    func `model CSV emits escaped identity associations only with personal information visible`() throws {
        func csv(_ ids: [String?], hidden: Bool) throws -> String {
            String(decoding: try WindowsCodexModelCSVExporter.encodedData(analysis: Self.analysis(ids),
                query: .init(days: 7, currency: "USD", codexModelsPage: 0), selectionRevision: Self.revision,
                stale: false, hidePersonalInfo: hidden, calendar: Self.calendar), as: UTF8.self)
        }
        let hidden = try csv([Self.id], hidden: true)
        #expect(!hidden.contains(Self.id) && !hidden.contains("\"session_id_association\""))
        let visible = try csv([Self.id], hidden: false)
        #expect(visible.contains(Self.id) && visible.contains("\"session_id_association\""))
        #expect(try csv(["=synthetic()"], hidden: false).contains("'=synthetic()"))
        #expect(!(try csv([nil], hidden: false)).contains(Self.id))
    }

    @Test
    func `session actions require a selected detail and stay within the bounded request contract`() throws {
        let query = Projection.Query(days: 7, currency: "USD", codexModelsPage: 0, codexSessions: Self.query())
        for kind in ["copyCodexSessionID", "copyCodexResume", "focusCodexSession"] {
            let action = WindowsAppSpendExport.Action(kind: kind, expectedRevision: Self.revision)
            #expect(action.isValid && action.accepts(query))
            #expect(!action.accepts(.init(currency: "USD", codexModelsPage: 0)))
            #expect(!action.accepts(.init(currency: "USD", codexModelsPage: 0,
                codexSessions: Self.query(reference: nil))))
            let request = WindowsAppProtocol.Request(protocolVersion: 1, requestID: UUID(), generation: UUID(),
                method: "spendAction", mutation: nil, spendQuery: query, spendAction: action)
            let data = try JSONEncoder().encode(request)
            #expect(data.count <= WindowsAppProtocol.maximumRequestBytes)
            #expect(try WindowsAppProtocol.request(data).spendAction?.kind == kind)
        }
        #expect(!WindowsAppSpendExport.Action(kind: "saveJSON", expectedRevision: Self.revision).accepts(query))
    }
}
#endif
