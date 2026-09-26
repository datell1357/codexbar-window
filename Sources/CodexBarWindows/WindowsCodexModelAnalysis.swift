#if os(Windows)
import Foundation
import CodexBarCore

/// Adjacent-period model analysis from the already captured native Codex daily reports.
/// This does not infer historical effort, session counts, or service tiers from present-day settings.
enum WindowsCodexModelAnalysis {
    struct Count: Sendable {
        private var sum = 0
        private var observed = false
        private var overflow = false
        private(set) var complete = true
        var value: Int? { self.observed && !self.overflow ? self.sum : nil }
        mutating func add(_ value: Int?) {
            guard let value, value >= 0 else { self.complete = false; return }
            self.observed = true
            guard !self.overflow else { return }
            let next = self.sum.addingReportingOverflow(value)
            if next.overflow { self.overflow = true; self.complete = false } else { self.sum = next.partialValue }
        }
    }
    struct Amount: Sendable {
        private var sum = 0.0
        private var observed = false
        private var overflow = false
        private(set) var complete = true
        var value: Double? { self.observed && !self.overflow ? self.sum : nil }
        mutating func add(_ value: Double?) {
            guard let value, value.isFinite, value >= 0 else { self.complete = false; return }
            self.observed = true
            guard !self.overflow else { return }
            let next = self.sum + value
            if next.isFinite { self.sum = next } else { self.overflow = true; self.complete = false }
        }
    }
    struct Totals: Sendable {
        var tokens = Count()
        var cost = Amount()
        var input = Count()
        var output = Count()
        var cached = Count()
        var cacheCreation = Count()
        var reasoning = Count()
        var standardTokens = Count()
        var priorityTokens = Count()
        var standardCost = Amount()
        var priorityCost = Amount()

        mutating func add(_ row: CostUsageDailyReport.ModelBreakdown, multiplier: Double) {
            self.tokens.add(row.totalTokens)
            self.cost.add(row.costUSD.map { $0 * multiplier })
            self.input.add(row.inputTokens); self.output.add(row.outputTokens)
            self.cached.add(row.cacheReadTokens); self.reasoning.add(row.reasoningTokens)
            self.cacheCreation.add(row.cacheCreationTokens)
            if let standard = row.standardTokens, standard >= 0,
               let priority = row.priorityTokens, priority >= 0, let total = row.totalTokens, total >= 0 {
                let sum = standard.addingReportingOverflow(priority)
                if !sum.overflow, sum.partialValue == total {
                    self.standardTokens.add(standard); self.priorityTokens.add(priority)
                } else { self.standardTokens.add(nil); self.priorityTokens.add(nil) }
            } else { self.standardTokens.add(nil); self.priorityTokens.add(nil) }
            if let standard = row.standardCostUSD, standard.isFinite, standard >= 0,
               let priority = row.priorityCostUSD, priority.isFinite, priority >= 0,
               let total = row.costUSD, total.isFinite, total >= 0,
               WindowsSpendDashboardModel.costsMatch(total, standard + priority) {
                self.standardCost.add(standard * multiplier); self.priorityCost.add(priority * multiplier)
            } else { self.standardCost.add(nil); self.priorityCost.add(nil) }
        }
    }
    struct Period: Sendable {
        let interval: DateInterval
        let fullSources: Int
        let tokensComplete: Bool
        let costComplete: Bool
        let models: [String: Totals]
        let tokens: Count
        let cost: Amount
        let boundaryAligned: Bool
    }
    struct Snapshot: Sendable {
        let currency: String?
        let sourceCount: Int
        let current: Period
        let previous: Period
        let collectionComplete: Bool
    }

    static func build(inputs: [WindowsSpendDashboardModel.ProviderInput], days: Int, now: Date,
                      calendar: Calendar, preferredCurrency: String, currency: String?,
                      conversionRates: [String: Double], collectionComplete: Bool) -> Snapshot {
        let days = max(1, min(WindowsSpendHistoryPolicy.scanDays, days))
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let current = DateInterval(start: start, end: end)
        // Match CodexModelsAnalyticsPeriods: adjacent intervals of equal elapsed duration.
        // Daily-only data cannot resolve a DST-shifted partial-day boundary; comparisons stay unavailable.
        let previous = DateInterval(start: start.addingTimeInterval(-current.duration), end: start)
        let sources = inputs.compactMap { input -> (WindowsSpendDashboardModel.ProviderInput, Double)? in
            guard input.provider == .codex, input.sourceKind == .native else { return nil }
            let original = input.snapshot.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard original.utf8.count == 3, original.utf8.allSatisfy({ (65...90).contains($0) }) else { return nil }
            let target = UsageFormatter.effectiveCurrencyCode(preferred: preferredCurrency, providerCurrency: original)
            let multiplier = WindowsSpendDashboardModel.currencyMultiplier(from: original, to: target, rates: conversionRates)
            guard (multiplier == nil ? original : target) == currency else { return nil }
            return (input, multiplier ?? 1)
        }
        return Snapshot(currency: currency, sourceCount: sources.count,
            current: Self.period(current, sources: sources, calendar: calendar),
            previous: Self.period(previous, sources: sources, calendar: calendar),
            collectionComplete: collectionComplete)
    }

