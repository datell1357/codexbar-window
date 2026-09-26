#if os(Windows)
import Foundation
import CodexBarCore

/// Pricing partitions are optional in legacy activity reports. Costs must reconcile with their own day/model.
enum WindowsCodexEffortPricing {
    struct Value: Sendable {
        var cost = WindowsCodexModelAnalysis.Amount()
        var pricedTokens = WindowsCodexModelAnalysis.Count()
        var unpricedTokens = WindowsCodexModelAnalysis.Count()
        var reconciled = true

        mutating func merge(_ other: Self) {
            self.cost.add(other.cost.value)
            if !other.cost.complete { self.cost.add(nil) }
            self.pricedTokens.add(other.pricedTokens.value)
            if !other.pricedTokens.complete { self.pricedTokens.add(nil) }
            self.unpricedTokens.add(other.unpricedTokens.value)
            if !other.unpricedTokens.complete { self.unpricedTokens.add(nil) }
            self.reconciled = self.reconciled && other.reconciled
        }
        var costComplete: Bool { self.reconciled && self.cost.complete && self.unpricedTokens.value == 0 }
    }
    private struct Key: Hashable {
        let day: String
        let model: String
    }
    struct Result {
        var byDay: [String: [String: [String: Value]]] = [:]
        var rows: [Int: Value] = [:]
    }
    /// Called only after activity token totals and bounds have passed the enclosing report reconciliation.
    static func build(daily: [CostUsageDailyReport.Entry], evidence: CodexModelActivityEvidence,
                      since: String, until: String, multiplier: Double) -> Result {
        guard multiplier.isFinite, multiplier > 0 else { return Result() }
        var expected: [Key: WindowsCodexModelAnalysis.Amount] = [:]
        for day in daily where day.date >= since && day.date <= until {
            for model in day.modelBreakdowns ?? [] {
                let key = Key(day: day.date, model: CodexModelsAnalyticsBuilder().canonicalID(model.modelName))
                expected[key, default: .init()].add(model.costUSD)
            }
        }
        var actual: [Key: WindowsCodexModelAnalysis.Amount] = [:]
        var invalid: Set<Key> = []
        for row in evidence.rows where row.day >= since && row.day <= until && row.tokens > 0 {
            let key = Key(day: row.day, model: CodexModelsAnalyticsBuilder().canonicalID(row.model))
            guard Self.valid(row) else { invalid.insert(key); continue }
            if let cost = row.knownCostUSD { actual[key, default: .init()].add(cost) }
            // An unpriced row contributes no known cost; it does not claim zero total cost.
        }
        var matched: Set<Key> = []
        for (key, amount) in actual {
            guard !invalid.contains(key), amount.complete, let known = amount.value,
                  let original = expected[key], original.complete, let total = original.value,
                  WindowsSpendDashboardModel.costsMatch(known, total) else { continue }
            matched.insert(key)
        }
        var result = Result()
        for (index, row) in evidence.rows.enumerated() where row.day >= since && row.day <= until && row.tokens > 0 {
            let model = CodexModelsAnalyticsBuilder().canonicalID(row.model)
            let key = Key(day: row.day, model: model)
            let effort = WindowsCodexActivityAnalysis.effort(row.effort)
            var value = Value()
            if Self.valid(row), !invalid.contains(key), matched.contains(key) || actual[key] == nil {
                value.pricedTokens.add(row.pricedTokens)
                value.unpricedTokens.add(row.unpricedTokens)
                let reconciled = matched.contains(key)
                value.reconciled = value.reconciled && reconciled
                let cost = reconciled ? row.knownCostUSD.map { $0 * multiplier } : nil
                value.cost.add(cost)
                if row.unpricedTokens != 0 { value.cost.add(nil) }
            } else {
                value.reconciled = false
                value.cost.add(nil)
                value.pricedTokens.add(nil)
                value.unpricedTokens.add(nil)
            }
            result.rows[index] = value
            result.byDay[row.day, default: [:]][model, default: [:]][effort, default: .init()].merge(value)
        }
        return result
    }
    private static func valid(_ row: CodexModelActivityEvidence.Row) -> Bool {
        guard let priced = row.pricedTokens, let unpriced = row.unpricedTokens, priced >= 0, unpriced >= 0 else { return false }
        let total = priced.addingReportingOverflow(unpriced)
        guard !total.overflow, total.partialValue == row.tokens else { return false }
        if let cost = row.knownCostUSD {
            return cost.isFinite && cost >= 0 && (priced > 0 || cost == 0)
        }
        return priced == 0
    }
    static func displayLabel(_ raw: String, hidePersonalInfo: Bool) -> String {
        let publicLabels: Set<String> = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra", "persistent"]
        return raw.isEmpty ? "Unrecorded" : hidePersonalInfo && !publicLabels.contains(raw) ? "Custom" : raw
    }
    static func displayed(_ values: [String: Value], hidePersonalInfo: Bool) -> [String: Value] {
        var result: [String: Value] = [:]
        for (raw, value) in values {
            result[self.displayLabel(raw, hidePersonalInfo: hidePersonalInfo), default: .init()].merge(value)
        }
        return result
    }
}
#endif
