#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

/// Source-only native fixtures. No oplock, file mutation, or test has been run on the Mac host.
@Suite(.serialized)
struct WindowsCostPublicationVerifierTests {
    private struct Fixture {
        let root: URL
        let file: URL
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        let data = Data((String(repeating: "{\"value\":1}\n", count: 20)).utf8)

        init() throws {
            self.root = FileManager.default.temporaryDirectory
                .appendingPathComponent("codexbar-publication-lease-\(UUID().uuidString)", isDirectory: true)
            self.file = self.root.appendingPathComponent("source.jsonl")
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
            try self.data.write(to: self.file)
            try FileManager.default.setAttributes([.modificationDate: self.time], ofItemAtPath: self.file.path)
        }

        func publication() throws -> CostUsageSourcePublication {
            let snapshot = try #require(CostUsageFileReadSnapshot.capture(at: self.file))
            let anchor = try #require(CostUsageScanner.codexTokenIndexAnchor(
                fileURL: self.file, indexedBytes: snapshot.size, expectedFile: snapshot))
            return CostUsageSourcePublication(entries: [.init(
                url: self.file, expectation: .file(snapshot), contentAnchors: [anchor])])
        }

        func mutate() throws {
            let replacement = Data((String(repeating: "{\"value\":9}\n", count: 20)).utf8)
            let writer = try FileHandle(forWritingTo: self.file)
            try writer.write(contentsOf: replacement)
            try writer.close()
            try FileManager.default.setAttributes([.modificationDate: self.time], ofItemAtPath: self.file.path)
        }

        func cleanup() { try? FileManager.default.removeItem(at: self.root) }
    }

    @Test
    func `supported read leases allow bounded verification and repeated publication checks`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.publication()
        let verifier = WindowsCostPublicationVerifier(entries: source.entries)
        defer { verifier.invalidate() }
        var result = WindowsCostPublicationVerifier.Progress.pending
        var calls = 0
        for _ in 0..<100 {
            calls += 1
            result = try verifier.advance(maxBytes: 7, maxEntries: 1, checkCancellation: nil)
            if result != .pending { break }
        }
        switch result {
        case .complete:
            #expect(calls >= (fixture.data.count + 6) / 7)
            let published = CostUsageSourcePublication(entries: source.entries, windowsVerifier: verifier)
            try published.check()
            try published.check()
            #expect(try verifier.canReuse(entries: source.entries, checkCancellation: nil))
        case .requiresFullCheck:
            // Unsupported/remote/capacity cases must still prove content via the ordinary path.
            try source.check()
            #expect(!(try verifier.canReuse(entries: source.entries, checkCancellation: nil)))
        case .pending:
            Issue.record("Stable content verification did not complete within its bounded slices")
        }
    }

    @Test
    func `boundary re-stat slices resume the cursor and wrap after a completed pass`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.publication()
        let verifier = WindowsCostPublicationVerifier(entries: source.entries)
        defer { verifier.invalidate() }
        var result = WindowsCostPublicationVerifier.Progress.pending
        for _ in 0..<100 {
            result = try verifier.advance(maxBytes: 7, maxEntries: 1, checkCancellation: nil)
            if result != .pending { break }
        }
        guard result == .complete else {
            // Lease-less sources cannot exercise the sliced boundary path.
            #expect(result == .requiresFullCheck)
            return
        }
        // A zero-visit slice stays partial; a one-visit slice completes the single entry.
        #expect(try verifier.canReuseSlice(entries: source.entries, maxEntries: 0, checkCancellation: nil) == 0)
        #expect(try verifier.canReuseSlice(entries: source.entries, maxEntries: 1, checkCancellation: nil) == 1)
        // A completed pass wraps the cursor so the next boundary starts fresh.
        #expect(try verifier.canReuseSlice(entries: source.entries, maxEntries: 1, checkCancellation: nil) == 1)
        try fixture.mutate()
        #expect(try verifier.canReuseSlice(entries: source.entries, maxEntries: 1, checkCancellation: nil) == nil)
    }

    @Test
    func `same stamp rewrite after verification cannot reuse the previous digest`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.publication()
        let verifier = WindowsCostPublicationVerifier(entries: source.entries)
        defer { verifier.invalidate() }
        let progress = try verifier.advance(maxBytes: 4096, maxEntries: 1, checkCancellation: nil)
        #expect(progress != .pending)
        try fixture.mutate()
        let published = CostUsageSourcePublication(entries: source.entries, windowsVerifier: verifier)
        #expect(throws: CostUsageSourcePublication.Failure.self) { try published.check() }
    }

    @Test
    func `mutation during bounded verification requires a full comparison before publication`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.publication()
        let verifier = WindowsCostPublicationVerifier(entries: source.entries)
        defer { verifier.invalidate() }
        let initial = try verifier.advance(maxBytes: 7, maxEntries: 1, checkCancellation: nil)
        #expect(initial != .complete)
        try fixture.mutate()
        let next = try verifier.advance(maxBytes: 4096, maxEntries: 1, checkCancellation: nil)
        #expect(next == .requiresFullCheck)
        let published = CostUsageSourcePublication(entries: source.entries, windowsVerifier: verifier)
        #expect(throws: CostUsageSourcePublication.Failure.self) { try published.check() }
    }

    @Test
    func `verification capacity falls back to content checks and token bindings cannot be substituted`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.publication()
        let tooMany = WindowsCostPublicationVerifier(entries: Array(repeating: source.entries[0], count: 65))
        #expect(try tooMany.advance(maxBytes: 1, maxEntries: 1, checkCancellation: nil) == .requiresFullCheck)
        #expect(!(try tooMany.canReuse(entries: source.entries, checkCancellation: nil)))
        let registry = WindowsCostPublicationVerifications()
        let verifier = WindowsCostPublicationVerifier(entries: [])
        #expect(try verifier.advance(maxBytes: 0, maxEntries: 0, checkCancellation: nil) == .complete)
        let token = registry.put(verifier)
        let wrong = registry.take(token, entries: source.entries)
        #expect(wrong !== verifier)
        let consumed = registry.take(token, entries: [])
        #expect(consumed !== verifier)
        let one = registry.put(verifier)
        #expect(registry.take(one, entries: []) === verifier)
        #expect(registry.take(one, entries: []) !== verifier)
    }

    @Test
    func `cancellation never produces a reusable verification`() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.publication()
        let verifier = WindowsCostPublicationVerifier(entries: source.entries)
        defer { verifier.invalidate() }
        enum Stop: Error { case requested }
        #expect(throws: Stop.self) {
            try verifier.advance(maxBytes: 4096, maxEntries: 1, checkCancellation: { throw Stop.requested })
        }
        #expect(!(try verifier.canReuse(entries: source.entries, checkCancellation: nil)))
    }
}
#endif