    private static func period(_ interval: DateInterval,
                               sources: [(WindowsSpendDashboardModel.ProviderInput, Double)],
                               calendar: Calendar) -> Period {
        let aligned = calendar.startOfDay(for: interval.start) == interval.start
            && calendar.startOfDay(for: interval.end) == interval.end
        let lastDay = calendar.startOfDay(for: interval.end.addingTimeInterval(-1))
        let firstDay = interval.start == calendar.startOfDay(for: interval.start) ? interval.start
            : calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: interval.start)) ?? interval.end
        guard firstDay <= lastDay else {
            return Period(interval: interval, fullSources: 0, tokensComplete: false, costComplete: false,
                models: [:], tokens: Count(), cost: Amount(), boundaryAligned: aligned)
        }
        var fullSources = 0
        var tokensComplete = aligned && !sources.isEmpty
        var costComplete = tokensComplete
        var models: [String: Totals] = [:]
        var totalTokens = Count(), totalCost = Amount()
        for (input, multiplier) in sources {
            let summary = WindowsSpendDashboardModel.inputSummary(input: input, costMultiplier: multiplier,
                bounds: firstDay...lastDay, calendar: calendar)
            let full = aligned && summary.coveredInterval?.lowerBound == interval.start
                && summary.coveredInterval?.upperBound == lastDay
            if full { fullSources += 1 }
            tokensComplete = tokensComplete && full && summary.totalTokens != nil && summary.hasCompleteTokenHistory
            costComplete = costComplete && full && summary.totalCost != nil && !summary.hasInvalidCostHistory
                && summary.hasConsistentCostHistory
            let groups = Dictionary(grouping: summary.entries, by: \.day)
            var sourceTokens = Count(), sourceCost = Amount()
            for day in groups.keys.sorted() {
                let entries = groups[day] ?? []
                guard entries.count == 1, let item = entries.first,
                      let next = calendar.date(byAdding: .day, value: 1, to: item.day),
                      item.day >= interval.start, next <= interval.end else {
                    tokensComplete = false; costComplete = false
                    continue // Do not double count duplicates or fabricate a partial day's allocation.
                }
                let entry = item.entry
                let rows = entry.modelBreakdowns ?? []
                var dayTokens = Count(), dayCost = Amount()
                for row in rows {
                    let name = CodexModelsAnalyticsBuilder().canonicalID(row.modelName)
                    guard !name.isEmpty else {
                        if row.totalTokens != 0 { tokensComplete = false }
                        if row.costUSD != 0 { costComplete = false }
                        continue
                    }
                    var value = models[name] ?? Totals()
                    value.add(row, multiplier: multiplier)
                    models[name] = value
                    dayTokens.add(row.totalTokens)
                    dayCost.add(row.costUSD.map { $0 * multiplier })
                    sourceTokens.add(row.totalTokens)
                    sourceCost.add(row.costUSD.map { $0 * multiplier })
                }
                if rows.isEmpty {
                    if entry.totalTokens == 0 { sourceTokens.add(0) } else { tokensComplete = false }
                    if entry.costUSD == 0 { sourceCost.add(0) } else { costComplete = false }
                } else {
                    tokensComplete = tokensComplete && dayTokens.complete && dayTokens.value == entry.totalTokens
                    costComplete = costComplete && dayCost.complete && Self.match(dayCost.value, entry.costUSD.map { $0 * multiplier })
                }
            }
            if groups.isEmpty {
                // A fully scanned empty period is zero only when the shared source summary proves it.
                sourceTokens.add(summary.totalTokens == 0 ? 0 : nil)
                sourceCost.add(summary.totalCost == 0 ? 0 : nil)
            }
            tokensComplete = tokensComplete && sourceTokens.complete
                && sourceTokens.value == summary.totalTokens
            costComplete = costComplete && sourceCost.complete && Self.match(sourceCost.value, summary.totalCost)
            totalTokens.add(sourceTokens.value)
            totalCost.add(sourceCost.value)
        }
        return Period(interval: interval, fullSources: fullSources,
            tokensComplete: tokensComplete && totalTokens.complete, costComplete: costComplete && totalCost.complete,
            models: models, tokens: totalTokens, cost: totalCost, boundaryAligned: aligned)
    }

    private static func match(_ lhs: Double?, _ rhs: Double?) -> Bool {
        guard let lhs, let rhs, lhs.isFinite, rhs.isFinite, lhs >= 0, rhs >= 0 else { return false }
        return WindowsSpendDashboardModel.costsMatch(lhs, rhs)
    }
}
#endif
