import Foundation

// Ported from the original SessionEquivalentForecast.swift calculation.
// The caller must supply histories for one resolved owner and the matching window pair.

public struct SessionEquivalentBurnEstimateCore: Equatable, Sendable {
    public let medianWeeklyPercentPerWindow: Double
    public let sampleCount: Int
}

public struct SessionEquivalentForecastCore: Equatable, Sendable {
    public static let sessionWindowMinutes = 300
    public static let weeklyWindowMinutes = 10080
    public static let resetTolerance: TimeInterval = 2 * 60

    public let estimatedWindowsToExhaustWeekly: Double
    public let windowsUntilReset: Int
    public let availableWindowsUntilReset: Double
    public let sampleCount: Int
    public let weeklyResetsAt: Date
    public let weeklyUsedPercent: Double
    public let weeklyWindowID: String?

    /// Histories and their persisted pair identity must come from the same owner bucket.
    /// A missing estimate remains absent; it is never replaced with a fixed quota ratio.
    public static func make(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        histories: [PlanUtilizationHistoryCore.Series],
        persistedHistoryIdentity: String?,
        now: Date,
        workDays: Int?,
        calendar: Calendar = .current) -> Self?
    {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              let windows = PlanUtilizationHistoryProjection.forecastWindows(provider: provider, snapshot: snapshot),
              windows.session.resetsAt?.timeIntervalSinceReferenceDate.isFinite ?? true else { return nil }
        if ![UsageProvider.codex, .claude, .antigravity].contains(provider) {
            guard let identity = windows.historyIdentity, identity == persistedHistoryIdentity else { return nil }
        }
        guard let estimate = SessionEquivalentBurnEstimatorCore.estimate(histories: histories,
            currentSessionResetsAt: windows.session.resetsAt, now: now) else { return nil }
        return Self.make(sessionWindow: windows.session, weeklyWindow: windows.weekly, burnEstimate: estimate,
            weeklyWindowID: windows.weeklyWindowID, now: now, workDays: workDays, calendar: calendar)
    }

    public init(
        estimatedWindowsToExhaustWeekly: Double,
        windowsUntilReset: Int,
        availableWindowsUntilReset: Double? = nil,
        sampleCount: Int,
        weeklyResetsAt: Date,
        weeklyUsedPercent: Double,
        weeklyWindowID: String? = nil)
    {
        self.estimatedWindowsToExhaustWeekly = estimatedWindowsToExhaustWeekly
        self.windowsUntilReset = windowsUntilReset
        self.availableWindowsUntilReset = availableWindowsUntilReset ?? Double(windowsUntilReset)
        self.sampleCount = sampleCount
        self.weeklyResetsAt = weeklyResetsAt
        self.weeklyUsedPercent = weeklyUsedPercent
        self.weeklyWindowID = weeklyWindowID
    }

