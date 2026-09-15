#if os(Windows)
import CodexBarCore
import Foundation

/// Bounded chart projection preserving unavailable measurements separately from measured zero.
public struct WindowsWidgetHistory: Sendable {
    public enum Mode: Sendable { case cost, tokens }
    public enum Failure: Error, Sendable { case tooManyPoints, invalidDate, duplicateDate, invalidValue, excessiveDateRange }
    public struct Point: Sendable {
        public let dayKey: String
        /// Zero-based calendar slot, including missing dates between observations.
        public let dayOffset: Int
        public let value: Double?
        public let fraction: Double?
    }
    public let mode: Mode
    public let points: [Point]
    public let maximum: Double
    public let calendarDayCount: Int
    public var missingDayCount: Int { self.calendarDayCount - self.points.count }
    public let currencyCode: String?
    public let isStale: Bool

    public static func make(from content: WindowsWidgetContentResolver.Content) throws -> Self {
        let ordered = try validatedDailyUsage(content.entry?.dailyUsage ?? [])
        // Original widget uses cost only when every supplied point carries cost data.
        let costMode = !ordered.isEmpty && ordered.allSatisfy { $0.costUSD != nil }
        let values: [Double?] = ordered.map { costMode ? $0.costUSD : $0.totalTokens.map(Double.init) }
        let scale = UsageChartScale(values: values.compactMap { $0 })
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstDate = ordered.first.flatMap { parseDay($0.dayKey) }
        let points = try zip(ordered, values).map { point, value -> Point in
            guard let firstDate, let date = parseDay(point.dayKey),
                  let offset = calendar.dateComponents([.day], from: firstDate, to: date).day,
                  offset >= 0, offset < 366 else { throw Failure.excessiveDateRange }
            return Point(dayKey: point.dayKey, dayOffset: offset, value: value,
                fraction: value.map { scale.fraction(for: $0) })
        }
        let calendarDayCount = points.last.map { $0.dayOffset + 1 } ?? 0
        let code = content.entry?.tokenUsage?.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let validCurrency = code.flatMap { value -> String? in
            value.utf8.count == 3 && value.utf8.allSatisfy { (65...90).contains($0) } ? value : nil
        }
        return Self(mode: costMode ? .cost : .tokens, points: points, maximum: scale.maximum, calendarDayCount: calendarDayCount,
            currencyCode: costMode ? validCurrency : nil, isStale: content.metricIsStale || content.state == .stale)
    }

    /// Shared publication and chart boundary; missing observations remain absent.
    static func validatedDailyUsage(_ raw: [WidgetSnapshot.DailyUsagePoint]) throws -> [WidgetSnapshot.DailyUsagePoint] {
        guard raw.count <= 366 else { throw Failure.tooManyPoints }
        var dates = Set<String>()
        var parsedDates: [String: Date] = [:]
        for point in raw {
            guard let date = parseDay(point.dayKey) else { throw Failure.invalidDate }
            parsedDates[point.dayKey] = date
            guard dates.insert(point.dayKey).inserted else { throw Failure.duplicateDate }
            if let cost = point.costUSD, !cost.isFinite || cost < 0 { throw Failure.invalidValue }
            if let tokens = point.totalTokens, tokens < 0 { throw Failure.invalidValue }
        }
        let ordered = raw.sorted { $0.dayKey < $1.dayKey }
        if let first = ordered.first, let last = ordered.last,
           let firstDate = parsedDates[first.dayKey], let lastDate = parsedDates[last.dayKey] {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            guard let span = calendar.dateComponents([.day], from: firstDate, to: lastDate).day,
                  span >= 0, span < 366 else { throw Failure.excessiveDateRange }
        }
        return ordered
    }

    // Shared with card captions; day keys are calendar dates in UTC, not local timestamps.
    static func parseDay(_ value: String) -> Date? {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) })
        else { return nil }
        let pieces = value.split(separator: "-")
        guard pieces.count == 3, let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]),
              (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return nil }
        let result = calendar.dateComponents([.year, .month, .day], from: date)
        return result.year == year && result.month == month && result.day == day ? date : nil
    }
}
#endif
