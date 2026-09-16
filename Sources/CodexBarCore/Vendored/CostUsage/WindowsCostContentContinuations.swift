#if os(Windows)
import Foundation

/// Single-use, process-local SHA states. A persisted UUID is not a digest or a trust claim.
/// Missing/evicted tokens rebuild the prefix; metadata alone never authorizes a final report.
final class WindowsCostContentContinuations: @unchecked Sendable {
    struct Binding: Equatable {
        let path: String
        let source: CostUsageFileReadSnapshot
        let readOffset: Int64
        let committedOffset: Int64
        let readAnchor: CostUsageCodexTokenIndexAnchor?
        let committedAnchor: CostUsageCodexTokenIndexAnchor?
    }

    private struct Entry {
        let binding: Binding
        let content: WindowsCostContentRead
    }

    static let shared = WindowsCostContentContinuations(capacity: 64)
    private let capacity: Int
    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]
    private var order: [UUID] = []

    init(capacity: Int) { self.capacity = max(1, capacity) }

    /// Removal transfers exclusive ownership to the caller, even for a rejected binding.
    func take(_ token: UUID?, binding: Binding) -> WindowsCostContentRead? {
        guard let token else { return nil }
        self.lock.lock()
        defer { self.lock.unlock() }
        self.order.removeAll { $0 == token }
        guard let entry = self.entries.removeValue(forKey: token), entry.binding == binding else { return nil }
        return entry.content
    }

    /// The caller must stop mutating the state after yielding it here.
    func put(_ content: WindowsCostContentRead, binding: Binding) -> UUID {
        self.lock.lock()
        defer { self.lock.unlock() }
        while self.order.count >= self.capacity {
            self.entries.removeValue(forKey: self.order.removeFirst())
        }
        let token = UUID()
        self.entries[token] = Entry(binding: binding, content: content)
        self.order.append(token)
        return token
    }

    func discard(_ token: UUID?) {
        guard let token else { return }
        self.lock.lock()
        defer { self.lock.unlock() }
        self.entries.removeValue(forKey: token)
        self.order.removeAll { $0 == token }
    }

    func reset(under root: URL) {
        let path = root.standardizedFileURL.path
        let prefix = path.hasSuffix("/") ? path : path + "/"
        self.lock.lock()
        defer { self.lock.unlock() }
        let discarded = self.entries.filter {
            $0.value.binding.path == path || $0.value.binding.path.hasPrefix(prefix)
        }.map(\.key)
        for token in discarded { self.entries.removeValue(forKey: token) }
        self.order.removeAll { self.entries[$0] == nil }
    }
}
#endif
