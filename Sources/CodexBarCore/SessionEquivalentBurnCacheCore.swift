import Foundation

/// Caches only a learned burn value. The caller must re-read the selected history revision;
/// current quota, reset countdown and workday settings are applied on every forecast request.
public struct SessionEquivalentBurnCacheCore: Sendable {
    private struct Key: Equatable, Sendable {
        let provider: UsageProvider
        let historyRevision: Data?
        let selectionIdentity: String
        let pairIdentity: String?
        let currentSessionResetsAt: Date?
        let weeklyWindowID: String?
        let idleMinute: Int64?
    }
    private struct Entry: Sendable {
        let key: Key
        let estimate: SessionEquivalentBurnEstimateCore?
    }
    private var entry: Entry?

    public init() {}

    public mutating func clear() { self.entry = nil }

    public mutating func forecast(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        histories: [PlanUtilizationHistoryCore.Series],
        historyRevision: Data?,
        selectionIdentity: String,
        persistedHistoryIdentity: String?,
        now: Date,
        workDays: Int?,
        calendar: Calendar = .current) -> SessionEquivalentForecastCore?
    {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              let windows = PlanUtilizationHistoryProjection.forecastWindows(provider: provider, snapshot: snapshot),
              windows.session.resetsAt?.timeIntervalSinceReferenceDate.isFinite ?? true else {
            self.clear(); return nil
        }
        if ![UsageProvider.codex, .claude, .antigravity].contains(provider) {
            guard let identity = windows.historyIdentity, identity == persistedHistoryIdentity else {
                self.clear(); return nil
            }
        }
        let idleMinute: Int64?
        if windows.session.resetsAt == nil {
            guard let minute = Int64(exactly: floor(now.timeIntervalSinceReferenceDate / 60)) else {
                self.clear(); return nil
            }
            idleMinute = minute
        } else { idleMinute = nil }
        let key = Key(provider: provider, historyRevision: historyRevision, selectionIdentity: selectionIdentity,
            pairIdentity: windows.historyIdentity, currentSessionResetsAt: windows.session.resetsAt,
            weeklyWindowID: windows.weeklyWindowID, idleMinute: idleMinute)
        let estimate: SessionEquivalentBurnEstimateCore?
        if let entry = self.entry, entry.key == key {
            estimate = entry.estimate
        } else {
            estimate = SessionEquivalentBurnEstimatorCore.estimate(histories: histories,
                currentSessionResetsAt: windows.session.resetsAt, now: now)
            self.entry = Entry(key: key, estimate: estimate)
        }
        guard let estimate else { return nil }
        return SessionEquivalentForecastCore.make(sessionWindow: windows.session, weeklyWindow: windows.weekly,
            burnEstimate: estimate, weeklyWindowID: windows.weeklyWindowID, now: now,
            workDays: workDays, calendar: calendar)
    }
}
