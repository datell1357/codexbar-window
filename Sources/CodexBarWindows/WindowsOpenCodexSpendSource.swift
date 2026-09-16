#if os(Windows)
import Foundation
import CodexBarCore

/// Ports the original subscription fan-out and native-source merge rules.
enum WindowsOpenCodexSpendSource {
    enum Observation: Sendable { case disabled, available, confirmedEmpty, unavailable }

    struct Inventory: Sendable {
        let snapshots: [UsageProvider: CostUsageTokenSnapshot]
        let observation: Observation
    }

    static func capture(settings: WindowsSpendSettings, environment: [String: String], cacheRoot: URL,
                        now: Date, historyDays: Int) throws -> Inventory {
        let rootID = WindowsSpendDashboardModel.openCodexSourceID
        guard settings.openCodexUsageLogsEnabled, !settings.hiddenSourceIDs.contains(rootID) else {
            return Inventory(snapshots: [:], observation: .disabled)
        }
        guard let url = OpenCodexUsageLog.usageLogURL(environment: environment) else {
            return Inventory(snapshots: [:], observation: .unavailable)
        }
        try Task.checkCancellation()
        let entries: [OpenCodexUsageEntry]
        do { entries = try OpenCodexUsageStore(cacheRoot: cacheRoot).loadEntries(logURL: url) }
        catch {
            try Task.checkCancellation()
            return Inventory(snapshots: [:], observation: .unavailable)
        }
        try Task.checkCancellation()
        let snapshots = OpenCodexUsageFanOut.snapshotsBySubscription(entries: entries, now: now,
            historyDays: historyDays, calendar: settings.bucketCalendar)
        let available = snapshots.values.contains { !$0.daily.isEmpty || !$0.sessions.isEmpty }
        return Inventory(snapshots: snapshots, observation: available ? .available : .confirmedEmpty)
    }

    static func merge(inputs: [WindowsSpendDashboardModel.ProviderInput], settings: WindowsSpendSettings,
                      environment: [String: String], cacheRoot: URL, now: Date,
                      historyDays: Int) throws -> (inputs: [WindowsSpendDashboardModel.ProviderInput], observation: Observation) {
        let inventory = try self.capture(settings: settings, environment: environment, cacheRoot: cacheRoot,
                                        now: now, historyDays: historyDays)
        return self.apply(inventory, to: inputs, settings: settings, now: now, historyDays: historyDays)
    }

    /// Reapply one captured supplement to native results, never to an already supplemented total.
    static func apply(_ inventory: Inventory, to inputs: [WindowsSpendDashboardModel.ProviderInput],
                      settings: WindowsSpendSettings, now: Date, historyDays: Int)
        -> (inputs: [WindowsSpendDashboardModel.ProviderInput], observation: Observation) {
        let rootID = WindowsSpendDashboardModel.openCodexSourceID
        guard inventory.observation == .available else {
            return (inputs.filter { $0.id != rootID }, inventory.observation)
        }
        let snapshots = inventory.snapshots
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
