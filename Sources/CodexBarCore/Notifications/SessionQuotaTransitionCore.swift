import Foundation

/// Platform-neutral session quota transition state machine.
///
/// Windows integration should map its credential/session identity to `codexOwnerKey`, persist the
/// returned `State`, and deliver `Evaluation.outcome` through the native notification layer. This
/// file intentionally has no persistence, timers, UI, or OS notification dependencies.
public enum SessionQuotaTransitionCore {
    public enum Transition: Equatable, Sendable {
        case none
        case depleted
        case restored
    }

    public enum WindowSource: String, Equatable, Sendable {
        case primary
        case copilotSecondaryFallback
        case antigravityQuotaSummary
        case antigravityLegacy
    }

    public struct State: Equatable, Sendable {
        public let remaining: Double
        public let source: WindowSource
        public let observedAt: Date
        /// Stable, provider-scoped owner identity. The app's opaque owner-key type is deliberately
        /// not part of Core so Windows can use Credential Manager/DPAPI-derived identifiers.
        public let codexOwnerKey: String?
        public let trustedResetBoundary: Date?
        public let pendingCodexRestoreObservationAt: Date?

        public init(
            remaining: Double,
            source: WindowSource,
            observedAt: Date,
            codexOwnerKey: String?,
            trustedResetBoundary: Date?,
            pendingCodexRestoreObservationAt: Date?)
        {
            self.remaining = remaining
            self.source = source
            self.observedAt = observedAt
            self.codexOwnerKey = codexOwnerKey
            self.trustedResetBoundary = trustedResetBoundary
            self.pendingCodexRestoreObservationAt = pendingCodexRestoreObservationAt
        }

        public func advancingObservationWatermark(to observedAt: Date) -> Self {
            guard observedAt > self.observedAt else { return self }
            return Self(
                remaining: self.remaining,
                source: self.source,
                observedAt: observedAt,
                codexOwnerKey: self.codexOwnerKey,
                trustedResetBoundary: self.trustedResetBoundary,
                pendingCodexRestoreObservationAt: self.pendingCodexRestoreObservationAt)
        }
    }

    public struct Observation: Equatable, Sendable {
        public let provider: UsageProvider
        public let remaining: Double
        public let source: WindowSource
        public let resetBoundary: Date?
        public let observedAt: Date
        public let evaluationTime: Date
        public let codexOwnerKey: String?

        public init(
            provider: UsageProvider,
            remaining: Double,
            source: WindowSource,
            resetBoundary: Date?,
            observedAt: Date,
            evaluationTime: Date,
            codexOwnerKey: String?)
        {
            self.provider = provider
            self.remaining = remaining
            self.source = source
            self.resetBoundary = resetBoundary
            self.observedAt = observedAt
            self.evaluationTime = evaluationTime
            self.codexOwnerKey = codexOwnerKey
        }
    }

    public enum Outcome: Equatable, Sendable {
        case none
        case depleted
        case restored
        case baselineChanged
        case staleCodexObservation
        case suppressedCodexRestore
        case awaitingCodexRestoreConfirmation

        public var transition: Transition {
            switch self {
            case .depleted: .depleted
            case .restored: .restored
            default: .none
            }
        }
    }

    public struct Evaluation: Equatable, Sendable {
        public let outcome: Outcome
        public let state: State

        public init(outcome: Outcome, state: State) {
            self.outcome = outcome
            self.state = state
        }
    }

    public static let depletedThreshold = 0.0001

    public static func isDepleted(_ remaining: Double?) -> Bool {
        guard let remaining else { return false }
        return remaining <= self.depletedThreshold
    }

    public static func transition(previousRemaining: Double?, currentRemaining: Double?) -> Transition {
        guard let previousRemaining, let currentRemaining else { return .none }
        let wasDepleted = self.isDepleted(previousRemaining)
        let isDepleted = self.isDepleted(currentRemaining)
        if !wasDepleted, isDepleted { return .depleted }
        if wasDepleted, !isDepleted { return .restored }
        return .none
    }

