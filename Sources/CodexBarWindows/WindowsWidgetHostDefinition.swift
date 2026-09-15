#if os(Windows)
import CodexBarCore
import Foundation

/// Stable IDs for the Windows host manifest, using the original widget kind identifiers.
public enum WindowsWidgetHostDefinition: String, CaseIterable, Sendable {
    case switcher = "CodexBarSwitcherWidget"
    case usage = "CodexBarUsageWidget"
    case history = "CodexBarHistoryWidget"
    case metric = "CodexBarCompactWidget"
    case burnDown = "CodexBarBurnDownWidget"
    case combinedBurnDown = "CodexBarCombinedBurnDownWidget"

    public enum Size: String, Codable, CaseIterable, Sendable { case small, medium, large }
    public enum Failure: Error, Sendable { case unknownDefinition, unsupportedSize }
    public struct HostInstance: Sendable {
        public let id: String
        public let definition: WindowsWidgetHostDefinition
        public let size: Size
        public var renderRequest: WindowsWidgetService.RenderRequest {
            // ProviderWidgetFamily describes row policy, not the native host's dimensions.
            .init(instanceID: self.id, family: self.size == .small ? .small : .medium, hostSize: self.size, expectedKind: self.definition.kind)
        }
        public init(id: String, definitionID: String, size: Size) throws {
            guard let definition = WindowsWidgetHostDefinition(rawValue: definitionID) else { throw Failure.unknownDefinition }
            guard definition.sizes.contains(size) else { throw Failure.unsupportedSize }
            try WindowsWidgetConfiguration(instances: [.init(id: id, kind: definition.kind)]).validate()
            self.id = id; self.definition = definition; self.size = size
        }
    }

    public var kind: WindowsWidgetConfiguration.Kind {
        switch self {
        case .switcher: .switcher
        case .usage: .usage
        case .history: .history
        case .metric: .metric
        case .burnDown: .burnDown
        case .combinedBurnDown: .combinedBurnDown
        }
    }

    public var sizes: [Size] {
        switch self {
        case .switcher, .usage: [.small, .medium, .large]
        case .history: [.medium, .large]
        case .metric: [.small]
        case .burnDown, .combinedBurnDown: [.medium]
        }
    }
}
#endif
