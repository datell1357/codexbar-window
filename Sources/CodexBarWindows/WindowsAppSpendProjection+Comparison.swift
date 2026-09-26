#if os(Windows)
import Foundation
import CodexBarCore

extension WindowsAppSpendProjection {
    struct ComparisonRow: Codable, Sendable {
        let days: Int
        let title: String
        let range: String
        let cost: String
        let tokens: String
        let coverage: String
        let details: String
    }

    /// Same-end-date rolling windows, matching the original cost comparison summaries.
    /// No previous-period percentage is inferred from overlapping windows or incomplete history.
    static func comparisons(snapshot: WindowsSpendDashboardController.Snapshot,
                            periods: [WindowsSpendDashboardController.Snapshot], currency: String?,
                            calendar: Calendar, text: (String, Int) -> String) -> [ComparisonRow] {
        let currentGroup = snapshot.model.groups.first { $0.currencyCode == currency }
        let expectedSources = currentGroup.map { Set($0.providers.map(\.id)) }
        return [7, 30, 90, WindowsSpendHistoryPolicy.scanDays].map { days in
            let candidates = periods.filter { $0.model.requestedDays == days }
            let candidate = candidates.count == 1 ? candidates.first : nil
            let group = candidate?.model.groups.first { $0.currencyCode == currency }
            var bucketCalendar = calendar
            if let currentGroup { bucketCalendar.timeZone = currentGroup.timeZone }
            let expectedStart = currentGroup.flatMap {
                bucketCalendar.date(byAdding: .day, value: -days, to: $0.chartDomain.upperBound)
            }
            let available = candidate?.publicationSequence == snapshot.publicationSequence
                && candidate?.generation == snapshot.generation && candidate?.loadedAt == snapshot.loadedAt
                && candidate?.model.availableSources == snapshot.model.availableSources
                && group != nil && currentGroup != nil && group?.timeZone == currentGroup?.timeZone
                && group?.providers.isEmpty == false && group?.providers.count == expectedSources?.count
                && group?.chartDomain.lowerBound == expectedStart
                && group?.chartDomain.upperBound == currentGroup?.chartDomain.upperBound
                && group.map { Set($0.providers.map(\.id)) } == expectedSources
            var range = "Collection date unavailable"
            let exclusiveEnd = currentGroup?.chartDomain.upperBound
                ?? snapshot.loadedAt.flatMap { bucketCalendar.date(byAdding: .day, value: 1, to: bucketCalendar.startOfDay(for: $0)) }
            if let exclusiveEnd,
               let start = bucketCalendar.date(byAdding: .day, value: -days, to: exclusiveEnd),
               let last = bucketCalendar.date(byAdding: .day, value: -1, to: exclusiveEnd) {
                range = Self.dayKey(start, calendar: bucketCalendar) + " – " + Self.dayKey(last, calendar: bucketCalendar)
                    + " · " + bucketCalendar.timeZone.identifier
            }
            var cost = "Unknown"
            var tokens = "Unknown"
            var coverage = "No matching currency/source data is available for this window."
            var details = ["These rolling windows overlap and end on the collection date.",
                           "A longer window does not mean its entire history was collected."]
            if available, let group {
                let total = group.providers.count
                let full = group.providers.count { $0.coveredDayCount >= days }
                let priced = group.providers.count { $0.totalCost.map { $0.isFinite && $0 >= 0 } == true }
                let counted = group.providers.count { $0.totalTokens.map { $0 >= 0 } == true }
                let incompleteCoverage = full < total
                if let amount = group.totalCost, amount.isFinite, amount >= 0 {
                    cost = (group.hasPartialCost || incompleteCoverage ? "~" : "")
                        + WindowsShareStatsFormatting.currency(amount, code: group.currencyCode)
                }
                if let count = group.totalTokens, count >= 0 {
                    tokens = (group.hasPartialTokens || incompleteCoverage ? "~" : "") + count.formatted()
                }
                coverage = "Full-period source coverage: \(full) / \(total) · Cost known: \(priced) / \(total)"
                    + " · Tokens known: \(counted) / \(total)"
                details.append(contentsOf: WindowsSpendSummary.accountingDetails(group))
                if incompleteCoverage || group.hasPartialCost || group.hasPartialTokens {
                    details.append("~ marks a known subtotal with incomplete source or date coverage; missing values are not zero.")
                }
                if snapshot.stale || candidate?.stale == true { details.append("Stale collection: values may come from an earlier successful capture.") }
                if !snapshot.sourceFailures.isEmpty || candidate?.sourceFailures.isEmpty == false {
                    details.append("Partial collection: some sources are pending or unavailable.")
                }
                if snapshot.openCodexObservation == .unavailable || candidate?.openCodexObservation == .unavailable {
                    details.append("OpenCodeX logs are unavailable.")
                }
            } else { details.append("Comparison data is unavailable for this collection.") }
            return ComparisonRow(days: days, title: text("Last \(days) days", 96), range: text(range, 256),
                cost: text(cost, 128), tokens: text(tokens, 128), coverage: text(coverage, 512),
                details: text(details.joined(separator: "\n"), 2048))
        }
    }
}
#endif
