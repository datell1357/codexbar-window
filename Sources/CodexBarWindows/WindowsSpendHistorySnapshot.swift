#if os(Windows)
import Foundation
import CodexBarCore

public struct WindowsSpendHistorySnapshot: Sendable {
    public struct Segment: Sendable {
        let start: Double
        let end: Double
        let paletteIndex: Int
    }
    public struct Day: Sendable {
        let label: String
        let segments: [Segment]
        let details: String
    }
    public struct Currency: Sendable {
        let code: String
        let days: [Day]
        let maximum: Double
        let maximumLabel: String
        let summary: String
    }
    let currencies: [Currency]

    static func make(_ snapshot: WindowsSpendDashboardController.Snapshot) -> Self {
        let currencies = snapshot.model.groups.map { group in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = group.timeZone
            let indices = Dictionary(uniqueKeysWithValues: group.providers.enumerated().map { ($0.element.id, $0.offset) })
            let points = Dictionary(grouping: group.dailyPoints, by: { calendar.startOfDay(for: $0.day) })
            let days = (0..<snapshot.model.requestedDays).compactMap { offset -> Day? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: group.chartDomain.lowerBound) else { return nil }
                let label = WindowsShareStatsFormatting.dataThrough(date, calendar: calendar)
                let rows = (points[date] ?? []).filter { $0.stackStart.isFinite && $0.stackEnd.isFinite && $0.stackStart >= 0 && $0.stackEnd >= $0.stackStart }
                let segments = rows.map { Segment(start: $0.stackStart, end: $0.stackEnd, paletteIndex: indices[$0.sourceID] ?? 0) }
                var details = [label]
                if rows.isEmpty { details.append("No known cost samples. This is not a confirmed zero.") }
                for row in rows {
                    let name = LogRedactor.redact(row.providerName).replacingOccurrences(of: "\0", with: "")
                    details.append(name + ": " + WindowsShareStatsFormatting.currency(row.cost, code: group.currencyCode))
                }
                if let maximum = rows.map(\.stackEnd).max() {
                    details.append("Known subtotal: " + WindowsShareStatsFormatting.currency(maximum, code: group.currencyCode))
                }
                return Day(label: label, segments: segments, details: details.joined(separator: "\r\n"))
            }
            let maximum = max(1, days.flatMap(\.segments).map(\.end).max() ?? 0)
            let total = group.totalCost.map { WindowsShareStatsFormatting.currency($0, code: group.currencyCode) } ?? "Unknown"
            var summary = ["Cost history · " + group.currencyCode,
                           "Period total: " + total,
                           "Covered days: \(group.coveredDayCount) / \(snapshot.model.requestedDays) · " + group.timeZone.identifier,
                           "Bars show known contributions; missing sources can make a daily bar incomplete. Gray ticks indicate no known sample.",
                           "Click a day to inspect it. Use the currency buttons to switch groups. Refresh closes this captured view."]
            if !snapshot.sourceFailures.isEmpty { summary.append("Partial collection: \(snapshot.sourceFailures.count) source(s) failed.") }
            if snapshot.stale { summary.append("Stale collection.") }
            return Currency(code: group.currencyCode, days: days, maximum: maximum,
                            maximumLabel: WindowsShareStatsFormatting.currency(maximum, code: group.currencyCode),
                            summary: summary.joined(separator: "\r\n"))
        }
        return Self(currencies: currencies)
    }
}
#endif
