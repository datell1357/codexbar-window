import Foundation

/// Reset-window chart projection shared by native consumers. The caller supplies histories
/// for one already-resolved owner; this layer never chooses or adopts an account bucket.
public enum PlanUtilizationHistoryChart {
    public static let maximumPoints = 30
    public static let maximumAxisLabels = 4

    public struct Point: Equatable, Sendable, Identifiable {
        /// Normalized period boundary, kept stable when the observed reset time drifts.
        public let id: Date
        public let index: Int
        /// Actual reset time when known, otherwise the inferred boundary.
        public let date: Date
        public let usedPercent: Double
        public let isObserved: Bool
        public let observedAt: Date?
    }

    public struct Series: Equatable, Sendable, Identifiable {
        public let name: String
        public let windowMinutes: Int
        public let points: [Point]
        public let axisIndexes: [Int]
        public var id: String { "\(self.name):\(self.windowMinutes)" }
        public var xDomain: ClosedRange<Double>? {
            self.points.isEmpty ? nil : -0.5...(Double(PlanUtilizationHistoryChart.maximumPoints) - 0.5)
        }
    }

    private struct Selection: Hashable {
        let name: String
        let minutes: Int
    }

    private struct Observation {
        let date: Date
        let capturedAt: Date
        let usedPercent: Double
        let hasReset: Bool
    }

    /// Mirrors the original chart's provider series normalization, current-window filtering,
    /// reset-boundary alignment, peak selection, missing periods and proportional date labels.
    public static func make(
        provider: UsageProvider,
        histories: [PlanUtilizationHistoryCore.Series],
        snapshot: UsageSnapshot? = nil,
        referenceDate: Date,
        calendar: Calendar = .current) throws -> [Series]
    {
        try PlanUtilizationHistoryCore.validate(histories)
        guard referenceDate.timeIntervalSince1970.isFinite else {
            throw PlanUtilizationHistoryCore.Failure.invalidData
        }
        let presentation = ProviderDescriptorRegistry.descriptor(for: provider).presentation
        let allowedNames: Set<String>? = snapshot.flatMap { snapshot in
            presentation.planUtilizationSeries(snapshot: snapshot).map { Set($0.map(self.historyName)) }
        }
        var grouped: [Selection: [PlanUtilizationHistoryCore.Entry]] = [:]
        for history in histories where !history.entries.isEmpty {
            let name = self.historyName(presentation.normalizePlanUtilizationSeries(
                self.providerSeries(history.name), windowMinutes: history.windowMinutes))
            guard allowedNames?.contains(name) ?? true else { continue }
            let minutes = PlanUtilizationHistoryCore.canonicalMinutes(history.windowMinutes, name: name)
            let selection = Selection(name: name, minutes: minutes)
            grouped[selection, default: []].append(contentsOf: history.entries)
        }
        return try grouped.keys.sorted { lhs, rhs in
            let leftOrder = self.sortOrder(lhs.name)
            let rightOrder = self.sortOrder(rhs.name)
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            if lhs.minutes != rhs.minutes { return lhs.minutes < rhs.minutes }
            return lhs.name < rhs.name
        }.map { selection in
            // Duplicate legacy lanes may normalize to the same monthly/session/weekly series.
            let entries = Array(Set(grouped[selection] ?? []))
            let points = try self.points(entries: entries, minutes: selection.minutes, referenceDate: referenceDate)
            return Series(name: selection.name, windowMinutes: selection.minutes, points: points,
                axisIndexes: self.axisIndexes(points: points, minutes: selection.minutes, calendar: calendar))
        }
    }

    private static func points(
        entries: [PlanUtilizationHistoryCore.Entry], minutes: Int, referenceDate: Date) throws -> [Point]
    {
        let interval = Double(minutes) * 60
        let referenceReset = entries.compactMap(\.resetsAt).map(self.normalizedDate).max()
        var observed: [Date: Observation] = [:]
        for entry in entries {
            let reset = entry.resetsAt.map(self.normalizedDate)
            let boundary: Date
            if let reset, let referenceReset {
                boundary = referenceReset.addingTimeInterval(
                    (reset.timeIntervalSince(referenceReset) / interval).rounded() * interval)
            } else if let reset {
                boundary = reset
            } else {
                boundary = self.periodBoundary(containing: entry.capturedAt, referenceReset: referenceReset, interval: interval)
            }
            guard boundary.timeIntervalSince1970.isFinite else { throw PlanUtilizationHistoryCore.Failure.invalidData }
            let candidate = Observation(date: reset ?? boundary, capturedAt: entry.capturedAt,
                usedPercent: max(0, min(100, entry.usedPercent)), hasReset: reset != nil)
            if let previous = observed[boundary], !self.prefer(candidate, over: previous) { continue }
            observed[boundary] = candidate
        }
        let boundaries = observed.keys.sorted()
        var points: [Point] = []
        var previous: Date?
        for boundary in boundaries {
            if let previous {
                try self.appendMissing(after: previous, through: boundary, inclusive: false,
                    interval: interval, points: &points)
            }
            if let observation = observed[boundary] {
                points.append(Point(id: boundary, index: 0, date: observation.date,
                    usedPercent: observation.usedPercent, isObserved: true, observedAt: observation.capturedAt))
                points = Array(points.suffix(self.maximumPoints))
            }
            previous = boundary
        }
        if let previous {
            let current = self.periodBoundary(containing: referenceDate, referenceReset: referenceReset, interval: interval)
            try self.appendMissing(after: previous, through: current, inclusive: true, interval: interval, points: &points)
        }
        return points.enumerated().map { index, point in
            Point(id: point.id, index: index, date: point.date, usedPercent: point.usedPercent,
                isObserved: point.isObserved, observedAt: point.observedAt)
        }
    }

