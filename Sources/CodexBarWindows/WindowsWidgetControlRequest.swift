#if os(Windows)
import Foundation

struct WindowsWidgetControlRequest: Decodable {
    enum Method: String, Decodable { case prepare, card, acknowledge }
    let protocolVersion: Int
    let sessionID: UUID
    let requestID: UUID
    let sequence: String
    let method: Method
    let theme: String?
    let ticket: UUID?
    let widgetID: String?
    let publishedIDs: [String]?

    static func decode(_ payload: Data, sessionID: UUID, sequence: UInt64) throws -> Self {
        guard payload.count <= 16 * 1024 else { throw WindowsWidgetHostEvent.Failure.oversized }
        let request = try JSONDecoder().decode(Self.self, from: payload)
        guard request.protocolVersion == 1, request.sessionID == sessionID,
              request.sequence == String(sequence) else { throw WindowsWidgetHostEvent.Failure.outOfOrder }
        switch request.method {
        case .prepare:
            guard ["light", "dark"].contains(request.theme ?? ""), request.ticket == nil,
                  request.widgetID == nil, request.publishedIDs == nil else { throw WindowsWidgetHostEvent.Failure.malformed }
        case .card:
            guard request.ticket != nil, let id = request.widgetID, request.theme == nil, request.publishedIDs == nil else {
                throw WindowsWidgetHostEvent.Failure.malformed
            }
            try WindowsWidgetConfiguration(instances: [.init(id: id, kind: .usage)]).validate()
        case .acknowledge:
            guard request.ticket != nil, request.theme == nil, request.widgetID == nil,
                  let ids = request.publishedIDs, ids.count <= WindowsWidgetConfiguration.maximumInstances else {
                throw WindowsWidgetHostEvent.Failure.malformed
            }
            try WindowsWidgetConfiguration(instances: ids.map { .init(id: $0, kind: .usage) }).validate()
        }
        return request
    }
}
#endif