    public static func make(
        sessionWindow: RateWindow,
        weeklyWindow: RateWindow,
        burnEstimate: SessionEquivalentBurnEstimateCore,
        weeklyWindowID: String? = nil,
        now: Date,
        workDays: Int?,
        calendar: Calendar = .current) -> Self?
    {
        guard !sessionWindow.isSyntheticPlaceholder,
              sessionWindow.windowMinutes.map({ PlanUtilizationHistoryCore.canonicalMinutes($0, name: "session") })
              == self.sessionWindowMinutes,
              weeklyWindow.windowMinutes.map({ PlanUtilizationHistoryCore.canonicalMinutes($0, name: "weekly") })
              == self.weeklyWindowMinutes,
              let weeklyResetsAt = weeklyWindow.resetsAt,
              weeklyWindow.usedPercent.isFinite,
              (0...100).contains(weeklyWindow.usedPercent),
              burnEstimate.medianWeeklyPercentPerWindow.isFinite,
              burnEstimate.medianWeeklyPercentPerWindow > 0,
              burnEstimate.sampleCount >= SessionEquivalentBurnEstimatorCore.minimumSampleCount
        else {
            return nil
        }

        let sessionSeconds = TimeInterval(Self.sessionWindowMinutes * 60)
        let weeklySeconds = TimeInterval(Self.weeklyWindowMinutes * 60)
        if let sessionResetsAt = sessionWindow.resetsAt {
            let sessionRemaining = sessionResetsAt.timeIntervalSince(now)
            guard sessionRemaining.isFinite,
                  sessionRemaining > 0,
                  sessionRemaining <= sessionSeconds + Self.resetTolerance
            else {
                return nil
            }
        }

        let weeklyRemaining = weeklyResetsAt.timeIntervalSince(now)
        guard weeklyRemaining.isFinite,
              weeklyRemaining > 0,
              weeklyRemaining <= weeklySeconds + Self.resetTolerance
        else {
            return nil
        }

        let remainingWeeklyPercent = (100 - weeklyWindow.usedPercent).clamped(to: 0...100)
        guard remainingWeeklyPercent > 0 else { return nil }
        let estimatedWindows = remainingWeeklyPercent / burnEstimate.medianWeeklyPercentPerWindow
        guard estimatedWindows.isFinite, estimatedWindows >= 0 else { return nil }

        let remainingSeconds = Self.effectiveRemainingSeconds(
            from: now,
            to: weeklyResetsAt,
            workDays: workDays,
            calendar: calendar)
        guard remainingSeconds >= 0 else { return nil }
        let availableWindowsUntilReset = remainingSeconds / sessionSeconds
        let windowsUntilReset = Int(floor(availableWindowsUntilReset))

        return Self(
            estimatedWindowsToExhaustWeekly: estimatedWindows,
            windowsUntilReset: windowsUntilReset,
            availableWindowsUntilReset: availableWindowsUntilReset,
            sampleCount: burnEstimate.sampleCount,
            weeklyResetsAt: weeklyResetsAt,
            weeklyUsedPercent: weeklyWindow.usedPercent,
            weeklyWindowID: weeklyWindowID)
    }

    public func applies(to weeklyWindow: RateWindow, windowID: String?) -> Bool {
        guard weeklyWindow.windowMinutes.map({ PlanUtilizationHistoryCore.canonicalMinutes($0, name: "weekly") })
            == Self.weeklyWindowMinutes,
            let resetsAt = weeklyWindow.resetsAt
        else {
            return false
        }
        return self.weeklyWindowID == windowID
            && abs(resetsAt.timeIntervalSince(self.weeklyResetsAt)) < 2 * 60
            && abs(weeklyWindow.usedPercent - self.weeklyUsedPercent) < 0.001
    }

    private static func effectiveRemainingSeconds(
        from now: Date,
        to resetsAt: Date,
        workDays: Int?,
        calendar: Calendar) -> TimeInterval
    {
        let wallClockSeconds = max(0, resetsAt.timeIntervalSince(now))
        guard let workDays, workDays >= 2, workDays < 7 else { return wallClockSeconds }

        var workSeconds: TimeInterval = 0
        var cursor = now
        while cursor < resetsAt {
            guard let nextDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: cursor)),
                nextDay > cursor
            else {
                return wallClockSeconds
            }
            let sliceEnd = min(nextDay, resetsAt)
            if Self.isWorkday(cursor, workDays: workDays, calendar: calendar) {
                workSeconds += sliceEnd.timeIntervalSince(cursor)
            }
            cursor = sliceEnd
        }
        return workSeconds
    }

    private static func isWorkday(_ date: Date, workDays: Int, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let isoWeekday = weekday == 1 ? 7 : weekday - 1
        return isoWeekday <= workDays
    }
}

public enum SessionEquivalentBurnEstimatorCore {
    public static let defaultSampleLimit = 7
    public static let minimumSampleCount = 3
    private static let observationAlignmentTolerance: TimeInterval = 0
    private static let resetEquivalenceTolerance = SessionEquivalentForecastCore.resetTolerance

    private struct SessionGroup {
        let resetsAt: Date
        var entries: [PlanUtilizationHistoryCore.Entry]
        var maximumUsedPercent: Double
    }

    private struct BurnObservation {
        let sessionUsedPercent: Double
        let weeklyEntry: PlanUtilizationHistoryCore.Entry
    }

