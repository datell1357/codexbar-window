import Foundation

/// Adds bounded metadata while the report already visits canonical usage rows.
/// No new source reads, price inference, current-thread settings or account discovery.
struct CostUsageCodexActivityBuilder {
    struct Limits {
        var files = 4096
        var events = 100_000
        var groups = 8192
    }
    private struct Key: Hashable {
        let day: String
        let model: String
        let effort: String?
        let session: Int?
    }
    private struct Group {
        var tokens = 0
        var cost = 0.0
        var sawCost = false
        var pricedTokens = 0
        var unpricedTokens = 0
        var pricingEvidenceComplete = true
    }
    private let range: CostUsageScanner.CostUsageDayRange
    private let limits: Limits
    private var fileCount = 0
    private var eventCount = 0
    private var complete = true
    private var exhausted = false
    private var sessions: [String: Int] = [:]
    private var groups: [Key: Group] = [:]

    init(range: CostUsageScanner.CostUsageDayRange, limits: Limits = .init()) {
        self.range = range
        self.limits = limits
    }

    mutating func add(_ usage: CostUsageFileUsage, reconciled: CostUsageScanner.CodexCanonicalPricingRows,
                      resolvedCost: (CostUsageScanner.CodexUsageRow) -> Double? = { _ in nil }) {
        guard !self.exhausted else { return }
        guard self.fileCount < max(0, self.limits.files) else { self.stop(); return }
        self.fileCount += 1
        if usage.codexScanComplete == false || usage.hasBufferedCodexForkRetryLines {
            self.complete = false
        }
        if reconciled.unresolvedGroups.contains(where: {
            self.includes($0.day) && OpenCodexRouteDispatcher.countsTowardCodexSubscription(modelName: $0.model)
        }) { self.complete = false }
        var reference: Int?
        if let session = usage.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !session.isEmpty, session.utf8.count <= 512 {
            if let known = self.sessions[session] { reference = known }
            else {
                reference = self.sessions.count
                self.sessions[session] = reference
            }
        }
        for row in reconciled.rows {
            guard self.eventCount < max(0, self.limits.events) else { self.stop(); return }
            self.eventCount += 1
            guard self.includes(row.day),
                  OpenCodexRouteDispatcher.countsTowardCodexSubscription(modelName: row.model) else { continue }
            let total = row.input.addingReportingOverflow(row.output)
            guard row.input >= 0, row.output >= 0, !total.overflow,
                  !row.model.isEmpty, row.model.utf8.count <= 256 else { self.complete = false; continue }
            guard total.partialValue > 0 else { continue }
            let key = Key(day: row.day, model: row.model,
                effort: usage.hasCurrentCodexParserMetadata
                    ? CostUsageCodexEffortContext.normalizedEffort(row.reasoningEffort) : nil,
                session: reference)
            guard self.groups[key] != nil || self.groups.count < max(0, self.limits.groups)
            else { self.stop(); return }
            var group = self.groups[key] ?? Group()
            let sum = group.tokens.addingReportingOverflow(total.partialValue)
            guard !sum.overflow else { self.stop(); return }
            group.tokens = sum.partialValue
            let unpriced = row.unpricedTokens ?? 0
            if row.eventIndex.map({ $0 >= 0 }) == true, row.cached >= 0, row.cached <= row.input,
               unpriced >= 0, unpriced <= total.partialValue {
                if let cost = resolvedCost(row) {
                    let costSum = group.cost + cost
                    if cost.isFinite, cost >= 0, costSum.isFinite, (unpriced < total.partialValue || cost == 0) {
                        group.cost = costSum
                        group.sawCost = true
                        group.pricedTokens += total.partialValue - unpriced
                        group.unpricedTokens += unpriced
                    } else { group.pricingEvidenceComplete = false }
                } else {
                    group.unpricedTokens += total.partialValue
                }
            } else { group.pricingEvidenceComplete = false }
            self.groups[key] = group
        }
    }

    func finish() -> CodexModelActivityEvidence {
        let rows = self.groups.map { key, group in
            CodexModelActivityEvidence.Row(day: key.day, model: key.model, effort: key.effort,
                sessionReference: key.session, tokens: group.tokens,
                knownCostUSD: group.pricingEvidenceComplete && group.sawCost ? group.cost : nil,
                pricedTokens: group.pricingEvidenceComplete ? group.pricedTokens : nil,
                unpricedTokens: group.pricingEvidenceComplete ? group.unpricedTokens : nil)
        }.sorted {
            if $0.day != $1.day { return $0.day < $1.day }
            if $0.model != $1.model { return $0.model < $1.model }
            if $0.effort != $1.effort { return ($0.effort ?? "") < ($1.effort ?? "") }
            return ($0.sessionReference ?? -1) < ($1.sessionReference ?? -1)
        }
        return .init(timeZoneIdentifier: self.range.calendar.timeZone.identifier,
            sinceDay: self.range.sinceKey, untilDay: self.range.untilKey, rowsComplete: self.complete, rows: rows)
    }

    private func includes(_ day: String) -> Bool {
        CostUsageScanner.CostUsageDayRange.isInRange(dayKey: day, since: self.range.sinceKey, until: self.range.untilKey)
    }
    private mutating func stop() { self.complete = false; self.exhausted = true }
}
