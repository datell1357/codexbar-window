#if os(Windows)
import Foundation
import WinSDK

/// Backend-side lifetime owner. The launcher still authenticates/starts the native host and transfers its handles.
actor WindowsWidgetBackendConnection {
    enum Failure: Error, Sendable { case closed, alreadyStarted, missingHost, hostExited, windows(UInt32) }
    enum EndReason: Sendable {
        case requested
        case handshakeTimedOut
        case startupFailed
        case bootstrapEncodingFailed
        case nativeServer(WindowsWidgetNativeServer.Status)
        case nativeStatusUnavailable
        case invalidationSignal(WindowsWidgetInvalidationSignal.Failure)
    }
    enum Phase: Sendable { case created, prepared, starting, listening, handshakeAccepted, closing, cleanupFailed, closed }
    struct Lifecycle: Sendable {
        let sessionID: UUID
        let phase: Phase
        let endReason: EndReason?
    }
    /// One runtime owner consumer; launcher reads the runtime snapshot instead of consuming this stream.
    /// The newest snapshot is retained, not an audit log of every transition.
    /// A failed cleanup leaves this stream open so an explicit close retry can report its result.
    nonisolated let lifecycleEvents: AsyncStream<Lifecycle>
    private let lifecycleContinuation: AsyncStream<Lifecycle>.Continuation
    private var lifecyclePhase: Phase = .created
    private var endReason: EndReason?
    let sessionID: UUID
    private let session: WindowsWidgetHostSession
    private let server: WindowsWidgetNativeServer
    private let signal: WindowsWidgetInvalidationSignal
    private let failures: AsyncStream<WindowsWidgetInvalidationSignal.Failure>
    private let failureContinuation: AsyncStream<WindowsWidgetInvalidationSignal.Failure>.Continuation
    private let stopReceiver: @Sendable () async throws -> Void
    private var observer: Task<Void, Never>?
    private var serverMonitor: Task<Void, Never>?
    private var closing: Task<Void, Error>?
    /// Holds the process object itself, avoiding handle-value reuse between bootstrap and server start.
    private final class HostProcess: @unchecked Sendable {
        let handle: HANDLE
        init(borrowing handle: HANDLE) throws {
            var duplicate: HANDLE?
            guard DuplicateHandle(GetCurrentProcess(), handle, GetCurrentProcess(), &duplicate,
                DWORD(PROCESS_DUP_HANDLE | PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE), false, 0),
                let duplicate else { throw Failure.windows(GetLastError()) }
            self.handle = duplicate
        }
        func requireAlive() throws {
            let result = WaitForSingleObject(self.handle, 0)
            if result == DWORD(WAIT_FAILED) { throw Failure.windows(GetLastError()) }
            guard result == DWORD(WAIT_TIMEOUT) else { throw Failure.hostExited }
        }
        deinit { _ = CloseHandle(self.handle) }
    }
    private var hostProcess: HostProcess?
    private var handshakeAccepted = false
    private var started = false
    private var stopRequested = false
    private(set) var signalFailure: WindowsWidgetInvalidationSignal.Failure?
    private(set) var cleanupFailed = false
    private(set) var terminalServerStatus: WindowsWidgetNativeServer.Status?
    private(set) var serverStatusUnavailable = false

    /// stopReceiver must stop AND join the native invalidation receiver before returning.
    /// It must be idempotent, including when startup failed before that receiver was created.
    /// If bootstrap was never delivered, it must also reclaim the transferred event via the trusted host
    /// cleanup protocol or wait for that dedicated host to exit; the backend must not close a remote value.
    init(installedDLL: URL, runtime: WindowsUsageRuntime, service: WindowsWidgetService,
         stopReceiver: @escaping @Sendable () async throws -> Void) throws {
        let signal = try WindowsWidgetInvalidationSignal()
        let pair = AsyncStream<WindowsWidgetInvalidationSignal.Failure>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        let continuation = pair.continuation
        let session = WindowsWidgetHostSession(sessionID: id, runtime: runtime, service: service,
            onContextInvalidated: signal.callback { failure in continuation.yield(failure) })
        // If construction fails, session has never subscribed/started and local owners release normally.
        let server = try WindowsWidgetNativeServer(installedDLL: installedDLL, session: session)
        self.sessionID = id
        self.session = session
        self.server = server
        self.signal = signal
        self.failures = pair.stream
        self.failureContinuation = continuation
        self.stopReceiver = stopReceiver
        let lifecycle = AsyncStream<Lifecycle>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.lifecycleEvents = lifecycle.stream
        self.lifecycleContinuation = lifecycle.continuation
        lifecycle.continuation.yield(Lifecycle(sessionID: id, phase: .created, endReason: nil))
    }

    func lifecycleSnapshot() -> Lifecycle {
        Lifecycle(sessionID: self.sessionID, phase: self.lifecyclePhase, endReason: self.endReason)
    }

    private func publishLifecycle(_ phase: Phase) {
        self.lifecyclePhase = phase
        self.lifecycleContinuation.yield(self.lifecycleSnapshot())
    }

    func pipeName() async -> String { await self.server.pipeName }

    /// Pre-start bootstrap only. The input is a local trusted process handle, not a PID or pipe-supplied number.
    /// Caller retains that process handle across this actor call and securely delivers the result to that host only.
    func duplicateSignalForTrustedHost(processHandleAddress: UInt) throws
        -> WindowsWidgetInvalidationSignal.RemoteWaitHandle {
        guard !self.stopRequested else { throw Failure.closed }
        guard !self.started else { throw Failure.alreadyStarted }
        guard processHandleAddress != 0, processHandleAddress != UInt.max,
              let process = HANDLE(bitPattern: processHandleAddress) else {
            throw WindowsWidgetInvalidationSignal.Failure.windows(UInt32(ERROR_INVALID_HANDLE))
        }
        guard self.hostProcess == nil else { throw WindowsWidgetInvalidationSignal.Failure.alreadyTransferred }
        let host = try HostProcess(borrowing: process)
        try host.requireAlive()
        let remote = try self.signal.duplicateForTrustedHost(host.handle)
        self.hostProcess = host
        self.publishLifecycle(.prepared)
        return remote
    }

    /// Prepare one payload for the authenticated target. If delivery fails, dispose this connection/host.
    func prepareBootstrap(processHandleAddress: UInt) async throws -> Data {
        try await self.prepareBootstrap(processHandleAddress: processHandleAddress, launchFrame: false)
    }

    /// The native executable consumes this framed delivery from its inherited launch pipe.
    /// It shares the one-transfer rule with prepareBootstrap; callers must choose one format.
    func prepareLaunchDelivery(processHandleAddress: UInt) async throws -> Data {
        try await self.prepareBootstrap(processHandleAddress: processHandleAddress, launchFrame: true)
    }

    private func prepareBootstrap(processHandleAddress: UInt, launchFrame: Bool) async throws -> Data {
        guard !self.stopRequested, !self.started else { throw Failure.closed }
        let pipeName = await self.server.pipeName
        let remote = try self.duplicateSignalForTrustedHost(processHandleAddress: processHandleAddress)
        do {
            if launchFrame {
                return try WindowsWidgetBootstrap.encodeLaunchDelivery(sessionID: self.sessionID,
                    pipeName: pipeName, event: remote)
            }
            return try WindowsWidgetBootstrap.encode(sessionID: self.sessionID, pipeName: pipeName, event: remote)
        } catch {
            // A remote handle was already transferred. This connection cannot safely prepare another payload.
            if self.endReason == nil { self.endReason = .bootstrapEncodingFailed }
            do { try await self.close() } catch { self.cleanupFailed = true }
            throw error
        }
    }

    func start() async throws {
        guard !self.stopRequested else { throw Failure.closed }
        guard !self.started else { throw Failure.alreadyStarted }
        guard let host = self.hostProcess else { throw Failure.missingHost }
        self.started = true
        self.publishLifecycle(.starting)
        let failures = self.failures
        self.observer = Task { [weak self] in
            for await failure in failures {
                guard !Task.isCancelled else { return }
                await self?.signalDeliveryFailed(failure)
                return
            }
        }
        do {
            try host.requireAlive()
            // Keep the exact bootstrap process object alive until the native server duplicates it.
            try await self.server.start(trustedClientProcessAddress: UInt(bitPattern: host.handle))
            withExtendedLifetime(host) {}
            guard !self.stopRequested else { throw Failure.closed }
            self.publishLifecycle(.listening)
            self.startServerMonitor()
        } catch {
            if self.endReason == nil { self.endReason = .startupFailed }
            // Preserve the original startup error; cleanup failure remains observable and close can retry.
            do { try await self.close() } catch { self.cleanupFailed = true }
            throw error
        }
    }

    private func startServerMonitor() {
        let server = self.server
        let session = self.session
        let handshakeDeadline = ContinuousClock.now.advanced(by: .seconds(30))
        self.serverMonitor = Task { [weak self] in
            var observedHandshake = false
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                guard !Task.isCancelled else { return }
                do {
                    let status = try await server.status()
                    guard !Task.isCancelled else { return }
                    if status.phase == 2 || status.phase == 3 {
                        await self?.serverTerminated(status)
                        return
                    }
                    if status.phase != 1 {
                        await self?.serverStatusFailed()
                        return
                    }
                    let accepted = await session.hasAcceptedTransportHandshake()
                    guard !Task.isCancelled else { return }
                    if accepted {
                        observedHandshake = true
                        await self?.transportHandshakeAccepted()
                    } else if !observedHandshake, ContinuousClock.now >= handshakeDeadline {
                        await self?.transportHandshakeTimedOut()
                        return
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    await self?.serverStatusFailed()
                    return
                }
            }
        }
    }

    private func transportHandshakeAccepted() {
        guard !self.stopRequested, !self.handshakeAccepted else { return }
        self.handshakeAccepted = true
        self.publishLifecycle(.handshakeAccepted)
    }

    private func transportHandshakeTimedOut() async {
        guard !self.stopRequested, !self.handshakeAccepted else { return }
        self.endReason = .handshakeTimedOut
        do { try await self.close() } catch { self.cleanupFailed = true }
    }

    private func serverTerminated(_ status: WindowsWidgetNativeServer.Status) async {
        guard !self.stopRequested else { return }
        self.endReason = .nativeServer(status)
        self.terminalServerStatus = status
        do { try await self.close() } catch { self.cleanupFailed = true }
    }

    private func serverStatusFailed() async {
        guard !self.stopRequested else { return }
        self.endReason = .nativeStatusUnavailable
        self.serverStatusUnavailable = true
        // Unobservable native state cannot be treated as a healthy serving connection.
        do { try await self.close() } catch { self.cleanupFailed = true }
    }

    private func signalDeliveryFailed(_ failure: WindowsWidgetInvalidationSignal.Failure) async {
        guard !self.stopRequested else { return }
        self.endReason = .invalidationSignal(failure)
        self.signalFailure = failure
        do { try await self.close() } catch { self.cleanupFailed = true }
    }

    func status() async throws -> WindowsWidgetNativeServer.Status { try await self.server.status() }

    func close() async throws {
        self.stopRequested = true
        self.serverMonitor?.cancel()
        self.serverMonitor = nil
        if let closing = self.closing { return try await closing.value }
        if self.endReason == nil { self.endReason = .requested }
        self.publishLifecycle(.closing)
        let server = self.server
        let signal = self.signal
        let stopReceiver = self.stopReceiver
        let task = Task {
            // Server close first closes the session callback source and drains the native request worker.
            try await server.close()
            try await stopReceiver()
            try signal.close()
        }
        self.closing = task
        do {
            try await task.value
            self.cleanupFailed = false
            self.publishLifecycle(.closed)
            self.lifecycleContinuation.finish()
            self.failureContinuation.finish()
            self.observer?.cancel()
            self.observer = nil
        } catch {
            self.cleanupFailed = true
            self.closing = nil
            self.publishLifecycle(.cleanupFailed)
            throw error
        }
    }

    deinit {
        self.lifecycleContinuation.finish()
        self.serverMonitor?.cancel()
        self.observer?.cancel()
        self.failureContinuation.finish()
        let server = self.server
        let signal = self.signal
        let stopReceiver = self.stopReceiver
        let pendingClose = self.closing
        // Explicit close is required for observable errors. Never overlap its remote cleanup with fallback.
        Task {
            if let pendingClose {
                do {
                    try await pendingClose.value
                    return
                } catch { /* The completed attempt failed; a sequential fallback may retry cleanup. */ }
            }
            do {
                try await server.close()
                try await stopReceiver()
                try signal.close()
            } catch { /* Native server retains unsafe-to-release resources if destruction fails. */ }
        }
    }
}
#endif
