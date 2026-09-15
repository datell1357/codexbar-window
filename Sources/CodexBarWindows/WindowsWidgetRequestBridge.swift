#if os(Windows)
import Dispatch
import Foundation

/// Synchronous C callback adapter, invoked ONLY on the native dedicated server worker.
/// Never call execute from a Swift actor, cooperative executor, or the UI thread.
public final class WindowsWidgetRequestBridge: @unchecked Sendable {
    private final class Completion: @unchecked Sendable {
        let signal = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var response: Data?
        func finish(_ response: Data?) {
            self.lock.lock(); self.response = response; self.lock.unlock()
            self.signal.signal()
        }
        func wait() -> Data? {
            self.signal.wait()
            self.lock.lock(); defer { self.lock.unlock() }
            return self.response
        }
    }
    private let session: WindowsWidgetHostSession
    private let lock = NSLock()
    private var closed = false
    private var active: Task<Void, Never>?
    public init(session: WindowsWidgetHostSession) { self.session = session }

    /// Owner must balance with releaseContext only after cancel, session close, and native worker join.
    public func makeRetainedContext() -> UnsafeMutableRawPointer { Unmanaged.passRetained(self).toOpaque() }
    public static func releaseContext(_ context: UnsafeMutableRawPointer) {
        Unmanaged<WindowsWidgetRequestBridge>.fromOpaque(context).release()
    }
    public func cancel() {
        self.lock.lock()
        self.closed = true
        let task = self.active
        self.lock.unlock()
        task?.cancel()
    }
    public func closeSession() async {
        self.cancel()
        await self.session.close()
    }
    private func complete(_ completion: Completion, response: Data?) {
        self.lock.lock()
        let accepted = self.closed ? nil : response
        self.active = nil
        self.lock.unlock()
        completion.finish(accepted)
    }
    fileprivate func execute(_ request: Data) -> Data? {
        self.lock.lock()
        guard !self.closed, self.active == nil else { self.lock.unlock(); return nil }
        let completion = Completion()
        self.active = Task {
            let response = try? await self.session.receiveEncoded(request)
            self.complete(completion, response: response)
        }
        self.lock.unlock()
        return completion.wait()
    }
}

@_cdecl("CodexBarWidgetHandleRequest")
public func codexBarWidgetHandleRequest(
    _ context: UnsafeMutableRawPointer?, _ request: UnsafePointer<UInt8>?, _ requestSize: UInt32,
    _ response: UnsafeMutablePointer<UInt8>?, _ responseCapacity: UInt32,
    _ responseSize: UnsafeMutablePointer<UInt32>?) -> Int32 {
    responseSize?.pointee = 0
    guard let context, let request, requestSize > 0, requestSize <= 16 * 1024,
          let response, responseCapacity >= 256 * 1024, let responseSize else { return 1 }
    let adapter = Unmanaged<WindowsWidgetRequestBridge>.fromOpaque(context).takeUnretainedValue()
    // Copy before scheduling Swift work. Native input/output pointers never escape this callback.
    let input = Data(bytes: request, count: Int(requestSize))
    guard let output = adapter.execute(input) else { return 2 }
    guard !output.isEmpty, output.count <= 256 * 1024 else { return 3 }
    output.copyBytes(to: response, count: output.count)
    responseSize.pointee = UInt32(output.count)
    return 0
}
#endif
