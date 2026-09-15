#if os(Windows)
import Foundation
import WinSDK

/// One unnamed auto-reset event per authenticated host session. No account data is stored in this event.
final class WindowsWidgetInvalidationSignal: @unchecked Sendable {
    enum Failure: Error, Sendable { case closed, alreadyTransferred, windows(UInt32) }
    private let lock = NSLock()
    private var handle: HANDLE?
    private var transferred = false

    init() throws {
        // Non-inheritable by default: the trusted launcher must explicitly duplicate only this handle.
        guard let handle = CreateEventW(nil, false, false, nil) else { throw Failure.windows(GetLastError()) }
        self.handle = handle
    }

    func signal() throws {
        self.lock.lock(); defer { self.lock.unlock() }
        guard let handle = self.handle else { throw Failure.closed }
        guard SetEvent(handle) else { throw Failure.windows(GetLastError()) }
    }

    /// Synchronous launcher-only borrow. Duplicate with SYNCHRONIZE into the authenticated target process.
    /// Never retain this local handle or transmit its numeric value as a remote process handle.
    /// The body must not call signal/close or await while the lifetime lock is held.
    private func withBorrowedHandle<T>(_ body: (HANDLE) throws -> T) throws -> T {
        self.lock.lock(); defer { self.lock.unlock() }
        guard let handle = self.handle else { throw Failure.closed }
        return try body(handle)
    }

    struct RemoteWaitHandle: Sendable {
        /// Valid ONLY in the authenticated target's handle table. Never CloseHandle this value locally.
        let value: UInt
    }

    /// The launcher retains a verified target process handle with PROCESS_DUP_HANDLE access throughout this call.
    /// The target must close the returned handle after its receiver duplicates/adopts it.
    /// If bootstrap fails, the launcher must stop that newly launched host to release its unclaimed handles.
    func duplicateForTrustedHost(_ process: HANDLE) throws -> RemoteWaitHandle {
        try self.withBorrowedHandle { local in
            guard !self.transferred else { throw Failure.alreadyTransferred }
            var remote: HANDLE?
            guard DuplicateHandle(GetCurrentProcess(), local, process, &remote,
                                  DWORD(SYNCHRONIZE), false, 0) else {
                throw Failure.windows(GetLastError())
            }
            // Success consumes this event's single receiver allocation, even if bootstrap later fails.
            // Auto-reset events must not be shared by independent receivers competing for one signal.
            self.transferred = true
            guard let remote else { throw Failure.windows(UInt32(ERROR_INVALID_HANDLE)) }
            return RemoteWaitHandle(value: UInt(bitPattern: remote))
        }
    }

    /// The native owner must terminate/reconnect the session when delivery fails; a failed signal is not success.
    /// Callback captures this owner strongly so session lifetime cannot outlive the signaling handle accidentally.
    func callback(onFailure: @escaping @Sendable (Failure) -> Void) -> @Sendable (UUID) -> Void {
        { [self] _ in
            do { try self.signal() }
            catch let failure as Failure { onFailure(failure) }
            catch { onFailure(.windows(UInt32(ERROR_GEN_FAILURE))) }
        }
    }

    /// Call after closing the session callback source and stopping its native receiver.
    /// Concurrent callbacks cannot access a handle after CloseHandle; close failures retain ownership for retry.
    func close() throws {
        self.lock.lock(); defer { self.lock.unlock() }
        guard let handle = self.handle else { return }
        guard CloseHandle(handle) else { throw Failure.windows(GetLastError()) }
        self.handle = nil
    }

    deinit {
        // Final reference excludes concurrent borrows/callbacks; explicit close reports errors to the owner.
        if let handle = self.handle { _ = CloseHandle(handle) }
    }
}
#endif
