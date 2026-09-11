import Foundation

/// Platform-neutral state transitions for predictive pace warnings.
///
/// Callers own persistence and notification delivery. A notification is emitted once per
/// provider/account/window reset cycle; reset-time corrections migrate the recorded key without
/// re-alerting.
public enum PredictivePaceWarningTransitionCore {
    public struct ResetWindow: Hashable, Sendable {
        public let windowMinutes: Int?
        public let resetsAt: Date

        public init(windowMinutes: Int?, resetsAt: Date) {
            self.windowMinutes = windowMinutes
            self.resetsAt = resetsAt
        }

        /// Returns true when both reset observations belong to the same quota cycle.
        public func belongsToSameCycle(as other: Self) -> Bool {
            guard self.windowMinutes == other.windowMinutes else { return false }
            let tolerance = self.windowMinutes.map { max(TimeInterval($0) * 60 / 2, 300) } ?? 300
            return abs(self.resetsAt.timeIntervalSince(other.resetsAt)) < tolerance
        }
    }

    public struct Key: Hashable, Sendable {
        public let provider: UsageProvider
        public let accountDiscriminator: String
        public let window: QuotaWarningWindow
        public let resetWindow: ResetWindow

        public init(
            provider: UsageProvider,
            accountDiscriminator: String,
            window: QuotaWarningWindow,
            resetWindow: ResetWindow)
        {
            self.provider = provider
            self.accountDiscriminator = accountDiscriminator
            self.window = window
            self.resetWindow = resetWindow
        }
    }

    /// Returns true when pace predicts exhaustion before the quota resets.
    public static func shouldNotify(pace: UsagePace) -> Bool {
        guard !pace.willLastToReset else { return false }
        guard let etaSeconds = pace.etaSeconds, etaSeconds > 0 else { return false }
        guard (pace.runOutProbability ?? 1) >= 0.5 else { return false }
        return true
    }

    /// Records one warning and returns true only when the caller should deliver it.
    public static func recordObservation(
        key: Key,
        pace: UsagePace,
        notifiedKeys: inout Set<Key>) -> Bool
    {
        if pace.willLastToReset {
            notifiedKeys.remove(key)
            return false
        }

        guard self.shouldNotify(pace: pace) else { return false }
        guard !notifiedKeys.contains(key) else { return false }
        notifiedKeys.insert(key)
        return true
    }

    /// Replaces sibling reset-time keys with the active observation while preserving cycle state.
    public static func reconcileSiblingWindowKeys(
        activeKey: Key,
        notifiedKeys: inout Set<Key>)
    {
        let siblingKeys = notifiedKeys.filter { key in
            key.provider == activeKey.provider &&
                key.accountDiscriminator == activeKey.accountDiscriminator &&
                key.window == activeKey.window
        }
        guard !siblingKeys.isEmpty else { return }

        let alreadyWarnedThisCycle = siblingKeys.contains { key in
            key.resetWindow.belongsToSameCycle(as: activeKey.resetWindow)
        }
        notifiedKeys.subtract(siblingKeys)
        if alreadyWarnedThisCycle {
            notifiedKeys.insert(activeKey)
        }
    }
}
