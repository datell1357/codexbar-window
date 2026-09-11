#if os(Windows)
import Foundation

/// Windows persistence for predictive pace warning preferences.
public struct WindowsPredictivePaceWarningSettings: Sendable, Equatable {
    /// Matches the macOS `MenuSettingsMenuOptions.weeklyProgressWorkDays` choices.
    public static let weeklyProgressWorkDayOptions: [Int?] = [nil, 4, 5, 7]
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

    public static func weeklyProgressWorkDaysLabel(_ workDays: Int?) -> String {
        switch workDays {
        case nil: return "Automatic"
        case 4: return "4 days"
        case 5: return "5 days"
        case 7: return "7 days"
        case let workDays?: return "\(workDays) days"
        }
    }
}
#endif
