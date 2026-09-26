#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarWindows

/// Synthetic in-memory models only. No defaults, providers, files, UI or transport are opened.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsAppSpendProjectionTests {
    private static let day = Date(timeIntervalSince1970: 1788912000)
    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private static func group(_ code: String = "USD", providerCount: Int = 1, label: String = "private@example.invalid")
        -> WindowsSpendDashboardModel.CurrencyGroup {
        let start = Self.calendar.date(byAdding: .day, value: -1, to: Self.day)!
        let end = Self.calendar.date(byAdding: .day, value: 1, to: Self.day)!
        return .init(currencyCode: code,
            providers: (0..<providerCount).map { .init(id: "private-source-\($0)", rank: $0 + 1, provider: .codex,
                displayName: label, totalTokens: nil, totalCost: 1, coveredDayCount: 1) },
            models: [],
            projects: [.init(rank: 1, provider: .codex, providerName: label, sourceID: "private-source",
                projectName: "Private Repository", path: "C:\\private\\repository", totalTokens: 20, totalCost: 1)],
            dailyPoints: [.init(sourceID: "private-source", provider: .codex, providerName: label,
                day: Self.day, cost: 0, stackStart: 0, stackEnd: 0)],
            totalTokens: nil, totalCost: Double(providerCount), coveredDayCount: 1,
            chartDomain: start...end, modelHistoryCompleteness: .incomplete,
            sessions: [.init(id: "private-session-id", sourceID: "private-source", provider: .codex,
                displayName: label, lastActivity: Self.day, totalTokens: 20, totalCost: 1, modelName: nil)],
            timeZone: Self.calendar.timeZone)
    }
    private static func snapshot(groups: [WindowsSpendDashboardModel.CurrencyGroup]? = nil,
                                 activity: [WindowsSpendDashboardModel.TokenActivityPoint] = [],
                                 stale: Bool = false, partial: Bool = false) -> WindowsSpendDashboardController.Snapshot {
        .init(generation: 1, phase: partial ? .partial : .ready,
            model: .init(requestedDays: 2, groups: groups ?? [Self.group()], tokenActivity: activity),
            sharePayload: nil, loadedAt: Self.day, stale: stale, failure: nil,
            openCodexObservation: .disabled,
            sourceFailures: partial ? [.init(sourceID: "private-source", provider: .codex)] : [])
    }
    private static func page(_ snapshot: WindowsSpendDashboardController.Snapshot,
                             query: WindowsAppSpendProjection.Query = .init(days: 2), privacy: Bool = true)
        -> WindowsAppSpendProjection.Page {
        WindowsAppSpendProjection.make(snapshot: snapshot, query: query,
            hidePersonalInfo: privacy, calendar: Self.calendar, selectionRevision: String(repeating: "0", count: 64))
    }

    private actor LoadCounter {
        var count = 0
        func load() -> WindowsSpendDashboardController.Scan {
            self.count += 1
            return .init(inputs: [], subscriptionNames: [:])
        }
    }

    @Test
    func `window period projection neither reloads sources nor changes controller options`() async {
        let counter = LoadCounter()
        let controller = WindowsSpendDashboardController(loader: { _ in await counter.load() }, publisher: { _ in })
        await controller.refresh()
        let week = await controller.snapshot(days: 7, now: Self.day)
        let year = await controller.snapshot(days: 365, now: Self.day)
        let hourly = await controller.snapshot(days: 7, selectedDay: Self.day, now: Self.day)
        let shared = await controller.snapshot(now: Self.day)
        #expect(week.model.requestedDays == 7)
        #expect(year.model.requestedDays == 365)
        #expect(hourly.model.requestedDays == 7)
        #expect(hourly.model.selectedDay != nil)
        #expect(shared.model.requestedDays == 30)
        #expect(shared.model.selectedDay == nil)
        #expect(await counter.count == 1)
        await controller.stop()
    }

    @Test
    func `query admits only bounded read-only chart selections`() {
        #expect(WindowsAppSpendProjection.Query(days: 365, section: "sessions", chart: "tokens", page: 100000).isValid)
        for query in [
            WindowsAppSpendProjection.Query(days: 0), .init(days: 366), .init(currency: "usd"),
            .init(currency: "../"), .init(section: "credentials"), .init(chart: "execute"), .init(page: -1)
        ] { #expect(!query.isValid) }
    }

    @Test
    func `currency selection never combines two currency groups`() {
        let snapshot = Self.snapshot(groups: [Self.group("EUR", providerCount: 2), Self.group("USD")])
        let page = Self.page(snapshot, query: .init(days: 2, currency: "USD"))
        #expect(page.currency == "USD")
        #expect(page.currencies == ["EUR", "USD"])
        #expect(page.totalRows == 1)
        let missing = Self.page(snapshot, query: .init(days: 2, currency: "KRW"))
        #expect(missing.currency == nil)
        #expect(missing.rows.isEmpty)
        #expect(missing.totalCost == "Unknown")
    }

    @Test
    func `daily missing coverage and confirmed zero remain different`() {
        let page = Self.page(Self.snapshot())
        #expect(page.points.count == 2)
        #expect(page.points[0].value == nil)
        #expect(page.points[1].value == 0)
        #expect(page.points[0].detail.contains("not a confirmed zero"))
        #expect(page.totalTokens == "Unknown")
    }

    @Test
    func `PII is removed before serializing each breakdown`() throws {
        for section in ["providers", "projects", "sessions"] {
            let page = Self.page(Self.snapshot(), query: .init(days: 2, section: section))
            let wire = String(decoding: try JSONEncoder().encode(page), as: UTF8.self)
            #expect(!wire.contains("private@example.invalid"))
            #expect(!wire.contains("Private Repository"))
            #expect(!wire.contains("private-source"))
            #expect(!wire.contains("private-session-id"))
            #expect(!wire.contains("repository"))
        }
        let visible = Self.page(Self.snapshot(), query: .init(days: 2, section: "projects"), privacy: false)
        #expect(visible.rows.first?.title == "Private Repository")
    }

    @Test
    func `breakdown paging preserves access to every captured row`() {
        let snapshot = Self.snapshot(groups: [Self.group(providerCount: 85)])
        let first = Self.page(snapshot)
        let middle = Self.page(snapshot, query: .init(days: 2, page: 1))
        let last = Self.page(snapshot, query: .init(days: 2, page: 100000))
        #expect(first.rows.count == 40)
        #expect(middle.rows.count == 40)
        #expect(last.rows.count == 5)
        #expect(last.page == 2)
        #expect(last.pageCount == 3)
        #expect(first.totalRows == 85)
        #expect(first.rows.first?.subtitle == "Source 1")
        #expect(last.rows.last?.subtitle == "Source 85")
    }

    @Test
    func `heatmap carries unscanned unknown and zero semantics`() {
        let activity: [WindowsSpendDashboardModel.TokenActivityPoint] = [
            .init(day: Self.day, totalTokens: nil, isScanned: false),
            .init(day: Self.day.addingTimeInterval(86400), totalTokens: nil),
            .init(day: Self.day.addingTimeInterval(172800), totalTokens: 0)
        ]
        let page = Self.page(Self.snapshot(activity: activity), query: .init(days: 2, chart: "tokens"))
        #expect(page.points.map(\.level) == [0, 1, 2])
        #expect(page.points.allSatisfy { $0.value == nil })
        #expect(page.points[0].detail.contains("Not scanned"))
        #expect(page.points[1].detail.contains("unknown"))
        #expect(page.points[2].detail.contains("0 tracked tokens"))
    }

    @Test
    func `stale and partial collection remain explicit in the native page`() {
        let page = Self.page(Self.snapshot(stale: true, partial: true))
        #expect(page.stale)
        #expect(page.partial)
        #expect(page.context.contains("Stale"))
        #expect(page.context.contains("Partial collection"))
    }

    @Test
    func `large names stay under the response byte budget without exposing raw keys`() throws {
        let snapshot = Self.snapshot(groups: [Self.group(providerCount: 85,
            label: String(repeating: "한\u{0301}", count: 10000))])
        let page = Self.page(snapshot, privacy: false)
        #expect(page.truncated)
        var response = WindowsAppProtocol.Response(protocolVersion: 1, requestID: UUID(),
            generation: UUID(), status: "ok", snapshot: nil)
        response.spend = page
        let data = try WindowsAppProtocol.response(response)
        #expect(data.count < WindowsAppProtocol.maximumResponseBytes)
        let decoded = try JSONDecoder().decode(WindowsAppProtocol.Response.self, from: data)
        #expect(decoded.snapshot == nil)
        #expect(decoded.spend?.rows.count == 40)
    }
}
#endif
