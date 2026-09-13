#if os(Windows)
import Foundation

/// Runtime-owned memory only. A new settings generation receives a new cache instance.
public final class WindowsSessionTitleCache: @unchecked Sendable {
    struct Value {
        let names: [String: String]
        let seenIDs: Set<String>
        let unresolvedIDs: Set<String>
        subscript(_ id: String) -> String? { self.names[id] }
    }
    private struct Entry {
        let fingerprint: [UInt64]
        let value: Value
        let storedAt: Date
    }
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    public init() {}

    func get(_ key: String, fingerprint: [UInt64]) -> Value? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let entry = self.entries[key] else { return nil }
        let age = Date().timeIntervalSince(entry.storedAt)
        guard entry.fingerprint == fingerprint, age >= 0, age < 120 else {
            self.entries[key] = nil
            return nil
        }
        return entry.value
    }

    func put(_ key: String, fingerprint: [UInt64], value: Value) {
        guard key.utf8.count <= 8192, value.seenIDs.count <= 64,
              value.unresolvedIDs.count <= 64, value.names.count <= 64 else { return }
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.entries[key] == nil, self.entries.count >= 64,
           let oldest = self.entries.min(by: { $0.value.storedAt < $1.value.storedAt })?.key {
            self.entries[oldest] = nil
        }
        self.entries[key] = Entry(fingerprint: fingerprint, value: value, storedAt: Date())
    }
}
#endif