    private static func normalizedDate(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
    }

    private static func periodBoundary(containing date: Date, referenceReset: Date?, interval: TimeInterval) -> Date {
        if let referenceReset {
            return referenceReset.addingTimeInterval(ceil(date.timeIntervalSince(referenceReset) / interval) * interval)
        }
        return Date(timeIntervalSince1970: (floor(date.timeIntervalSince1970 / interval) + 1) * interval)
    }

    private static func prefer(_ candidate: Observation, over existing: Observation) -> Bool {
        if candidate.usedPercent != existing.usedPercent { return candidate.usedPercent > existing.usedPercent }
        if candidate.hasReset != existing.hasReset { return candidate.hasReset }
        if candidate.date != existing.date { return candidate.date > existing.date }
        return candidate.capturedAt >= existing.capturedAt
    }

    /// Only generate the visible suffix. A dormant account may contain years of empty periods;
    /// iterating every period before taking the last 30 would allocate unbounded intermediate data.
    private static func appendMissing(
        after start: Date, through end: Date, inclusive: Bool, interval: TimeInterval, points: inout [Point]) throws
    {
        let distance = end.timeIntervalSince(start) / interval
        guard distance.isFinite else { throw PlanUtilizationHistoryCore.Failure.invalidData }
        let count = inclusive ? floor(distance) : ceil(distance) - 1
        guard count > 0 else { return }
        let visibleCount = Int(min(Double(self.maximumPoints), count))
        if count >= Double(self.maximumPoints) { points.removeAll(keepingCapacity: true) }
        for index in 0..<visibleCount {
            let offset = count - Double(visibleCount) + 1 + Double(index)
            let boundary = start.addingTimeInterval(offset * interval)
            guard boundary.timeIntervalSince1970.isFinite, boundary > start,
                  points.last.map({ boundary > $0.id }) ?? true else {
                throw PlanUtilizationHistoryCore.Failure.invalidData
            }
            points.append(Point(id: boundary, index: 0, date: boundary, usedPercent: 0,
                isObserved: false, observedAt: nil))
        }
        points = Array(points.suffix(self.maximumPoints))
    }

    private static func axisIndexes(points: [Point], minutes: Int, calendar: Calendar) -> [Int] {
        guard let first = points.first else { return [] }
        var candidates = [first.index]
        for index in 1..<points.count {
            if minutes > 300 || !calendar.isDate(points[index].date, inSameDayAs: points[index - 1].date) {
                candidates.append(points[index].index)
            }
        }
        let proportionalBudget = Int(ceil(Double(self.maximumAxisLabels) * Double(points.count) / Double(self.maximumPoints)))
        let budget = max(1, min(self.maximumAxisLabels, proportionalBudget, candidates.count))
        guard budget > 1 else { return [candidates[0]] }
        let step = Double(candidates.count - 1) / Double(budget - 1)
        var selected: [Int] = []
        for position in 0..<budget {
            let index = candidates[Int((Double(position) * step).rounded())]
            if !selected.contains(index) { selected.append(index) }
        }
        let trailingCutoff = first.index + Int(floor(Double(points.count) * 0.8))
        if selected.count > 1, let last = selected.last, last >= trailingCutoff { selected.removeLast() }
        if points.count == self.maximumPoints, let last = points.last?.index, !selected.contains(last) {
            selected.append(last)
        }
        return selected
    }

    private static func providerSeries(_ name: String) -> ProviderPlanUtilizationSeries {
        switch name {
        case "session": .session
        case "monthly": .monthly
        case "opus": .tertiary
        default: .weekly
        }
    }

    private static func historyName(_ series: ProviderPlanUtilizationSeries) -> String {
        switch series {
        case .session: "session"
        case .weekly: "weekly"
        case .monthly: "monthly"
        case .tertiary: "opus"
        }
    }

    private static func sortOrder(_ name: String) -> Int {
        switch name {
        case "session": 0
        case "weekly": 1
        case "monthly", "opus": 2
        default: 100
        }
    }
}