    public static func evaluate(
        previous: State?,
        observation: Observation,
        notificationsEnabled: Bool,
        forceBaseline: Bool = false) -> Evaluation
    {
        if forceBaseline {
            return Evaluation(outcome: .baselineChanged, state: self.baselineState(observation: observation))
        }
        guard let previous else {
            let outcome: Outcome = notificationsEnabled && self.isDepleted(observation.remaining) ? .depleted : .none
            return Evaluation(outcome: outcome, state: self.baselineState(observation: observation))
        }

        let ownerChanged = observation.provider == .codex && previous.codexOwnerKey != observation.codexOwnerKey
        guard previous.source == observation.source, !ownerChanged else {
            return Evaluation(outcome: .baselineChanged, state: self.baselineState(observation: observation))
        }
        if observation.provider == .codex, observation.observedAt <= previous.observedAt {
            return Evaluation(outcome: .staleCodexObservation, state: previous)
        }
        guard notificationsEnabled else {
            return Evaluation(outcome: .none, state: self.updatedState(previous: previous, observation: observation))
        }

        let transition = self.transition(previousRemaining: previous.remaining, currentRemaining: observation.remaining)
        if transition != .restored || observation.provider != .codex {
            let outcome: Outcome = switch transition {
            case .none: .none
            case .depleted: .depleted
            case .restored: .restored
            }
            let preserveBoundary = observation.provider == .codex &&
                previous.trustedResetBoundary != nil &&
                self.isDepleted(previous.remaining) && self.isDepleted(observation.remaining)
            let preserveCodexBoundary = preserveBoundary ||
                (observation.provider == .codex && previous.trustedResetBoundary.map {
                    observation.evaluationTime < $0 || observation.observedAt < $0
                } == true)
            return Evaluation(
                outcome: outcome,
                state: self.updatedState(
                    previous: previous,
                    observation: observation,
                    preserveCodexResetBoundary: preserveCodexBoundary))
        }

        if let trustedResetBoundary = previous.trustedResetBoundary {
            guard observation.evaluationTime >= trustedResetBoundary,
                  observation.observedAt >= trustedResetBoundary
            else {
                return Evaluation(
                    outcome: .suppressedCodexRestore,
                    state: self.preservedDepletedState(previous: previous, observation: observation))
            }
            if let resetBoundary = self.validResetBoundary(
                observation.resetBoundary,
                observedAt: observation.observedAt,
                evaluationTime: observation.evaluationTime),
               !self.equivalentResetBoundaries(trustedResetBoundary, resetBoundary),
               resetBoundary > trustedResetBoundary
            {
                return Evaluation(
                    outcome: .restored,
                    state: self.updatedState(previous: previous, observation: observation))
            }
        }

        if let pending = previous.pendingCodexRestoreObservationAt, observation.observedAt > pending {
            return Evaluation(
                outcome: .restored,
                state: self.updatedState(previous: previous, observation: observation))
        }
        return Evaluation(
            outcome: .awaitingCodexRestoreConfirmation,
            state: self.preservedDepletedState(
                previous: previous,
                observation: observation,
                pendingRestoreObservationAt: observation.observedAt))
    }

    /// Selects the same session lanes as the macOS implementation. Windows callers provide the
    /// resulting window/source to `Observation`; this helper keeps provider-specific lane semantics in Core.
    public static func sessionWindow(
        provider: UsageProvider,
        snapshot: UsageSnapshot) -> (window: RateWindow, source: WindowSource)?
    {
        guard provider != .mimo, provider != .qoder else { return nil }
        if provider == .antigravity {
            guard let window = self.antigravityWindow(snapshot: snapshot, windowMinutes: 5 * 60) else { return nil }
            let source: WindowSource = self.hasAntigravityQuotaSummaryWindows(snapshot: snapshot)
                ? .antigravityQuotaSummary
                : .antigravityLegacy
            return (window, source)
        }
        if let primary = snapshot.primary, self.isSessionWindow(primary) {
            if provider == .crof, snapshot.secondary == nil { return nil }
            return (primary, .primary)
        }
        if provider == .copilot, let secondary = snapshot.secondary {
            return (secondary, .copilotSecondaryFallback)
        }
        return nil
    }

