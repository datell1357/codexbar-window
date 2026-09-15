#if os(Windows)
import Dispatch
import Foundation

/// Owns the native server and callback lifetime. Native joins execute on a dedicated Dispatch queue.
actor WindowsWidgetNativeServer {
    enum Failure: Error, Sendable { case native(Int32), closed, invalidName }
    struct Status: Sendable { let phase: UInt32; let result: Int32 }
    private final class State: @unchecked Sendable {
        let library: WindowsWidgetNativeLibrary
        let bridge: WindowsWidgetRequestBridge
        let queue = DispatchQueue(label: "CodexBar.widgets.native-server", qos: .utility)
        let context: UnsafeMutableRawPointer
        var server: UnsafeMutableRawPointer?
        // Keep DLL/callback memory alive even if shutdown fails; release only after confirmed native destruction.
        var nativeLease: Unmanaged<State>?
        init(library: WindowsWidgetNativeLibrary, session: WindowsWidgetHostSession) throws {
            self.library = library
            self.bridge = WindowsWidgetRequestBridge(session: session)
            self.context = self.bridge.makeRetainedContext()
            var server: UnsafeMutableRawPointer?
            let status = library.create(self.context, codexBarWidgetHandleRequest, &server)
            guard status >= 0, let server else {
                WindowsWidgetRequestBridge.releaseContext(self.context)
                throw Failure.native(status < 0 ? status : -2147467259)
            }
            self.server = server
        }
        func perform<T: Sendable>(_ body: @escaping @Sendable (State) throws -> T) async throws -> T {
            try await withCheckedThrowingContinuation { continuation in
                self.queue.async { continuation.resume(with: Result { try body(self) }) }
            }
        }
        static func check(_ status: Int32) throws { if status < 0 { throw Failure.native(status) } }
        func close() async throws {
            self.bridge.cancel()
            try await self.perform { state in
                if let server = state.server { try Self.check(state.library.cancel(server)) }
            }
            await self.bridge.closeSession()
            try await self.perform { state in
                guard let server = state.server else { return }
                try Self.check(state.library.join(server))
                try Self.check(state.library.destroy(server))
                state.server = nil
                WindowsWidgetRequestBridge.releaseContext(state.context)
                let lease = state.nativeLease
                state.nativeLease = nil
                lease?.release()
            }
        }
    }
    private let state: State
    let pipeName: String
    private var closing: Task<Void, Error>?
    private var stopRequested = false

    init(installedDLL: URL, session: WindowsWidgetHostSession) throws {
        let library = try WindowsWidgetNativeLibrary(installedDLL: installedDLL)
        let state = try State(library: library, session: session)
        var units = [UInt16](repeating: 0, count: 257)
        var required: UInt32 = 0
        let result = units.withUnsafeMutableBufferPointer {
            library.name(state.server, $0.baseAddress, UInt32($0.count), &required)
        }
        guard result >= 0, required > 1, required <= units.count, units[Int(required) - 1] == 0 else {
            // Worker has not started, so destruction cannot wait on a Swift callback here.
            let destroyed = library.destroy(state.server)
            if destroyed >= 0 { WindowsWidgetRequestBridge.releaseContext(state.context) }
            else { state.nativeLease = Unmanaged.passRetained(state) }
            throw Failure.invalidName
        }
        self.pipeName = String(decoding: units.prefix(Int(required) - 1), as: UTF16.self)
        self.state = state
        state.nativeLease = Unmanaged.passRetained(state)
    }

    /// Address of the launcher's trusted process HANDLE; caller keeps it open until this method returns.
    func start(trustedClientProcessAddress: UInt) async throws {
        guard !self.stopRequested, self.closing == nil, trustedClientProcessAddress != 0 else { throw Failure.closed }
        try await self.state.perform { state in
            guard let server = state.server else { throw Failure.closed }
            try State.check(state.library.start(server, UnsafeMutableRawPointer(bitPattern: trustedClientProcessAddress)))
        }
    }
    func status() async throws -> Status {
        guard !self.stopRequested else { throw Failure.closed }
        let status = try await self.state.perform { state in
            guard let server = state.server else { throw Failure.closed }
            var phase: UInt32 = 0; var result: Int32 = 0
            try State.check(state.library.status(server, &phase, &result))
            return Status(phase: phase, result: result)
        }
        guard !self.stopRequested else { throw Failure.closed }
        return status
    }
    func close() async throws {
        self.stopRequested = true
        if let closing = self.closing { return try await closing.value }
        let state = self.state
        let task = Task { try await state.close() }
        self.closing = task
        do { try await task.value }
        catch { self.closing = nil; throw error }
    }
    deinit {
        let state = self.state
        let pendingClose = self.closing
        // Join an already scheduled cleanup instead of racing a second cancel/session-close sequence.
        // A failed explicit cleanup permits one fallback retry; the State lease still prevents unsafe unload.
        Task {
            if let pendingClose {
                do { try await pendingClose.value; return }
                catch { /* Existing close is terminal; fallback may now retry sequentially. */ }
            }
            try? await state.close()
        }
    }
}
#endif
