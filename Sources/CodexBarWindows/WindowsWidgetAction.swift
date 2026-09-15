#if os(Windows)
import CodexBarCore
import Foundation

/// Routes an authenticated host callback against the exact card retained by the host.
public enum WindowsWidgetAction {
    public static let switchProviderVerb = "codexbar.switchProvider"
    public enum Failure: Error, Sendable { case unsupportedAction, oversized, malformed, staleCard, invalidProvider }
    private struct Selection: Decodable {
        let provider: String
        let actionToken: UUID
    }

    /// Use the host-retained card so its rendered revision and token cannot be accidentally mixed.
    public static func handle(verb: String, arguments: Data, widgetID: String,
                              card: WindowsWidgetCardBatch.Card,
                              service: WindowsWidgetService) async throws -> WindowsWidgetConfigurationStore.Snapshot {
        try await handle(verb: verb, arguments: arguments, widgetID: widgetID,
            expectedActionToken: card.actionToken, rendered: card.rendered, service: service)
    }

    /// widgetID must come from the host event; rendered and expectedActionToken come from host-owned card state.
    /// The host must reject an invalidated account/privacy context before calling this method.
    public static func handle(verb: String, arguments: Data, widgetID: String,
                              expectedActionToken: UUID, rendered: WindowsWidgetService.Rendered,
                              service: WindowsWidgetService) async throws -> WindowsWidgetConfigurationStore.Snapshot {
        try Task.checkCancellation()
        guard verb == switchProviderVerb else { throw Failure.unsupportedAction }
        guard arguments.count <= 4096 else { throw Failure.oversized }
        guard widgetID == rendered.presentation.instanceID else { throw Failure.staleCard }
        let selection: Selection
        do { selection = try JSONDecoder().decode(Selection.self, from: arguments) }
        catch { throw Failure.malformed }
        guard selection.actionToken == expectedActionToken else { throw Failure.staleCard }
        guard selection.provider.utf8.count <= 128,
              let provider = UsageProvider(rawValue: selection.provider) else { throw Failure.invalidProvider }
        // switchProvider checks the card's available choices; save compares the retained settings revision.
        return try await service.switchProvider(provider, from: rendered)
    }
}
#endif
