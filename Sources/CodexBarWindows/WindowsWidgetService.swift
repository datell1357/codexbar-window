#if os(Windows)
import CodexBarCore
import Foundation

/// Application-facing coordinator; the platform host supplies trusted snapshot data and widget IDs.
public struct WindowsWidgetService: Sendable {
    public struct Rendered: Sendable {
        /// Retain this revision for a subsequent settings action; saving a stale revision is rejected.
        public let settings: WindowsWidgetConfigurationStore.Snapshot
        public let presentation: WindowsWidgetPresentation
    }
    public struct RenderRequest: Sendable {
        public let instanceID: String
        public let family: ProviderWidgetFamily
        public let hostSize: WindowsWidgetHostDefinition.Size?
        public let expectedKind: WindowsWidgetConfiguration.Kind?
        public init(instanceID: String, family: ProviderWidgetFamily, hostSize: WindowsWidgetHostDefinition.Size? = nil,
                    expectedKind: WindowsWidgetConfiguration.Kind? = nil) {
            self.instanceID = instanceID; self.family = family; self.hostSize = hostSize; self.expectedKind = expectedKind
        }
    }
    public enum LifecycleFailure: Error, Sendable { case definitionChanged, unsupportedSetting }
    public enum RequestFailure: Error, Sendable { case tooManyRequests, invalidID, duplicateID }
    public enum RenderFailure: Sendable { case missingInstance, invalidContent }
    public enum Outcome: Sendable {
        case rendered(WindowsWidgetPresentation)
        case failed(instanceID: String, reason: RenderFailure)
    }
    public struct Batch: Sendable {
        public let settings: WindowsWidgetConfigurationStore.Snapshot
        /// Same order as requests, including explicit failures; no widget silently disappears.
        public let outcomes: [Outcome]
    }

    private let store: WindowsWidgetConfigurationStore
    public init(store: WindowsWidgetConfigurationStore) { self.store = store }

    public func settings() async throws -> WindowsWidgetConfigurationStore.Snapshot {
        try Task.checkCancellation()
        let result = try await self.store.load()
        try Task.checkCancellation()
        return result
    }

    public func render(instanceID: String, usage: WidgetSnapshot?, family: ProviderWidgetFamily,
                       now: Date, maximumAge: TimeInterval, hostSize: WindowsWidgetHostDefinition.Size? = nil) async throws -> Rendered {
        let settings = try await self.settings()
        let presentation = try WindowsWidgetPresentation.make(instanceID: instanceID,
            configuration: settings.configuration, snapshot: usage, family: family, now: now, maximumAge: maximumAge, hostSize: hostSize)
        try Task.checkCancellation()
        return Rendered(settings: settings, presentation: presentation)
    }

    public func renderBatch(_ requests: [RenderRequest], usage: WidgetSnapshot?,
                            now: Date, maximumAge: TimeInterval) async throws -> Batch {
        try Task.checkCancellation()
        guard requests.count <= WindowsWidgetConfiguration.maximumInstances else { throw RequestFailure.tooManyRequests }
        var ids = Set<String>()
        for request in requests {
            guard !request.instanceID.isEmpty, request.instanceID.utf8.count <= 256,
                  !request.instanceID.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else { throw RequestFailure.invalidID }
            guard ids.insert(request.instanceID).inserted else { throw RequestFailure.duplicateID }
        }
        let settings = try await self.settings()
        let configured = Dictionary(uniqueKeysWithValues: settings.configuration.instances.map { ($0.id, $0) })
        var outcomes: [Outcome] = []
        outcomes.reserveCapacity(requests.count)
        for request in requests {
            try Task.checkCancellation()
            guard let instance = configured[request.instanceID] else {
                outcomes.append(.failed(instanceID: request.instanceID, reason: .missingInstance))
                continue
            }
            if let expectedKind = request.expectedKind, instance.kind != expectedKind {
                outcomes.append(.failed(instanceID: request.instanceID, reason: .invalidContent))
                continue
            }
            do {
                let presentation = try WindowsWidgetPresentation.make(instanceID: request.instanceID,
                    configuration: settings.configuration, snapshot: usage, family: request.family,
                    now: now, maximumAge: maximumAge, hostSize: request.hostSize)
                outcomes.append(.rendered(presentation))
            } catch {
                outcomes.append(.failed(instanceID: request.instanceID, reason: .invalidContent))
            }
        }
        try Task.checkCancellation()
        return Batch(settings: settings, outcomes: outcomes)
    }

