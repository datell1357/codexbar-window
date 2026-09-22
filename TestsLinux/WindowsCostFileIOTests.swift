#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

/// Synthetic Windows-only fixtures. Added during implementation; not executed on the Mac host.
struct WindowsCostFileIOTests {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-cost-io-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    @Test
    func `same size and timestamp replacement has a different native identity`() throws {
        try self.withDirectory { root in
            let target = root.appendingPathComponent("session.jsonl")
            let replacement = root.appendingPathComponent("replacement.jsonl")
            try Data("first".utf8).write(to: target)
            try Data("other".utf8).write(to: replacement)
            let time = Date(timeIntervalSince1970: 1_700_000_000)
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: target.path)
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: replacement.path)
            let before = try WindowsCostFileMetadata.requiredFile(at: target)
            let replacementStamp = try WindowsCostFileMetadata.requiredFile(at: replacement)
            // Keep the original object alive under another name; no file-ID reuse is possible.
            try FileManager.default.moveItem(at: target, to: root.appendingPathComponent("old.jsonl"))
            try FileManager.default.moveItem(at: replacement, to: target)
            let after = try WindowsCostFileMetadata.requiredFile(at: target)
            #expect(before.size == after.size)
            #expect(before.mtimeUnixMs == after.mtimeUnixMs)
            #expect(before.fileID != after.fileID)
            #expect(replacementStamp.fileID == after.fileID)
            let stream = try FileHandle(forReadingFrom: target)
            defer { try? stream.close() }
            #expect(try WindowsCostFileMetadata.opened(stream) == after)
            #expect(CostUsageScanner.codexFileMetadata(fileURL: target).fileId == after.fileID)
        }
    }

    @Test
    func `directory enumeration retains native entries across calls and distinguishes file kinds`() throws {
        try self.withDirectory { root in
            for name in ["한글.jsonl", "plain.jsonl", "ignore.txt"] {
                try Data("{}\n".utf8).write(to: root.appendingPathComponent(name))
            }
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("folder.jsonl", isDirectory: true), withIntermediateDirectories: false)
            let snapshot = try #require(WindowsCostFileMetadata.atURL(root))
            #expect(snapshot.isDirectory)
            let cursor = try WindowsCostDirectoryCursor(directoryURL: root, snapshot: snapshot)
            var names: [String] = []
            var directoryNames: [String] = []
            var visits = 0
            while let entry = try cursor.next() {
                visits += 1
                #expect(visits <= 6)
                if visits > 6 { break }
                if entry.name == "." || entry.name == ".." { continue }
                if entry.isDirectory { directoryNames.append(entry.name) } else { names.append(entry.name) }
            }
            #expect(names.sorted() == ["한글.jsonl", "plain.jsonl", "ignore.txt"].sorted())
            #expect(directoryNames == ["folder.jsonl"])
            #expect(try cursor.next() == nil)
            #expect(try WindowsCostFileMetadata.atURL(root.appendingPathComponent("missing")) == nil)
            #expect(throws: (any Error).self) { try WindowsCostFileMetadata.requiredFile(at: root) }
        }
    }

    @Test
    func `Claude cache replacement publishes new bytes and cancellation preserves the old cache`() throws {
        try self.withDirectory { root in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
            let first = try #require(CostUsageClaudeCacheIO.save(
                provider: .claude, cache: CostUsageClaudeCache(), cacheRoot: root, calendar: calendar))
            let url = CostUsageClaudeCacheIO.cacheFileURL(provider: .claude, cacheRoot: root)
            let firstBytes = try Data(contentsOf: url)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 3600))
            let second = try #require(CostUsageClaudeCacheIO.save(
                provider: .claude, cache: CostUsageClaudeCache(), cacheRoot: root, calendar: calendar))
            let secondBytes = try Data(contentsOf: url)
            #expect(firstBytes != secondBytes)
            #expect(first.fileID != second.fileID)
            #expect(CostUsageClaudeFileStamp.read(at: url) == second)

            enum Cancelled: Error { case requested }
            var checks = 0
            #expect(throws: Cancelled.self) {
                _ = try CostUsageClaudeCacheIO.save(
                    provider: .claude, cache: CostUsageClaudeCache(), cacheRoot: root, calendar: calendar,
                    checkCancellation: {
                        checks += 1
                        if checks == 2 { throw Cancelled.requested }
                    })
            }
            #expect(checks == 2)
            #expect(try Data(contentsOf: url) == secondBytes)
            #expect(CostUsageClaudeFileStamp.read(at: url) == second)
        }
    }

    @Test
    func `bounded reader honors its limit and fails closed on overflow`() throws {
        try self.withDirectory { root in
            let file = root.appendingPathComponent("bounded.json")
            try Data(repeating: 0x41, count: 128).write(to: file)
            #expect(try WindowsBoundedFileReader.readIfPresent(at: file, maximumBytes: 128)?.count == 128)
            #expect(throws: WindowsBoundedFileReader.Failure.self) {
                _ = try WindowsBoundedFileReader.readIfPresent(at: file, maximumBytes: 64)
            }
            #expect(try WindowsBoundedFileReader.readIfPresent(
                at: root.appendingPathComponent("missing.json"), maximumBytes: 64) == nil)
        }
    }

    @Test
    func `an oversized persisted cache artifact fails closed to an empty cache`() throws {
        try self.withDirectory { root in
            let url = CostUsageClaudeCacheIO.cacheFileURL(provider: .claude, cacheRoot: root)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0x7B, count: CostUsageClaudeCacheIO.maximumPersistedBytes + 1).write(to: url)
            let cache = CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: root)
            #expect(cache.usage.files.isEmpty)
            #expect(cache.windowsContent == nil)
        }
    }
}
#endif
