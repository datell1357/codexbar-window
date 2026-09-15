import Foundation

/// Resolves usage ownership from the winning strategy, never from an unrelated local login.
/// OAuth identifiers are one-way credential discriminators supplied by the fetcher, not secrets.
public enum ClaudeUsageOwnerResolution: Equatable, Sendable {
    case oauth(historyOwnerIdentifier: String)
    case cliAccount(uuid: String)
    case cliWithoutAccount
    case other
    case unavailable

    public static func requiresCLIAccountObservation(
        strategy: ProviderFetchKind?, credentialOwner: ClaudeOAuthCredentialOwner?
    ) -> Bool {
        strategy == .cli || (strategy == .oauth && credentialOwner != .environment && credentialOwner != .codexbar)
    }

    public static func resolve(
        strategy: ProviderFetchKind?, credentialOwner: ClaudeOAuthCredentialOwner?,
        historyOwnerIdentifier: String?, accountUUIDBefore: String?, accountUUIDAfter: String?
    ) -> Self {
        let before = self.normalized(accountUUIDBefore)
        let after = self.normalized(accountUUIDAfter)
        if self.requiresCLIAccountObservation(strategy: strategy, credentialOwner: credentialOwner), before != after {
            return .unavailable
        }
        if strategy == .oauth {
            guard let owner = self.normalized(historyOwnerIdentifier), owner.utf8.count == 64,
                  owner.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                return .unavailable
            }
            // A CLI profile UUID can corroborate stability; it does not replace OAuth credential ownership.
            return .oauth(historyOwnerIdentifier: owner)
        }
        if strategy == .cli {
            guard let before, let uuid = UUID(uuidString: before) else { return .cliWithoutAccount }
            return .cliAccount(uuid: uuid.uuidString.lowercased())
        }
        return .other
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty else {
            return nil
        }
        return value
    }
}
