#if os(Windows)
import Foundation
import WinSDK

/// A single, read-only snapshot of the Windows power policy.
///
/// `GetSystemPowerStatus` is sampled on demand; this adapter deliberately does
/// not start a polling loop or pretend that battery presence is low-power mode.
public struct WindowsPowerState: Equatable, Sendable {
    public enum ACLine: Equatable, Sendable { case offline, online, unknown }
    public enum Availability: Equatable, Sendable {
        case available
        case unavailable(UInt32)
    }

    public let availability: Availability
    public let acLine: ACLine
    public let batterySaverEnabled: Bool

    public init(
        availability: Availability,
        acLine: ACLine = .unknown,
        batterySaverEnabled: Bool = false)
    {
        self.availability = availability
        self.acLine = acLine
        self.batterySaverEnabled = batterySaverEnabled
    }

    public var isAvailable: Bool {
        if case .available = self.availability { return true }
        return false
    }

    /// Reads the system snapshot once. The error code is retained when the
    /// native call fails so callers can surface an explicit unavailable state.
    public static func read() -> Self {
        var status = SYSTEM_POWER_STATUS()
        guard GetSystemPowerStatus(&status) != 0 else {
            let errorCode = GetLastError()
            return Self(availability: .unavailable(errorCode))
        }
        let line: ACLine = switch status.ACLineStatus {
        case 0: .offline
        case 1: .online
        default: .unknown
        }
        // SYSTEM_STATUS_FLAG_POWER_SAVER_MODE is 0x01 in the Windows SDK.
        // BatteryFlag and ACLineStatus are intentionally not used for this.
        let saver = status.SystemStatusFlag & 0x01 != 0
        return Self(availability: .available, acLine: line, batterySaverEnabled: saver)
    }

    public static func snapshot() -> Self { Self.read() }

    public func lowPowerModeEnabled(for preference: WindowsRefreshSettings.LowPowerModePreference) -> Bool {
        switch preference {
        case .off: false
        case .on: true
        case .automatic: self.batterySaverEnabled
        }
    }
}
#endif
