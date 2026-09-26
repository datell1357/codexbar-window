#if os(Windows)
import Foundation
import CodexBarCore

enum WindowsCodexModelTimeline {
    struct Sample: Sendable {
        let interval: DateInterval
        let clipped: Bool
        let tokens: Int?
        let tokensComplete: Bool
        let cost: Double?
        let costComplete: Bool
        let sessionReferences: Int?
        let sessionsComplete: Bool
    }
    private struct Bucket {
        var start: Date
        var end: Date
        let full: DateInterval
        var tokens = WindowsCodexModelAnalysis.Count()
        var cost = WindowsCodexModelAnalysis.Amount()
        var sessions: [String: Set<WindowsCodexActivityAnalysis.Reference>] = [:]
        var sawSessions = false
        var sessionsComplete = true
    }

    /// Calendar groups use the selected collection time zone; weeks start Monday.
    /// The first/last groups are clipped to the requested interval, never padded with inferred data.
    static func build(_ value: WindowsCodexModelAnalysis.Snapshot, model: String?,
                      granularity: String, calendar: Calendar) -> [Sample] {
        guard ["daily", "weekly", "monthly"].contains(granularity) else { return [] }
        let period = value.current
        guard period.boundaryAligned else { return [] }
        var groupingCalendar = calendar
        groupingCalendar.firstWeekday = 2
        groupingCalendar.minimumDaysInFirstWeek = 4
        let component: Calendar.Component = granularity == "weekly" ? .weekOfYear : granularity == "monthly" ? .month : .day
        var buckets: [Date: Bucket] = [:]
        var day = period.interval.start
        var visited = 0
        while day < period.interval.end {
            guard visited < WindowsSpendHistoryPolicy.scanDays,
                  let next = calendar.date(byAdding: .day, value: 1, to: day), next > day,
                  let full = groupingCalendar.dateInterval(of: component, for: day) else { return [] }
            visited += 1
            var bucket = buckets[full.start] ?? Bucket(start: day, end: next, full: full)
            bucket.end = min(next, period.interval.end)
            for (name, totals) in period.dailyModels[day] ?? [:] where model == nil || name == model {
                bucket.tokens.add(totals.tokens.value)
                if !totals.tokens.complete { bucket.tokens.add(nil) }
                bucket.cost.add(totals.cost.value)
                if !totals.cost.complete { bucket.cost.add(nil) }
            }
            let key = WindowsAppSpendProjection.dayKey(day, calendar: calendar)
            for (name, activity) in period.activity.byDay[key] ?? [:] where model == nil || name == model {
                bucket.sawSessions = true
                bucket.sessions[name, default: []].formUnion(activity.sessions)
                bucket.sessionsComplete = bucket.sessionsComplete && activity.sessionsComplete
            }
            buckets[full.start] = bucket
            day = next
        }
        return buckets.keys.sorted().compactMap { key in
            guard let bucket = buckets[key] else { return nil }
            var references = 0
            var overflow = false
            for values in bucket.sessions.values {
                let sum = references.addingReportingOverflow(values.count)
                if sum.overflow { overflow = true; break }
                references = sum.partialValue
            }
            let sessionsComplete = period.tokensComplete && period.activity.complete
                && bucket.sessionsComplete && !overflow
            let sessionsKnown = !overflow && (sessionsComplete
                || (bucket.sawSessions && (references > 0 || bucket.sessionsComplete)))
            return Sample(interval: .init(start: bucket.start, end: bucket.end),
                clipped: bucket.start != bucket.full.start || bucket.end != bucket.full.end,
                tokens: bucket.tokens.value ?? (period.tokensComplete ? 0 : nil),
                tokensComplete: period.tokensComplete && bucket.tokens.complete,
                cost: bucket.cost.value ?? (period.costComplete ? 0 : nil),
                costComplete: period.costComplete && bucket.cost.complete,
                sessionReferences: sessionsKnown ? references : nil, sessionsComplete: sessionsComplete)
        }
    }
}
#endif
