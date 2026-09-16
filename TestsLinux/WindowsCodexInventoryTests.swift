#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

/// Implementation-only fixtures. No Windows directory or cache operation was executed on the Mac.
struct WindowsCodexInventoryTests {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-codex-inventory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    @Test
    func `shallow inventory distinguishes missing empty and non-directory roots`() throws {
        try self.withDirectory { root in
            #expect(try WindowsCostDirectoryInventory.read(in: root)?.entries.isEmpty == true)
            #expect(try WindowsCostDirectoryInventory.read(in: root.appendingPathComponent("absent")) == nil)
            let file = root.appendingPathComponent("ordinary-file")
            try Data("x".utf8).write(to: file)
            #expect(throws: WindowsCostSourceInventory.Failure.self) {
                try WindowsCostDirectoryInventory.read(in: file)
            }
        }
    }

    @Test
    func `shallow inventory separates jsonl files from folders and hidden names`() throws {
        try self.withDirectory { root in
            try Data("{}\n".utf8).write(to: root.appendingPathComponent("세션.JSONL"))
            try Data("{}\n".utf8).write(to: root.appendingPathComponent(".hidden.jsonl"))
            try Data("ignored".utf8).write(to: root.appendingPathComponent("readme.txt"))
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("folder.jsonl", isDirectory: true), withIntermediateDirectories: false)
            let all = try #require(WindowsCostDirectoryInventory.read(in: root))
            #expect(Set(all.entries.map(\.url.lastPathComponent)) == ["세션.JSONL", "folder.jsonl"])
            #expect(all.entries.first(where: { $0.url.lastPathComponent == "folder.jsonl" })?.snapshot.isDirectory == true)
            let files = try #require(WindowsCostDirectoryInventory.read(in: root, includeDirectories: false))
            #expect(files.entries.map(\.url.lastPathComponent) == ["세션.JSONL"])
        }
    }

    @Test
    func `cancelled directory reading cannot return partial inventory`() throws {
        try self.withDirectory { root in
            try Data("{}\n".utf8).write(to: root.appendingPathComponent("session.jsonl"))
            enum Cancelled: Error { case requested }
            var checks = 0
            #expect(throws: Cancelled.self) {
                try WindowsCostDirectoryInventory.read(in: root, checkCancellation: {
                    checks += 1
                    if checks == 2 { throw Cancelled.requested }
                })
            }
            #expect(checks == 2)
        }
    }

    @Test
    func `parent discovery refuses an invalid root instead of recording a missing session`() throws {
        try self.withDirectory { root in
            let file = root.appendingPathComponent("root-is-a-file")
            try Data("{}".utf8).write(to: file)
            let index = CostUsageScanner.CodexSessionFileIndex(files: [], roots: [file])
            #expect(throws: WindowsCostSourceInventory.Failure.self) {
                try index.lookup(sessionId: "synthetic-parent")
            }
            #expect(!index.persistedState.missingSessionIds.contains("synthetic-parent"))
            #expect(!index.persistedState.isComplete)
        }
    }

    @Test
    func `cached parent mapped to a directory is not a valid or missing file`() throws {
        try self.withDirectory { root in
            let index = CostUsageScanner.CodexSessionFileIndex(
                files: [], roots: [root], cachedSessionFiles: ["synthetic-parent": root])
            #expect(throws: WindowsCostSourceInventory.Failure.self) {
                try index.lookup(sessionId: "synthetic-parent")
            }
            #expect(!index.persistedState.missingSessionIds.contains("synthetic-parent"))
            #expect(throws: WindowsCostSourceInventory.Failure.self) {
                try CostUsageScanner.codexFileExists(fileURL: root)
            }
            #expect(try CostUsageScanner.codexFileExists(fileURL: root.appendingPathComponent("absent.jsonl")) == false)
        }
    }
}
#endif
