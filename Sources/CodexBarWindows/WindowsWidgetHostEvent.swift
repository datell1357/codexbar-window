#if os(Windows)
import Foundation

/// Decode only after the transport authenticates its native provider peer.
/// The transport owns sequence advancement and response correlation; payload IDs are not authentication.
public struct WindowsWidgetHostEvent: Sendable {
    public enum Kind: String, Decodable, Sendable {
        case created, deleted, action, contextChanged, activated, deactivated, customizationRequested
    }
    public enum Failure: Error, Sendable { case oversized, malformed, unsupportedVersion, wrongSession, outOfOrder }
    public let requestID: UUID
    public let sequence: UInt64
    public let kind: Kind
    public let widgetID: String
    public let instance: WindowsWidgetHostDefinition.HostInstance?
    public let verb: String?
    public let arguments: Data?

    private struct Envelope: Decodable {
        let protocolVersion: Int
        let sessionID: UUID
        let requestID: UUID
        let sequence: String
        let kind: Kind
        let widgetID: String
        let definitionID: String?
        let size: WindowsWidgetHostDefinition.Size?
        let verb: String?
        let arguments: String?
    }
    public static func decode(_ data: Data, expectedSessionID: UUID, expectedSequence: UInt64) throws -> Self {
        guard data.count <= 16 * 1024 else { throw Failure.oversized }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw Failure.malformed }
        guard envelope.protocolVersion == 1 else { throw Failure.unsupportedVersion }
        guard envelope.sessionID == expectedSessionID else { throw Failure.wrongSession }
        guard let sequence = UInt64(envelope.sequence), String(sequence) == envelope.sequence,
              sequence == expectedSequence else { throw Failure.outOfOrder }
        try WindowsWidgetConfiguration(instances: [.init(id: envelope.widgetID, kind: .usage)]).validate()
        let instance: WindowsWidgetHostDefinition.HostInstance?
        switch envelope.kind {
        case .deleted, .deactivated:
            guard envelope.definitionID == nil, envelope.size == nil else { throw Failure.malformed }
            instance = nil
        default:
            guard let definition = envelope.definitionID, let size = envelope.size else { throw Failure.malformed }
            instance = try .init(id: envelope.widgetID, definitionID: definition, size: size)
        }
        let arguments: Data?
        if envelope.kind == .action {
            guard let verb = envelope.verb,
                  [WindowsWidgetAction.switchProviderVerb, WindowsWidgetCustomization.saveVerb,
                   WindowsWidgetCustomization.cancelVerb].contains(verb), let text = envelope.arguments else {
                throw Failure.malformed
            }
            let bytes = Data(text.utf8)
            guard bytes.count <= 4096 else { throw Failure.oversized }
            guard (try? JSONSerialization.jsonObject(with: bytes)) is [String: Any] else { throw Failure.malformed }
            arguments = bytes
        } else {
            guard envelope.verb == nil, envelope.arguments == nil else { throw Failure.malformed }
            arguments = nil
        }
        return Self(requestID: envelope.requestID, sequence: sequence, kind: envelope.kind,
            widgetID: envelope.widgetID, instance: instance, verb: envelope.verb, arguments: arguments)
    }
}
#endif
