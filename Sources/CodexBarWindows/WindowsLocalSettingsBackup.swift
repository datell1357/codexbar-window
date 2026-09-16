#if os(Windows)
import CodexBarCore
import CoreFoundation
import Foundation

/// Local settings recovery, including values intentionally excluded from device synchronization.
/// History, executable plugin files, approval grants and OS credential stores are separate stores.
enum WindowsLocalSettingsBackup {
    enum Failure: Error { case invalidSnapshot, unsupportedVersion, invalidPreferences, preferencesUnavailable, changed }
    enum Scope: String, Codable, Sendable { case localSettings, preferencesRecovery }

    struct Snapshot: Codable, Sendable {
        let version: Int
        let scope: Scope
        let backupID: UUID
        let createdAt: Date
        let configuration: Data?
        let preferences: Data
        let widgets: Data?

        init(scope: Scope, configuration: Data? = nil, preferences: Data, widgets: Data? = nil) {
            self.version = 1
            self.scope = scope
            self.backupID = UUID()
            self.createdAt = Date()
            self.configuration = configuration
            self.preferences = preferences
            self.widgets = widgets
        }
    }

    static let maximumArchiveBytes = 64 * 1024 * 1024
    static let maximumPreferencesBytes = 8 * 1024 * 1024
    private static let magic = Data("CodexBar.Windows.LocalSettingsBackup.v1\0".utf8)

    /// Caller holds exclusive profile ownership before creating a UserDefaults instance.
    static func capture() throws -> Snapshot {
        let configURL = CodexBarConfigStore.defaultURL()
        let configuration = try WindowsRecoveryFileAccess.readIfPresent(configURL,
            limit: WindowsConfigurationBackup.maximumConfigurationBytes)
        let widgets = try WindowsRecoveryFileAccess.readIfPresent(
            WindowsWidgetConfigurationStore.defaultURL(configFileURL: configURL),
            limit: WindowsWidgetConfiguration.maximumEncodedBytes)
        let preferences = try self.capturePreferences()
        // Older apps and external tools may not hold the profile lease. Reject observable changes
        // across collection; this is not a filesystem/registry transaction against those writers.
        guard configuration == (try WindowsRecoveryFileAccess.readIfPresent(configURL,
                  limit: WindowsConfigurationBackup.maximumConfigurationBytes)),
              widgets == (try WindowsRecoveryFileAccess.readIfPresent(
                  WindowsWidgetConfigurationStore.defaultURL(configFileURL: configURL),
                  limit: WindowsWidgetConfiguration.maximumEncodedBytes)),
              try self.samePreferences(preferences, self.capturePreferences()) else { throw Failure.changed }
        return Snapshot(scope: .localSettings, configuration: configuration, preferences: preferences, widgets: widgets)
    }

