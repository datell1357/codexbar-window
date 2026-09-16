#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

/// Synthetic source-only fixtures. No Windows discovery or persistence fixture was executed on the Mac.
struct WindowsCostSessionIdentityTests {
    private func withRoots(_ body: (URL, URL) throws -> Void) throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-session-identity-\(UUID().uuidString)", isDirectory: true)
        let sessions = base.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try body(base, sessions)
    }

    private func header(_ id: String) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: [
            "type": "session_meta", "timestamp": "2026-08-01T12:00:00Z", "payload": ["session_id": id],
        ], options: [.sortedKeys])
        data.append(10)
        return data
    }

    private func roundTrip(_ state: CostUsageCodexSessionDiscovery) throws -> CostUsageCodexSessionDiscovery {
        try JSONDecoder().decode(CostUsageCodexSessionDiscovery.self, from: JSONEncoder().encode(state))
    }

    private func found(_ index: CostUsageScanner.CodexSessionFileIndex, id: String, file: URL) throws {
        guard case let .found(actual) = try index.lookup(sessionId: id) else {
            Issue.record("Expected a head-verified session mapping")
            return
        }
        #expect(actual.standardizedFileURL == file.standardizedFileURL)
    }

    @Test
    func `same timestamp directory replacement invalidates a persisted missing lookup`() throws {
        try self.withRoots { base, sessions in
            let time = Date(timeIntervalSince1970: 1_700_000_000)
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: sessions.path)
            let first = CostUsageScanner.CodexSessionFileIndex(files: [], roots: [sessions])
            guard case .missing = try first.lookup(sessionId: "parent") else {
                Issue.record("An empty directory should have no parent")
                return
            }
            let state = try self.roundTrip(first.persistedState)
            let before = try #require(state.directoryStamps[sessions.path]?.windowsSnapshot)
            try FileManager.default.moveItem(at: sessions, to: base.appendingPathComponent("original-directory"))
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: false)
            let file = sessions.appendingPathComponent("parent.jsonl")
            try self.header("parent").write(to: file)
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: sessions.path)
            let current = try #require(WindowsCostFileMetadata.atURL(sessions))
            #expect(before.fileID != current.fileID)
            #expect(before.modifiedSeconds == current.modifiedSeconds)
            #expect(before.modifiedNanoseconds == current.modifiedNanoseconds)
            let resumed = CostUsageScanner.CodexSessionFileIndex(
                files: [], roots: [sessions], cachedDiscovery: state)
            try self.found(resumed, id: "parent", file: file)
            #expect(resumed.persistedState.directoryStamps[sessions.path]?.windowsSnapshot?.fileID == current.fileID)
        }
    }

    @Test
    func `same size and timestamp replacement cannot reuse the old parent ID`() throws {
        try self.withRoots { base, sessions in
            let file = sessions.appendingPathComponent("parent.jsonl")
            let time = Date(timeIntervalSince1970: 1_700_000_000)
            try self.header("before").write(to: file)
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
            let first = CostUsageScanner.CodexSessionFileIndex(files: [file], roots: [sessions])
            try self.found(first, id: "before", file: file)
            let state = try self.roundTrip(first.persistedState)
            let before = try #require(state.fileStamps[file.path]?.windowsSnapshot)
            try FileManager.default.moveItem(at: file, to: base.appendingPathComponent("original.jsonl"))
            try self.header("after!").write(to: file)
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
            let current = try WindowsCostFileMetadata.requiredFile(at: file)
            #expect(before.size == current.size)
            #expect(before.modifiedSeconds == current.modifiedSeconds)
            #expect(before.fileID != current.fileID)
            let resumed = CostUsageScanner.CodexSessionFileIndex(
                files: [], roots: [sessions], cachedDiscovery: state)
            guard case .missing = try resumed.lookup(sessionId: "before") else {
                Issue.record("The replacement must not inherit the previous session ID")
                return
            }
            try self.found(resumed, id: "after!", file: file)
        }
    }

    @Test
    func `caller supplied mappings require an actual session header`() throws {
        try self.withRoots { _, sessions in
            let file = sessions.appendingPathComponent("parent.jsonl")
            try self.header("actual").write(to: file)
            let index = CostUsageScanner.CodexSessionFileIndex(
                files: [], roots: [sessions], cachedSessionFiles: ["stale": file])
            guard case .missing = try index.lookup(sessionId: "stale") else {
                Issue.record("A cache-provided ID must not be assigned to a different header")
                return
            }
            try self.found(index, id: "actual", file: file)
        }
    }

    @Test
    func `fresh metadata alone cannot assign an unparsed session ID`() throws {
        try self.withRoots { _, sessions in
            let file = sessions.appendingPathComponent("parent.jsonl")
            try self.header("actual").write(to: file)
            let metadata = try CostUsageScanner.requiredCodexFileMetadata(fileURL: file)
            let index = CostUsageScanner.CodexSessionFileIndex(files: [], roots: [sessions])
            index.remember(fileURL: file, sessionId: "stale", metadata: metadata)
            guard case .missing = try index.lookup(sessionId: "stale") else {
                Issue.record("A fresh stat must not rebind a cached ID to unparsed contents")
                return
            }
            try self.found(index, id: "actual", file: file)
        }
    }

    @Test
    func `a partial head restarts after source replacement`() throws {
        try self.withRoots { base, sessions in
            let file = sessions.appendingPathComponent("parent.jsonl")
            try self.header("before").write(to: file)
            let first = CostUsageScanner.CodexSessionFileIndex(
                files: [file], roots: [sessions], scanBudget: .init(maxFileBytes: 8, maxBytesPerRefresh: 8))
            guard case .deferred = try first.lookup(sessionId: "before") else {
                Issue.record("The small budget should leave an unfinished header")
                return
            }
            let state = try self.roundTrip(first.persistedState)
            #expect(state.headScan?.windowsSnapshot != nil)
            #expect((state.headScan?.resumeState?.offset ?? 0) > 0)
            try FileManager.default.moveItem(at: file, to: base.appendingPathComponent("original.jsonl"))
            var replacement = Data([10])
            replacement.append(try self.header("after!"))
            try replacement.write(to: file)
            let resumed = CostUsageScanner.CodexSessionFileIndex(
                files: [], roots: [sessions], cachedDiscovery: state)
            guard case .missing = try resumed.lookup(sessionId: "before") else {
                Issue.record("Old buffered header bytes must not identify the replacement")
                return
            }
            try self.found(resumed, id: "after!", file: file)
        }
    }

    @Test
    func `negative cache notices an appended header with unchanged directory metadata`() throws {
        try self.withRoots { _, sessions in
            let file = sessions.appendingPathComponent("parent.jsonl")
            try Data().write(to: file)
            let time = Date(timeIntervalSince1970: 1_700_000_000)
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: sessions.path)
            let first = CostUsageScanner.CodexSessionFileIndex(files: [file], roots: [sessions])
            guard case .missing = try first.lookup(sessionId: "later") else {
                Issue.record("An empty file has no session ID")
                return
            }
            let state = try self.roundTrip(first.persistedState)
            let writer = try FileHandle(forWritingTo: file)
            try writer.write(contentsOf: self.header("later"))
            try writer.close()
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: sessions.path)
            let current = try #require(WindowsCostFileMetadata.atURL(sessions))
            #expect(state.directoryStamps[sessions.path]?.matchesWindows(.init(native: current)) == true)
            let resumed = CostUsageScanner.CodexSessionFileIndex(
                files: [], roots: [sessions], cachedDiscovery: state)
            try self.found(resumed, id: "later", file: file)
        }
    }

    @Test
    func `legacy stamps decode but do not authorize Windows reuse`() throws {
        try self.withRoots { _, sessions in
            let file = sessions.appendingPathComponent("parent.jsonl")
            try self.header("actual").write(to: file)
            let first = CostUsageScanner.CodexSessionFileIndex(files: [file], roots: [sessions])
            guard case .missing = try first.lookup(sessionId: "absent") else {
                Issue.record("The fixture has no requested parent")
                return
            }
            var state = try self.roundTrip(first.persistedState)
            let directory = try #require(state.directoryStamps[sessions.path])
            state.directoryStamps[sessions.path] = .init(
                mtimeUnixMs: directory.mtimeUnixMs, jsonlFileCount: directory.jsonlFileCount)
            state.fileStamps[file.path]?.windowsSnapshot = nil
            state.generation = "legacy-generation"
            var heads = 0
            let resumed = CostUsageScanner.CodexSessionFileIndex(
                files: [], roots: [sessions], cachedDiscovery: try self.roundTrip(state),
                headParseObserver: { heads += 1 })
            guard case .missing = try resumed.lookup(sessionId: "absent") else {
                Issue.record("Migration must preserve a real missing result")
                return
            }
            #expect(heads > 0)
            #expect(resumed.persistedState.generation?.hasPrefix("windows-v2:") == true)
            #expect(resumed.persistedState.fileStamps[file.path]?.windowsSnapshot != nil)
        }
    }

    @Test
    func `negative validation resumes its file cursor after a small budget`() throws {
        try self.withRoots { _, sessions in
            let files = try (0..<3).map { number in
                let file = sessions.appendingPathComponent("session-\(number).jsonl")
                try self.header("session-\(number)").write(to: file)
                return file
            }
            let first = CostUsageScanner.CodexSessionFileIndex(files: files, roots: [sessions])
            guard case let .missing(originalKey) = try first.lookup(sessionId: "absent") else {
                Issue.record("The fixture has no requested parent")
                return
            }
            var state = try self.roundTrip(first.persistedState)
            var completed = false
            var observedFileProgress = false
            for _ in 0..<6 {
                let resumed = CostUsageScanner.CodexSessionFileIndex(
                    files: [], roots: [sessions], cachedDiscovery: state,
                    scanBudget: .init(maxFileBytes: 1, maxBytesPerRefresh: 1))
                let result = try resumed.lookup(sessionId: "absent")
                state = try self.roundTrip(resumed.persistedState)
                observedFileProgress = observedFileProgress || (state.validationFileIndex ?? 0) > 0
                if case let .missing(key) = result {
                    #expect(key == originalKey)
                    completed = true
                    break
                }
                guard case .deferred = result else {
                    Issue.record("An unchanged negative inventory cannot create a parent")
                    return
                }
            }
            #expect(observedFileProgress)
            #expect(completed)
        }
    }
}
#endif
