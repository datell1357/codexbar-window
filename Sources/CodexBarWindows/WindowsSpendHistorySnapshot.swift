#if os(Windows)
import Foundation
import CodexBarCore

public struct WindowsSpendHistorySnapshot: Sendable {
    public struct Segment: Sendable {
        let start: Double
        let end: Double
        let paletteIndex: Int
    }
    public struct ActivityCell: Sendable {
        let row: Int
        let column: Int
        let level: Int
    }
    public struct Day: Sendable {
        var activity: ActivityCell? = nil
        var date: Date? = nil
        let label: String
        let segments: [Segment]
        let details: String
    }
    public struct Legend: Sendable {
        let paletteIndex: Int
        let caption: String
    }
    public struct Series: Sendable {
        let legend: [Legend]
        let code: String
        let days: [Day]
        let maximum: Double
        let maximumLabel: String
        let summary: String
    }
    enum Kind: Sendable { case cost, tokens, hourly }
    var generation: UInt64 = 0
    var preferredSeriesCode: String? = nil
    var kind: Kind = .cost
    let series: [Series]
    var title: String { switch self.kind { case .cost: "Cost history"; case .tokens: "Token activity"; case .hourly: "Hourly cost history" } }

    static func hourly(_ snapshot: WindowsSpendDashboardController.Snapshot, day: Date) -> Self {
        let daily = Self.make(snapshot)
        let series = snapshot.model.groups.map { group -> Series in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = group.timeZone
            let indices = Dictionary(uniqueKeysWithValues: group.providers.enumerated().map { ($0.element.id, $0.offset) })
            let start = calendar.startOfDay(for: day)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            let formatter = DateFormatter()
            formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "HH:mm XXX"
            var cursor = start
            var slots: [Day] = []
            while cursor < end, slots.count < 26 {
                guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor), next > cursor else { break }
                let rows = group.hourlyPoints.filter { $0.hour >= cursor && $0.hour < min(next, end) && $0.cost.isFinite && $0.cost >= 0 }
                    .sorted { $0.sourceID < $1.sourceID }
                var segments: [Segment] = []
                var subtotal = 0.0
                var details = [WindowsShareStatsFormatting.dataThrough(cursor, calendar: calendar) + " · " + formatter.string(from: cursor)]
                for row in rows {
                    let old = subtotal
                    subtotal += row.cost
                    guard subtotal.isFinite else { segments.removeAll(); break }
                    segments.append(.init(start: old, end: subtotal, paletteIndex: indices[row.sourceID] ?? 0))
                    details.append(LogRedactor.redact(row.providerName).replacingOccurrences(of: "\0", with: "")
                        + ": " + WindowsShareStatsFormatting.currency(row.cost, code: group.currencyCode))
                }
                if rows.isEmpty { details.append("No known hourly samples. This is not a confirmed zero.") }
                else if subtotal.isFinite { details.append("Known subtotal: " + WindowsShareStatsFormatting.currency(subtotal, code: group.currencyCode)) }
                else { details.append("The known hourly subtotal is unavailable because it overflowed.") }
                slots.append(Day(date: cursor, label: formatter.string(from: cursor), segments: segments, details: details.joined(separator: "\r\n")))
                cursor = next
            }
            let maximum = max(1, slots.flatMap(\.segments).map(\.end).max() ?? 0)
            let summary = "Hourly costs · " + group.currencyCode + " · " + WindowsShareStatsFormatting.dataThrough(day, calendar: calendar)
                + "\r\n" + WindowsSpendSummary.accountingDetails(group).joined(separator: "\r\n")
                + "\r\n" + group.timeZone.identifier + " · source hour samples are grouped into local hour intervals."
                + "\r\nMissing samples are not zero; hourly totals may not explain the full daily total. UTC offsets distinguish repeated clock hours."
                + (snapshot.stale ? "\r\nStale data: this view uses the previous collection while a refresh is pending or failed." : "")
                + (snapshot.openCodexObservation == .unavailable ? "\r\nOpenCodeX logs are unavailable; this collection is partial." : "")
                + (snapshot.sourceFailures.isEmpty ? "" : "\r\nPartial collection: \(snapshot.sourceFailures.count) failed source(s).")
            return Series(legend: daily.series.first { $0.code == group.currencyCode }?.legend ?? [], code: group.currencyCode,
                          days: slots, maximum: maximum, maximumLabel: WindowsShareStatsFormatting.currency(maximum, code: group.currencyCode), summary: summary)
        }
        return Self(kind: .hourly, series: series)
    }

    static func tokenActivity(_ snapshot: WindowsSpendDashboardController.Snapshot, calendar: Calendar) -> Self {
        let points = snapshot.model.tokenActivity.sorted { $0.day < $1.day }
        guard let first = points.first else { return Self(kind: .tokens, series: []) }
        let weekday = (calendar.component(.weekday, from: first.day) + 5) % 7
        let maximum = max(1, points.compactMap(\.totalTokens).max() ?? 0)
        let days = points.compactMap { point -> Day? in
            guard let offset = calendar.dateComponents([.day], from: first.day, to: point.day).day, offset >= 0 else { return nil }
            let level: Int
            let status: String
            if !point.isScanned {
                level = 0; status = "Not scanned. No activity conclusion can be drawn."
            } else if let tokens = point.totalTokens, tokens >= 0 {
                if tokens == 0 { level = 2 }
                else { level = 2 + max(1, min(4, Int(ceil(log1p(Double(tokens)) / log1p(Double(maximum)) * 4)))) }
                status = tokens.formatted(.number.grouping(.automatic)) + " tracked tokens"
            } else {
                level = 1; status = "Scanned, but token count is unknown."
            }
            let label = WindowsShareStatsFormatting.dataThrough(point.day, calendar: calendar)
            return Day(activity: .init(row: (offset + weekday) % 7, column: (offset + weekday) / 7, level: level),
                       label: label, segments: [], details: label + "\r\n" + status)
        }
        var summary = "Token activity · last \(points.count) days · " + calendar.timeZone.identifier
        if snapshot.stale { summary += "\r\nStale data: this view uses the previous collection while a refresh is pending or failed." }
        summary += "\r\nRows run Monday to Sunday; columns are weeks. Unscanned, unknown and confirmed zero have distinct cells."
        summary += "\r\nGreen intensity is logarithmic relative to the largest known day. Select a day for its exact tracked count."
        summary += "\r\nTracked counts include scanned sources; sources without coverage may be absent."
        if snapshot.openCodexObservation == .unavailable { summary += "\r\nOpenCodeX logs are unavailable; this collection is partial." }
        if !snapshot.sourceFailures.isEmpty { summary += "\r\nPartial collection: \(snapshot.sourceFailures.count) failed source(s) are excluded." }
        return Self(kind: .tokens, series: [Series(legend: [], code: "Tokens", days: days, maximum: Double(maximum),
                                                   maximumLabel: maximum.formatted(), summary: summary)])
    }

    static func make(_ snapshot: WindowsSpendDashboardController.Snapshot) -> Self {
        let currencies = snapshot.model.groups.map { group in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = group.timeZone
            let indices = Dictionary(uniqueKeysWithValues: group.providers.enumerated().map { ($0.element.id, $0.offset) })
            let legend = (0..<6).compactMap { color -> Legend? in
                let names = group.providers.enumerated().filter { $0.offset % 6 == color }.map { entry in
                    String(LogRedactor.redact(entry.element.displayName).unicodeScalars
                        .filter { $0.value >= 0x20 && $0.value != 0x7F }.map(String.init).joined().prefix(160))
                }
                return names.isEmpty ? nil : Legend(paletteIndex: color, caption: names.joined(separator: ", "))
            }
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
                return Day(date: date, label: label, segments: segments, details: details.joined(separator: "\r\n"))
            }
            let maximum = max(1, days.flatMap(\.segments).map(\.end).max() ?? 0)
            let total = group.totalCost.map { WindowsShareStatsFormatting.currency($0, code: group.currencyCode) } ?? "Unknown"
            var summary = ["Cost history · " + group.currencyCode,
                           "Period total: " + (group.hasPartialCost ? "~" : "") + total,
                           "Covered days: \(group.coveredDayCount) / \(snapshot.model.requestedDays) · " + group.timeZone.identifier,
                           "Bars show known contributions; missing sources can make a daily bar incomplete. Gray ticks indicate no known sample.",
                           "Select a day with the chart or Previous/Next day buttons. All days clears the selection. Use currency buttons to switch groups.",
                           "Legend colors may group multiple sources; the selected-day text lists exact contributions."]
            summary.append(contentsOf: legend.map { "Color group \($0.paletteIndex + 1): " + $0.caption })
            if snapshot.openCodexObservation == .unavailable { summary.append("OpenCodeX logs are unavailable; this collection is partial.") }
            if !snapshot.sourceFailures.isEmpty { summary.append("Partial collection: \(snapshot.sourceFailures.count) source(s) failed.") }
            if snapshot.stale { summary.append("Stale collection.") }
            summary.append(contentsOf: WindowsSpendSummary.accountingDetails(group))
            return Series(legend: legend, code: group.currencyCode, days: days, maximum: maximum,
                            maximumLabel: WindowsShareStatsFormatting.currency(maximum, code: group.currencyCode),
                            summary: summary.joined(separator: "\r\n"))
        }
        return Self(series: currencies)
    }
}
#endif