    static func capturePreferences() throws -> Data {
        guard let defaults = UserDefaults(suiteName: WindowsRefreshSettings.suiteName), defaults.synchronize(),
              let domain = defaults.persistentDomain(forName: WindowsRefreshSettings.suiteName) else {
            throw Failure.preferencesUnavailable
        }
        var budget = 65536
        _ = try self.value(domain, depth: 0, budget: &budget)
        let bytes: Data
        do { bytes = try PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0) }
        catch { throw Failure.invalidPreferences }
        guard bytes.count <= self.maximumPreferencesBytes else { throw Failure.invalidPreferences }
        return bytes
    }

    static func encode(_ snapshot: Snapshot) throws -> Data {
        try self.validate(snapshot)
        let bytes = try JSONEncoder().encode(snapshot)
        let protected = try WindowsRecoveryProtection.transform(bytes, protect: true, purpose: .localSettings,
            maximumBytes: self.maximumArchiveBytes - self.magic.count)
        return self.magic + protected
    }

    static func decode(_ archive: Data) throws -> Snapshot {
        guard archive.count > self.magic.count, archive.count <= self.maximumArchiveBytes,
              archive.starts(with: self.magic) else { throw Failure.invalidSnapshot }
        let bytes = try WindowsRecoveryProtection.transform(Data(archive.dropFirst(self.magic.count)),
            protect: false, purpose: .localSettings, maximumBytes: self.maximumArchiveBytes - self.magic.count)
        let snapshot: Snapshot
        do { snapshot = try JSONDecoder().decode(Snapshot.self, from: bytes) }
        catch { throw Failure.invalidSnapshot }
        try self.validate(snapshot)
        return snapshot
    }

    static func preferencesDomain(_ bytes: Data) throws -> [String: Any] {
        guard !bytes.isEmpty, bytes.count <= self.maximumPreferencesBytes,
              let propertyList = try? PropertyListSerialization.propertyList(from: bytes, options: [], format: nil),
              let domain = propertyList as? [String: Any] else { throw Failure.invalidPreferences }
        var budget = 65536
        _ = try self.value(domain, depth: 0, budget: &budget)
        return domain
    }

    static func samePreferences(_ left: Data, _ right: Data) throws -> Bool {
        var leftBudget = 65536
        var rightBudget = 65536
        return try self.value(self.preferencesDomain(left), depth: 0, budget: &leftBudget) ==
            self.value(self.preferencesDomain(right), depth: 0, budget: &rightBudget)
    }

    private static func validate(_ snapshot: Snapshot) throws {
        guard snapshot.version == 1 else { throw Failure.unsupportedVersion }
        guard snapshot.createdAt.timeIntervalSince1970.isFinite else { throw Failure.invalidSnapshot }
        if snapshot.scope == .preferencesRecovery {
            guard snapshot.configuration == nil, snapshot.widgets == nil else { throw Failure.invalidSnapshot }
        }
        if let configuration = snapshot.configuration {
            _ = try WindowsConfigurationBackup.protectedConfiguration(configuration)
        }
        _ = try self.preferencesDomain(snapshot.preferences)
        if let widgets = snapshot.widgets {
            do { _ = try WindowsWidgetConfiguration.decode(widgets) }
            catch { throw Failure.invalidSnapshot }
        }
    }

    /// Compare property-list values without depending on dictionary serialization order or losing
    /// Bool versus integer semantics through NSDictionary/NSNumber's numeric equality.
    private indirect enum Value: Equatable {
        case dictionary([String: Value]), array([Value]), string(String), data(Data), date(UInt64)
        case boolean(Bool), integer(String), floating(UInt64)
    }

    private static func value(_ input: Any, depth: Int, budget: inout Int) throws -> Value {
        guard depth <= 32, budget > 0 else { throw Failure.invalidPreferences }
        budget -= 1
        if let dictionary = input as? [String: Any] {
            guard dictionary.count <= budget else { throw Failure.invalidPreferences }
            var result: [String: Value] = [:]
            for (key, item) in dictionary {
                guard key.utf8.count <= 4096 else { throw Failure.invalidPreferences }
                result[key] = try self.value(item, depth: depth + 1, budget: &budget)
            }
            return .dictionary(result)
        }
        if let array = input as? [Any] {
            guard array.count <= budget else { throw Failure.invalidPreferences }
            return .array(try array.map { try self.value($0, depth: depth + 1, budget: &budget) })
        }
        if let data = input as? Data {
            guard data.count <= self.maximumPreferencesBytes else { throw Failure.invalidPreferences }
            return .data(data)
        }
        if let date = input as? Date {
            guard date.timeIntervalSince1970.isFinite else { throw Failure.invalidPreferences }
            return .date(date.timeIntervalSince1970.bitPattern)
        }
        if let number = input as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .boolean(number.boolValue) }
            let kind = String(cString: number.objCType)
            if kind == "f" || kind == "d" {
                guard number.doubleValue.isFinite else { throw Failure.invalidPreferences }
                return .floating(number.doubleValue.bitPattern)
            }
            guard ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q", "B"].contains(kind) else {
                throw Failure.invalidPreferences
            }
            return .integer(number.stringValue)
        }
        if let text = input as? String {
            guard text.utf8.count <= self.maximumPreferencesBytes else { throw Failure.invalidPreferences }
            return .string(text)
        }
        throw Failure.invalidPreferences
    }
}
#endif
