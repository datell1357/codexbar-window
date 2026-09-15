#if os(Windows)
import CodexBarCore
import Foundation

/// Converts ownership-confirmed runtime results to quota and supported optional widget values.
public enum WindowsWidgetSnapshotBuilder {
    public struct TokenCost: Sendable {
        public let accountRevision: UUID
        public let summary: WidgetSnapshot.TokenUsageSummary
        public let dailyUsage: [WidgetSnapshot.DailyUsagePoint]
        public init(accountRevision: UUID, summary: WidgetSnapshot.TokenUsageSummary,
                    dailyUsage: [WidgetSnapshot.DailyUsagePoint] = []) {
            self.accountRevision = accountRevision; self.summary = summary; self.dailyUsage = dailyUsage
        }
    }
    /// The runtime adapter supplies the original projection's dashboard attachment decision.
    public struct CodexExtras: Sendable {
        public enum DashboardVisibility: Sendable { case hidden, displayOnly, attached }
        public let accountRevision: UUID
        public let dashboardVisibility: DashboardVisibility
        public let creditsRemaining: Double?
        public let codeReviewRemainingPercent: Double?
        public let updatedAt: Date
        public init(accountRevision: UUID, dashboardVisibility: DashboardVisibility,
                    creditsRemaining: Double?, codeReviewRemainingPercent: Double?, updatedAt: Date) {
            self.accountRevision = accountRevision; self.dashboardVisibility = dashboardVisibility
            self.creditsRemaining = creditsRemaining; self.codeReviewRemainingPercent = codeReviewRemainingPercent
            self.updatedAt = updatedAt
        }
    }
    /// Cost sources may refresh without a quota result. Ownership is still mandatory.
    public struct CostOnlyObservation: Sendable {
        public let provider: UsageProvider
        public let cost: TokenCost
        public init(provider: UsageProvider, cost: TokenCost) { self.provider = provider; self.cost = cost }
    }
    public struct Observation: Sendable {
        public let presentation: WindowsUsagePresentation
        public let accountRevision: UUID
        public let tokenCost: TokenCost?
        public let codexExtras: CodexExtras?
        public init(presentation: WindowsUsagePresentation, accountRevision: UUID, tokenCost: TokenCost? = nil,
                    codexExtras: CodexExtras? = nil) {
            self.presentation = presentation; self.accountRevision = accountRevision; self.tokenCost = tokenCost
            self.codexExtras = codexExtras
        }
    }
    public enum Failure: Error, Sendable { case oversized, invalidProvider, duplicateProvider, invalidDate, invalidWindow, invalidCost }

    public static func make(observations: [Observation], enabled: [UsageProvider],
                            expectedAccountRevisions: [UsageProvider: UUID], showUsed: Bool,
                            now: Date, costOnly: [CostOnlyObservation] = []) throws -> WidgetSnapshot {
        guard observations.count <= 256, costOnly.count <= 256, enabled.count <= 256, expectedAccountRevisions.count <= 256 else { throw Failure.oversized }
        guard now.timeIntervalSince1970.isFinite else { throw Failure.invalidDate }
        var enabledIDs = [ProviderInstanceID]()
        for provider in enabled where WindowsWidgetConfiguration.selectableProviders.contains(provider) {
            if !enabledIDs.contains(provider.instanceID) { enabledIDs.append(provider.instanceID) }
        }
        var entries = [WidgetSnapshot.ProviderEntry]()
        var seen = Set<UsageProvider>()
        for observation in observations {
            let presentation = observation.presentation
            guard let provider = presentation.provider, presentation.instanceID == provider.instanceID else { throw Failure.invalidProvider }
            guard enabledIDs.contains(provider.instanceID),
                  expectedAccountRevisions[provider] == observation.accountRevision else { continue }
            guard seen.insert(provider).inserted else { throw Failure.duplicateProvider }
            let usage = presentation.snapshot
            guard usage.updatedAt.timeIntervalSince1970.isFinite, usage.updatedAt.timeIntervalSince(now) <= 60 else { throw Failure.invalidDate }
            let extras = try codexExtras(observation: observation, now: now)
            // The shared snapshot has one quota/extras timestamp; preserve the oldest contributing observation.
            let entryUpdatedAt = extras.map { min(usage.updatedAt, $0.updatedAt) } ?? usage.updatedAt
            entries.append(.init(provider: provider, updatedAt: entryUpdatedAt,
                primary: try sanitized(usage.primary), secondary: try sanitized(usage.secondary),
                tertiary: try sanitized(usage.tertiary), usageRows: try providerUsageRows(provider: provider, usage: usage, now: now), creditsRemaining: extras?.creditsRemaining,
                codeReviewRemainingPercent: extras?.codeReviewRemainingPercent, tokenUsage: try tokenSummary(observation: observation, now: now), dailyUsage: try dailyUsage(observation: observation), providerCost: try devinCost(presentation: presentation, now: now), quotaOwnerKey: nil))
        }
        let quotaProviders = seen
        for observation in costOnly {
            let provider = observation.provider
            guard enabledIDs.contains(provider.instanceID), !quotaProviders.contains(provider),
                  expectedAccountRevisions[provider] == observation.cost.accountRevision else { continue }
            guard seen.insert(provider).inserted else { throw Failure.duplicateProvider }
            let summary = try tokenSummary(cost: observation.cost, now: now)
            guard let updatedAt = summary.updatedAt else { throw Failure.invalidDate }
            let history = try WindowsWidgetHistory.validatedDailyUsage(observation.cost.dailyUsage)
            entries.append(.init(provider: provider, updatedAt: updatedAt, primary: nil, secondary: nil, tertiary: nil,
                usageRows: [], creditsRemaining: nil, codeReviewRemainingPercent: nil,
                tokenUsage: summary, dailyUsage: history, providerCost: nil, quotaOwnerKey: nil))
        }
        return WidgetSnapshot(entries: entries, enabledProviders: enabledIDs, usageBarsShowUsed: showUsed, generatedAt: now)
    }

