#if os(Windows)
import Foundation
import WinSDK

/// A ConPTY process with an application-shutdown lease.
///
/// Launches are reserved before CreateProcessW, registered while suspended,
/// and resumed only after ownership has been recorded. The registry stores
/// object identity, so a recycled PID cannot unregister a different session.
/// Persistent session actors can adopt this lease without
/// sharing their read stream or weakening one-shot runner ownership.
final class WindowsTrackedConPTYProcess: @unchecked Sendable {
    /// All mutable state is protected by `condition`; the unchecked marker
    /// allows the registry to be held by the static process-wide coordinator.
    private final class Registry: @unchecked Sendable {
        private let condition = NSCondition()
        private var shuttingDown = false
        private var launches = 0
        private var processes: [ObjectIdentifier: WindowsTrackedConPTYProcess] = [:]

        func beginLaunch() -> Bool {
            condition.lock(); defer { condition.unlock() }
            guard !shuttingDown else { return false }
            launches += 1
            return true
        }

        func endLaunch() {
            condition.lock()
            launches = max(0, launches - 1)
            if launches == 0 { condition.broadcast() }
            condition.unlock()
        }

        func register(_ process: WindowsTrackedConPTYProcess) -> Bool {
            condition.lock(); defer { condition.unlock() }
            guard !shuttingDown else { return false }
            let id = ObjectIdentifier(process)
            processes[id] = process
            return true
        }

        /// Remove only when the registry entry still points at this object.
        func unregister(_ process: WindowsTrackedConPTYProcess) {
            condition.lock()
            let id = ObjectIdentifier(process)
            if processes[id] === process {
                processes.removeValue(forKey: id)
            }
            condition.unlock()
        }

        func drainForShutdown() -> [WindowsTrackedConPTYProcess] {
            condition.lock()
            shuttingDown = true
            while launches > 0 { condition.wait() }
            let drained = Array(processes.values)
            processes.removeAll()
            condition.unlock()
            return drained
        }
    }

    private static let registry = Registry()
    private let process: WindowsConPTYProcess
    private let stateLock = NSLock()
    private var closed = false

    private init(process: WindowsConPTYProcess) {
        self.process = process
    }

    /// Perform a suspended, registered, and resumed launch. A failed resume
    /// always releases the lease. Persistent session actors decide reuse and
    /// retain the lease they own; this registry never shares a read stream.
    static func launch(
        target: WindowsLaunchTarget,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL?,
        rows: UInt16 = 50,
        cols: UInt16 = 160,
        maxOutputBytes: Int = BoundedOutputBuffer.defaultMaxBytes) throws -> WindowsTrackedConPTYProcess
    {
        guard registry.beginLaunch() else { throw CancellationError() }
        var lease: WindowsTrackedConPTYProcess?
        defer { registry.endLaunch() }
        do {
            let process = try WindowsConPTYProcess.launch(
                target: target, arguments: arguments, environment: environment,
                currentDirectoryURL: currentDirectoryURL, rows: rows, cols: cols,
                maxOutputBytes: maxOutputBytes)
            let candidate = WindowsTrackedConPTYProcess(process: process)
            guard registry.register(candidate) else {
                process.close()
                throw CancellationError()
            }
            lease = candidate
            do {
                try process.resume()
            } catch {
                candidate.close()
                throw error
            }
            return candidate
        } catch {
            lease?.close()
            throw error
        }
    }

    var processID: DWORD { process.processID }
    var isExited: Bool { process.isExited }
    var exitStatus: Int32? { process.exitStatus }

    func read() -> WindowsConPTYProcess.ReadResult { process.read() }
    func write(_ data: Data, deadline: Date?, cancellationCheck: @Sendable () -> Bool) throws {
        try process.write(data, deadline: deadline, cancellationCheck: cancellationCheck)
    }

    func terminate() { process.terminate() }

    /// Idempotently unregister this exact lease before closing its ConPTY.
    func close() {
        stateLock.lock()
        guard !closed else { stateLock.unlock(); return }
        closed = true
        stateLock.unlock()
        Self.registry.unregister(self)
        process.close()
    }

    /// Used by the application shutdown coordinator; callers own the returned
    /// leases and must close each one after the shutdown fence is set.
    static func drainForShutdown() -> [WindowsTrackedConPTYProcess] {
        registry.drainForShutdown()
    }
}
#endif
