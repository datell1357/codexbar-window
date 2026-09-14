#if os(Windows)
import CodexBarCore
import Foundation

/// Windows widget settings; no credentials, account names, or executable actions are persisted here.
public struct WindowsWidgetConfiguration: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case switcher, usage, history, metric, burnDown, combinedBurnDown
    }
    public enum Metric: String, Codable, CaseIterable, Sendable {
        case credits, todayCost, last30DaysCost
    }
    public enum Window: String, Codable, CaseIterable, Sendable {
        case session, weekly
    }
    public struct Instance: Codable, Sendable, Equatable {
        public let id: String
        public var kind: Kind
        public var provider: UsageProvider
        public var metric: Metric
        public var window: Window

        public init(id: String, kind: Kind, provider: UsageProvider = .codex,
                    metric: Metric = .credits, window: Window = .session) {
            self.id = id; self.kind = kind; self.provider = provider
            self.metric = metric; self.window = window
        }
    }
    public enum Mutation: Sendable {
        case upsert(Instance)
        case remove(id: String)
        case selectSharedProvider(UsageProvider)
    }
    public enum Failure: Error, Sendable {
        case unsupportedVersion, invalidInstanceID, duplicateInstanceID, unsupportedProvider
        case tooManyInstances, missingInstance, oversizedData, malformedData
    }

    public static let maximumInstances = 128
    public static let maximumEncodedBytes = 256 * 1024
    /// Mirrors the original ProviderChoice inventory, rather than implying every provider has widget data.
    public static let selectableProviders: [UsageProvider] = [
        .codex, .claude, .gemini, .alibaba, .alibabatokenplan, .qwencloud,
        .antigravity, .cursor, .zai, .copilot, .devin, .minimax, .kilo,
        .opencode, .opencodego, .mistral, .kimi,
    ]
    public static let burnDownProviders: [UsageProvider] = [.codex, .claude]

    public let schemaVersion: Int
    public private(set) var sharedProvider: UsageProvider
    public private(set) var instances: [Instance]

    public init(sharedProvider: UsageProvider = .codex, instances: [Instance] = []) {
        self.schemaVersion = 1; self.sharedProvider = sharedProvider; self.instances = instances
    }

    public static func providers(for kind: Kind) -> [UsageProvider] {
        switch kind {
        case .burnDown, .combinedBurnDown: self.burnDownProviders
        default: self.selectableProviders
        }
    }

    public func validate() throws {
        guard self.schemaVersion == 1 else { throw Failure.unsupportedVersion }
        guard self.instances.count <= Self.maximumInstances else { throw Failure.tooManyInstances }
        guard Self.selectableProviders.contains(self.sharedProvider) else { throw Failure.unsupportedProvider }
        var seen = Set<String>()
        for instance in self.instances {
            guard !instance.id.isEmpty, instance.id.utf8.count <= 256,
                  !instance.id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else { throw Failure.invalidInstanceID }
            guard seen.insert(instance.id).inserted else { throw Failure.duplicateInstanceID }
            guard Self.providers(for: instance.kind).contains(instance.provider) else { throw Failure.unsupportedProvider }
        }
    }

    public func applying(_ mutation: Mutation) throws -> Self {
        try self.validate()
        var updated = self
        switch mutation {
        case let .upsert(instance):
            if let index = updated.instances.firstIndex(where: { $0.id == instance.id }) {
                updated.instances[index] = instance
            } else {
                guard updated.instances.count < Self.maximumInstances else { throw Failure.tooManyInstances }
                updated.instances.append(instance)
            }
        case let .remove(id):
            guard let index = updated.instances.firstIndex(where: { $0.id == id }) else { throw Failure.missingInstance }
            updated.instances.remove(at: index)
        case let .selectSharedProvider(provider): updated.sharedProvider = provider
        }
        try updated.validate()
        return updated
    }

    /// Only Switcher instances follow the shared selection. Other instances retain their own provider.
    public func selectedProvider(for id: String) throws -> UsageProvider {
        try self.validate()
        guard let instance = self.instances.first(where: { $0.id == id }) else { throw Failure.missingInstance }
        return instance.kind == .switcher ? self.sharedProvider : instance.provider
    }

    public func encoded() throws -> Data {
        try self.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumEncodedBytes else { throw Failure.oversizedData }
        return data
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= Self.maximumEncodedBytes else { throw Failure.oversizedData }
        let value: Self
        do { value = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw Failure.malformedData }
        try value.validate()
        return value
    }
}
#endif
