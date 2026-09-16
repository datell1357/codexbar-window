import Foundation

/// The token identifies a live process-local enumeration, not an ordinal that can be replayed
/// on a new FindFirstFile handle. A decoded token without its handle restarts from the beginning.
struct CostUsageWindowsDirectoryPageState: Codable, Equatable, Sendable {
    var version: Int = 1
    let path: String
    let snapshot: CostUsageFileReadSnapshot
    let cursorID: String
    let offset: Int64
    let jsonlFileCount: Int
}

#if os(Windows)
final class WindowsCostDirectoryPages: @unchecked Sendable {
    struct Page {
        let directorySnapshot: WindowsCostFileMetadata.Snapshot?
        let entries: [WindowsCostDirectoryInventory.Entry]
        let continuation: CostUsageWindowsDirectoryPageState?
        let jsonlFileCount: Int
        let visits: Int
        let restarted: Bool
    }

    private struct Slot {
        let path: String
        let cursor: WindowsCostDirectoryCursor
        var jsonlFileCount: Int
    }

    static let shared = WindowsCostDirectoryPages()
    private let lock = NSLock()
    private let capacity: Int
    private var slots: [String: Slot] = [:]

    init(capacity: Int = 64) { self.capacity = max(1, capacity) }

    func read(
        in directory: URL,
        continuation: CostUsageWindowsDirectoryPageState?,
        visitLimit: Int,
        admitVisit: (() -> Bool)? = nil,
        checkCancellation: (() throws -> Void)? = nil,
        publicationObservations: CostUsagePublicationObservations? = nil) throws -> Page
    {
        self.lock.lock()
        defer { self.lock.unlock() }
        let path = directory.standardizedFileURL.path
        var activeID: String?
        do {
            try Self.check(checkCancellation)
            guard let snapshot = try WindowsCostFileMetadata.atURL(directory) else {
                self.discardUnlocked(continuation, path: path)
                try publicationObservations?.missing(directory)
                return Page(directorySnapshot: nil, entries: [], continuation: nil,
                            jsonlFileCount: 0, visits: 0, restarted: continuation != nil)
            }
            guard snapshot.isDirectory else { throw WindowsCostSourceInventory.Failure.unreadableDirectory }
            let matching: String?
            if let continuation, continuation.version == 1, continuation.path == path,
               continuation.offset >= 0, continuation.jsonlFileCount >= 0,
               continuation.snapshot == CostUsageFileReadSnapshot(native: snapshot),
               let slot = self.slots[continuation.cursorID], slot.path == path,
               slot.cursor.snapshot == snapshot, slot.cursor.logicalOffset == continuation.offset,
               slot.jsonlFileCount == continuation.jsonlFileCount
            {
                matching = continuation.cursorID
            } else {
                matching = nil
            }
            let cursorID: String
            if let matching {
                cursorID = matching
            } else {
                self.discardUnlocked(continuation, path: path)
                if self.slots.count >= self.capacity, let evicted = self.slots.keys.first {
                    self.slots.removeValue(forKey: evicted)
                }
                cursorID = UUID().uuidString
                self.slots[cursorID] = Slot(
                    path: path, cursor: try WindowsCostDirectoryCursor(directoryURL: directory, snapshot: snapshot),
                    jsonlFileCount: 0)
            }
            activeID = cursorID
            guard var slot = self.slots[cursorID] else { throw WindowsCostSourceInventory.Failure.sourceChanged }
            var entries: [WindowsCostDirectoryInventory.Entry] = []
            var visits = 0
            var complete = false
            while visits < max(0, visitLimit) {
                try Self.check(checkCancellation)
                guard admitVisit?() != false else { break }
                visits += 1
                guard let entry = try slot.cursor.next() else {
                    complete = true
                    break
                }
                guard slot.cursor.logicalOffset < Int64.max else { throw WindowsCostSourceInventory.Failure.sourceChanged }
                slot.cursor.logicalOffset += 1
                guard !entry.isHidden, !entry.name.hasPrefix(".") else { continue }
                guard entry.isDirectory || entry.name.lowercased().hasSuffix(".jsonl") else { continue }
                let url = directory.appendingPathComponent(entry.name, isDirectory: entry.isDirectory)
                guard let observed = try WindowsCostFileMetadata.atURL(url), observed.isDirectory == entry.isDirectory
                else { throw WindowsCostSourceInventory.Failure.sourceChanged }
                if !observed.isDirectory {
                    guard slot.jsonlFileCount < Int.max else { throw WindowsCostSourceInventory.Failure.sourceChanged }
                    slot.jsonlFileCount += 1
                }
                entries.append(.init(url: url, snapshot: observed))
            }
            for entry in entries {
                try Self.check(checkCancellation)
                guard try WindowsCostFileMetadata.atURL(entry.url) == entry.snapshot else {
                    throw WindowsCostSourceInventory.Failure.sourceChanged
                }
                if entry.snapshot.isDirectory {
                    try publicationObservations?.directory(entry.url, snapshot: .init(native: entry.snapshot))
                } else {
                    try publicationObservations?.file(entry.url, snapshot: .init(native: entry.snapshot))
                }
            }
            try Self.check(checkCancellation)
            guard try WindowsCostFileMetadata.atURL(directory) == snapshot else {
                throw WindowsCostSourceInventory.Failure.sourceChanged
            }
            try publicationObservations?.directory(directory, snapshot: .init(native: snapshot))
            let next: CostUsageWindowsDirectoryPageState?
            if complete {
                self.slots.removeValue(forKey: cursorID)
                next = nil
            } else {
                self.slots[cursorID] = slot
                next = CostUsageWindowsDirectoryPageState(
                    path: path, snapshot: .init(native: snapshot), cursorID: cursorID,
                    offset: slot.cursor.logicalOffset, jsonlFileCount: slot.jsonlFileCount)
            }
            return Page(directorySnapshot: snapshot, entries: entries, continuation: next,
                        jsonlFileCount: slot.jsonlFileCount, visits: visits, restarted: matching == nil)
        } catch {
            if let activeID { self.slots.removeValue(forKey: activeID) }
            self.discardUnlocked(continuation, path: path)
            throw error
        }
    }

    func discard(_ continuation: CostUsageWindowsDirectoryPageState?) {
        guard let continuation else { return }
        self.lock.lock()
        defer { self.lock.unlock() }
        self.discardUnlocked(continuation, path: continuation.path)
    }

    func reset(under root: URL) {
        let path = root.standardizedFileURL.path.replacingOccurrences(of: "\\", with: "/")
        let prefix = path.hasSuffix("/") ? path : path + "/"
        self.lock.lock()
        defer { self.lock.unlock() }
        let keys = self.slots.compactMap { key, slot -> String? in
            let candidate = slot.path.replacingOccurrences(of: "\\", with: "/")
            return candidate == path || candidate.hasPrefix(prefix) ? key : nil
        }
        for key in keys { self.slots.removeValue(forKey: key) }
    }

    private func discardUnlocked(_ continuation: CostUsageWindowsDirectoryPageState?, path: String) {
        guard let continuation, self.slots[continuation.cursorID]?.path == path else { return }
        self.slots.removeValue(forKey: continuation.cursorID)
    }

    private static func check(_ callback: (() throws -> Void)?) throws {
        try Task.checkCancellation()
        try callback?()
    }
}
#endif
