import Foundation

/// A user-selected, single-bucket move. The caller must bind confirmation to the exact document
/// and current account. No email, preferred-account or single-account inference is performed here.
public enum PlanUtilizationHistoryOwnershipTransfer {
    public enum Source: Equatable, Sendable { case unscoped, account(String) }

    public static func apply(_ document: PlanUtilizationHistoryCore.Document, source: Source,
                             target: String) throws -> PlanUtilizationHistoryCore.Document {
        try document.validate()
        guard !target.isEmpty, target.utf8.count <= 512, !target.contains("\0"),
              target != "__unscoped__", target != "__codexbar_unscoped__" else {
            throw PlanUtilizationHistoryCore.Failure.invalidData
        }
        let sourceKey: String
        let samples: [PlanUtilizationHistoryCore.Series]
        switch source {
        case .unscoped:
            sourceKey = "__codexbar_unscoped__"
            samples = document.unscoped
        case let .account(key):
            guard key != target, key != "__unscoped__", key != "__codexbar_unscoped__",
                  let histories = document.accounts[key] else {
                throw PlanUtilizationHistoryCore.Failure.invalidData
            }
            sourceKey = key
            samples = histories
        }
        guard samples.contains(where: { !$0.entries.isEmpty }) else { throw PlanUtilizationHistoryCore.Failure.invalidData }
        let existing = document.accounts[target] ?? []
        var result = document
        result.accounts[target] = try PlanUtilizationHistoryCore.merging(existing, samples: samples)
        let sourcePair = document.sessionEquivalentWindowPairIdentities[sourceKey]
        let targetPair = document.sessionEquivalentWindowPairIdentities[target]
        if let sourcePair, existing.allSatisfy({ $0.entries.isEmpty }) || sourcePair == targetPair {
            result.sessionEquivalentWindowPairIdentities[target] = sourcePair
        } else {
            // Dynamic quota-pair forecasts cannot reuse mixed or missing pair provenance.
            result.sessionEquivalentWindowPairIdentities[target] = "__codexbar_invalidated__"
        }
        result.sessionEquivalentWindowPairIdentities.removeValue(forKey: sourceKey)
        switch source {
        case .unscoped:
            result.unscoped = []
            if result.preferredAccountKey == "__unscoped__" { result.preferredAccountKey = target }
        case let .account(key):
            result.accounts.removeValue(forKey: key)
            if result.preferredAccountKey == key { result.preferredAccountKey = target }
        }
        try result.validate()
        return result
    }
}
