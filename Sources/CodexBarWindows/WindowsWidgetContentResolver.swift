#if os(Windows)
import CodexBarCore
import Foundation

/// Pure selection/freshness policy used before native widget rendering. Performs no I/O or fallback saves.
public enum WindowsWidgetContentResolver {
    public enum State: String, Sendable {
        case missingSnapshot, empty, disabled, stale, ready
    }
    public enum Failure: Error, Sendable { case invalidClockPolicy, invalidSnapshot, missingInstance }
    public struct Content: Sendable {
        public let instance: WindowsWidgetConfiguration.Instance
        public let provider: UsageProvider
        public let availableProviders: [UsageProvider]
        public let entry: WidgetSnapshot.ProviderEntry?
        public let state: State
        public let showUsed: Bool
        public let metricIsStale: Bool
    }

    public static func resolve(
        instanceID: String, configuration: WindowsWidgetConfiguration, snapshot: WidgetSnapshot?,
        now: Date, maximumAge: TimeInterval, clockSkewTolerance: TimeInterval = 60) throws -> Content
    {
        try configuration.validate()
        guard now.timeIntervalSince1970.isFinite, maximumAge.isFinite, maximumAge > 0,
              clockSkewTolerance.isFinite, clockSkewTolerance >= 0 else { throw Failure.invalidClockPolicy }
        guard let instance = configuration.instances.first(where: { $0.id == instanceID }) else {
            throw Failure.missingInstance
        }
        let configured = try configuration.selectedProvider(for: instanceID)
        guard let snapshot else {
            return Content(instance: instance, provider: configured, availableProviders: [], entry: nil,
                state: .missingSnapshot, showUsed: false, metricIsStale: false)
        }
        guard snapshot.entries.count <= 256, snapshot.enabledProviders.count <= 256,
              snapshot.generatedAt.timeIntervalSince1970.isFinite,
              snapshot.generatedAt.timeIntervalSince(now) <= clockSkewTolerance else { throw Failure.invalidSnapshot }
        var identities = Set<String>()
        for entry in snapshot.entries {
            guard identities.insert(entry.provider.rawValue).inserted,
                  entry.updatedAt.timeIntervalSince1970.isFinite,
                  entry.updatedAt.timeIntervalSince(now) <= clockSkewTolerance else { throw Failure.invalidSnapshot }
        }
        // Matches the original legacy snapshot fallback when enabledProviders was not populated.
        let enabled = snapshot.enabledProviders.isEmpty ? snapshot.entries.map(\.provider) : snapshot.enabledProviders
        var available: [UsageProvider] = []
        for id in enabled {
            guard let provider = id.firstPartyProvider,
                  WindowsWidgetConfiguration.providers(for: instance.kind).contains(provider),
                  !available.contains(provider) else { continue }
            available.append(provider)
        }
        let selected = instance.kind == .switcher && !available.contains(configured)
            ? (available.first ?? configured) : configured
        if !snapshot.enabledProviders.isEmpty, !enabled.contains(selected.instanceID) {
            return Content(instance: instance, provider: selected, availableProviders: available, entry: nil,
                state: .disabled, showUsed: snapshot.usageBarsShowUsed, metricIsStale: false)
        }
        guard let entry = snapshot.entries.first(where: { $0.provider == selected.instanceID }) else {
            return Content(instance: instance, provider: selected, availableProviders: available, entry: nil,
                state: .empty, showUsed: snapshot.usageBarsShowUsed, metricIsStale: false)
        }
        let stale = now.timeIntervalSince(snapshot.generatedAt) > maximumAge || now.timeIntervalSince(entry.updatedAt) > maximumAge
        // Cost data has its own update time; quota refresh must not make old cost data look fresh.
        let metricIsStale: Bool
        let extraBalance = instance.metric == .credits && selected == .devin && entry.providerCost?.period == "Extra usage balance"
        let metricTimestamp = extraBalance ? entry.providerCost?.updatedAt : entry.tokenUsage?.updatedAt
        if let timestamp = metricTimestamp {
            metricIsStale = !timestamp.timeIntervalSince1970.isFinite || timestamp.timeIntervalSince(now) > clockSkewTolerance ||
                now.timeIntervalSince(timestamp) > maximumAge ||
                (!extraBalance && (entry.tokenUsage?.isStale(comparedTo: entry.updatedAt) ?? false))
        } else {
            metricIsStale = stale
        }
        return Content(instance: instance, provider: selected, availableProviders: available, entry: entry,
            state: stale ? .stale : .ready, showUsed: snapshot.usageBarsShowUsed, metricIsStale: metricIsStale)
    }
}
#endif