    private static func codexExtras(observation: Observation, now: Date) throws -> CodexExtras? {
        guard observation.presentation.provider == .codex, let extras = observation.codexExtras,
              extras.accountRevision == observation.accountRevision else { return nil }
        if case .displayOnly = extras.dashboardVisibility { return nil }
        let review: Double?
        if case .attached = extras.dashboardVisibility { review = extras.codeReviewRemainingPercent }
        else { review = nil }
        guard extras.creditsRemaining != nil || review != nil else { return nil }
        guard extras.updatedAt.timeIntervalSince1970.isFinite,
              extras.updatedAt.timeIntervalSince(now) <= 60 else { throw Failure.invalidDate }
        for value in [extras.creditsRemaining, review].compactMap({ $0 }) {
            guard value.isFinite else { throw Failure.invalidWindow }
        }
        return CodexExtras(accountRevision: extras.accountRevision, dashboardVisibility: extras.dashboardVisibility,
            creditsRemaining: extras.creditsRemaining, codeReviewRemainingPercent: review, updatedAt: extras.updatedAt)
    }

    private static func dailyUsage(observation: Observation) throws -> [WidgetSnapshot.DailyUsagePoint] {
        guard let cost = observation.tokenCost, cost.accountRevision == observation.accountRevision else { return [] }
        return try WindowsWidgetHistory.validatedDailyUsage(cost.dailyUsage)
    }

    private static func tokenSummary(observation: Observation, now: Date) throws -> WidgetSnapshot.TokenUsageSummary? {
        guard let cost = observation.tokenCost, cost.accountRevision == observation.accountRevision else { return nil }
        return try tokenSummary(cost: cost, now: now)
    }

