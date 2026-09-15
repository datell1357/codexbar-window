#if os(Windows)
import CodexBarCore
import Foundation

/// Semantic predictive warning delivered to the Windows notification adapter.
/// Formatting and privacy redaction remain owned by the host UI layer.
public struct WindowsPredictivePaceWarningNotification: Sendable {
    public let providerID: ProviderInstanceID?
    public let providerName: String
    public let window: QuotaWarningWindow
    public let etaSeconds: TimeInterval
    public let accountDisplayName: String?
    public let estimatedExhaustionAt: Date
    public let isCurrent: @Sendable () -> Bool

    public init(
        providerName: String,
        window: QuotaWarningWindow,
        etaSeconds: TimeInterval,
        accountDisplayName: String? = nil,
        providerID: ProviderInstanceID? = nil,
        observedAt: Date = Date(),
        isCurrent: @escaping @Sendable () -> Bool = { true })
    {
        self.providerID = providerID
        self.estimatedExhaustionAt = observedAt.addingTimeInterval(etaSeconds)
        self.isCurrent = isCurrent
        self.providerName = providerName
        self.window = window
        self.etaSeconds = etaSeconds
        self.accountDisplayName = accountDisplayName
    }

    public func isDeliverable(now: Date = Date()) -> Bool {
        self.isCurrent() && self.etaSeconds.isFinite && self.etaSeconds > 0
            && self.estimatedExhaustionAt.timeIntervalSince1970.isFinite && now < self.estimatedExhaustionAt
    }

    /// Produces the same semantic copy as the macOS notification path. Windows
    /// keeps formatting here so both the balloon and the optional overlay share
    /// one privacy decision and countdown representation.
    public func copy(hidePersonalInfo: Bool, now: Date = .init()) -> (title: String, body: String) {
        let label = self.window.displayName
        let title = "\(self.providerName) \(label) pace warning"
        let target = self.estimatedExhaustionAt.timeIntervalSince1970.isFinite
            ? max(now, self.estimatedExhaustionAt) : now
        let countdown = UsageFormatter.resetCountdownDescription(from: target, now: now)
        let duration = countdown.hasPrefix("in ") ? String(countdown.dropFirst(3)) : countdown
        let account = self.accountDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if hidePersonalInfo || account?.isEmpty != false {
            return (
                title,
                "At the current pace, this quota may run out in \(duration), before it resets.")
        }
        return (
            title,
            "Account \(account!). At the current pace, this quota may run out in \(duration), before it resets.")
    }
}
#endif
