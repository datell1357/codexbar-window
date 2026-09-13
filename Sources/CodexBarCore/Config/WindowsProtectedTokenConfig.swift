#if os(Windows)
import Foundation

/// Disk-only transformation: the in-memory provider model continues to hold resolved credentials.
enum WindowsProtectedTokenConfig {
    private static let marker = "windowsTokenProtectionVersion"
    private static let protectedKey = "windowsProtectedToken"
    private static let providerProtectedKey = "windowsProtectedProviderSecrets"
    private static let secretKeys = ["apiKey", "secretKey", "cookieHeader", "pluginSecrets"]
    enum Failure: Error { case invalidFormat }

    static func encode(_ data: Data) throws -> Data { try transform(data, saving: true) }
    static func decode(_ data: Data) throws -> Data { try transform(data, saving: false) }

    private static func validateFields(_ fields: [String: Any]) throws {
        guard Set(fields.keys).isSubset(of: Set(Self.secretKeys)) else { throw Failure.invalidFormat }
        for (key, value) in fields {
            if value is NSNull { continue }
            if key == "pluginSecrets" {
                guard value is [String: String] else { throw Failure.invalidFormat }
            } else { guard value is String else { throw Failure.invalidFormat } }
        }
    }

    private static func transform(_ data: Data, saving: Bool) throws -> Data {
        guard data.count <= 32 * 1024 * 1024,
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var providers = root["providers"] as? [[String: Any]] else { throw Failure.invalidFormat }
        var formatVersion = 0
        if let version = root[Self.marker] {
            guard !saving, let number = version as? NSNumber,
                  String(cString: number.objCType) != "c", [1, 2].contains(number.intValue),
                  number.doubleValue == Double(number.intValue) else { throw Failure.invalidFormat }
            formatVersion = number.intValue
        }
        var hasProtectedToken = false
        for providerIndex in providers.indices {
            guard let rawID = providers[providerIndex]["id"] as? String,
                  let providerID = ProviderInstanceID(rawValue: rawID) else { throw Failure.invalidFormat }
            var fields: [String: Any] = [:]
            for key in Self.secretKeys {
                if let value = providers[providerIndex][key] { fields[key] = value }
            }
            if saving {
                guard providers[providerIndex][Self.providerProtectedKey] == nil else { throw Failure.invalidFormat }
                if !fields.isEmpty {
                    try Self.validateFields(fields)
                    let payload = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
                    let encrypted = try WindowsTokenAccountProtection.providerFields(payload, providerID: providerID, protect: true)
                    for key in Self.secretKeys { providers[providerIndex].removeValue(forKey: key) }
                    providers[providerIndex][Self.providerProtectedKey] = encrypted.base64EncodedString()
                    hasProtectedToken = true
                }
            } else if let encoded = providers[providerIndex][Self.providerProtectedKey] {
                guard formatVersion == 2, fields.isEmpty, let text = encoded as? String,
                      text.utf8.count <= 700_000, let encrypted = Data(base64Encoded: text) else { throw Failure.invalidFormat }
                let payload = try WindowsTokenAccountProtection.providerFields(encrypted, providerID: providerID, protect: false)
                guard let restored = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else { throw Failure.invalidFormat }
                try Self.validateFields(restored)
                for (key, value) in restored { providers[providerIndex][key] = value }
                providers[providerIndex].removeValue(forKey: Self.providerProtectedKey)
                hasProtectedToken = true
            } else if formatVersion == 2, !fields.isEmpty { throw Failure.invalidFormat }
            guard var accountData = providers[providerIndex]["tokenAccounts"] as? [String: Any] else {
                if let value = providers[providerIndex]["tokenAccounts"], !(value is NSNull) { throw Failure.invalidFormat }
                continue
            }
            guard var accounts = accountData["accounts"] as? [[String: Any]] else { throw Failure.invalidFormat }
            var seen = Set<UUID>()
            for index in accounts.indices {
                guard let idText = accounts[index]["id"] as? String, let accountID = UUID(uuidString: idText),
                      seen.insert(accountID).inserted else { throw Failure.invalidFormat }
                if saving {
                    guard accounts[index][Self.protectedKey] == nil,
                          let token = accounts[index]["token"] as? String else { throw Failure.invalidFormat }
                    let encrypted = try WindowsTokenAccountProtection.protect(token: token, providerID: providerID, accountID: accountID)
                    accounts[index].removeValue(forKey: "token")
                    accounts[index][Self.protectedKey] = encrypted.base64EncodedString()
                    hasProtectedToken = true
                } else if let encoded = accounts[index][Self.protectedKey] {
                    guard root[Self.marker] != nil, accounts[index]["token"] == nil,
                          let text = encoded as? String, text.utf8.count <= 700_000,
                          let encrypted = Data(base64Encoded: text) else { throw Failure.invalidFormat }
                    accounts[index]["token"] = try WindowsTokenAccountProtection.unprotect(
                        encrypted, providerID: providerID, accountID: accountID)
                    accounts[index].removeValue(forKey: Self.protectedKey)
                    hasProtectedToken = true
                } else {
                    // A declared protected file must never silently downgrade one account to plaintext.
                    guard root[Self.marker] == nil, accounts[index]["token"] is String else { throw Failure.invalidFormat }
                }
            }
            accountData["accounts"] = accounts
            providers[providerIndex]["tokenAccounts"] = accountData
        }
        root["providers"] = providers
        if saving, hasProtectedToken { root[Self.marker] = 2 }
        if !saving { root.removeValue(forKey: Self.marker) }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }
}
#endif
