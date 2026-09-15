#if os(Windows)
import CodexBarCore
import Foundation

public struct WindowsPluginSettingsSnapshot: Sendable {
    let token: UUID
    let instanceID: ProviderInstanceID
    let sourceHash: String
    let sourceURL: URL
    let fields: [ProviderPluginSetting]
    let values: [String: String]
    let storedSecretKeys: Set<String>
}

public enum WindowsPluginSettingChange: Sendable {
    case replace(String)
    case remove
}

/// Keys absent from the patch are unchanged. Secrets are never copied into a displayed snapshot.
enum WindowsPluginSettingsEditor {
    static func applying(_ changes: [String: WindowsPluginSettingChange],
                         fields: [ProviderPluginSetting], to provider: ProviderConfig) throws -> ProviderConfig {
        var result = provider
        var values = provider.pluginSettings ?? [:]
        var secrets = provider.pluginSecrets ?? [:]
        for (key, change) in changes {
            guard let field = fields.first(where: { $0.key == key }) else {
                throw WindowsPluginApprovalFailure.changed
            }
            let replacement: String?
            switch change {
            case let .replace(value):
                guard value.utf8.count <= 16384, !value.contains("\0") else {
                    throw WindowsPluginApprovalFailure.unavailable
                }
                replacement = value
            case .remove: replacement = nil
            }
            // A field edited under a changed manifest kind must not leave a second value in the wrong store.
            values[key] = nil
            secrets[key] = nil
            if field.kind == .secure { secrets[key] = replacement }
            else { values[key] = replacement }
        }
        result.pluginSettings = values.isEmpty ? nil : values
        result.pluginSecrets = secrets.isEmpty ? nil : secrets
        return result
    }
}
#endif
