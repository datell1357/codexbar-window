#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

/// Implementation-only Windows fixtures; no real provider directories or credentials are used.
struct WindowsCostSourceInventoryTests {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-cost-inventory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    @Test
    func `inventory distinguishes absent empty and invalid roots`() throws {
        try self.withDirectory { root in
            #expect(try WindowsCostSourceInventory.jsonlFiles(in: root)?.isEmpty == true)
            #expect(try WindowsCostSourceInventory.jsonlFiles(in: root.appendingPathComponent("missing")) == nil)
            let ordinaryFile = root.appendingPathComponent("ordinary-file")
            try Data("{}".utf8).write(to: ordinaryFile)
            #expect(throws: WindowsCostSourceInventory.Failure.self) {
                try WindowsCostSourceInventory.jsonlFiles(in: ordinaryFile)
            }
        }
    }

    @Test
    func `recursive inventory includes empty logs and excludes directories named jsonl`() throws {
        try self.withDirectory { root in
            let nested = root.appendingPathComponent("project.jsonl", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
            let log = nested.appendingPathComponent("세션.jsonl")
            let empty = nested.appendingPathComponent("empty.jsonl")
            try Data("{}\n".utf8).write(to: log)
            try Data().write(to: empty)
            try Data("ignored".utf8).write(to: root.appendingPathComponent("notes.txt"))
            let inventory = try #require(WindowsCostSourceInventory.jsonlFiles(in: root))
            #expect(Set(inventory.keys.map(\.lastPathComponent)) == ["세션.jsonl", "empty.jsonl"])
            #expect(inventory.values.contains { $0.size == 0 })
            for (url, stamp) in inventory {
                try WindowsCostSourceInventory.requireUnchangedFile(at: url, stamp: stamp)
            }
        }
    }

    @Test
    func `custom cancellation during enumeration never returns a partial inventory`() throws {
        try self.withDirectory { root in
            try Data("{}\n".utf8).write(to: root.appendingPathComponent("session.jsonl"))
            enum Cancelled: Error { case requested }
            var calls = 0
            #expect(throws: Cancelled.self) {
                try WindowsCostSourceInventory.jsonlFiles(in: root, checkCancellation: {
                    calls += 1
                    if calls == 2 { throw Cancelled.requested }
                })
            }
            #expect(calls == 2)
        }
    }

    @Test
    func `files changed since inventory cannot reuse the old source stamp`() throws {
        try self.withDirectory { root in
            let log = root.appendingPathComponent("session.jsonl")
            try Data("{}\n".utf8).write(to: log)
            let stamp = try CostUsageClaudeFileStamp.readRequired(at: log)
            try WindowsCostSourceInventory.requireUnchangedFile(at: log, stamp: stamp)
            let writer = try FileHandle(forWritingTo: log)
            _ = try writer.seekToEnd()
            try writer.write(contentsOf: Data("{}\n".utf8))
            try writer.close()
            #expect(throws: WindowsCostSourceInventory.Failure.self) {
                try WindowsCostSourceInventory.requireUnchangedFile(at: log, stamp: stamp)
            }
        }
    }
}
#endif
