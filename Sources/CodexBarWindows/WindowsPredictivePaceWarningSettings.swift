#if os(Windows)
import Foundation

/// Windows persistence for predictive pace warning preferences.
public struct WindowsPredictivePaceWarningSettings: Sendable, Equatable {
    public let notificationsEnabled: Bool
    public let weeklyProgressWorkDays: Int?
    public let historicalTrackingEnabled: Bool

    public init(
        notificationsEnabled: Bool = false,
        weeklyProgressWorkDays: Int? = nil,
        historicalTrackingEnabled: Bool = false)
    {
        self.notificationsEnabled = notificationsEnabled
        self.weeklyProgressWorkDays = weeklyProgressWorkDays
        self.historicalTrackingEnabled = historicalTrackingEnabled
    }

    public static func load(userDefaults: UserDefaults? = nil) -> Self {
        let defaults = userDefaults ?? UserDefaults(suiteName: WindowsRefreshSettings.suiteName) ?? .standard
        return Self(
            notificationsEnabled: defaults.object(forKey: "predictivePaceWarningNotificationsEnabled") as? Bool
                ?? false,
            weeklyProgressWorkDays: defaults.object(forKey: "weeklyProgressWorkDays") as? Int,
            historicalTrackingEnabled: defaults.object(forKey: "historicalTrackingEnabled") as? Bool ?? false)
    }
}
#endif
