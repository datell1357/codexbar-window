import Crypto
import Foundation

/// Builds the stable account scope used by predictive pace warning state.
public enum PredictivePaceWarningOwnerIdentityCore {
    public struct Input: Sendable {
        public let provider: UsageProvider
        public let snapshotAccountID: String?
        public let snapshotEmail: String?
        public let codexSelectedWorkspaceAccountID: String?
        public let codexSelectedEmail: String?
        public let tokenAccountID: UUID?
        public let claudeResolvedDiscriminator: String?

        public init(
            provider: UsageProvider,
            snapshotAccountID: String? = nil,
            snapshotEmail: String? = nil,
            codexSelectedWorkspaceAccountID: String? = nil,
            codexSelectedEmail: String? = nil,
            tokenAccountID: UUID? = nil,
            claudeResolvedDiscriminator: String? = nil)
        {
            self.provider = provider
            self.snapshotAccountID = snapshotAccountID
            self.snapshotEmail = snapshotEmail
            self.codexSelectedWorkspaceAccountID = codexSelectedWorkspaceAccountID
            self.codexSelectedEmail = codexSelectedEmail
            self.tokenAccountID = tokenAccountID
            self.claudeResolvedDiscriminator = claudeResolvedDiscriminator
        }
    }

    public static func discriminator(_ input: Input) -> String? {
        switch input.provider {
        case .codex:
            if let accountID = normalized(input.codexSelectedWorkspaceAccountID)
                ?? normalized(input.snapshotAccountID)
            {
                return "codex:v1:provider-account:\(accountID)"
            }
            guard let email = normalized(input.snapshotEmail)
                ?? normalized(input.codexSelectedEmail)
            else { return nil }
            return "codex:v1:email-hash:\(sha256Hex(email))"

        case .claude:
            if let tokenAccountID = input.tokenAccountID {
                return "token-account:\(tokenAccountID.uuidString.lowercased())"
            }
            if let resolved = normalizedPreservingCase(input.claudeResolvedDiscriminator) {
                return resolved
            }
            guard let email = normalized(input.snapshotEmail) else { return nil }
            return "email:\(email)"

        default:
            return nil
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = normalizedPreservingCase(value) else { return nil }
        return value.lowercased()
    }

    private static func normalizedPreservingCase(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