    /// Restore an authenticated OS inventory without deleting settings for temporarily absent widgets.
    /// All definitions are checked before a single atomic save; existing customization is preserved.
    public func reconcileHostInstances(_ instances: [WindowsWidgetHostDefinition.HostInstance]) async throws
        -> WindowsWidgetConfigurationStore.Snapshot {
        guard instances.count <= WindowsWidgetConfiguration.maximumInstances else { throw RequestFailure.tooManyRequests }
        guard Set(instances.map(\.id)).count == instances.count else { throw RequestFailure.duplicateID }
        let current = try await self.settings()
        let existing = Dictionary(uniqueKeysWithValues: current.configuration.instances.map { ($0.id, $0) })
        var mutations: [WindowsWidgetConfiguration.Mutation] = []
        for instance in instances {
            if let saved = existing[instance.id] {
                guard saved.kind == instance.definition.kind else { throw LifecycleFailure.definitionChanged }
            } else {
                mutations.append(.upsert(.init(id: instance.id, kind: instance.definition.kind)))
            }
        }
        guard existing.count + mutations.count <= WindowsWidgetConfiguration.maximumInstances else {
            throw WindowsWidgetConfiguration.Failure.tooManyInstances
        }
        return try await self.store.save(expected: current, mutations: mutations)
    }

    /// Replayed host creation events preserve the saved provider/metric/window rather than resetting defaults.
    public func registerInstance(id: String, kind: WindowsWidgetConfiguration.Kind) async throws
        -> WindowsWidgetConfigurationStore.Snapshot {
        let instance = WindowsWidgetConfiguration.Instance(id: id, kind: kind)
        try WindowsWidgetConfiguration(instances: [instance]).validate()
        let current = try await self.settings()
        if let existing = current.configuration.instances.first(where: { $0.id == id }) {
            guard existing.kind == kind else { throw LifecycleFailure.definitionChanged }
            return current
        }
        return try await self.update(expected: current, mutation: .upsert(instance))
    }

    /// Duplicate deletion events are idempotent. Cross-process changes still surface as revision conflicts.
    public func unregisterInstance(id: String) async throws -> WindowsWidgetConfigurationStore.Snapshot {
        try WindowsWidgetConfiguration(instances: [.init(id: id, kind: .usage)]).validate()
        let current = try await self.settings()
        guard current.configuration.instances.contains(where: { $0.id == id }) else { return current }
        return try await self.update(expected: current, mutation: .remove(id: id))
    }

    /// The customization UI retains this settings snapshot. Kind and ID are never supplied by form data.
    public func customizeInstance(id: String, expected: WindowsWidgetConfigurationStore.Snapshot,
                                  provider: UsageProvider, metric: WindowsWidgetConfiguration.Metric? = nil,
                                  window: WindowsWidgetConfiguration.Window? = nil) async throws
        -> WindowsWidgetConfigurationStore.Snapshot {
        try Task.checkCancellation()
        try expected.configuration.validate()
        guard var instance = expected.configuration.instances.first(where: { $0.id == id })
        else { throw WindowsWidgetConfiguration.Failure.missingInstance }
        guard WindowsWidgetConfiguration.providers(for: instance.kind).contains(provider)
        else { throw WindowsWidgetConfiguration.Failure.unsupportedProvider }
        switch instance.kind {
        case .switcher:
            guard metric == nil, window == nil else { throw LifecycleFailure.unsupportedSetting }
            return try await self.update(expected: expected, mutation: .selectSharedProvider(provider))
        case .metric:
            guard window == nil else { throw LifecycleFailure.unsupportedSetting }
            if let metric { instance.metric = metric }
        case .burnDown:
            guard metric == nil else { throw LifecycleFailure.unsupportedSetting }
            if let window { instance.window = window }
        case .usage, .history, .combinedBurnDown:
            guard metric == nil, window == nil else { throw LifecycleFailure.unsupportedSetting }
        }
        instance.provider = provider
        return try await self.update(expected: expected, mutation: .upsert(instance))
    }

    public func update(expected: WindowsWidgetConfigurationStore.Snapshot,
                       mutation: WindowsWidgetConfiguration.Mutation) async throws -> WindowsWidgetConfigurationStore.Snapshot {
        try Task.checkCancellation()
        // Do not report cancellation after a successful commit: the caller must receive the saved revision.
        return try await self.store.save(expected: expected, mutation: mutation)
    }

    public func switchProvider(_ provider: UsageProvider, from rendered: Rendered) async throws -> WindowsWidgetConfigurationStore.Snapshot {
        guard case let .switcher(providers, _) = rendered.presentation.body,
              providers.contains(provider) else { throw WindowsWidgetConfiguration.Failure.unsupportedProvider }
        return try await self.update(expected: rendered.settings, mutation: .selectSharedProvider(provider))
    }
}
#endif
