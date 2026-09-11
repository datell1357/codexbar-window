import Crypto
import Foundation

/// The account and ambiguity facts used when deciding whether stored Codex history belongs to
/// the currently selected account.  Identity resolution remains an app concern; this type only
/// applies the reconciliation snapshot and visible-account projection rules.
public struct CodexHistoricalOwnershipContext: Sendable, Equatable {
    public let canonicalKey: String?
    public let canonicalEmailHashKey: String?
    public let historicalLegacyEmailHash: String?
    public let planUtilizationLegacyEmailHash: String?
    public let currentWeeklyResetAt: Date?
    public let hasAdjacentMultiAccountVeto: Bool
    public let hasAdjacentEmailScopeAmbiguity: Bool

    public init(
        canonicalKey: String?,
        canonicalEmailHashKey: String?,
        historicalLegacyEmailHash: String?,
        planUtilizationLegacyEmailHash: String?,
        currentWeeklyResetAt: Date?,
        hasAdjacentMultiAccountVeto: Bool,
        hasAdjacentEmailScopeAmbiguity: Bool)
    {
        self.canonicalKey = canonicalKey
        self.canonicalEmailHashKey = canonicalEmailHashKey
        self.historicalLegacyEmailHash = historicalLegacyEmailHash
        self.planUtilizationLegacyEmailHash = planUtilizationLegacyEmailHash
        self.currentWeeklyResetAt = currentWeeklyResetAt
        self.hasAdjacentMultiAccountVeto = hasAdjacentMultiAccountVeto
        self.hasAdjacentEmailScopeAmbiguity = hasAdjacentEmailScopeAmbiguity
    }

    public static func resolve(
        identity: CodexIdentity,
        normalizedEmail: String?,
        currentWeeklyResetAt: Date?,
        snapshot: CodexAccountReconciliationSnapshot,
        projection: CodexVisibleAccountProjection? = nil,
        includeVisibleAccounts: Bool = false) -> Self
    {
        let canonicalKey = CodexHistoryOwnership.canonicalKey(for: identity)
        let email = normalizedEmail.flatMap { CodexIdentityResolver.normalizeEmail($0) }
        let canonicalEmailHashKey = email.map { CodexHistoryOwnership.canonicalEmailHashKey(for: $0) }
        let legacy = email.map { CodexHistoryOwnership.legacyEmailHash(normalizedEmail: $0) }
        let planLegacy = email.map {
            sha256Hex("\(UsageProvider.codex.rawValue):email:\($0)")
        }
        let multi = hasAdjacentMultiAccountVeto(snapshot: snapshot)
            || (includeVisibleAccounts && projection.map(hasVisibleMultiAccountVeto(projection:)) == true)
        let emailAmbiguity = email.map {
            hasAdjacentEmailScopeAmbiguity(normalizedEmail: $0, snapshot: snapshot)
                || (projection.map { visibleProjection in
                    hasVisibleEmailScopeAmbiguity(
                        normalizedEmail: $0, projection: visibleProjection, snapshot: snapshot)
                } == true)
        } ?? false
        return Self(
            canonicalKey: canonicalKey,
            canonicalEmailHashKey: canonicalEmailHashKey,
            historicalLegacyEmailHash: legacy,
            planUtilizationLegacyEmailHash: planLegacy,
            currentWeeklyResetAt: currentWeeklyResetAt,
            hasAdjacentMultiAccountVeto: multi,
            hasAdjacentEmailScopeAmbiguity: emailAmbiguity)
    }

    private static func hasAdjacentMultiAccountVeto(snapshot: CodexAccountReconciliationSnapshot) -> Bool {
        var distinct: Set<String> = []
        if let owner = snapshot.activeStoredAccount ?? snapshot.matchingStoredAccountForLiveSystemAccount {
            distinct.formUnion(managedOwnerKeys(account: owner, snapshot: snapshot))
        }
        if let live = snapshot.liveSystemAccount {
            distinct.insert(CodexIdentityMatcher.selectionKey(
                for: snapshot.runtimeIdentity(for: live), fallbackEmail: live.email))
        }
        return distinct.count > 1
    }

    private static func hasAdjacentEmailScopeAmbiguity(
        normalizedEmail: String,
        snapshot: CodexAccountReconciliationSnapshot) -> Bool
    {
        var distinct: Set<String> = []
        if let owner = snapshot.activeStoredAccount ?? snapshot.matchingStoredAccountForLiveSystemAccount,
           CodexIdentityResolver.normalizeEmail(snapshot.runtimeEmail(for: owner)) == normalizedEmail
        {
            distinct.formUnion(managedOwnerKeys(account: owner, snapshot: snapshot))
        }
        if let live = snapshot.liveSystemAccount,
           CodexIdentityResolver.normalizeEmail(live.email) == normalizedEmail
        {
            distinct.insert(CodexIdentityMatcher.selectionKey(
                for: snapshot.runtimeIdentity(for: live), fallbackEmail: live.email))
        }
        return distinct.count > 1
    }

    private static func managedOwnerKeys(
        account: ManagedCodexAccount,
        snapshot: CodexAccountReconciliationSnapshot) -> Set<String>
    {
        let email = snapshot.runtimeEmail(for: account)
        let remote = snapshot.managedRemoteIdentity(for: account)
        var keys = [CodexIdentityMatcher.selectionKey(for: remote, fallbackEmail: email)]
        let runtime = snapshot.runtimeIdentity(for: account)
        if runtime != .unresolved, !CodexIdentityMatcher.matches(runtime, remote) {
            keys.append(CodexIdentityMatcher.selectionKey(for: runtime, fallbackEmail: email))
        }
        return Set(keys)
    }

    private static func hasVisibleMultiAccountVeto(projection: CodexVisibleAccountProjection) -> Bool {
        var distinct: Set<String> = []
        for account in projection.visibleAccounts {
            if let id = ManagedCodexAccount.normalizeWorkspaceAccountID(account.workspaceAccountID) {
                distinct.insert("provider:\(id)")
            } else if let email = CodexIdentityResolver.normalizeEmail(account.email) {
                distinct.insert("email:\(email)")
            }
        }
        return distinct.count > 1
    }

    private static func hasVisibleEmailScopeAmbiguity(
        normalizedEmail: String,
        projection: CodexVisibleAccountProjection,
        snapshot: CodexAccountReconciliationSnapshot) -> Bool
    {
        var distinct: Set<String> = []
        for account in projection.visibleAccounts where CodexIdentityResolver.normalizeEmail(account.email) == normalizedEmail {
            if let id = ManagedCodexAccount.normalizeWorkspaceAccountID(account.workspaceAccountID) {
                distinct.insert("provider:\(id)")
            } else {
                distinct.insert("email:\(normalizedEmail)")
            }
            if let storedID = account.storedAccountID,
               let stored = snapshot.storedAccounts.first(where: { $0.id == storedID }),
               CodexIdentityResolver.normalizeEmail(snapshot.runtimeEmail(for: stored)) == normalizedEmail
            {
                distinct.formUnion(managedOwnerKeys(account: stored, snapshot: snapshot))
            }
        }
        return distinct.count > 1
    }

    private static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
