#if os(Windows)
import Foundation

/// Serializes only the public response contract, never persisted configuration or source errors.
public enum WindowsWidgetHostResponseCodec {
    public enum Failure: Error, Sendable { case oversized, invalidForm }
    public static func encode(_ response: WindowsWidgetHostSession.Response, sessionID: UUID) throws -> Data {
        var fields: [String: Any] = ["protocolVersion": 1, "sessionID": sessionID.uuidString.lowercased()]
        switch response {
        case let .accepted(reply, nextSequence):
            fields["requestID"] = reply.requestID.uuidString.lowercased()
            fields["accepted"] = true
            fields["consumed"] = true
            fields["nextSequence"] = String(nextSequence)
            switch reply.effect {
            case .refreshRequired: fields["effect"] = "refreshRequired"
            case .idle: fields["effect"] = "idle"
            case let .removed(id):
                fields["effect"] = "removed"; fields["widgetID"] = id
            case let .customization(form):
                guard form.template.utf8.count <= 64 * 1024, form.data.utf8.count <= 64 * 1024 else {
                    throw Failure.oversized
                }
                guard (try? JSONSerialization.jsonObject(with: Data(form.template.utf8))) is [String: Any],
                      (try? JSONSerialization.jsonObject(with: Data(form.data.utf8))) is [String: Any] else {
                    throw Failure.invalidForm
                }
                fields["effect"] = "customization"
                fields["widgetID"] = form.instance.id
                fields["actionToken"] = form.actionToken.uuidString.lowercased()
                fields["template"] = form.template
                fields["data"] = form.data
            }
        case let .rejected(requestID, code, consumed, nextSequence):
            if let requestID { fields["requestID"] = requestID.uuidString.lowercased() }
            fields["accepted"] = false
            fields["consumed"] = consumed
            fields["nextSequence"] = String(nextSequence)
            fields["error"] = code.rawValue
        }
        let bytes = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        guard bytes.count <= 256 * 1024 else { throw Failure.oversized }
        return bytes
    }
}
#endif
