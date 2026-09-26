#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarWindows

/// Synthetic response fixtures only. No provider, browser, local account or cost-file reads.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsSpendProviderProjectionTests {
    private static let now = ISO8601DateFormatter().date(from: "2026-09-09T12:00:00Z")!

    private static func mistral() -> UsageSnapshot {
        MistralUsageSnapshot(totalCost: 2, currency: "EUR", currencySymbol: "€",
            totalInputTokens: 20, totalOutputTokens: 5, totalCachedTokens: 0, modelCount: 1,
            daily: [.init(day: "2026-09-09", cost: 2, inputTokens: 20, cachedTokens: 0,
                outputTokens: 5, models: [])],
            startDate: Self.now, endDate: Self.now, updatedAt: Self.now).toUsageSnapshot()
    }

    private static func openCodeGo(daily: [CostUsageDailyReport.Entry]) -> UsageSnapshot {
        OpenCodeGoUsageSnapshot(hasMonthlyUsage: true, rollingUsagePercent: 20,
            weeklyUsagePercent: 30, monthlyUsagePercent: 40, rollingResetInSec: 60,
            weeklyResetInSec: 600, monthlyResetInSec: 6000, zenBalanceUSD: 99,
            daily: daily, updatedAt: Self.now).toUsageSnapshot()
    }

    private static func source(_ provider: UsageProvider,
                               projection: WindowsSpendProviderProjection?) -> WindowsSpendSnapshotLoader.Source {
        .init(id: provider.rawValue + ":fixture", provider: provider, displayName: provider.rawValue,
            modelProviderName: provider.rawValue, environment: [:], cacheRoot: nil,
            codexHomePath: nil, cursorCookieHeader: nil, subscriptionName: nil,
            allowVertexClaudeFallback: false, includePiSessions: false, providerProjection: projection)
    }

    @Test
    func `mistral loader uses captured billing currency and coverage without a local scan`() async throws {
        let usage = Self.mistral()
        let projection = try #require(WindowsSpendProviderProjection(provider: .mistral, usage: usage))
        let source = Self.source(.mistral, projection: projection)
        let scan = try await WindowsSpendSnapshotLoader.make(sources: [source],
            allowPricingRefresh: false, capturedAt: Self.now)(30)
        let result = try #require(scan.inputs.first?.snapshot)
        #expect(result == usage.mistralUsage?.toCostUsageTokenSnapshot(historyDays: 30))
        #expect(result.currencyCode == "EUR")
        #expect(result.costProvenance == .vendorMetered)
        #expect(scan.sourceFailures.isEmpty)
        #expect(scan.retentionEligibleSourceIDs.isEmpty)
    }

    @Test
    func `opencode local history is an estimate and never the prepaid balance`() async throws {
        let entry = CostUsageDailyReport.Entry(date: "2026-09-09", inputTokens: 20,
            outputTokens: 5, totalTokens: 25, costUSD: 2, modelsUsed: nil, modelBreakdowns: nil)
        let usage = Self.openCodeGo(daily: [entry])
        let projection = try #require(WindowsSpendProviderProjection(provider: .opencodego, usage: usage))
        let source = Self.source(.opencodego, projection: projection)
        let scan = try await WindowsSpendSnapshotLoader.make(sources: [source],
            allowPricingRefresh: false, capturedAt: Self.now)(30)
        let result = try #require(scan.inputs.first?.snapshot)
        #expect(result == usage.opencodegoUsage?.toCostUsageTokenSnapshot(historyDays: 30))
        #expect(result.costProvenance == .listPriceEstimate)
        #expect(result.last30DaysCostUSD != 99)
        #expect(scan.sourceFailures.isEmpty)
        #expect(scan.widgetCosts.isEmpty)
    }

    @Test
    func `missing or cross provider response fails instead of returning a successful zero`() async throws {
        let mistral = try #require(WindowsSpendProviderProjection(provider: .mistral, usage: Self.mistral()))
        for source in [Self.source(.mistral, projection: nil), Self.source(.opencodego, projection: mistral)] {
            let scan = try await WindowsSpendSnapshotLoader.make(sources: [source],
                allowPricingRefresh: false, capturedAt: Self.now)(30)
            #expect(scan.inputs.isEmpty)
            #expect(scan.sourceFailures.count == 1)
            #expect(scan.sourceFailures.first?.sourceID == source.id)
            #expect(scan.retentionEligibleSourceIDs.isEmpty)
        }
    }

    @Test
    func `web quota without local rows cannot manufacture opencode cost history`() async throws {
        let projection = try #require(WindowsSpendProviderProjection(provider: .opencodego,
            usage: Self.openCodeGo(daily: [])))
        let scan = try await WindowsSpendSnapshotLoader.make(
            sources: [Self.source(.opencodego, projection: projection)],
            allowPricingRefresh: false, capturedAt: Self.now)(30)
        #expect(scan.inputs.isEmpty)
        #expect(scan.sourceFailures.count == 1)
        #expect(scan.widgetCosts.isEmpty)
    }

    @Test
    func `identical totals from a new fetch cannot reuse the previous collection`() throws {
        let usage = Self.mistral()
        let first = try #require(WindowsSpendProviderProjection(provider: .mistral, usage: usage))
        let next = try #require(WindowsSpendProviderProjection(provider: .mistral, usage: usage))
        #expect(first == first)
        #expect(first != next)
        #expect(Self.source(.mistral, projection: first) != Self.source(.mistral, projection: next))
        #expect(!Self.source(.mistral, projection: first).supportsRetainedCollection)
    }

    @Test
    func `mistral widget ownership requires the explicit winning web session`() throws {
        let settings = MistralProviderSettings(cookieSource: .manual,
            manualCookieHeader: "ory_session_fixture=synthetic-a; csrftoken=synthetic-csrf")
        let owner = try #require(WindowsSpendProviderProjection.mistralWidgetOwner(settings: settings, strategy: .web))
        #expect(!owner.contains("synthetic-a"))
        #expect(WindowsSpendProviderProjection.mistralWidgetOwner(settings: settings, strategy: .apiToken) == nil)
        #expect(WindowsSpendProviderProjection.mistralWidgetOwner(settings: .init(cookieSource: .auto,
            manualCookieHeader: settings.manualCookieHeader), strategy: .web) == nil)
        #expect(WindowsSpendProviderProjection.mistralWidgetOwner(settings: .init(cookieSource: .manual,
            manualCookieHeader: "csrftoken=synthetic-csrf"), strategy: .web) == nil)
        #expect(WindowsSpendProviderProjection.mistralWidgetOwner(settings: .init(cookieSource: .manual,
            manualCookieHeader: "ory_session_fixture=synthetic-b"), strategy: .web) != owner)
    }

    @Test
    func `mistral cost widget uses the captured quota revision and billing labels`() async throws {
        let revision = UUID()
        let projection = try #require(WindowsSpendProviderProjection(provider: .mistral,
            usage: Self.mistral(), confirmedQuotaAccountRevision: revision))
        var source = Self.source(.mistral, projection: projection)
        source.widgetAccountRevision = revision
        let scan = try await WindowsSpendSnapshotLoader.make(sources: [source],
            allowPricingRefresh: false, capturedAt: Self.now)(30)
        let cost = try #require(scan.widgetCosts.first?.cost)
        #expect(cost.accountRevision == revision)
        #expect(cost.summary.currencyCode == "EUR")
        #expect(cost.summary.sessionLabel == "Latest billing day")
        #expect(scan.widgetCostFailures.isEmpty)
    }

    @Test
    func `a different quota revision withdraws the widget while preserving the billing result`() async throws {
        let projection = try #require(WindowsSpendProviderProjection(provider: .mistral,
            usage: Self.mistral(), confirmedQuotaAccountRevision: UUID()))
        var source = Self.source(.mistral, projection: projection)
        source.widgetAccountRevision = UUID()
        let scan = try await WindowsSpendSnapshotLoader.make(sources: [source],
            allowPricingRefresh: false, capturedAt: Self.now)(30)
        #expect(scan.inputs.count == 1)
        #expect(scan.sourceFailures.isEmpty)
        #expect(scan.widgetCosts.isEmpty)
        #expect(scan.widgetCostFailures.first?.accountIdentityUnconfirmed == true)
    }

    @Test
    func `a supplied quota revision cannot turn local opencode estimates into account owned costs`() async throws {
        let revision = UUID()
        let entry = CostUsageDailyReport.Entry(date: "2026-09-09", inputTokens: 20,
            outputTokens: 5, totalTokens: 25, costUSD: 2, modelsUsed: nil, modelBreakdowns: nil)
        let projection = try #require(WindowsSpendProviderProjection(provider: .opencodego,
            usage: Self.openCodeGo(daily: [entry]), confirmedQuotaAccountRevision: revision))
        #expect(projection.confirmedQuotaAccountRevision == nil)
        #expect(!projection.confirmsWidgetRevision(revision, provider: .opencodego))
        var source = Self.source(.opencodego, projection: projection)
        source.widgetAccountRevision = revision
        let scan = try await WindowsSpendSnapshotLoader.make(sources: [source],
            allowPricingRefresh: false, capturedAt: Self.now)(30)
        #expect(scan.inputs.count == 1)
        #expect(scan.widgetCosts.isEmpty)
        #expect(scan.widgetCostFailures.first?.accountIdentityUnconfirmed == true)
    }
}
#endif
