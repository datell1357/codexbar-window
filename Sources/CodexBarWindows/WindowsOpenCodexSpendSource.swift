#if os(Windows)
import Foundation
import CodexBarCore

/// Ports the original subscription fan-out and native-source merge rules.
enum WindowsOpenCodexSpendSource {
    enum Observation: Sendable { case disabled, available, confirmedEmpty, unavailable }

    static func merge(inputs: [WindowsSpendDashboardModel.ProviderInput], settings: WindowsSpendSettings,
                      environment: [String: String], cacheRoot: URL, now: Date,
                      historyDays: Int) throws -> (inputs: [WindowsSpendDashboardModel.ProviderInput], observation: Observation) {
        let rootID = WindowsSpendDashboardModel.openCodexSourceID
        guard settings.openCodexUsageLogsEnabled, !settings.hiddenSourceIDs.contains(rootID) else {
            return (inputs.filter { $0.id != rootID }, .disabled)
        }
        guard let url = OpenCodexUsageLog.usageLogURL(environment: environment) else { return (inputs, .unavailable) }
        try Task.checkCancellation()
        let entries: [OpenCodexUsageEntry]
        do { entries = try OpenCodexUsageStore(cacheRoot: cacheRoot).loadEntries(logURL: url) }
        catch {
            try Task.checkCancellation()
            return (inputs, .unavailable)
        }
        try Task.checkCancellation()
        guard !entries.isEmpty else { return (inputs, .confirmedEmpty) }
        let snapshots = OpenCodexUsageFanOut.snapshotsBySubscription(entries: entries, now: now,
            historyDays: historyDays, calendar: settings.bucketCalendar)
        var merged = inputs.filter { $0.id != rootID }
        var published = false
        for provider in snapshots.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let supplement = snapshots[provider], !supplement.daily.isEmpty || !supplement.sessions.isEmpty else { continue }
            published = true
            let name = ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
            if provider == .codex, settings.hideNativeCodexWhenOpenCodexPresent {
                merged.append(.init(id: rootID, provider: provider, displayName: name,
                                    snapshot: supplement, sourceKind: .openCodex))
                continue
            }
            let matches = merged.indices.filter { merged[$0].provider == provider }
            let index: Int? = provider == .codex
                ? (matches.count == 1 ? matches.first : nil)
                : (matches.count == 1 ? matches.first : merged.firstIndex { $0.provider == provider && $0.sourceKind == .native })
            if let index {
                let base = merged[index]
                merged[index] = .init(id: base.id, provider: base.provider, displayName: base.displayName,
                    modelProviderName: base.modelProviderName,
                    snapshot: OpenCodexUsageFanOut.mergeSnapshots(base.snapshot, supplement, now: now,
                        historyDays: historyDays, calendar: settings.bucketCalendar),
                    tokenActivityCache: base.tokenActivityCache, sourceKind: base.sourceKind)
            } else {
                merged.append(.init(provider: provider, displayName: name, snapshot: supplement, sourceKind: .openCodex))
            }
        }
        return (merged, published ? .available : .confirmedEmpty)
    }
}
#endif