    static func tokenSummary(cost: TokenCost, now: Date) throws -> WidgetSnapshot.TokenUsageSummary {
        let summary = cost.summary
        for amount in [summary.sessionCostUSD, summary.last30DaysCostUSD].compactMap({ $0 }) {
            guard amount.isFinite, amount >= 0 else { throw Failure.invalidCost }
        }
        for count in [summary.sessionTokens, summary.last30DaysTokens].compactMap({ $0 }) {
            guard count >= 0 else { throw Failure.invalidCost }
        }
        let currency = summary.currencyCode
        guard currency.utf8.count == 3, currency.utf8.allSatisfy({ (65...90).contains($0) }) else { throw Failure.invalidCost }
        for label in [summary.sessionLabel, summary.last30DaysLabel] {
            guard label.utf8.count <= 256,
                  !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw Failure.invalidCost }
        }
        // New publications require a cost observation time instead of inheriting a newer quota timestamp.
        guard let updatedAt = summary.updatedAt, updatedAt.timeIntervalSince1970.isFinite,
              updatedAt.timeIntervalSince(now) <= 60 else { throw Failure.invalidDate }
        return WidgetSnapshot.TokenUsageSummary(sessionCostUSD: summary.sessionCostUSD,
            sessionTokens: summary.sessionTokens, last30DaysCostUSD: summary.last30DaysCostUSD,
            last30DaysTokens: summary.last30DaysTokens, currencyCode: currency, sessionLabel: summary.sessionLabel,
            last30DaysLabel: summary.last30DaysLabel, updatedAt: updatedAt)
    }

    private static func devinCost(presentation: WindowsUsagePresentation, now: Date) throws -> ProviderCostSnapshot? {
        guard presentation.provider == .devin, presentation.showOptionalUsage,
              let cost = presentation.snapshot.providerCost, cost.period == "Extra usage balance" else { return nil }
        let currency = cost.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard cost.used.isFinite, cost.limit.isFinite, currency.utf8.count == 3,
              currency.utf8.allSatisfy({ (65...90).contains($0) }) else { throw Failure.invalidWindow }
        guard cost.updatedAt.timeIntervalSince1970.isFinite, cost.updatedAt.timeIntervalSince(now) <= 60,
              cost.resetsAt?.timeIntervalSince1970.isFinite ?? true else { throw Failure.invalidDate }
        // Copy only fields consumed by the widget balance projection; do not retain unrelated provider metadata.
        return ProviderCostSnapshot(used: cost.used, limit: cost.limit, currencyCode: currency,
            period: "Extra usage balance", resetsAt: cost.resetsAt, updatedAt: cost.updatedAt)
    }

    private static func providerUsageRows(provider: UsageProvider, usage: UsageSnapshot,
                                           now: Date) throws -> [WidgetSnapshot.WidgetUsageRowSnapshot]? {
        if provider == .codex { return try codexUsageRows(usage: usage) }
        guard provider == .antigravity else { return try claudeUsageRows(provider: provider, usage: usage, now: now) }
        let extras = usage.extraRateWindows ?? []
        guard extras.count <= 256 else { throw Failure.oversized }
        let idle = AntigravityQuotaFamilyVisibility.idleWindowIDs(in: usage)
        let summaries = extras.filter { $0.id.hasPrefix("antigravity-quota-summary-") && !idle.contains($0.id) }
        let selected = !summaries.isEmpty ? summaries : (usage.primary == nil && usage.secondary == nil
            ? extras.filter { $0.id.hasPrefix("antigravity-compact-fallback-") && $0.usageKnown } : [])
        guard !selected.isEmpty else { return nil }
        guard selected.count <= 64 else { throw Failure.oversized }
        var seen = Set<String>()
        return try selected.map { named in
            guard !named.id.isEmpty, named.id.utf8.count <= 256, named.title.utf8.count <= 1024,
                  !named.id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  !named.title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  seen.insert(named.id).inserted else { throw Failure.invalidWindow }
            let remaining: Double?
            if named.usageKnown {
                remaining = try sanitized(named.window)?.remainingPercent
            } else { remaining = nil }
            // Original summary rows omit windows; unknown usage must not become a synthetic percentage.
            return .init(id: named.id, title: named.title, percentLeft: remaining)
        }
    }

    private static func codexUsageRows(usage: UsageSnapshot) throws -> [WidgetSnapshot.WidgetUsageRowSnapshot] {
        let metadata = ProviderDescriptorRegistry.descriptor(for: .codex).metadata
        var order: [String] = []
        var windows: [String: RateWindow] = [:]
        for (candidate, fallback) in [(usage.primary, "session"), (usage.secondary, "weekly")] {
            guard let window = try sanitized(candidate) else { continue }
            let lane: String
            switch window.windowMinutes {
            case 300: lane = "session"
            case 10080: lane = "weekly"
            case 43200: lane = "monthly"
            default: lane = fallback
            }
            if !order.contains(lane) { order.append(lane) }
            // The original projection keeps the last slotted value for a repeated semantic lane.
            windows[lane] = window
        }
        return order.compactMap { lane in
            guard let window = windows[lane] else { return nil }
            let title = lane == "monthly" ? "Monthly" : (lane == "session" ? metadata.sessionLabel : metadata.weeklyLabel)
            return .init(id: lane, title: title, percentLeft: window.remainingPercent, window: window)
        }
    }

    private static func claudeUsageRows(provider: UsageProvider, usage: UsageSnapshot,
                                         now: Date) throws -> [WidgetSnapshot.WidgetUsageRowSnapshot]? {
        guard provider == .claude else { return nil }
        let policy = ProviderDescriptorRegistry.descriptor(for: .claude).presentation
        let resolution = policy.menuBarWindow(context: ProviderMenuBarWindowContext(metric: .automatic,
            snapshot: usage, supportsAverage: false, prioritizesExhaustedQuotas: false, now: now))
        guard case let .resolved(candidate) = resolution, let window = try sanitized(candidate) else { return nil }
        if let cost = usage.providerCost, !cost.used.isFinite || !cost.limit.isFinite { throw Failure.invalidWindow }
        let period = usage.providerCost?.period?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        if let period, !period.isEmpty, period.utf8.count <= 256,
           !period.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            title = period
        } else { title = "Extra usage" }
        return [.init(id: "extraUsage", title: title, percentLeft: window.remainingPercent, window: window)]
    }

    private static func sanitized(_ window: RateWindow?) throws -> RateWindow? {
        guard let window else { return nil }
        guard window.usedPercent.isFinite, window.resetsAt?.timeIntervalSince1970.isFinite ?? true,
              window.nextRegenPercent?.isFinite ?? true else { throw Failure.invalidWindow }
        if let minutes = window.windowMinutes, minutes <= 0 { throw Failure.invalidWindow }
        // Free-form source descriptions are not part of the cross-process quota contract.
        return RateWindow(usedPercent: window.usedPercent, windowMinutes: window.windowMinutes,
            resetsAt: window.resetsAt, resetDescription: nil, nextRegenPercent: window.nextRegenPercent)
    }
}
#endif
