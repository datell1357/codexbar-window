#if os(Windows)
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Bounded content verification while advisory read leases remain intact. There is no
/// metadata-only fallback: unavailable/broken leases require the ordinary full recheck.
final class WindowsCostPublicationVerifier: @unchecked Sendable {
    enum Progress: Equatable { case pending, complete, requiresFullCheck }
    private enum Failure: Error { case leaseBroken }

    private final class Content {
        let lease: WindowsCostReadLease
        let handle: FileHandle
        let readGuard: WindowsCostFileReadGuard
        let anchors: [CostUsageCodexTokenIndexAnchor]
        var digest = SHA256()
        var offset: Int64 = 0
        var nextAnchor = 0

        init?(entry: CostUsageSourcePublication.Entry, current: CostUsageFileReadSnapshot) throws {
            let anchors = entry.contentAnchors.sorted { $0.indexedBytes < $1.indexedBytes }
            guard anchors.allSatisfy({ $0.windowStart == 0 && $0.indexedBytes > 0
                && $0.indexedBytes <= current.size }) else {
                throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
            }
            guard let lease = try WindowsCostReadLease.acquire(at: entry.url, expected: current) else { return nil }
            self.lease = lease
            do {
                let handle = try FileHandle(forReadingFrom: entry.url)
                do {
                    self.readGuard = try WindowsCostFileReadGuard(file: handle, url: entry.url, expected: lease.snapshot)
                } catch {
                    try? handle.close()
                    throw error
                }
                self.handle = handle
                self.anchors = anchors
            } catch {
                lease.close()
                throw error
            }
        }

        func advance(bytes: inout Int64, checkCancellation: (() throws -> Void)?) throws -> Bool {
            while self.nextAnchor < self.anchors.count {
                try Task.checkCancellation()
                try checkCancellation?()
                guard self.lease.isIntact else { throw Failure.leaseBroken }
                try self.readGuard.check()
                let anchor = self.anchors[self.nextAnchor]
                if self.offset == anchor.indexedBytes {
                    var copy = self.digest
                    let digest = copy.finalize().map { String(format: "%02x", $0) }.joined()
                    guard digest == anchor.sha256 else {
                        throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
                    }
                    self.nextAnchor += 1
                    continue
                }
                guard bytes > 0 else { return false }
                let count = Int(min(64 * 1024, min(bytes, anchor.indexedBytes - self.offset)))
                guard let data = try self.handle.read(upToCount: count), !data.isEmpty else {
                    throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
                }
                self.digest.update(data: data)
                self.offset += Int64(data.count)
                bytes -= Int64(data.count)
                guard self.lease.isIntact else { throw Failure.leaseBroken }
            }
            return true
        }

        deinit { try? self.handle.close(); self.lease.close() }
    }

    let entries: [CostUsageSourcePublication.Entry]
    private let lock = NSLock()
    private var nextEntry = 0
    private var contents: [Int: Content] = [:]
    private var fallback = false

    init(entries: [CostUsageSourcePublication.Entry]) {
        self.entries = entries
        // Bound retained native handles. Larger sets continue through full verification.
        self.fallback = entries.filter { !$0.contentAnchors.isEmpty }.count > 64
    }

    func advance(
        maxBytes: Int64, maxEntries: Int, checkCancellation: (() throws -> Void)?) throws -> Progress
    {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.fallback { return .requiresFullCheck }
        if !self.leasesIntact { self.abandon(); return .requiresFullCheck }
        var bytes = max(0, maxBytes)
        var visits = max(0, maxEntries)
        do {
            while self.nextEntry < self.entries.count, visits > 0 {
                try Task.checkCancellation()
                try checkCancellation?()
                visits -= 1
                let entry = self.entries[self.nextEntry]
                let current = try CostUsageSourcePublication.checkMetadata(entry)
                if !entry.contentAnchors.isEmpty {
                    guard let current else { throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable }
                    if self.contents[self.nextEntry] == nil {
                        guard let content = try Content(entry: entry, current: current) else {
                            self.abandon()
                            return .requiresFullCheck
                        }
                        self.contents[self.nextEntry] = content
                    }
                    guard let content = self.contents[self.nextEntry],
                          try content.advance(bytes: &bytes, checkCancellation: checkCancellation) else {
                        return .pending
                    }
                }
                self.nextEntry += 1
            }
            guard self.leasesIntact else { self.abandon(); return .requiresFullCheck }
            return self.nextEntry == self.entries.count ? .complete : .pending
        } catch Failure.leaseBroken {
            self.abandon()
            return .requiresFullCheck
        }
    }

