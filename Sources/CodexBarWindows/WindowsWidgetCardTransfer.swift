#if os(Windows)
import Foundation

/// One manifest followed by individually bounded card payloads; successful publication is acknowledged separately.
enum WindowsWidgetCardTransfer {
    enum Failure: Error { case unknownCard, oversized }
    /// Check the complete escaped JSON response before marking an individual card ready.
    /// UUID contents have fixed ASCII width; the largest sequence reserves every possible sequence length.
    static func requireTransferable(_ payload: WindowsWidgetAdaptiveCard.Payload, widgetID: String) throws {
        let guid = "00000000-0000-0000-0000-000000000000"
        let card: [String: Any] = [
            "ticket": guid, "widgetID": widgetID, "state": "failed",
            "template": payload.template, "data": payload.data,
            "nextRefresh": payload.nextRefresh.timeIntervalSince1970,
        ]
        _ = try self.encode([
            "protocolVersion": 1, "sessionID": guid, "requestID": guid,
            "accepted": true, "consumed": true, "nextSequence": String(UInt64.max), "payload": card,
        ])
    }

    static func manifest(ticket: UUID, cards: WindowsWidgetCardBatch) throws -> Data {
        let items: [[String: String]] = cards.outcomes.map { outcome in
            switch outcome {
            case let .ready(card): ["widgetID": card.instanceID, "state": "ready"]
            case let .customizing(id): ["widgetID": id, "state": "customizing"]
            case let .failed(id, reason):
                ["widgetID": id, "state": reason == .missingInstance ? "removed" : "failed"]
            }
        }
        return try self.encode(["state": "ready", "ticket": ticket.uuidString.lowercased(), "items": items])
    }
    static func card(ticket: UUID, widgetID: String, cards: WindowsWidgetCardBatch) throws -> Data {
        for outcome in cards.outcomes {
            let payload: WindowsWidgetAdaptiveCard.Payload?
            let state: String
            switch outcome {
            case let .ready(card) where card.instanceID == widgetID:
                payload = card.payload; state = "ready"
            case let .customizing(id) where id == widgetID:
                payload = nil; state = "customizing"
            case let .failed(id, reason) where id == widgetID:
                payload = cards.failurePayloads[id]
                state = reason == .missingInstance ? "removed" : "failed"
            default: continue
            }
            var fields: [String: Any] = ["ticket": ticket.uuidString.lowercased(), "widgetID": widgetID, "state": state]
            if let payload {
                fields["template"] = payload.template
                fields["data"] = payload.data
                fields["nextRefresh"] = payload.nextRefresh.timeIntervalSince1970
            }
            return try self.encode(fields)
        }
        throw Failure.unknownCard
    }
    static func encode(_ fields: [String: Any]) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        guard data.count <= WindowsWidgetFrame.maximumPayloadBytes else { throw Failure.oversized }
        return data
    }
}
#endif
