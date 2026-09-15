import Foundation

/// Codex's original continuity rules for materializing legacy plan history.
/// The caller supplies freshly reconciled ownership; this code never infers it from a preferred key.
public enum CodexPlanUtilizationHistoryMigration {
    public static func materialize(
        _ document: PlanUtilizationHistoryCore.Document,
        ownership: CodexHistoricalOwnershipContext,
        adoptUnscoped: Bool = true
    ) throws -> PlanUtilizationHistoryCore.Document {
        try document.validate()
        guard let target = ownership.canonicalKey,
              case let .canonical(normalized) = CodexHistoryOwnership.classifyPersistedKey(target),
              normalized == target else { return document }
        var sources = Set<String>()
        for (key, histories) in document.accounts where !histories.isEmpty && key != target {
            let owner = self.owner(key, ownership: ownership)
            if self.matches(owner, target: target, ownership: ownership),
               !self.ambiguousEmailScope(owner, ownership: ownership) {
                sources.insert(key)
            }
        }
        if let opaque = self.recoverableOpaqueKey(document, target: target, ownership: ownership) {
            sources.insert(opaque)
        }
        let takeUnscoped = adoptUnscoped && !document.unscoped.isEmpty
            && CodexHistoryOwnership.hasStrictSingleAccountContinuity(
                scopedRawKeys: self.overlappingKeys(document), targetCanonicalKey: target,
                canonicalEmailHashKey: ownership.canonicalEmailHashKey,
                legacyEmailHash: ownership.planUtilizationLegacyEmailHash,
                hasAdjacentMultiAccountVeto: ownership.hasAdjacentMultiAccountVeto)
        // Preserve the original no-op fast path for an already materialized account.
        guard !sources.isEmpty || takeUnscoped else { return document }
        var result = document
        var histories = document.accounts[target] ?? []
        for key in sources.sorted() {
            histories = try PlanUtilizationHistoryCore.merging(histories, samples: document.accounts[key] ?? [])
        }
        if takeUnscoped {
            histories = try PlanUtilizationHistoryCore.merging(histories, samples: document.unscoped)
        }
        result.accounts[target] = histories
        // Sources disappear only from the replacement document after all merges succeed.
        for key in sources {
            result.accounts.removeValue(forKey: key)
            result.sessionEquivalentWindowPairIdentities.removeValue(forKey: key)
        }
        if takeUnscoped {
            result.unscoped = []
            result.sessionEquivalentWindowPairIdentities.removeValue(forKey: "__codexbar_unscoped__")
        }
        if let preferred = document.preferredAccountKey,
           sources.contains(preferred) || (takeUnscoped && preferred == "__unscoped__") {
            result.preferredAccountKey = target
        }
        try result.validate()
        return result
    }

    private static func owner(_ key: String, ownership: CodexHistoricalOwnershipContext) -> CodexHistoryPersistedOwner {
        CodexHistoryOwnership.classifyPersistedKey(key, legacyEmailHash: ownership.planUtilizationLegacyEmailHash)
    }

    private static func matches(_ owner: CodexHistoryPersistedOwner, target: String,
                                ownership: CodexHistoricalOwnershipContext) -> Bool {
        CodexHistoryOwnership.belongsToTargetContinuity(owner, targetCanonicalKey: target,
            canonicalEmailHashKey: ownership.canonicalEmailHashKey)
    }

    private static func ambiguousEmailScope(_ owner: CodexHistoryPersistedOwner,
                                           ownership: CodexHistoricalOwnershipContext) -> Bool {
        guard ownership.hasAdjacentEmailScopeAmbiguity else { return false }
        switch owner {
        case let .canonical(key): return key == ownership.canonicalEmailHashKey
        case .legacyEmailHash: return true
        case .legacyOpaqueScoped, .legacyUnscoped: return false
        }
    }

    private static func recoverableOpaqueKey(_ document: PlanUtilizationHistoryCore.Document, target: String,
                                             ownership: CodexHistoricalOwnershipContext) -> String? {
        guard !ownership.hasAdjacentMultiAccountVeto,
              let weeklyReset = ownership.currentWeeklyResetAt,
              weeklyReset.timeIntervalSince1970.isFinite else { return nil }
        let candidates = document.accounts.compactMap { key, histories -> String? in
            guard case .legacyOpaqueScoped = self.owner(key, ownership: ownership),
                  let weekly = histories.first(where: { $0.name == "weekly" && $0.windowMinutes == 10080 }),
                  let session = histories.first(where: { $0.name == "session" && $0.windowMinutes == 300 }),
                  !session.entries.isEmpty else { return nil }
            let resets = Set(weekly.entries.compactMap(\.resetsAt))
            guard resets.count >= 2,
                  resets.contains(where: { self.equivalent($0, weeklyReset) }),
                  resets.contains(where: { !self.equivalent($0, weeklyReset) }) else { return nil }
            return key
        }
        guard candidates.count == 1, let candidate = candidates.first else { return nil }
        let conflict = document.accounts.contains { key, histories in
            guard key != candidate, histories.contains(where: { series in
                series.entries.contains { self.equivalent($0.resetsAt, weeklyReset) }
            }) else { return false }
            let owner = self.owner(key, ownership: ownership)
            switch owner {
            case .canonical, .legacyEmailHash:
                return !self.matches(owner, target: target, ownership: ownership)
            case .legacyOpaqueScoped, .legacyUnscoped:
                return false
            }
        }
        return conflict ? nil : candidate
    }

    private static func equivalent(_ lhs: Date?, _ rhs: Date) -> Bool {
        guard let lhs else { return false }
        return abs(lhs.timeIntervalSince(rhs)) < 120
    }

    private static func overlappingKeys(_ document: PlanUtilizationHistoryCore.Document) -> [String] {
        let dates = document.unscoped.flatMap(\.entries).map(\.capturedAt)
        guard let first = dates.min(), let last = dates.max() else { return [] }
        let allHistories = document.unscoped + document.accounts.values.flatMap { $0 }
        let expansion = TimeInterval(allHistories.map(\.windowMinutes).max() ?? 0) * 60
        let lower = first.addingTimeInterval(-expansion)
        let upper = last.addingTimeInterval(expansion)
        guard lower.timeIntervalSince1970.isFinite, upper.timeIntervalSince1970.isFinite else {
            // Every scoped owner must participate when a safe time window cannot be represented.
            return Array(document.accounts.keys)
        }
        let window = lower...upper
        return document.accounts.compactMap { key, histories in
            histories.contains { $0.entries.contains { window.contains($0.capturedAt) } } ? key : nil
        }
    }
}
