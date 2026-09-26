import Foundation

/// Effort recorded in a rollout turn_context, not an inference from present-day thread settings.
/// This label describes the persisted context; it does not prove every server request used that effort.
struct CostUsageCodexEffortContext: Codable, Equatable, Sendable {
    let effort: String
    let model: String
    let turnID: String?
    let timestampUnixMs: Int64

    init?(effort: String?, model: String?, turnID: String?, timestampUnixMs: Int64?) {
        guard let effort = Self.normalizedEffort(effort),
              let model = CostUsageScanner.codexModelEvidence(model),
              let timestampUnixMs else { return nil }
        self.effort = effort
        self.model = CostUsagePricing.normalizeCodexModel(model.lowercased())
        self.turnID = turnID
        self.timestampUnixMs = timestampUnixMs
    }

    static func normalizedEffort(_ raw: String?) -> String? {
        guard let raw, raw.utf8.count <= 128 else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Public protocol accepts model-defined labels. Keep bounded identifier labels without
        // retaining arbitrary text, paths or settings JSON as an effort name.
        guard (1...64).contains(value.utf8.count),
              value.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 })
        else { return nil }
        return value
    }

    func value(model: String?, turnID: String?, timestampUnixMs: Int64?, reportedModel: String? = nil) -> String? {
        guard let timestampUnixMs, timestampUnixMs >= self.timestampUnixMs,
              self.turnID == turnID,
              let model = CostUsageScanner.codexModelEvidence(model),
              CostUsagePricing.normalizeCodexModel(model.lowercased()) == self.model else { return nil }
        if let reportedModel = CostUsageScanner.codexModelEvidence(reportedModel),
           CostUsagePricing.normalizeCodexModel(reportedModel.lowercased()) != self.model { return nil }
        // Decoded old/untrusted cache values must pass the same label boundary.
        return Self.normalizedEffort(self.effort)
    }
}