    public static func estimate(
        histories: [PlanUtilizationHistoryCore.Series],
        currentSessionResetsAt: Date?,
        now: Date,
        sampleLimit: Int = Self.defaultSampleLimit) -> SessionEquivalentBurnEstimateCore?
    {
        guard sampleLimit > 0,
              let sessionHistory = histories.first(where: {
                  $0.name == "session"
                      && PlanUtilizationHistoryCore.canonicalMinutes($0.windowMinutes, name: $0.name)
                      == SessionEquivalentForecastCore.sessionWindowMinutes
              }),
              let weeklyHistory = histories.first(where: {
                  $0.name == "weekly"
                      && PlanUtilizationHistoryCore.canonicalMinutes($0.windowMinutes, name: $0.name)
                      == SessionEquivalentForecastCore.weeklyWindowMinutes
              })
        else {
            return nil
        }

        let sessionDuration = TimeInterval(SessionEquivalentForecastCore.sessionWindowMinutes * 60)
        let weeklyDuration = TimeInterval(SessionEquivalentForecastCore.weeklyWindowMinutes * 60)
        guard Self.isChronologicallyOrdered(sessionHistory.entries),
              Self.isChronologicallyOrdered(weeklyHistory.entries)
        else {
            return nil
        }
        if let currentSessionResetsAt {
            let currentSessionRemaining = currentSessionResetsAt.timeIntervalSince(now)
            guard currentSessionRemaining.isFinite,
                  currentSessionRemaining > 0,
                  currentSessionRemaining <= sessionDuration + Self.resetEquivalenceTolerance
            else {
                return nil
            }
        }

        var groups: [SessionGroup] = []
        groups.reserveCapacity(sessionHistory.entries.count)
        for entry in sessionHistory.entries {
            guard entry.usedPercent.isFinite,
                  (0...100).contains(entry.usedPercent),
                  let resetsAt = entry.resetsAt,
                  Self.isPlausibleReset(
                      resetsAt,
                      capturedAt: entry.capturedAt,
                      duration: sessionDuration)
            else {
                continue
            }
            if let lastIndex = groups.indices.last,
               abs(groups[lastIndex].resetsAt.timeIntervalSince(resetsAt)) <= Self.resetEquivalenceTolerance
            {
                groups[lastIndex].entries.append(entry)
                groups[lastIndex].maximumUsedPercent = max(groups[lastIndex].maximumUsedPercent, entry.usedPercent)
            } else {
                guard groups.last.map({ $0.resetsAt <= resetsAt }) ?? true else { return nil }
                groups.append(SessionGroup(
                    resetsAt: resetsAt,
                    entries: [entry],
                    maximumUsedPercent: entry.usedPercent))
            }
        }

        let completedActiveGroups = groups.reversed().compactMap { group -> SessionGroup? in
            let precedesCurrentSession = currentSessionResetsAt.map {
                group.resetsAt < $0.addingTimeInterval(-Self.resetEquivalenceTolerance)
            } ?? true
            guard precedesCurrentSession,
                  group.resetsAt <= now,
                  group.maximumUsedPercent > 0
            else {
                return nil
            }
            return group
        }

        let weeklyEntries = weeklyHistory.entries.filter { entry in
            entry.usedPercent.isFinite
                && (0...100).contains(entry.usedPercent)
                && entry.resetsAt.map {
                    Self.isPlausibleReset($0, capturedAt: entry.capturedAt, duration: weeklyDuration)
                } == true
        }
        guard !weeklyEntries.isEmpty else { return nil }

        var burns: [Double] = []
        let candidateGroups = completedActiveGroups.prefix(sampleLimit)
        burns.reserveCapacity(candidateGroups.count)
        for group in candidateGroups {
            guard let fullAllowanceBurn = Self.normalizedBurn(
                for: group,
                weeklyEntries: weeklyEntries,
                sessionDuration: sessionDuration)
            else { continue }
            burns.append(fullAllowanceBurn)
        }

        guard burns.count >= Self.minimumSampleCount else { return nil }
        burns.sort()
        let middle = burns.count / 2
        let median = burns.count.isMultiple(of: 2)
            ? (burns[middle - 1] + burns[middle]) / 2
            : burns[middle]
        guard median.isFinite, median > 0 else { return nil }
        return SessionEquivalentBurnEstimateCore(
            medianWeeklyPercentPerWindow: median,
            sampleCount: burns.count)
    }

