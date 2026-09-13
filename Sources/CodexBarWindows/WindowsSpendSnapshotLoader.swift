#if os(Windows)
import Foundation
import CodexBarCore

/// Captured collection inputs. Environment/cookie values may contain secrets and must not be logged.
struct WindowsSpendSnapshotLoader {
    struct Source: Sendable {
        let id: String
        let provider: UsageProvider
        let displayName: String
        let modelProviderName: String
        let environment: [String: String]
        let cacheRoot: URL?
        let codexHomePath: String?
        let cursorCookieHeader: String?
        let subscriptionName: WindowsShareStatsSubscriptionName?
        let allowVertexClaudeFallback: Bool
        let includePiSessions: Bool
    }
    enum Failure: Error { case invalidSources, missingCodexHome }

    static func make(sources: [Source], forceRefresh: Bool = false,
                     allowPricingRefresh: Bool = true) -> WindowsSpendDashboardController.Loader {
        { days in
            guard Set(sources.map(\.id)).count == sources.count,
                  sources.allSatisfy({ !$0.id.isEmpty }) else { throw Failure.invalidSources }
            let now = Date()
            let calendar = Calendar.current
            let historyDays = max(1, min(WindowsSpendHistoryPolicy.scanDays, days))
            var inputs: [WindowsSpendDashboardModel.ProviderInput] = []
            var names: [String: WindowsShareStatsSubscriptionName] = [:]
            // Sequential collection avoids overlapping local scans and required/optional child lifetimes.
            for source in sources {
                try Task.checkCancellation()
                let environment: [String: String]
                if source.provider == .codex {
                    guard let home = source.codexHomePath,
                          let normalized = CodexHomeScope.normalizedHomePath(home) else { throw Failure.missingCodexHome }
                    environment = CodexHomeScope.scopedEnvironment(base: source.environment, codexHome: normalized)
                } else {
                    environment = source.environment
                }
                let fetcher = CostUsageFetcher(cacheRoot: source.cacheRoot, calendar: calendar)
                let snapshot = try await fetcher.loadTokenSnapshot(provider: source.provider,
                    environment: environment, now: now, forceRefresh: forceRefresh,
                    allowVertexClaudeFallback: source.allowVertexClaudeFallback,
                    codexHomePath: source.codexHomePath, historyDays: historyDays,
                    cursorCookieHeaderOverride: source.cursorCookieHeader,
                    allowPricingRefresh: allowPricingRefresh, refreshPricingInBackground: false,
                    includePiSessions: source.includePiSessions)
                try Task.checkCancellation()
                let activity: CostUsageTokenActivityCache?
                if source.provider == .codex {
                    activity = await fetcher.loadCachedCodexTokenActivity(now: now,
                        codexHomePath: source.codexHomePath, maximumDays: historyDays)
                } else {
                    activity = nil
                }
                try Task.checkCancellation()
                inputs.append(.init(id: source.id, provider: source.provider, displayName: source.displayName,
                    modelProviderName: source.modelProviderName, snapshot: snapshot, tokenActivityCache: activity))
                if let name = source.subscriptionName { names[source.id] = name }
            }
            return .init(inputs: inputs, subscriptionNames: names)
        }
    }
}
#endif
