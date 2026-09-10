import Foundation

/// Platform-neutral quota warning state machine and lane selector.
///
/// Callers own persistence and notification delivery. Missing ordinary windows clear the exact
/// key; synthetic placeholders preserve their state because they are not authoritative samples.
public enum QuotaWarningTransitionCore {
    public struct Key: Hashable, Sendable {
        public let provider: UsageProvider
        public let lane: QuotaWarningWindow
        public let accountDiscriminator: String?
        public let windowID: String?

        public init(provider: UsageProvider, lane: QuotaWarningWindow, accountDiscriminator: String? = nil,
                    windowID: String? = nil)
        {
            self.provider = provider
            self.lane = lane
            self.accountDiscriminator = accountDiscriminator
            self.windowID = windowID
        }
    }

    public enum Source: String, Equatable, Sendable {
        case primary
        case antigravityQuotaSummary
        case antigravityLegacy
    }

    public struct State: Equatable, Sendable {
        public var lastRemaining: Double?
        public var firedThresholds: Set<Int>
        public var source: Source?

        public init(lastRemaining: Double? = nil, firedThresholds: Set<Int> = [], source: Source? = nil) {
            self.lastRemaining = lastRemaining
            self.firedThresholds = firedThresholds
            self.source = source
        }
    }

    public enum Outcome: Equatable, Sendable {
        case none
        case warning(threshold: Int)
        case baselineChanged
    }

    public struct Evaluation: Equatable, Sendable {
        public let outcome: Outcome
        public let state: State?

        public init(outcome: Outcome, state: State?) {
            self.outcome = outcome
            self.state = state
        }
    }

    public struct Candidate: Equatable, Sendable {
        public let key: Key
        public let window: RateWindow
        public let source: Source?
        public let displayLabel: String?

        public init(key: Key, window: RateWindow, source: Source? = nil, displayLabel: String? = nil) {
            self.key = key
            self.window = window
            self.source = source
            self.displayLabel = displayLabel
        }
    }

    public struct Reconciliation: Equatable, Sendable {
        /// Extras are authoritative only when at least one recognized, usage-known extra exists.
        public let authoritative: Bool
        public let recognizedExtraWindowIDs: Set<String>

        public init(authoritative: Bool, recognizedExtraWindowIDs: Set<String>) {
            self.authoritative = authoritative
            self.recognizedExtraWindowIDs = recognizedExtraWindowIDs
        }
    }

    public struct CandidateSelection: Equatable, Sendable {
        /// If a primary or secondary lane is absent, the caller clears that exact key. Missing
        /// extras are intentionally non-authoritative and preserve their existing state.
        public let candidates: [Candidate]
        public let reconciliation: Reconciliation

        public init(candidates: [Candidate], reconciliation: Reconciliation) {
            self.candidates = candidates
            self.reconciliation = reconciliation
        }
    }

    /// A disabled lane returns `state == nil`; callers should clear every key for that provider/lane
    /// (including account and extra-window variants). A globally disabled warning path should skip this
    /// reducer and preserve persisted state until the lane is explicitly cleared.
    public static func evaluate(
        previous: State?,
        current: RateWindow?,
        source: Source? = nil,
        thresholds: [Int],
        enabled: Bool = true) -> Evaluation
    {
        guard enabled else { return Evaluation(outcome: .none, state: nil) }
        guard let current else { return Evaluation(outcome: .none, state: nil) }
        guard !current.isSyntheticPlaceholder else { return Evaluation(outcome: .none, state: previous) }
        let active = QuotaWarningThresholds.active(thresholds)
        guard let previous else {
            let candidate = active.filter { current.remainingPercent <= Double($0) }.min()
            let fired = candidate.map { selected in Set(active.filter { $0 >= selected }) } ?? []
            return Evaluation(outcome: candidate.map { .warning(threshold: $0) } ?? .none,
                state: State(lastRemaining: current.remainingPercent, firedThresholds: fired, source: source))
        }
        guard previous.source == source else {
            return Evaluation(outcome: .baselineChanged,
                              state: State(lastRemaining: current.remainingPercent, source: source))
        }
        var state = previous
        state.firedThresholds.subtract(previous.firedThresholds.filter { current.remainingPercent > Double($0) })
        let eligible = active.filter { current.remainingPercent <= Double($0) && !state.firedThresholds.contains($0) }
        let crossed = eligible.filter { threshold in
            previous.lastRemaining.map { $0 > Double(threshold) } ?? true
        }.min()
        if let crossed {
            state.firedThresholds.formUnion(active.filter { $0 >= crossed })
            state.lastRemaining = current.remainingPercent
            return Evaluation(outcome: .warning(threshold: crossed), state: state)
        }
        state.lastRemaining = current.remainingPercent
        return Evaluation(outcome: .none, state: state)
    }