    func canReuse(
        entries: [CostUsageSourcePublication.Entry], checkCancellation: (() throws -> Void)?) throws -> Bool
    {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard entries == self.entries, !self.fallback, self.nextEntry == entries.count else { return false }
        guard self.leasesIntact else { self.abandon(); return false }
        // Recheck names/native IDs/directories at each actual publication boundary. An
        // intact lease proves only its opened stream, not that a path still names that stream.
        for entry in entries {
            try Task.checkCancellation()
            try checkCancellation?()
            _ = try CostUsageSourcePublication.checkMetadata(entry)
        }
        guard self.leasesIntact else { self.abandon(); return false }
        return true
    }

    private var leasesIntact: Bool { self.contents.values.allSatisfy { $0.lease.isIntact } }

    func invalidate() {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.abandon()
    }

    private func abandon() {
        self.fallback = true
        self.contents.removeAll()
    }
}

/// Live verification cannot be reconstructed from disk as trusted evidence. A missed token
/// starts verification from zero; rows remain staged until that verification completes.
final class WindowsCostPublicationVerifications: @unchecked Sendable {
    static let shared = WindowsCostPublicationVerifications()
    private let lock = NSLock()
    private var entries: [UUID: WindowsCostPublicationVerifier] = [:]
    private var order: [UUID] = []

    func take(_ token: UUID?, entries: [CostUsageSourcePublication.Entry]) -> WindowsCostPublicationVerifier {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let token else { return WindowsCostPublicationVerifier(entries: entries) }
        self.order.removeAll { $0 == token }
        guard let value = self.entries.removeValue(forKey: token) else {
            return WindowsCostPublicationVerifier(entries: entries)
        }
        guard value.entries == entries else {
            value.invalidate()
            return WindowsCostPublicationVerifier(entries: entries)
        }
        return value
    }

    func put(_ value: WindowsCostPublicationVerifier) -> UUID {
        self.lock.lock()
        defer { self.lock.unlock() }
        while self.order.count >= 4 { self.entries.removeValue(forKey: self.order.removeFirst())?.invalidate() }
        let token = UUID()
        self.entries[token] = value
        self.order.append(token)
        return token
    }

    func discard(_ token: UUID?) {
        guard let token else { return }
        self.lock.lock()
        defer { self.lock.unlock() }
        self.entries.removeValue(forKey: token)?.invalidate()
        self.order.removeAll { $0 == token }
    }
}

/// Resume keys for sliced publication checks that have no durable home, such as the Codex
/// report boundary. Process-local: a lost token or cursor restarts the pass from zero, and
/// canonical entry equality does the real binding. Keys are caller-chosen identities.
final class WindowsCostPublicationResumeKeys: @unchecked Sendable {
    static let shared = WindowsCostPublicationResumeKeys()
    private let lock = NSLock()
    private var tokens: [String: UUID] = [:]
    private var checked: [String: Int] = [:]
    private var order: [String] = []
    private let capacity = 8

    func token(for key: String) -> UUID? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.tokens[key]
    }

    func setToken(_ token: UUID?, for key: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.order.removeAll { $0 == key }
        if let token {
            self.tokens[key] = token
            self.order.append(key)
        } else {
            self.tokens.removeValue(forKey: key)
        }
        self.evictIfNeeded()
    }

    func checkedCount(for key: String) -> Int? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.checked[key]
    }

    func setCheckedCount(_ count: Int?, for key: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.order.removeAll { $0 == key }
        if let count {
            self.checked[key] = count
            self.order.append(key)
        } else {
            self.checked.removeValue(forKey: key)
        }
        self.evictIfNeeded()
    }

    func clear(for key: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.tokens.removeValue(forKey: key)
        self.checked.removeValue(forKey: key)
        self.order.removeAll { $0 == key }
    }

    private func evictIfNeeded() {
        while self.order.count > self.capacity, let oldest = self.order.first {
            self.order.removeFirst()
            self.tokens.removeValue(forKey: oldest)
            self.checked.removeValue(forKey: oldest)
        }
    }
}
#endif