    private static func normalizedBurn(
        for group: SessionGroup,
        weeklyEntries: [PlanUtilizationHistoryCore.Entry],
        sessionDuration: TimeInterval) -> Double?
    {
        guard let firstSessionEntry = group.entries.first,
              let lastSessionEntry = group.entries.last
        else {
            return nil
        }

        var observations: [BurnObservation] = []
        let windowStart = group.resetsAt.addingTimeInterval(-sessionDuration)
        if let weeklyStart = Self.nearestEntry(
            to: windowStart,
            entries: weeklyEntries,
            tolerance: Self.resetEquivalenceTolerance,
            requireNotAfterTarget: true),
            weeklyStart.capturedAt <= windowStart,
            weeklyStart.capturedAt < firstSessionEntry.capturedAt
        {
            observations.append(BurnObservation(sessionUsedPercent: 0, weeklyEntry: weeklyStart))
        }

        for sessionEntry in group.entries {
            guard let weeklyEntry = Self.nearestEntry(
                to: sessionEntry.capturedAt,
                entries: weeklyEntries,
                tolerance: Self.observationAlignmentTolerance)
            else {
                continue
            }
            observations.append(BurnObservation(
                sessionUsedPercent: sessionEntry.usedPercent,
                weeklyEntry: weeklyEntry))
        }

        if group.maximumUsedPercent >= 100,
           let weeklyEnd = Self.nearestEntry(
               to: group.resetsAt,
               entries: weeklyEntries,
               tolerance: Self.resetEquivalenceTolerance,
               requireNotAfterTarget: true),
           weeklyEnd.capturedAt <= group.resetsAt,
           lastSessionEntry.capturedAt < weeklyEnd.capturedAt
        {
            observations.append(BurnObservation(sessionUsedPercent: 100, weeklyEntry: weeklyEnd))
        }

        observations.sort { lhs, rhs in
            if lhs.weeklyEntry.capturedAt != rhs.weeklyEntry.capturedAt {
                return lhs.weeklyEntry.capturedAt < rhs.weeklyEntry.capturedAt
            }
            return lhs.sessionUsedPercent < rhs.sessionUsedPercent
        }
        guard let start = observations.first,
              let end = observations.last,
              start.weeklyEntry.capturedAt < end.weeklyEntry.capturedAt,
              let startReset = start.weeklyEntry.resetsAt,
              let endReset = end.weeklyEntry.resetsAt,
              abs(startReset.timeIntervalSince(endReset)) <= Self.resetEquivalenceTolerance
        else {
            return nil
        }

        let sessionConsumption = end.sessionUsedPercent - start.sessionUsedPercent
        let weeklyBurn = end.weeklyEntry.usedPercent - start.weeklyEntry.usedPercent
        guard sessionConsumption.isFinite,
              sessionConsumption > 0,
              weeklyBurn.isFinite,
              weeklyBurn > 0
        else {
            return nil
        }
        let fullAllowanceBurn = 100 * weeklyBurn / sessionConsumption
        guard fullAllowanceBurn.isFinite, fullAllowanceBurn > 0 else { return nil }
        return fullAllowanceBurn
    }

    private static func nearestEntry(
        to target: Date,
        entries: [PlanUtilizationHistoryCore.Entry],
        tolerance: TimeInterval,
        requireNotAfterTarget: Bool = false) -> PlanUtilizationHistoryCore.Entry?
    {
        var lower = 0
        var upper = entries.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if entries[middle].capturedAt < target {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        var candidates: [PlanUtilizationHistoryCore.Entry] = []
        if lower < entries.count {
            candidates.append(entries[lower])
        }
        if lower > 0 {
            candidates.append(entries[lower - 1])
        }
        return candidates
            .filter { !requireNotAfterTarget || $0.capturedAt <= target }
            .filter { abs($0.capturedAt.timeIntervalSince(target)) <= tolerance }
            .min { lhs, rhs in
                abs(lhs.capturedAt.timeIntervalSince(target)) < abs(rhs.capturedAt.timeIntervalSince(target))
            }
    }

    private static func isChronologicallyOrdered(_ entries: [PlanUtilizationHistoryCore.Entry]) -> Bool {
        guard entries.allSatisfy(\.capturedAt.timeIntervalSinceReferenceDate.isFinite) else { return false }
        return zip(entries, entries.dropFirst()).allSatisfy { pair in
            pair.0.capturedAt <= pair.1.capturedAt
        }
    }

    private static func isPlausibleReset(
        _ resetsAt: Date,
        capturedAt: Date,
        duration: TimeInterval) -> Bool
    {
        let remaining = resetsAt.timeIntervalSince(capturedAt)
        return remaining.isFinite
            && remaining >= -Self.resetEquivalenceTolerance
            && remaining <= duration + Self.resetEquivalenceTolerance
    }
}
