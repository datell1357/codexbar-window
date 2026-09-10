#if os(Windows)
import CodexBarCore
import Foundation

/// The quota-warning preferences used by the Windows side of CodexBar.
///
/// This is a value snapshot: loading it never writes defaults back to the
/// defaults store, and provider resolution returns another independent value.
/// Delivery (including sound and on-screen overlays) is intentionally outside
/// this settings contract.
public struct WindowsQuotaWarningSettings: Sendable, Equatable {
    public static let defaultThresholds = QuotaWarningThresholds.defaults

    public let notificationsEnabled: Bool
    public let sessionThresholds: [Int]
    public let weeklyThresholds: [Int]
    public let sessionEnabled: Bool
    public let weeklyEnabled: Bool

    public init(
        notificationsEnabled: Bool = false,
        sessionThresholds: [Int] = QuotaWarningThresholds.defaults,
        weeklyThresholds: [Int] = QuotaWarningThresholds.defaults,
        sessionEnabled: Bool = true,
        weeklyEnabled: Bool = true)
    {
        self.notificationsEnabled = notificationsEnabled
        self.sessionThresholds = QuotaWarningThresholds.sanitized(sessionThresholds)
        self.weeklyThresholds = QuotaWarningThresholds.sanitized(weeklyThresholds)
        self.sessionEnabled = sessionEnabled
        self.weeklyEnabled = weeklyEnabled
    }

    /// Loads the Windows-only defaults keys used by the source SettingsStore.
    /// Per-window values fall back to the legacy shared threshold key, then to
    /// the Core defaults. Invalid and empty arrays are normalized by Core.
    public static func load(userDefaults: UserDefaults? = nil) -> Self {
        let defaults = userDefaults ?? UserDefaults(suiteName: WindowsRefreshSettings.suiteName) ?? .standard
        let shared = QuotaWarningThresholds.sanitized(
            defaults.array(forKey: "quotaWarningThresholds") as? [Int] ?? QuotaWarningThresholds.defaults)
        let session = QuotaWarningThresholds.sanitized(
            defaults.array(forKey: "quotaWarningSessionThresholds") as? [Int] ?? shared)
        let weekly = QuotaWarningThresholds.sanitized(
            defaults.array(forKey: "quotaWarningWeeklyThresholds") as? [Int] ?? shared)
        return Self(
            notificationsEnabled: defaults.object(forKey: "quotaWarningNotificationsEnabled") as? Bool ?? false,
            sessionThresholds: session,
            weeklyThresholds: weekly,
            sessionEnabled: defaults.object(forKey: "quotaWarningSessionEnabled") as? Bool ?? true,
            weeklyEnabled: defaults.object(forKey: "quotaWarningWeeklyEnabled") as? Bool ?? true)
    }

    public func thresholds(for window: QuotaWarningWindow) -> [Int] {
        switch window {
        case .session: self.sessionThresholds
        case .weekly: self.weeklyThresholds
        }
    }

    public func isEnabled(for window: QuotaWarningWindow) -> Bool {
        switch window {
        case .session: self.sessionEnabled
        case .weekly: self.weeklyEnabled
        }
    }

    /// Applies the provider's Core quota-warning overrides to this snapshot.
    /// Core owns sanitization and the rule that an explicit threshold enables a
    /// lane when its enabled flag is absent.
    public func resolved(providerConfig: ProviderConfig) -> Self {
        guard let config = providerConfig.quotaWarnings else { return self }
        return Self(
            notificationsEnabled: self.notificationsEnabled,
            sessionThresholds: config.thresholds(for: .session, global: self.sessionThresholds),
            weeklyThresholds: config.thresholds(for: .weekly, global: self.weeklyThresholds),
            sessionEnabled: config.isEnabled(for: .session, global: self.sessionEnabled),
            weeklyEnabled: config.isEnabled(for: .weekly, global: self.weeklyEnabled))
    }
}
#endif
