#if os(Windows)
import CodexBarCore
import Foundation

/// One successful provider response, retained only inside its runtime refresh generation.
/// A new response always gets a new revision, even when its timestamp or totals are unchanged.
struct WindowsSpendProviderProjection: Sendable, Equatable {
    private enum Payload: Sendable {
        case mistral(MistralUsageSnapshot)
        case openCodeGo(OpenCodeGoUsageSnapshot)
        case native(CostUsageTokenSnapshot)
    }

    enum Failure: Error { case noLocalHistory }

    let provider: UsageProvider
    let revision = UUID()
    /// Only Mistral billing and quota from the same authenticated response may share this revision.
    /// OpenCode Go daily rows are device-local and cannot prove the quota account's ownership.
    let confirmedQuotaAccountRevision: UUID?
    private let payload: Payload

    static func supports(_ provider: UsageProvider) -> Bool {
        switch provider {
        case .mistral, .opencodego, .openai, .openrouter, .xai, .grok: true
        default: false
        }
    }

    init?(provider: UsageProvider, usage: UsageSnapshot, confirmedQuotaAccountRevision: UUID? = nil) {
        self.provider = provider
        self.confirmedQuotaAccountRevision = provider == .mistral ? confirmedQuotaAccountRevision : nil
        switch provider {
        case .mistral:
            guard let usage = usage.mistralUsage else { return nil }
            self.payload = .mistral(usage)
        case .opencodego:
            guard let usage = usage.opencodegoUsage else { return nil }
            self.payload = .openCodeGo(usage)
        case .openai:
            guard let usage = usage.openAIAPIUsage else { return nil }
            self.payload = .native(usage.toCostUsageTokenSnapshot())
        case .openrouter, .grok:
            // The provider owns the cost semantics. Grok contributes local tokens only;
            // OpenRouter publishes its own metered history. Never derive spend from quota.
            guard let cost = usage.costUsage else { return nil }
            self.payload = .native(cost)
        case .xai:
            guard let cost = XAICostUsageMapping.tokenSnapshot(
                from: usage, historyDays: WindowsSpendHistoryPolicy.scanDays) else { return nil }
            self.payload = .native(cost)
        default:
            return nil
        }
    }

    /// Mirrors the explicit session selection used by MistralWebFetchStrategy. No cookie is retained.
    /// Automatic imports need their own winning-credential evidence before they can use this path.
    static func mistralWidgetOwner(settings: MistralProviderSettings?, strategy: ProviderFetchKind?) -> String? {
        guard strategy == .web, let settings, settings.cookieSource == .manual,
              let header = CookieHeaderNormalizer.normalize(settings.manualCookieHeader),
              CookieHeaderNormalizer.pairs(from: header).contains(where: {
                  $0.name.hasPrefix("ory_session_") && !$0.value.isEmpty
              }) else { return nil }
        return "mistral-session:" + CookieHeaderCache.credentialFingerprint(header)
    }

    func confirmsWidgetRevision(_ revision: UUID, provider: UsageProvider) -> Bool {
        provider == .mistral && self.provider == provider && self.confirmedQuotaAccountRevision == revision
    }

    func snapshot(historyDays: Int) throws -> CostUsageTokenSnapshot {
        let days = max(1, min(WindowsSpendHistoryPolicy.scanDays, historyDays))
        switch self.payload {
        case let .mistral(usage):
            // Preserve billing currency, coverage, unknown values and vendor-reported provenance.
            return usage.toCostUsageTokenSnapshot(historyDays: days)
        case let .openCodeGo(usage):
            // Web/API quota or a prepaid balance alone is not local token/cost history.
            guard !usage.daily.isEmpty else { throw Failure.noLocalHistory }
            return usage.toCostUsageTokenSnapshot(historyDays: days)
        case let .native(snapshot):
            // Preserve the observed window/coverage. Requesting a year from the spend UI
            // cannot promote a provider's 30-day response into a complete year.
            return snapshot
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.provider == rhs.provider && lhs.revision == rhs.revision
    }
}
#endif
