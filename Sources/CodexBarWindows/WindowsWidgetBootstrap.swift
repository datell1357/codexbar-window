#if os(Windows)
import Foundation

/// Deliver over the launcher's authenticated private bootstrap channel, never argv, logs, or public files.
/// This payload is not a trust anchor: the native host independently retains its trusted backend process handle.
enum WindowsWidgetBootstrap {
    enum Failure: Error { case invalidPipe, invalidHandle, oversized }
    static func encode(sessionID: UUID, pipeName: String,
                       event: WindowsWidgetInvalidationSignal.RemoteWaitHandle) throws -> Data {
        let prefix = "\\\\.\\pipe\\CodexBar.Widgets."
        guard pipeName.hasPrefix(prefix), pipeName.utf8.count <= 256 else { throw Failure.invalidPipe }
        let suffix = pipeName.dropFirst(prefix.count)
        guard suffix.utf8.count == 36,
              let nonce = UUID(uuidString: String(suffix)),
              nonce.uuidString.lowercased() == suffix else {
            throw Failure.invalidPipe
        }
        guard event.value != 0, event.value != UInt.max else { throw Failure.invalidHandle }
        let payload = try JSONSerialization.data(withJSONObject: [
            "protocolVersion": 1,
            "sessionID": sessionID.uuidString.lowercased(),
            "pipeName": pipeName,
            // String preserves pointer-sized integers across JSON implementations.
            "invalidationHandle": String(event.value),
        ], options: [.sortedKeys])
        guard payload.count <= 4096 else { throw Failure.oversized }
        return payload
    }
}
#endif
