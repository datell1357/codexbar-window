#if os(Windows)
import Foundation

/// Owns the UI-started task synchronously so Cancel can win before the runtime actor starts it.
final class WindowsCursorBrowserImportTask: @unchecked Sendable {
    private let lock = NSLock()
    private var current: (id: UUID, task: Task<Void, Never>)?

    func start(id: UUID, operation: @escaping @Sendable () async -> Void) {
        self.lock.lock()
        self.current?.task.cancel()
        self.current = (id, Task {
            guard !Task.isCancelled else { return }
            await operation()
        })
        self.lock.unlock()
    }

    func cancel(id: UUID) {
        self.lock.lock()
        if self.current?.id == id {
            self.current?.task.cancel()
            self.current = nil
        }
        self.lock.unlock()
    }

    deinit { self.current?.task.cancel() }
}
#endif
