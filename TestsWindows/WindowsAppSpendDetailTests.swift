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

/// In-memory captures only; no providers, disk, settings, native UI or pipe connections.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsAppSpendDetailTests {
    private typealias Projection = WindowsAppSpendProjection
    private typealias Model = WindowsSpendDashboardModel
    private static let revision = String(repeating: "a", count: 64)
    private static var calendar: Calendar { Self.calendar(zone: "UTC") }
    private static func calendar(zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }
    private static func date(_ year: Int = 2026, _ month: Int = 9, _ day: Int = 8,
                             calendar: Calendar = Self.calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    private static func group(code: String = "USD", names: [String] = ["Private Alpha", "Private Beta"],
                              sessionIDs: [String] = ["private-session"], modelCount: Int = 85,
                              label: String = "private@example.invalid", start: Date = Self.date(),
                              days: Int = 3, calendar: Calendar = Self.calendar,
                              projectDays: [Model.ProjectDayRow] = [], hourly: [Model.HourlyPoint] = [],
                              selectedDay: Date? = nil) -> Model.CurrencyGroup {
        let models: [Model.ModelRow] = (0..<modelCount).map {
            .init(rank: $0 + 1, provider: .codex, providerName: label, modelName: "example-model-\($0)",
                  totalTokens: $0, totalCost: nil, tokenMix: .init(inputTokens: $0))
        }
        let projects: [Model.ProjectRow] = names.enumerated().map { index, name in
            .init(rank: index + 1, provider: .codex, providerName: label, sourceID: "private-source",
                  projectName: name, path: "C:\\private\\repository", totalTokens: 100, totalCost: 250,
                  daily: projectDays, models: models)
        }
        let sessions: [Model.SessionRow] = sessionIDs.map {
            .init(id: $0, sourceID: "private-source", provider: .codex, displayName: label,
                  lastActivity: start, totalTokens: 100, totalCost: 250, modelName: nil,
                  requestCount: 3, tokenMix: .init(inputTokens: 100), models: models)
        }
        let end = calendar.date(byAdding: .day, value: days, to: start)!
        return .init(currencyCode: code,
            providers: [.init(id: "private-source", rank: 1, provider: .codex, displayName: label,
                              totalTokens: 100, totalCost: 250, coveredDayCount: 1)],
            models: [], projects: projects, dailyPoints: [], totalTokens: 100, totalCost: 250,
            coveredDayCount: 1, chartDomain: start...end, modelHistoryCompleteness: .incomplete,
            sessions: sessions, selectedDay: selectedDay, hourlyPoints: hourly, timeZone: calendar.timeZone)
    }
    private static func snapshot(_ groups: [Model.CurrencyGroup] = [Self.group()], days: Int = 3)
        -> WindowsSpendDashboardController.Snapshot {
        .init(generation: 1, phase: .ready, model: .init(requestedDays: days, groups: groups),
              sharePayload: nil, loadedAt: Self.date(), stale: false, failure: nil, openCodexObservation: .disabled,
              sourceFailures: [], publicationSequence: 9)
    }
    private static func query(_ kind: String = "project", index: Int? = 0, day: String? = nil, page: Int = 0)
        -> Projection.Query {
        .init(days: 3, currency: "USD", section: kind == "session" ? "sessions" : "projects",
              detail: .init(kind: kind, index: index, day: day, revision: Self.revision, page: page))
    }
    private static func page(_ snapshot: WindowsSpendDashboardController.Snapshot = Self.snapshot(),
                             query: Projection.Query = Self.query(), calendar: Calendar = Self.calendar,
                             hourly: WindowsSpendDashboardController.Snapshot? = nil, privacy: Bool = true)
        -> Projection.Page {
        Projection.make(snapshot: snapshot, query: query, hidePersonalInfo: privacy,
                        calendar: calendar, selectionRevision: Self.revision, hourlySnapshot: hourly)
    }

    @Test
    func `detail shape and revision reject invalid or stale selections`() {
        let snapshot = Self.snapshot()
        for selection in [
            Projection.DetailQuery(kind: "project", index: -1, day: nil, revision: Self.revision),
            .init(kind: "project", index: 0, day: "2026-09-08", revision: Self.revision),
            .init(kind: "session", index: nil, day: nil, revision: Self.revision),
            .init(kind: "session", index: 0, day: nil, revision: "old"),
            .init(kind: "hourly", index: 0, day: "2026-09-08", revision: Self.revision),
            .init(kind: "hourly", index: nil, day: "2026-9-8", revision: Self.revision),
            .init(kind: "execute", index: 0, day: nil, revision: Self.revision),
            .init(kind: "project", index: 0, day: nil, revision: Self.revision, page: -1)
        ] {
            #expect(!selection.isValid)
        }
        var query = Self.query()
        #expect(Projection.acceptsDetail(query, snapshot: snapshot, calendar: Self.calendar, revision: Self.revision))
        #expect(!Projection.acceptsDetail(query, snapshot: snapshot, calendar: Self.calendar,
                                         revision: String(repeating: "b", count: 64)))
        query.currency = nil
        #expect(Self.page(snapshot, query: query).detail == nil)
        query.currency = "EUR"
        #expect(Self.page(snapshot, query: query).detail == nil)
        query = Self.query(index: 2)
        #expect(Self.page(snapshot, query: query).detail == nil)
        query = Self.query()
        query.section = "sessions"
        #expect(Self.page(snapshot, query: query).detail == nil)
    }

    @Test
    func `hourly selection uses strict dates and the exclusive period boundary`() {
        let snapshot = Self.snapshot()
        for day in ["2026-02-30", "2026-09-07", "2026-09-11", "2026-09-08T00:00"] {
            #expect(!Projection.acceptsDetail(Self.query("hourly", index: nil, day: day),
                snapshot: snapshot, calendar: Self.calendar, revision: Self.revision))
        }
        var query = Self.query("hourly", index: nil, day: "2026-09-08")
        #expect(Projection.acceptsDetail(query, snapshot: snapshot, calendar: Self.calendar, revision: Self.revision))
        query.chart = "tokens"
        #expect(!Projection.acceptsDetail(query, snapshot: snapshot, calendar: Self.calendar, revision: Self.revision))
    }

    @Test
    func `selection seal binds collection privacy period currency and row identity`() {
        let defaultKey = SymmetricKey(data: Data(repeating: 1, count: 32))
        let snapshot = Self.snapshot([Self.group(), Self.group(code: "EUR")])
        let query = Self.query()
        func seal(_ snapshot: WindowsSpendDashboardController.Snapshot, _ query: Projection.Query,
                  context: String = "collection:1:9", privacy: Bool = true, key: SymmetricKey? = nil) -> String {
            WindowsAppSpendSelection.revision(snapshot: snapshot, query: query,
                context: context, hidePersonalInfo: privacy, key: key ?? defaultKey)
        }
        let original = seal(snapshot, query)
        #expect(original.count == 64)
        #expect(original == seal(snapshot, query))
        #expect(original != seal(snapshot, query, context: "collection:2:10"))
        #expect(original != seal(snapshot, query, privacy: false))
        #expect(original != seal(snapshot, query, key: SymmetricKey(data: Data(repeating: 2, count: 32))))
        #expect(original != seal(snapshot.refreshing(), query))
        #expect(original != seal(Self.snapshot([Self.group(names: ["Private Beta", "Private Alpha"])]), query))
        #expect(original != seal(Self.snapshot([Self.group(sessionIDs: ["different-private-session"])]), query))
        var changed = query
        changed.days = 7
        #expect(original != seal(snapshot, changed))
        changed = query
        changed.currency = "EUR"
        #expect(original != seal(snapshot, changed))
        changed = query
        changed.detail?.page = 1
        #expect(original == seal(snapshot, changed))
    }

    @Test
    func `project and session model pages preserve every row and hide private identity`() throws {
        for kind in ["project", "session"] {
            let first = Self.page(query: Self.query(kind))
            let second = Self.page(query: Self.query(kind, page: 1))
            let last = Self.page(query: Self.query(kind, page: 100000))
            #expect(first.rows.first?.selectionIndex == 0)
            #expect(first.detail?.rows.count == 40)
            #expect(second.detail?.rows.first?.title == "example-model-40")
            #expect(last.detail?.page == 2)
            #expect(last.detail?.rows.count == 5)
            #expect(last.detail?.totalRows == 85)
            #expect(last.detail?.rows.last?.title == "example-model-84")
            #expect(first.detail?.rows.first?.cost == "Unknown")
            #expect(first.detail?.rows.first?.details.contains("Input: 0") == true)
            let wire = String(decoding: try JSONEncoder().encode(first), as: UTF8.self)
            for secret in ["private@example.invalid", "Private Alpha", "private-source", "private-session", "repository"] {
                #expect(!wire.contains(secret))
            }
        }
        #expect(Self.page().detail?.context.contains("incomplete") == true)
        #expect(Self.page(query: Self.query("session")).detail?.context.contains("before the selected period") == true)
        #expect(Self.page(privacy: false).detail?.title == "Private Alpha")
    }

    @Test
    func `project chart preserves missing duplicate and confirmed zero days`() {
        let start = Self.date()
        let second = Self.calendar.date(byAdding: .day, value: 1, to: start)!
        let third = Self.calendar.date(byAdding: .day, value: 2, to: start)!
        let group = Self.group(projectDays: [
            .init(day: second, totalTokens: 1, totalCost: 1),
            .init(day: second, totalTokens: 2, totalCost: 2),
            .init(day: third, totalTokens: 0, totalCost: 0)
        ])
        let page = Self.page(Self.snapshot([group]))
        #expect(page.detail?.points.count == 3)
        #expect(page.detail?.points.map(\.value) == [nil, nil, 0])
        #expect(page.detail?.points[0].detail.contains("not a confirmed zero") == true)
        #expect(page.detail?.points[1].detail.contains("unambiguous") == true)
    }

    @Test
    func `hourly charts retain DST slots offsets known zero and unknown hours`() throws {
        let calendar = Self.calendar(zone: "America/New_York")
        for (month, day, expected) in [(3, 8, 23), (11, 1, 25)] {
            let start = Self.date(2026, month, day, calendar: calendar)
            let hourly: [Model.HourlyPoint] = (0..<3).map { index in
                .init(sourceID: "private-source", provider: .codex, providerName: "private@example.invalid",
                      hour: start.addingTimeInterval(Double(index) * 3600), cost: Double(index),
                      stackStart: 0, stackEnd: Double(index))
            }
            let main = Self.snapshot([Self.group(start: start, calendar: calendar)])
            let selected = Self.snapshot([Self.group(start: start, calendar: calendar, hourly: hourly, selectedDay: start)])
            let query = Self.query("hourly", index: nil, day: month == 3 ? "2026-03-08" : "2026-11-01")
            let page = Self.page(main, query: query, calendar: calendar, hourly: selected)
            let detail = try #require(page.detail)
            #expect(detail.points.count == expected)
            #expect(detail.points[0].value == 0)
            #expect(detail.points[1].value == 1)
            #expect(detail.points[2].value == 2)
            #expect(detail.points[3].value == nil)
            #expect(detail.rows.count == 3)
            #expect(detail.rows.allSatisfy { $0.tokens == "Unknown" })
            if month == 11 {
                #expect(detail.points[1].label == "01:00 -04:00")
                #expect(detail.points[2].label == "01:00 -05:00")
            }
            let wire = String(decoding: try JSONEncoder().encode(page), as: UTF8.self)
            #expect(!wire.contains("private@example.invalid"))
            #expect(!wire.contains("private-source"))
        }
    }

    @Test
    func `hourly detail rejects another day or publication and retains source paging`() {
        let start = Self.date()
        let query = Self.query("hourly", index: nil, day: "2026-09-08", page: 1)
        let rows: [Model.HourlyPoint] = (0..<45).map { index in
            .init(sourceID: "private-source-\(index)", provider: .codex, providerName: "Private source",
                  hour: start, cost: 1, stackStart: Double(index), stackEnd: Double(index + 1))
        }
        let selected = Self.snapshot([Self.group(hourly: rows, selectedDay: start)])
        let detail = Self.page(query: query, hourly: selected).detail
        #expect(detail?.totalRows == 45)
        #expect(detail?.rows.count == 5)
        #expect(detail?.points.first?.value == 45)
        #expect(Self.page(query: query, hourly: Self.snapshot()).detail == nil)
        var anotherPublication = selected
        anotherPublication.publicationSequence += 1
        #expect(Self.page(query: query, hourly: anotherPublication).detail == nil)
    }

    @Test
    func `parent and detail share one bounded response budget`() throws {
        let snapshot = Self.snapshot([Self.group(names: Array(repeating: String(repeating: "\u{0001}", count: 10000), count: 40),
                                                label: String(repeating: "한\u{0301}", count: 10000))])
        let page = Self.page(snapshot, privacy: false)
        #expect(page.truncated)
        var response = WindowsAppProtocol.Response(protocolVersion: 1, requestID: UUID(),
                                                   generation: UUID(), status: "ok", snapshot: nil)
        response.spend = page
        let data = try WindowsAppProtocol.response(response)
        #expect(data.count < WindowsAppProtocol.maximumResponseBytes)
        let decoded = try JSONDecoder().decode(WindowsAppProtocol.Response.self, from: data)
        #expect(decoded.spend?.rows.count == 40)
        #expect(decoded.spend?.detail?.rows.count == 40)
    }
}
#endif
