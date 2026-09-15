import Foundation

/// Non-Codex account adoption and legacy window-pair metadata from the original usage store.
/// Account ownership and OAuth provenance must be resolved by the runtime before constructing this request.
public struct PlanUtilizationAccountMigration: Equatable, Sendable {
    public let provider: UsageProvider
    public let adoptUnscoped: Bool
    public let legacyClaudeEmailKey: String?
    /// Keys are account keys, with "__unscoped__" for the legacy defaults entry.
    public let legacyPairIdentities: [String: String]

    public init(provider: UsageProvider, adoptUnscoped: Bool,
                legacyClaudeEmailKey: String? = nil, legacyPairIdentities: [String: String] = [:]) {
        self.provider = provider
        self.adoptUnscoped = adoptUnscoped
        self.legacyClaudeEmailKey = legacyClaudeEmailKey
        self.legacyPairIdentities = legacyPairIdentities
    }

    public func materialize(_ document: PlanUtilizationHistoryCore.Document, accountKey: String?) throws
        -> PlanUtilizationHistoryCore.Document
    {
        try document.validate()
        guard self.provider != .codex else { throw PlanUtilizationHistoryCore.Failure.invalidData }
        var result = document
        // Evaluate this before legacy-key merging: any pre-existing Claude owner vetoes unscoped adoption.
        let canAdopt = self.adoptUnscoped && !(self.provider == .claude
            && (document.preferredAccountKey == "__unscoped__" || !document.accounts.isEmpty))
        if self.provider == .claude, let accountKey, let legacy = self.legacyClaudeEmailKey,
           legacy != accountKey, let histories = document.accounts[legacy], !histories.isEmpty {
            result.accounts[accountKey] = try PlanUtilizationHistoryCore.merging(
                result.accounts[accountKey] ?? [], samples: histories)
            result.accounts.removeValue(forKey: legacy)
            result.sessionEquivalentWindowPairIdentities.removeValue(forKey: legacy)
            if result.preferredAccountKey == legacy { result.preferredAccountKey = accountKey }
        }
        let generic = self.provider != .claude && self.provider != .antigravity
        if let accountKey, canAdopt, !result.unscoped.isEmpty {
            let targetHasHistory = !(result.accounts[accountKey] ?? []).isEmpty
            result.accounts[accountKey] = try PlanUtilizationHistoryCore.merging(
                result.accounts[accountKey] ?? [], samples: result.unscoped)
            result.unscoped = []
            if generic {
                // Persisted values take precedence; a target legacy value contributes only with target history.
                self.materializePairIdentity(accountKey: nil, document: &result)
                if targetHasHistory { self.materializePairIdentity(accountKey: accountKey, document: &result) }
                let sourceKey = "__codexbar_unscoped__"
                if let source = result.sessionEquivalentWindowPairIdentities[sourceKey] {
                    if let target = result.sessionEquivalentWindowPairIdentities[accountKey], target != source {
                        result.sessionEquivalentWindowPairIdentities[accountKey] = "__codexbar_invalidated__"
                    } else { result.sessionEquivalentWindowPairIdentities[accountKey] = source }
                    result.sessionEquivalentWindowPairIdentities.removeValue(forKey: sourceKey)
                }
            }
        }
        if generic { self.materializePairIdentity(accountKey: accountKey, document: &result) }
        try result.validate()
        return result
    }

    private func materializePairIdentity(accountKey: String?, document: inout PlanUtilizationHistoryCore.Document) {
        let storageKey = accountKey ?? "__codexbar_unscoped__"
        guard document.sessionEquivalentWindowPairIdentities[storageKey] == nil,
              let legacy = self.legacyPairIdentities[accountKey ?? "__unscoped__"] else { return }
        document.sessionEquivalentWindowPairIdentities[storageKey] = legacy
    }
}
