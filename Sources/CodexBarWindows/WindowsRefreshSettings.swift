#if os(Windows)
import Foundation

/// Windows persistence for the refresh cadence.  The suite is deliberately
/// separate from the macOS defaults database so roaming or stale values cannot
/// silently alter the Windows scheduler.
public struct WindowsRefreshSettings: Sendable, Equatable {
    public enum Frequency: String, Sendable, CaseIterable {
        case manual, oneMinute, twoMinutes, fiveMinutes, fifteenMinutes, thirtyMinutes
        case adaptive, adaptiveAgentAware

        public var seconds: TimeInterval? {
            switch self {
            case .manual, .adaptive, .adaptiveAgentAware: nil
            case .oneMinute: 60
            case .twoMinutes: 120
            case .fiveMinutes: 300
            case .fifteenMinutes: 900
            case .thirtyMinutes: 1800
            }
        }

        public var usesAdaptivePolicy: Bool {
            self == .adaptive || self == .adaptiveAgentAware
        }
    }

    public enum ActivityConsent: String, Sendable {
        case undecided, allowed, declined
    }

    public static let suiteName = "CodexBar.Windows"
    public let frequency: Frequency
    public let activityConsent: ActivityConsent

    public init(
        frequency: Frequency,
        activityConsent: ActivityConsent = .undecided)
    {
        self.frequency = frequency
        self.activityConsent = activityConsent
    }

    public var agentAwareRefreshAvailable: Bool {
        self.activityConsent == .allowed
    }

    public static func load(userDefaults: UserDefaults? = nil) -> WindowsRefreshSettings {
        let defaults = userDefaults ?? UserDefaults(suiteName: Self.suiteName) ?? .standard
        let hadPreviousInstallationState = defaults.object(forKey: "providerDetectionCompleted") != nil
            || defaults.object(forKey: "appGroupMigrationVersion") != nil
        let rawObject = defaults.object(forKey: "refreshFrequency")
        let raw = rawObject as? String
        let frequency: Frequency
        if let raw, let stored = Frequency(rawValue: raw) {
            frequency = stored
        } else {
            // Preserve CodexBar's migration rule: a genuinely new install is
            // adaptive, while legacy or invalid state retains five minutes.
            frequency = rawObject == nil && !hadPreviousInstallationState ? .adaptive : .fiveMinutes
            defaults.set(frequency.rawValue, forKey: "refreshFrequency")
        }
        let consent: ActivityConsent
        if let rawConsent = defaults.string(forKey: "adaptiveActivityScanConsent"),
           let stored = ActivityConsent(rawValue: rawConsent)
        {
            consent = stored
        } else {
            consent = .undecided
            defaults.set(consent.rawValue, forKey: "adaptiveActivityScanConsent")
        }
        return Self(frequency: frequency, activityConsent: consent)
    }
}
#endif
