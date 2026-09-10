#if os(Windows)
import Foundation

/// Windows persistence for the refresh cadence.  The suite is deliberately
/// separate from the macOS defaults database so roaming or stale values cannot
/// silently alter the Windows scheduler.
public struct WindowsRefreshSettings: Sendable, Equatable {
    public enum LowPowerModePreference: String, Sendable, CaseIterable {
        case off, on, automatic
    }
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
    public let lowPowerModePreference: LowPowerModePreference

    public init(
        frequency: Frequency,
        activityConsent: ActivityConsent = .undecided,
        lowPowerModePreference: LowPowerModePreference = .off)
    {
        self.frequency = frequency
        self.activityConsent = activityConsent
        self.lowPowerModePreference = lowPowerModePreference
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
        let powerPreference: LowPowerModePreference
        if let raw = defaults.string(forKey: "backgroundWorkLowPowerModePreference"),
           let stored = LowPowerModePreference(rawValue: raw)
        {
            powerPreference = stored
        } else {
            // Match the source SettingsStore migration: legacy bool, default off.
            let legacyEnabled = defaults.object(forKey: "backgroundWorkLowPowerModeEnabled") as? Bool ?? false
            powerPreference = legacyEnabled ? .on : .off
            defaults.set(powerPreference.rawValue, forKey: "backgroundWorkLowPowerModePreference")
        }
        return Self(
            frequency: frequency,
            activityConsent: consent,
            lowPowerModePreference: powerPreference)
    }

    public func resolvedLowPowerModeEnabled(state: WindowsPowerState = .read()) -> Bool {
        state.lowPowerModeEnabled(for: self.lowPowerModePreference)
    }
}
#endif