    /// Selects notification lanes without the session-transition six-hour/Copilot fallback semantics.
    public static func candidates(provider: UsageProvider, snapshot: UsageSnapshot,
                                  accountDiscriminator: String? = nil) -> CandidateSelection
    {
        if provider == .mimo || provider == .qoder || (provider == .crof && snapshot.secondary == nil) {
            return CandidateSelection(
                candidates: [],
                reconciliation: Reconciliation(authoritative: false, recognizedExtraWindowIDs: []))
        }
        var result: [Candidate] = []
        if provider == .antigravity {
            let hasSummary = snapshot.extraRateWindows?.contains {
                $0.id.hasPrefix("antigravity-quota-summary-")
            } == true
            let summary = snapshot.extraRateWindows?.filter {
                $0.usageKnown && $0.id.hasPrefix("antigravity-quota-summary-")
            } ?? []
            let source: Source = hasSummary ? .antigravityQuotaSummary : .antigravityLegacy
            let legacyWindows = [snapshot.primary, snapshot.secondary, snapshot.tertiary].compactMap { $0 }
            let primary = hasSummary
                ? summary
                    .filter { $0.window.windowMinutes == 5 * 60 }
                    .max { $0.window.usedPercent < $1.window.usedPercent }?.window
                : legacyWindows.filter { $0.windowMinutes == 5 * 60 || $0.windowMinutes == nil }
                    .max { $0.usedPercent < $1.usedPercent }
            let weekly = hasSummary
                ? summary
                    .filter { $0.window.windowMinutes == 7 * 24 * 60 }
                    .max { $0.window.usedPercent < $1.window.usedPercent }?.window
                : legacyWindows.filter { $0.windowMinutes == 7 * 24 * 60 }
                    .max { $0.usedPercent < $1.usedPercent }
            if let primary {
                result.append(Candidate(
                    key: Key(provider: provider, lane: .session, accountDiscriminator: accountDiscriminator),
                    window: primary,
                    source: source))
            }
            if let weekly {
                result.append(Candidate(
                    key: Key(provider: provider, lane: .weekly, accountDiscriminator: accountDiscriminator),
                    window: weekly,
                    source: source))
            }
        } else {
            if let primary = snapshot.primary {
                result.append(Candidate(
                    key: Key(provider: provider, lane: .session, accountDiscriminator: accountDiscriminator),
                    window: primary,
                    displayLabel: provider == .amp ? AmpProviderDescriptor.primaryLabel(snapshot: snapshot) : nil))
            }
            if let secondary = snapshot.secondary {
                result.append(Candidate(
                    key: Key(provider: provider, lane: .weekly, accountDiscriminator: accountDiscriminator),
                    window: secondary,
                    displayLabel: provider == .amp ? AmpProviderDescriptor.secondaryLabel(snapshot: snapshot) : nil))
            }
        }
        let recognized = provider == .claude ? (snapshot.extraRateWindows ?? []).filter {
            $0.usageKnown && ($0.id.hasPrefix("claude-weekly-scoped-") || $0.id == "claude-routines")
        } : []
        result += recognized.map {
            Candidate(
                key: Key(
                    provider: provider,
                    lane: .weekly,
                    accountDiscriminator: accountDiscriminator,
                    windowID: $0.id),
                window: $0.window,
                displayLabel: $0.title)
        }
        return CandidateSelection(candidates: result, reconciliation: Reconciliation(authoritative: !recognized.isEmpty,
            recognizedExtraWindowIDs: Set(recognized.map(\.id))))
    }

}
