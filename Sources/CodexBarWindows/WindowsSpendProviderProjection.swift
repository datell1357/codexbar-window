#if os(Windows)
import CodexBarCore
import Foundation

/// One successful provider response, retained only inside its runtime refresh generation.
/// A new response always gets a new revision, even when its timestamp or totals are unchanged.
struct WindowsSpendProviderProjection: Sendable, Equatable {
    private enum Payload: Sendable {
        case mistral(MistralUsageSnapshot)
        case openCodeGo(OpenCodeGoUsageSnapshot)
    }

    enum Failure: Error { case noLocalHistory }

    let provider: UsageProvider
    let revision = UUID()
    private let payload: Payload

    static func supports(_ provider: UsageProvider) -> Bool {
        provider == .mistral || provider == .opencodego
    }

    init?(provider: UsageProvider, usage: UsageSnapshot) {
        self.provider = provider
        switch provider {
        case .mistral:
            guard let usage = usage.mistralUsage else { return nil }
            self.payload = .mistral(usage)
        case .opencodego:
            guard let usage = usage.opencodegoUsage else { return nil }
            self.payload = .openCodeGo(usage)
        default:
            return nil
        }
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
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.provider == rhs.provider && lhs.revision == rhs.revision
    }
}
#endif
