#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

/// Synthetic fixtures for the Windows read boundary. Written without running on the Mac host.
struct WindowsCostFileReadGuardTests {
    private func withLog(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-cost-read-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.jsonl")
        try Data("{\"id\":1}\n{\"id\":2}\n".utf8).write(to: file)
        try body(file)
    }

    @Test
    func `replacement between observation and open emits no lines`() throws {
        try self.withLog { file in
            let expected = try #require(CostUsageFileReadSnapshot.capture(at: file))
            let old = file.deletingLastPathComponent().appendingPathComponent("old.jsonl")
            try FileManager.default.moveItem(at: file, to: old)
            try Data("{\"id\":3}\n{\"id\":4}\n".utf8).write(to: file)
            var emitted = 0
            #expect(throws: WindowsCostFileReadGuard.Failure.self) {
                try CostUsageJsonl.scan(
                    fileURL: file, maxLineBytes: 1024, prefixBytes: 1024,
                    expectedFile: expected, onLine: { _ in emitted += 1 })
            }
            #expect(emitted == 0)
        }
    }

    @Test
    func `append during read is reserved for the next scan`() throws {
        try self.withLog { file in
            let expected = try #require(CostUsageFileReadSnapshot.capture(at: file))
            var firstPass: [Data] = []
            var appendError: (any Error)?
            let progress = try CostUsageJsonl.scanBounded(
                fileURL: file, maxLineBytes: 1024, prefixBytes: 1024,
                maxBytesToRead: nil, resumeState: nil, expectedFile: expected,
                onLine: { line in
                    firstPass.append(line.bytes)
                    guard firstPass.count == 1 else { return }
                    do {
                        let writer = try FileHandle(forWritingTo: file)
                        defer { try? writer.close() }
                        _ = try writer.seekToEnd()
                        try writer.write(contentsOf: Data("{\"id\":3}\n".utf8))
                    } catch { appendError = error }
                })
            try #require(appendError == nil)
            #expect(firstPass == [Data("{\"id\":1}".utf8), Data("{\"id\":2}".utf8)])
            #expect(progress.readOffset == expected.size)
            #expect(progress.committedOffset == expected.size)
            let updated = try #require(CostUsageFileReadSnapshot.capture(at: file))
            #expect(updated.size > expected.size)
            var secondPass: [Data] = []
            _ = try CostUsageJsonl.scan(
                fileURL: file, offset: progress.committedOffset, maxLineBytes: 1024, prefixBytes: 1024,
                expectedFile: updated, onLine: { secondPass.append($0.bytes) })
            #expect(secondPass == [Data("{\"id\":3}".utf8)])
        }
    }

    @Test
    func `truncation during callbacks cannot return successful progress`() throws {
        try self.withLog { file in
            let expected = try #require(CostUsageFileReadSnapshot.capture(at: file))
            var mutated = false
            var mutationError: (any Error)?
            #expect(throws: WindowsCostFileReadGuard.Failure.self) {
                try CostUsageJsonl.scan(
                    fileURL: file, maxLineBytes: 1024, prefixBytes: 1024, expectedFile: expected,
                    onLine: { _ in
                        guard !mutated else { return }
                        mutated = true
                        do {
                            let writer = try FileHandle(forWritingTo: file)
                            defer { try? writer.close() }
                            try writer.truncate(atOffset: 0)
                        } catch { mutationError = error }
                    })
            }
            #expect(mutated)
            #expect(mutationError == nil)
        }
    }

    @Test
    func `changed write time at the same size invalidates the open read`() throws {
        try self.withLog { file in
            let expected = try #require(CostUsageFileReadSnapshot.capture(at: file))
            let stream = try FileHandle(forReadingFrom: file)
            defer { try? stream.close() }
            let readGuard = try WindowsCostFileReadGuard(file: stream, url: file, expected: expected)
            let writer = try FileHandle(forWritingTo: file)
            try writer.write(contentsOf: Data("{\"id\":8}\n{\"id\":9}\n".utf8))
            try writer.close()
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_700_000_300)], ofItemAtPath: file.path)
            let updated = try #require(CostUsageFileReadSnapshot.capture(at: file))
            #expect(expected.fileID == updated.fileID)
            #expect(expected.size == updated.size)
            #expect(throws: WindowsCostFileReadGuard.Failure.self) { try readGuard.check() }
        }
    }

    @Test
    func `resume beyond the observed file boundary is rejected`() throws {
        try self.withLog { file in
            let expected = try #require(CostUsageFileReadSnapshot.capture(at: file))
            #expect(throws: WindowsCostFileReadGuard.Failure.self) {
                try CostUsageJsonl.scan(
                    fileURL: file, offset: expected.size + 1, maxLineBytes: 1024, prefixBytes: 1024,
                    expectedFile: expected, onLine: { _ in Issue.record("No out-of-bounds row is valid") })
            }
        }
    }
}
#endif
