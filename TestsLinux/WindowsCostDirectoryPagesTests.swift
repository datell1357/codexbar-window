#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

/// Unexecuted native paging fixtures. No provider directories or credentials are used.
extension WindowsCostPublicationTests {
    private func withPagedDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-directory-pages-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            WindowsCostDirectoryPages.shared.reset(under: root)
            try? FileManager.default.removeItem(at: root)
        }
        try body(root)
    }

    @Test
    func `pages bound native visits while covering all visible files and directories`() throws {
        try self.withPagedDirectory { root in
            var expected: Set<URL> = []
            for index in 0..<25 {
                let file = root.appendingPathComponent("session-\(index).jsonl")
                try Data("{}\n".utf8).write(to: file)
                expected.insert(file)
            }
            let nested = root.appendingPathComponent("nested", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
            expected.insert(nested)
            try Data().write(to: root.appendingPathComponent(".hidden.jsonl"))
            try Data().write(to: root.appendingPathComponent("ignored.txt"))
            let pages = WindowsCostDirectoryPages()
            let observations = CostUsagePublicationObservations()
            var continuation: CostUsageWindowsDirectoryPageState?
            var seen: Set<URL> = []
            var complete = false
            for _ in 0..<30 {
                let page = try pages.read(
                    in: root, continuation: continuation, visitLimit: 3,
                    publicationObservations: observations)
                #expect(page.visits <= 3)
                #expect(page.entries.count <= 3)
                for entry in page.entries { #expect(seen.insert(entry.url).inserted) }
                continuation = page.continuation
                if continuation == nil {
                    #expect(page.jsonlFileCount == 25)
                    complete = true
                    break
                }
            }
            #expect(complete)
            #expect(seen == expected)
            try observations.freeze().check()
        }
    }

    @Test
    func `a serialized offset without its live handle restarts enumeration instead of skipping`() throws {
        try self.withPagedDirectory { root in
            let expected = Set((0..<12).map { root.appendingPathComponent("\($0).jsonl") })
            for file in expected { try Data().write(to: file) }
            let original = WindowsCostDirectoryPages()
            let first = try original.read(in: root, continuation: nil, visitLimit: 5)
            let checkpoint = try JSONDecoder().decode(
                CostUsageWindowsDirectoryPageState.self, from: JSONEncoder().encode(#require(first.continuation)))
            let restarted = WindowsCostDirectoryPages()
            var page = try restarted.read(in: root, continuation: checkpoint, visitLimit: 5)
            #expect(page.restarted)
            #expect(page.continuation?.cursorID != checkpoint.cursorID)
            #expect(page.jsonlFileCount == page.entries.filter { !$0.snapshot.isDirectory }.count)
            var seen = Set(page.entries.map(\.url))
            for _ in 0..<20 {
                guard let continuation = page.continuation else { break }
                page = try restarted.read(in: root, continuation: continuation, visitLimit: 5)
                seen.formUnion(page.entries.map(\.url))
            }
            #expect(page.continuation == nil)
            #expect(seen == expected)
            #expect(page.jsonlFileCount == 12)
        }
    }

    @Test
    func `eviction and independent readers cannot borrow another enumeration ordinal`() throws {
        try self.withPagedDirectory { root in
            let other = root.appendingPathComponent("other", isDirectory: true)
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: false)
            for index in 0..<8 { try Data().write(to: root.appendingPathComponent("\(index).jsonl")) }
            let bounded = WindowsCostDirectoryPages(capacity: 1)
            let first = try bounded.read(in: root, continuation: nil, visitLimit: 3)
            let token = try #require(first.continuation)
            _ = try bounded.read(in: other, continuation: nil, visitLimit: 0)
            let replay = try bounded.read(in: root, continuation: token, visitLimit: 3)
            #expect(replay.restarted)
            #expect(replay.continuation?.cursorID != token.cursorID)

            let independent = WindowsCostDirectoryPages()
            let a = try independent.read(in: root, continuation: nil, visitLimit: 3)
            let b = try independent.read(in: root, continuation: nil, visitLimit: 3)
            #expect(a.continuation?.cursorID != b.continuation?.cursorID)
            let resumed = try independent.read(in: root, continuation: a.continuation, visitLimit: 3)
            #expect(!resumed.restarted)
            #expect(resumed.continuation?.cursorID == a.continuation?.cursorID)
        }
    }

    @Test
    func `admission and cancellation do not install a completed partial directory`() throws {
        try self.withPagedDirectory { root in
            for index in 0..<8 { try Data().write(to: root.appendingPathComponent("\(index).jsonl")) }
            let pages = WindowsCostDirectoryPages()
            var admitted = 0
            let first = try pages.read(in: root, continuation: nil, visitLimit: 20, admitVisit: {
                guard admitted < 2 else { return false }
                admitted += 1
                return true
            })
            #expect(first.visits == 2)
            let token = try #require(first.continuation)
            enum Stop: Error { case requested }
            #expect(throws: Stop.self) {
                try pages.read(in: root, continuation: token, visitLimit: 20, checkCancellation: { throw Stop.requested })
            }
            let retry = try pages.read(in: root, continuation: token, visitLimit: 3)
            #expect(retry.restarted)
            #expect(retry.continuation != nil)
        }
    }

    @Test
    func `same timestamp directory replacement discards its saved cursor`() throws {
        try self.withPagedDirectory { root in
            let source = root.appendingPathComponent("source", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
            for index in 0..<8 { try Data().write(to: source.appendingPathComponent("\(index).jsonl")) }
            let time = Date(timeIntervalSince1970: 1_700_000_000)
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: source.path)
            let pages = WindowsCostDirectoryPages()
            let first = try pages.read(in: source, continuation: nil, visitLimit: 3)
            try FileManager.default.moveItem(at: source, to: root.appendingPathComponent("retained"))
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
            let replacement = source.appendingPathComponent("replacement.jsonl")
            try Data().write(to: replacement)
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: source.path)
            let page = try pages.read(in: source, continuation: first.continuation, visitLimit: 10)
            #expect(page.restarted)
            #expect(page.continuation == nil)
            #expect(page.entries.map(\.url) == [replacement])
            #expect(page.jsonlFileCount == 1)
        }
    }

    @Test
    func `parent discovery persists an incomplete directory page through SQLite and resumes after handle loss`() throws {
        try self.withPagedDirectory { root in
            let logs = root.appendingPathComponent("logs", isDirectory: true)
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: false)
            for index in 0..<280 { try Data().write(to: logs.appendingPathComponent("ignored-\(index).txt")) }
            let first = CostUsageScanner.CodexSessionFileIndex(files: [], roots: [logs])
            guard case .deferred = try first.lookup(sessionId: "absent") else {
                Issue.record("The first directory page must not prove a missing session")
                return
            }
            let state = first.persistedState
            #expect(state.windowsDirectoryPage != nil)
            #expect(state.nextDirectoryIndex == 0)
            #expect(state.directoryStamps[logs.path] == nil)
            var cache = CostUsageCache()
            cache.codexSessionDiscovery = state
            let cacheRoot = root.appendingPathComponent("cache")
            _ = CostUsageStoreAccess.replace(cacheRoot: cacheRoot, cache: cache)
            let restored = try #require(CostUsageStoreAccess.read(cacheRoot: cacheRoot).codexSessionDiscovery)
            #expect(restored.windowsDirectoryPage == state.windowsDirectoryPage)
            WindowsCostDirectoryPages.shared.reset(under: logs)
            let second = CostUsageScanner.CodexSessionFileIndex(files: [], roots: [logs], cachedDiscovery: restored)
            guard case .deferred = try second.lookup(sessionId: "absent") else {
                Issue.record("A lost handle must replay the first page")
                return
            }
            #expect(second.persistedState.windowsDirectoryPage?.cursorID != state.windowsDirectoryPage?.cursorID)
            let last = CostUsageScanner.CodexSessionFileIndex(
                files: [], roots: [logs], cachedDiscovery: second.persistedState)
            guard case .missing = try last.lookup(sessionId: "absent") else {
                Issue.record("Expected completion only after native enumeration reached its end")
                return
            }
            #expect(last.persistedState.windowsDirectoryPage == nil)
            #expect(last.persistedState.isComplete)
        }
    }

    @Test
    func `one unit refresh budgets still advance parent directory enumeration`() throws {
        try self.withPagedDirectory { root in
            for index in 0..<3 { try Data().write(to: root.appendingPathComponent("ignored-\(index).txt")) }
            var state: CostUsageCodexSessionDiscovery?
            var finished = false
            var offsets: Set<Int64> = []
            for _ in 0..<30 {
                let index = CostUsageScanner.CodexSessionFileIndex(
                    files: [], roots: [root], cachedDiscovery: state,
                    scanBudget: .init(maxFileBytes: 1, maxBytesPerRefresh: 1))
                let result = try index.lookup(sessionId: "absent")
                state = index.persistedState
                if let offset = state?.windowsDirectoryPage?.offset { offsets.insert(offset) }
                if case .missing = result { finished = true; break }
            }
            #expect(offsets.count > 1)
            #expect(finished)
        }
    }
}
#endif
