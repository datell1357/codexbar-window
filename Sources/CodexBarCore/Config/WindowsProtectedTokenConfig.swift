#if os(Windows)
import Foundation

/// Disk-only transformation: the in-memory provider model continues to hold resolved credentials.
enum WindowsProtectedTokenConfig {
    private static let marker = "windowsTokenProtectionVersion"
    private static let protectedKey = "windowsProtectedToken"
    enum Failure: Error { case invalidFormat }

    static func encode(_ data: Data) throws -> Data { try transform(data, saving: true) }
    static func decode(_ data: Data) throws -> Data { try transform(data, saving: false) }

    private static func transform(_ data: Data, saving: Bool) throws -> Data {
        guard data.count <= 32 * 1024 * 1024,
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var providers = root["providers"] as? [[String: Any]] else { throw Failure.invalidFormat }
        if let version = root[Self.marker] {
            guard !saving, let number = version as? NSNumber,
                  String(cString: number.objCType) != "c", number.intValue == 1,
                  number.doubleValue == 1 else { throw Failure.invalidFormat }
        }
        var hasProtectedToken = false
        for providerIndex in providers.indices {
            guard var accountData = providers[providerIndex]["tokenAccounts"] as? [String: Any] else {
                if let value = providers[providerIndex]["tokenAccounts"], !(value is NSNull) { throw Failure.invalidFormat }
                continue
            }
            guard let rawID = providers[providerIndex]["id"] as? String,
                  let providerID = ProviderInstanceID(rawValue: rawID),
                  var accounts = accountData["accounts"] as? [[String: Any]] else { throw Failure.invalidFormat }
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
        if saving, hasProtectedToken { root[Self.marker] = 1 }
        if !saving { root.removeValue(forKey: Self.marker) }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }
}
#endif