    private static func baselineState(observation: Observation) -> State {
        State(
            remaining: observation.remaining,
            source: observation.source,
            observedAt: observation.observedAt,
            codexOwnerKey: observation.provider == .codex ? observation.codexOwnerKey : nil,
            trustedResetBoundary: observation.provider == .codex
                ? self.validResetBoundary(
                    observation.resetBoundary,
                    observedAt: observation.observedAt,
                    evaluationTime: observation.evaluationTime)
                : nil,
            pendingCodexRestoreObservationAt: nil)
    }

    private static func updatedState(
        previous: State,
        observation: Observation,
        preserveCodexResetBoundary: Bool = false) -> State {
        let boundary: Date? = if observation.provider != .codex {
            nil
        } else if preserveCodexResetBoundary {
            previous.trustedResetBoundary
        } else {
            self.monotonicResetBoundary(
                previous: previous.trustedResetBoundary,
                current: self.validResetBoundary(
                    observation.resetBoundary,
                    observedAt: observation.observedAt,
                    evaluationTime: observation.evaluationTime))
        }
        return State(
            remaining: observation.remaining,
            source: observation.source,
            observedAt: observation.observedAt,
            codexOwnerKey: observation.provider == .codex ? observation.codexOwnerKey : nil,
            trustedResetBoundary: boundary,
            pendingCodexRestoreObservationAt: nil)
    }

    private static func preservedDepletedState(
        previous: State,
        observation: Observation,
        pendingRestoreObservationAt: Date? = nil) -> State {
        State(
            remaining: previous.remaining,
            source: observation.source,
            observedAt: observation.observedAt,
            codexOwnerKey: observation.codexOwnerKey,
            trustedResetBoundary: previous.trustedResetBoundary,
            pendingCodexRestoreObservationAt: pendingRestoreObservationAt)
    }

    private static func monotonicResetBoundary(previous: Date?, current: Date?) -> Date? {
        guard let previous else { return current }
        return self.resetBoundaryAdvanced(previous: previous, current: current) ? current : previous
    }

    private static func resetBoundaryAdvanced(previous: Date, current: Date?) -> Bool {
        guard let current else { return false }
        return !self.equivalentResetBoundaries(previous, current) && current > previous
    }

    private static func equivalentResetBoundaries(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return false }
        return abs(lhs.timeIntervalSince(rhs)) < 2 * 60
    }

    private static func validResetBoundary(_ candidate: Date?, observedAt: Date, evaluationTime: Date) -> Date? {
        guard let candidate, candidate > observedAt, candidate > evaluationTime else { return nil }
        return candidate
    }

    private static func isSessionWindow(_ window: RateWindow) -> Bool {
        guard let minutes = window.windowMinutes else { return true }
        return minutes <= 6 * 60
    }

    private static let antigravityQuotaSummaryWindowIDPrefix = "antigravity-quota-summary-"

    private static func hasAntigravityQuotaSummaryWindows(snapshot: UsageSnapshot) -> Bool {
        snapshot.extraRateWindows?.contains { $0.id.hasPrefix(self.antigravityQuotaSummaryWindowIDPrefix) } == true
    }

    private static func antigravityWindow(snapshot: UsageSnapshot, windowMinutes: Int) -> RateWindow? {
        let windows: [RateWindow] = if self.hasAntigravityQuotaSummaryWindows(snapshot: snapshot) {
            snapshot.extraRateWindows?.filter {
                $0.usageKnown
                    && $0.id.hasPrefix(self.antigravityQuotaSummaryWindowIDPrefix)
                    && $0.window.windowMinutes == windowMinutes
            }.map(\.window) ?? []
        } else {
            [snapshot.primary, snapshot.secondary, snapshot.tertiary].compactMap(\.self).filter {
                $0.windowMinutes == windowMinutes || (windowMinutes == 5 * 60 && $0.windowMinutes == nil)
            }
        }
        return windows.max { $0.usedPercent < $1.usedPercent }
    }
}
