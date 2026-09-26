#if os(Windows)
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Non-secret general preferences shared by the tray and native app.
enum WindowsAppGeneralPreferences {
    // Includes cadence migration in WindowsRefreshSettings.load. This serializes this backend's
    // writers, not arbitrary external processes editing the defaults store.
    private static let persistenceLock = NSRecursiveLock()
    static let frequencies = WindowsRefreshSettings.Frequency.allCases.filter { $0 != .adaptiveAgentAware }

    static func withPersistenceLock<T>(_ body: () -> T) -> T {
        self.persistenceLock.lock()
        defer { self.persistenceLock.unlock() }
        return body()
    }

    struct Values: Codable, Sendable, Equatable {
        var frequency: String
        var lowPowerMode: String
        var statusChecksEnabled: Bool
        var refreshOnMenuOpen: Bool

        var revision: String {
            let fields = ["native-general-preferences-v1", self.frequency, self.lowPowerMode,
                          String(self.statusChecksEnabled), String(self.refreshOnMenuOpen)]
            return SHA256.hash(data: Data(fields.joined(separator: "\0").utf8))
                .map { String(format: "%02x", $0) }.joined()
        }

        func applying(_ mutation: Mutation) -> Self? {
            guard mutation.isValid, mutation.expectedRevision == self.revision else { return nil }
            var updated = self
            switch mutation.key {
            case "frequency": updated.frequency = mutation.choice!
            case "lowPowerMode": updated.lowPowerMode = mutation.choice!
            case "statusChecksEnabled": updated.statusChecksEnabled = mutation.value!
            case "refreshOnMenuOpen": updated.refreshOnMenuOpen = mutation.value!
            default: return nil
            }
            return updated
        }
    }

    struct Mutation: Codable, Sendable {
        let key: String
        let expectedRevision: String
        var value: Bool? = nil
        var choice: String? = nil

        var isValid: Bool {
            guard self.expectedRevision.utf8.count == 64,
                  self.expectedRevision.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
            else { return false }
            switch self.key {
            case "frequency":
                return self.value == nil && self.choice.map { choice in
                    WindowsAppGeneralPreferences.frequencies.contains { $0.rawValue == choice }
                } == true
            case "lowPowerMode":
                return self.value == nil && self.choice.flatMap(WindowsRefreshSettings.LowPowerModePreference.init(rawValue:)) != nil
            case "statusChecksEnabled", "refreshOnMenuOpen":
                return self.value != nil && self.choice == nil
            default: return false
            }
        }
    }

    struct Page: Codable, Sendable {
        let revision: String
        let values: Values
        init(_ values: Values) {
            self.revision = values.revision
            self.values = values
        }
    }

    static func accepts(_ request: WindowsAppProtocol.Request) -> Bool {
        guard request.mutation == nil, request.spendQuery == nil, request.spendPreferencesQuery == nil,
              request.spendPreferencesMutation == nil, request.spendAction == nil,
              request.viewPreferencesMutation == nil else { return false }
        switch request.method {
        case "generalPreferences": return request.generalPreferencesMutation == nil
        case "setGeneralPreference": return request.generalPreferencesMutation?.isValid == true
        default: return false
        }
    }

    struct SaveResult: Sendable {
        let status: String
        let page: Page
        // True also after an uncertain flush: reconcile the runtime with the in-memory value.
        let changed: Bool
    }

    static func load(_ defaults: UserDefaults) -> Values {
        self.withPersistenceLock {
            let refresh = WindowsRefreshSettings.load(userDefaults: defaults)
            return .init(frequency: refresh.frequency.rawValue, lowPowerMode: refresh.lowPowerModePreference.rawValue,
                statusChecksEnabled: defaults.object(forKey: "statusChecksEnabled") as? Bool ?? true,
                refreshOnMenuOpen: defaults.object(forKey: "refreshAllProvidersOnMenuOpen") as? Bool ?? false)
        }
    }

    /// A synchronous transaction seam for dictionary-only fixtures. No await between capture and write.
    static func save(_ mutation: Mutation, read: () -> Values,
                     write: (Values, Values) -> Void, synchronize: () -> Bool) -> SaveResult {
        self.withPersistenceLock {
            let current = read()
            guard mutation.isValid else { return .init(status: "invalidRequest", page: .init(current), changed: false) }
            guard let updated = current.applying(mutation) else {
                return .init(status: "settingsChanged", page: .init(current), changed: false)
            }
            guard updated != current else { return .init(status: "ok", page: .init(current), changed: false) }
            write(updated, current)
            let persisted = synchronize()
            let reloaded = read()
            return .init(status: !persisted ? "settingsSaveFailed" : reloaded == updated ? "ok" : "settingsChanged",
                page: .init(reloaded), changed: true)
        }
    }

    static func save(_ mutation: Mutation, defaults: UserDefaults) -> SaveResult {
        self.save(mutation, read: { self.load(defaults) }, write: { updated, previous in
            if updated.frequency != previous.frequency { defaults.set(updated.frequency, forKey: "refreshFrequency") }
            if updated.lowPowerMode != previous.lowPowerMode {
                defaults.set(updated.lowPowerMode, forKey: "backgroundWorkLowPowerModePreference")
            }
            if updated.statusChecksEnabled != previous.statusChecksEnabled {
                defaults.set(updated.statusChecksEnabled, forKey: "statusChecksEnabled")
            }
            if updated.refreshOnMenuOpen != previous.refreshOnMenuOpen {
                defaults.set(updated.refreshOnMenuOpen, forKey: "refreshAllProvidersOnMenuOpen")
            }
        }, synchronize: { defaults.synchronize() })
    }

    /// Tray choices/toggles use the same lock and current revision, without a stale UI snapshot.
    static func change(_ key: String, choice: String? = nil, defaults: UserDefaults) -> SaveResult {
        self.withPersistenceLock {
            let current = self.load(defaults)
            let value: Bool? = switch key {
            case "statusChecksEnabled": !current.statusChecksEnabled
            case "refreshOnMenuOpen": !current.refreshOnMenuOpen
            default: nil
            }
            return self.save(.init(key: key, expectedRevision: current.revision, value: value, choice: choice),
                defaults: defaults)
        }
    }
}
#endif
