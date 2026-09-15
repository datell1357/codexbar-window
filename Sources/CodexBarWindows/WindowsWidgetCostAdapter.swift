#if os(Windows)
import CodexBarCore
import Foundation

/// Copies an ownership-confirmed cost source without project paths, sessions, or credential fingerprints.
public enum WindowsWidgetCostAdapter {
    public enum Failure: Error, Sendable { case unsupportedProvider, scopeChanged, oversized }

    /// The runtime must establish account ownership before supplying confirmedAccountRevision.
    /// If a source is credential-scoped, the expected fingerprint must match; nil never confirms a scoped source.
    public static func make(provider: UsageProvider, snapshot: CostUsageTokenSnapshot,
                            confirmedAccountRevision: UUID, expectedScopeFingerprint: String?, now: Date) throws
        -> WindowsWidgetSnapshotBuilder.TokenCost {
        guard WindowsWidgetConfiguration.selectableProviders.contains(provider) else { throw Failure.unsupportedProvider }
        if snapshot.credentialScopeFingerprint != nil || expectedScopeFingerprint != nil {
            guard let expected = expectedScopeFingerprint, !expected.isEmpty,
                  snapshot.credentialScopeFingerprint == expected else { throw Failure.scopeChanged }
        }
        guard snapshot.daily.count <= 366, (1...366).contains(snapshot.historyDays) else { throw Failure.oversized }
        let daily = try WindowsWidgetHistory.validatedDailyUsage(snapshot.daily.map {
            .init(dayKey: $0.date, totalTokens: $0.totalTokens, costUSD: $0.costUSD)
        })
        let fallbackTokens: Int? = {
            guard !daily.isEmpty else { return nil }
            var total = 0
            for point in daily {
                // An unknown day is not a measured zero and must not produce a complete-looking total.
                guard let tokens = point.totalTokens else { return nil }
                let (next, overflow) = total.addingReportingOverflow(tokens)
                guard !overflow else { return nil }
                total = next
            }
            return total
        }()
        let sessionLabel: String
        if provider == .mistral { sessionLabel = "Latest billing day" }
        else if provider == .codex { sessionLabel = "Today API est. · not billed" }
        else { sessionLabel = "Today" }
        let period = snapshot.historyLabel ?? (snapshot.historyDays == 1 ? "Today" : "\(snapshot.historyDays)d")
        let historyLabel = provider == .codex ? period + " API est. · not billed" : period
        let summary = WidgetSnapshot.TokenUsageSummary(sessionCostUSD: snapshot.sessionCostUSD,
            sessionTokens: snapshot.sessionTokens, last30DaysCostUSD: snapshot.last30DaysCostUSD,
            last30DaysTokens: snapshot.last30DaysTokens ?? fallbackTokens, currencyCode: snapshot.currencyCode,
            sessionLabel: sessionLabel, last30DaysLabel: historyLabel, updatedAt: snapshot.updatedAt)
        let cost = WindowsWidgetSnapshotBuilder.TokenCost(accountRevision: confirmedAccountRevision,
            summary: summary, dailyUsage: daily)
        let validated = try WindowsWidgetSnapshotBuilder.tokenSummary(cost: cost, now: now)
        return .init(accountRevision: confirmedAccountRevision, summary: validated, dailyUsage: daily)
    }
}
#endif
