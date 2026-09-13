#if os(Windows)
import Foundation

/// In-memory validity for modal snapshots; no account data is retained here.
final class WindowsSnapshotValidity: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = UUID()

    func invalidate() {
        self.lock.lock()
        self.generation = UUID()
        self.lock.unlock()
    }

    func capture() -> @Sendable () -> Bool {
        self.lock.lock()
        let captured = self.generation
        self.lock.unlock()
        return { [self] in
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.generation == captured
        }
    }
}
#endif
