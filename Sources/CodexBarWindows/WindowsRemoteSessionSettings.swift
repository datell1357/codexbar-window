#if os(Windows)
import CodexBarCore
import Foundation

public struct WindowsRemoteSessionSettings: Codable, Sendable {
    public var enabled: Bool
    public var discoverTailscale: Bool
    public var targets: [RemoteSessionTarget]

    public static let defaults = Self(enabled: false, discoverTailscale: true, targets: [])
    static let storageKey = "windowsRemoteSessionSettingsV1"

    public static func load(from defaults: UserDefaults) throws -> Self {
        if let raw = defaults.object(forKey: self.storageKey) {
            guard let data = raw as? Data else { throw SettingsError.invalidStoredData }
            guard data.count <= 256 * 1024 else { throw SettingsError.invalidStoredData }
            do {
                let decoded = try JSONDecoder().decode(Self.self, from: data)
                try decoded.checkTargets()
                return decoded
            } catch { throw SettingsError.invalidStoredData }
        }
        // Preserve old manual hosts for editing. Unspecified OS entries must be configured before
        // saving/enabling them; do not guess that a Windows remote runs a POSIX shell.
        let legacy = defaults.string(forKey: "agentSessionsManualHosts") ?? ""
        let values = legacy.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var targets: [RemoteSessionTarget] = []
        for value in values {
            guard let target = RemoteSessionTarget(configurationValue: value) else {
                throw SettingsError.invalidStoredData
            }
            targets.append(target)
        }
        return Self(enabled: false, discoverTailscale: true, targets: targets)
    }

    public func save(to defaults: UserDefaults) throws {
        try self.checkTargets()
        let data = try JSONEncoder().encode(self)
        guard data.count <= 256 * 1024 else { throw SettingsError.invalidStoredData }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func checkTargets() throws {
        guard self.targets.count <= 32 else { throw SettingsError.tooManyHosts }
        var seen = Set<String>()
        for target in self.targets {
            guard target.configurationError == nil else { throw SettingsError.invalidTarget }
            guard seen.insert(target.id).inserted else { throw SettingsError.duplicateHost }
        }
    }

    enum SettingsError: LocalizedError {
        case invalidStoredData, tooManyHosts, invalidTarget, duplicateHost
        var errorDescription: String? {
            switch self {
            case .invalidStoredData: "Stored remote session settings could not be read. They were not overwritten."
            case .tooManyHosts: "Up to 32 manual remote hosts can be configured."
            case .invalidTarget: "Choose an OS and a valid host. Windows CLI overrides must be absolute .exe paths."
            case .duplicateHost: "This remote host is already configured."
            }
        }
    }
}
#endif
