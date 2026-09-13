#if os(Windows)
import Foundation
import CodexBarCore

/// Local side effects after confirmed config removal. Never revoke remote credentials.
enum WindowsAccountRemovalCleanup {
    static func removeSharedCredentialIfNeeded(provider: UsageProvider, removed: ProviderTokenAccount,
                                               remaining: [ProviderTokenAccount],
                                               store: AntigravityOAuthCredentialsStore = .init()) throws {
        guard provider == .antigravity,
              let credential = AntigravityOAuthCredentialsStore.credentials(fromTokenAccountValue: removed.token) else { return }
        let retained = remaining.contains { account in
            guard let other = AntigravityOAuthCredentialsStore.credentials(fromTokenAccountValue: account.token) else { return false }
            return Self.sameAccount(other, credential)
        }
        guard !retained else { return }
        try store.deleteIfPresent { shared in Self.sameStoredCredential(shared, credential) }
    }

    private static func token(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func email(_ value: String?) -> String? { Self.token(value)?.lowercased() }

    private static func sameAccount(_ lhs: AntigravityOAuthCredentials, _ rhs: AntigravityOAuthCredentials) -> Bool {
        if let left = Self.email(lhs.resolvedAccountEmail), let right = Self.email(rhs.resolvedAccountEmail) {
            return left == right
        }
        if let left = Self.token(lhs.refreshToken), let right = Self.token(rhs.refreshToken) { return left == right }
        if let left = Self.token(lhs.accessToken), let right = Self.token(rhs.accessToken) { return left == right }
        return false
    }

    private static func sameStoredCredential(_ shared: AntigravityOAuthCredentials,
                                             _ removed: AntigravityOAuthCredentials) -> Bool {
        if let left = Self.token(shared.refreshToken), let right = Self.token(removed.refreshToken) { return left == right }
        if let left = Self.token(shared.accessToken), let right = Self.token(removed.accessToken) { return left == right }
        guard Self.token(shared.refreshToken) == nil, Self.token(removed.refreshToken) == nil,
              Self.token(shared.accessToken) == nil, Self.token(removed.accessToken) == nil,
              let left = Self.email(shared.resolvedAccountEmail), let right = Self.email(removed.resolvedAccountEmail)
        else { return false }
        return left == right
    }
}
#endif
