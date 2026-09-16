#if os(Windows)
import Dispatch
import Foundation
import WinSDK

/// Advisory read-only oplock. It never requests write/handle caching or acknowledges a
/// break. Unsupported/remote/busy sources keep the ordinary full-content verification path.
final class WindowsCostReadLease: @unchecked Sendable {
    private final class Capacity: @unchecked Sendable {
        static let shared = Capacity()
        private let lock = NSLock()
        private var count = 0
        func acquire() -> Bool {
            self.lock.lock()
            defer { self.lock.unlock() }
            guard self.count < 256 else { return false }
            self.count += 1
            return true
        }
        func release() { self.lock.lock(); self.count -= 1; self.lock.unlock() }
    }

    /// Buffers must outlive the asynchronous DeviceIoControl request, including cancellation.
    private final class Operation: @unchecked Sendable {
        let file: HANDLE
        let event: HANDLE
        let overlapped: UnsafeMutablePointer<OVERLAPPED>
        let input: UnsafeMutablePointer<REQUEST_OPLOCK_INPUT_BUFFER>
        let output: UnsafeMutablePointer<REQUEST_OPLOCK_OUTPUT_BUFFER>

        init(file: HANDLE, event: HANDLE) {
            self.file = file
            self.event = event
            self.overlapped = .allocate(capacity: 1)
            self.input = .allocate(capacity: 1)
            self.output = .allocate(capacity: 1)
            self.overlapped.initialize(to: OVERLAPPED())
            self.overlapped.pointee.hEvent = event
            self.input.initialize(to: REQUEST_OPLOCK_INPUT_BUFFER())
            self.output.initialize(to: REQUEST_OPLOCK_OUTPUT_BUFFER())
            self.input.pointee.StructureVersion = WORD(REQUEST_OPLOCK_CURRENT_VERSION)
            self.input.pointee.StructureLength = WORD(MemoryLayout<REQUEST_OPLOCK_INPUT_BUFFER>.size)
            self.input.pointee.RequestedOplockLevel = DWORD(OPLOCK_LEVEL_CACHE_READ)
            self.input.pointee.Flags = DWORD(REQUEST_OPLOCK_INPUT_FLAG_REQUEST)
        }

        func request() -> Bool {
            let success = DeviceIoControl(
                self.file, DWORD(FSCTL_REQUEST_OPLOCK), self.input,
                DWORD(MemoryLayout<REQUEST_OPLOCK_INPUT_BUFFER>.size), self.output,
                DWORD(MemoryLayout<REQUEST_OPLOCK_OUTPUT_BUFFER>.size), nil, self.overlapped)
            // Only an outstanding request means the read oplock was granted.
            return success == 0 && GetLastError() == DWORD(ERROR_IO_PENDING)
        }

        func retire(pending: Bool) {
            if !pending { self.dispose(); return }
            _ = CancelIoEx(self.file, self.overlapped)
            DispatchQueue.global(qos: .utility).async {
                var transferred: DWORD = 0
                // Do not release OVERLAPPED/output storage just because CancelIoEx returned.
                // Cleanup runs off the scan/UI queue; the capacity slot stays occupied until completion.
                while GetOverlappedResult(self.file, self.overlapped, &transferred, true) == 0,
                      GetLastError() == DWORD(ERROR_IO_INCOMPLETE) {
                    _ = WaitForSingleObject(self.event, 1000)
                }
                self.dispose()
            }
        }

        private func dispose() {
            CloseHandle(self.file)
            CloseHandle(self.event)
            self.overlapped.deinitialize(count: 1)
            self.overlapped.deallocate()
            self.input.deinitialize(count: 1)
            self.input.deallocate()
            self.output.deinitialize(count: 1)
            self.output.deallocate()
            Capacity.shared.release()
        }
    }

    let snapshot: CostUsageFileReadSnapshot
    private let lock = NSLock()
    private var operation: Operation?

    private init(operation: Operation, snapshot: CostUsageFileReadSnapshot) {
        self.operation = operation
        self.snapshot = snapshot
    }

    static func acquire(at url: URL, expected: CostUsageFileReadSnapshot) throws -> WindowsCostReadLease? {
        let path = Array(try WindowsCostFileMetadata.path(url).utf16) + [UInt16(0)]
        guard Capacity.shared.acquire() else { return nil }
        let file = path.withUnsafeBufferPointer {
            CreateFileW($0.baseAddress, DWORD(GENERIC_READ),
                        DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE), nil,
                        DWORD(OPEN_EXISTING), DWORD(FILE_FLAG_OVERLAPPED), nil)
        }
        guard let file, file != INVALID_HANDLE_VALUE else { Capacity.shared.release(); return nil }
        guard let event = CreateEventW(nil, true, false, nil) else {
            CloseHandle(file)
            Capacity.shared.release()
            return nil
        }
        let operation = Operation(file: file, event: event)
        guard operation.request() else { operation.retire(pending: false); return nil }
        do {
            let snapshot = try CostUsageFileReadSnapshot(native: WindowsCostFileMetadata.openedNativeFile(file))
            guard CostUsageSourcePublication.allowsAppend(snapshot, from: expected) else {
                throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
            }
            let lease = WindowsCostReadLease(operation: operation, snapshot: snapshot)
            guard lease.isIntact else { lease.close(); return nil }
            return lease
        } catch {
            operation.retire(pending: true)
            throw error
        }
    }

    var isIntact: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let operation else { return false }
        return WaitForSingleObject(operation.event, 0) == DWORD(WAIT_TIMEOUT)
    }

    func close() {
        self.lock.lock()
        let operation = self.operation
        self.operation = nil
        self.lock.unlock()
        operation?.retire(pending: true)
    }

    deinit { self.close() }
}
#endif
