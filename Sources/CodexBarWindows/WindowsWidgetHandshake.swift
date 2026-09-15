#if os(Windows)
import Foundation

/// Application protocol negotiation after OS-level peer authentication. UUIDs do not authenticate a peer.
enum WindowsWidgetHandshake {
    enum Failure: Error { case invalidHello }
    private struct Hello: Decodable {
        let protocolVersion: Int
        let method: String
        let sessionID: UUID
        let requestID: UUID
        let maximumFrameBytes: Int
        let maximumEventBytes: Int
    }
    static func accept(_ payload: Data, sessionID: UUID) throws -> Data {
        guard payload.count <= 4096 else { throw Failure.invalidHello }
        let hello = try JSONDecoder().decode(Hello.self, from: payload)
        guard hello.protocolVersion == 1, hello.method == "hello", hello.sessionID == sessionID,
              hello.maximumFrameBytes == WindowsWidgetFrame.maximumPayloadBytes,
              hello.maximumEventBytes == 16 * 1024 else { throw Failure.invalidHello }
        return try JSONSerialization.data(withJSONObject: [
            "protocolVersion": 1, "method": "hello", "accepted": true,
            "sessionID": sessionID.uuidString.lowercased(), "requestID": hello.requestID.uuidString.lowercased(),
            "maximumFrameBytes": WindowsWidgetFrame.maximumPayloadBytes,
            "maximumEventBytes": 16 * 1024, "nextSequence": "0",
        ], options: [.sortedKeys])
    }
}
#endif
