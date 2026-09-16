#if os(Windows)
import Foundation
import Testing
import WinSDK
@testable import CodexBarCore

/// Source-only NTFS link fixtures. Native junction/hard-link creation failures are test
/// failures, not skipped coverage; the Windows runner must support these filesystem operations.
extension WindowsCostPublicationTests {
    private final class TraversalFixture {
        let root: URL
        let logs: URL
        private var junctions: [URL] = []

        init() throws {
            self.root = FileManager.default.temporaryDirectory
                .appendingPathComponent("codexbar-cost-traversal-\(UUID().uuidString)", isDirectory: true)
            self.logs = self.root.appendingPathComponent("logs", isDirectory: true)
            try FileManager.default.createDirectory(at: self.logs, withIntermediateDirectories: true)
        }

        func directory(_ name: String) throws -> URL {
            let url = self.logs.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        func hardLink(_ alias: URL, to target: URL) throws {
            let aliasPath = Array(alias.path.utf16) + [UInt16(0)]
            let targetPath = Array(target.path.utf16) + [UInt16(0)]
            let result = aliasPath.withUnsafeBufferPointer { a in
                targetPath.withUnsafeBufferPointer { t in CreateHardLinkW(a.baseAddress, t.baseAddress, nil) }
            }
            guard result != 0 else { throw WindowsCostFileMetadata.failure(GetLastError()) }
        }

        /// MountPointReparseBuffer layout: eight-byte header, four UInt16 offsets/lengths,
        /// then null-terminated UTF-16 substitute and print names. No shell or real user paths.
        func junction(_ alias: URL, to target: URL) throws {
            try FileManager.default.createDirectory(at: alias, withIntermediateDirectories: false)
            self.junctions.append(alias)
            let nativeTarget = target.path.replacingOccurrences(of: "/", with: "\\")
            let substitute = Array(("\\??\\" + nativeTarget).utf16)
            let printable = Array(nativeTarget.utf16)
            let names = substitute + [UInt16(0)] + printable + [UInt16(0)]
            guard (8 + names.count * 2) <= Int(UInt16.max) else { throw CocoaError(.fileWriteInvalidFileName) }
            var buffer = Data()
            func append16(_ value: UInt16) {
                var encoded = value.littleEndian
                withUnsafeBytes(of: &encoded) { buffer.append(contentsOf: $0) }
            }
            var tag = UInt32(IO_REPARSE_TAG_MOUNT_POINT).littleEndian
            withUnsafeBytes(of: &tag) { buffer.append(contentsOf: $0) }
            append16(UInt16(8 + names.count * 2))
            append16(0)
            append16(0)
            append16(UInt16(substitute.count * 2))
            append16(UInt16((substitute.count + 1) * 2))
            append16(UInt16(printable.count * 2))
            for unit in names { append16(unit) }
            let aliasPath = Array(alias.path.utf16) + [UInt16(0)]
            let opened = aliasPath.withUnsafeBufferPointer {
                CreateFileW($0.baseAddress, DWORD(GENERIC_WRITE),
                            DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE), nil,
                            DWORD(OPEN_EXISTING), DWORD(FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT), nil)
            }
            guard let opened, opened != INVALID_HANDLE_VALUE else {
                throw WindowsCostFileMetadata.failure(GetLastError())
            }
            defer { CloseHandle(opened) }
            var returned: DWORD = 0
            let count = DWORD(buffer.count)
            let success = buffer.withUnsafeMutableBytes {
                DeviceIoControl(opened, DWORD(FSCTL_SET_REPARSE_POINT), $0.baseAddress, count,
                                nil, 0, &returned, nil)
            }
            guard success != 0 else { throw WindowsCostFileMetadata.failure(GetLastError()) }
        }

        func removeJunction(_ alias: URL) throws {
            let path = Array(alias.path.utf16) + [UInt16(0)]
            guard path.withUnsafeBufferPointer({ RemoveDirectoryW($0.baseAddress) }) != 0 else {
                throw WindowsCostFileMetadata.failure(GetLastError())
            }
            self.junctions.removeAll { $0 == alias }
        }

        func cleanup() {
            // Unlink junctions first; never let recursive fixture cleanup follow their targets.
            var allUnlinked = true
            for url in self.junctions.reversed() {
                let path = Array(url.path.utf16) + [UInt16(0)]
                if path.withUnsafeBufferPointer({ RemoveDirectoryW($0.baseAddress) }) == 0 {
                    allUnlinked = false
                }
            }
            if allUnlinked { try? FileManager.default.removeItem(at: self.root) }
        }
    }

    @Test
    func `recursive inventory follows linked logs once and terminates an ancestor junction`() throws {
        let fixture = try TraversalFixture()
        defer { fixture.cleanup() }
        let project = try fixture.directory("project")
        try Data("{}\n".utf8).write(to: project.appendingPathComponent("session.jsonl"))
        let alias = fixture.logs.appendingPathComponent("alias", isDirectory: true)
        try fixture.junction(alias, to: project)
        try fixture.junction(project.appendingPathComponent("back", isDirectory: true), to: fixture.logs)
        let observations = CostUsagePublicationObservations()
        var checks = 0
        enum Loop: Error { case exceeded }
        let files = try #require(WindowsCostSourceInventory.jsonlFiles(
            in: fixture.logs, checkCancellation: {
                checks += 1
                if checks > 1000 { throw Loop.exceeded }
            }, publicationObservations: observations))
        #expect(files.count == 1)
        #expect(files.keys.first == alias.appendingPathComponent("session.jsonl"))
        #expect(checks < 1000)
        try observations.freeze().check()
        #expect(observations.freeze().entries.contains { $0.url == project })
        #expect(observations.freeze().entries.contains { $0.url == alias.appendingPathComponent("back") })
    }

    @Test
    func `excluded directory does not suppress an independently eligible alias`() throws {
        let fixture = try TraversalFixture()
        defer { fixture.cleanup() }
        let excluded = try fixture.directory("2026")
        try Data("{}\n".utf8).write(to: excluded.appendingPathComponent("session.jsonl"))
        let alias = fixture.logs.appendingPathComponent("linked-project", isDirectory: true)
        try fixture.junction(alias, to: excluded)
        let files = try #require(WindowsCostSourceInventory.jsonlFiles(
            in: fixture.logs, descendIntoDirectory: { $0 != excluded }))
        #expect(Array(files.keys) == [alias.appendingPathComponent("session.jsonl")])
    }

    @Test
    func `duplicate directory aliases remain protected against retargeting`() throws {
        let fixture = try TraversalFixture()
        defer { fixture.cleanup() }
        let first = try fixture.directory("a-project")
        let second = fixture.root.appendingPathComponent("other-project", isDirectory: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: false)
        try Data("{}\n".utf8).write(to: first.appendingPathComponent("source.jsonl"))
        let alias = fixture.logs.appendingPathComponent("z-alias", isDirectory: true)
        try fixture.junction(alias, to: first)
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: fixture.logs.path)
        let original = try #require(WindowsCostFileMetadata.atURL(fixture.logs))
        let observations = CostUsagePublicationObservations()
        let files = try #require(WindowsCostSourceInventory.jsonlFiles(
            in: fixture.logs, publicationObservations: observations))
        #expect(files.count == 1)
        #expect(files.keys.first == first.appendingPathComponent("source.jsonl"))
        try fixture.removeJunction(alias)
        try fixture.junction(alias, to: second)
        try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: fixture.logs.path)
        #expect(try WindowsCostFileMetadata.atURL(fixture.logs) == original)
        #expect(throws: CostUsageSourcePublication.Failure.self) { try observations.freeze().check() }
    }

    @Test
    func `hard linked files have one representative but every alias has a publication observation`() throws {
        let fixture = try TraversalFixture()
        defer { fixture.cleanup() }
        let first = fixture.logs.appendingPathComponent("a.jsonl")
        let alias = fixture.logs.appendingPathComponent("z.jsonl")
        try Data("{}\n".utf8).write(to: first)
        try fixture.hardLink(alias, to: first)
        let observations = CostUsagePublicationObservations()
        let files = try #require(WindowsCostSourceInventory.jsonlFiles(
            in: fixture.logs, publicationObservations: observations))
        #expect(Array(files.keys) == [first])
        #expect(observations.freeze().entries.contains { $0.url == alias })
        try FileManager.default.moveItem(at: alias, to: fixture.root.appendingPathComponent("retained.jsonl"))
        try Data("{}\n".utf8).write(to: alias)
        #expect(throws: CostUsageSourcePublication.Failure.self) { try observations.freeze().check() }
    }

    @Test
    func `Claude roots do not double count unkeyed rows through hard links`() throws {
        let fixture = try TraversalFixture()
        defer { fixture.cleanup() }
        let first = try fixture.directory("first")
        let second = try fixture.directory("second")
        let source = first.appendingPathComponent("source.jsonl")
        let event: [String: Any] = [
            "type": "assistant", "timestamp": "2026-08-01T12:00:00Z",
            "message": ["model": "synthetic-traversal-model", "usage": ["input_tokens": 17, "output_tokens": 0]],
        ]
        var data = try JSONSerialization.data(withJSONObject: event)
        data.append(10)
        try data.write(to: source)
        try fixture.hardLink(second.appendingPathComponent("linked.jsonl"), to: source)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let options = CostUsageScanner.Options(
            claudeProjectsRoots: [first, second], cacheRoot: fixture.root.appendingPathComponent("cache"), calendar: calendar)
        let report = try CostUsageScanner.loadDailyReportCancellable(
            provider: .claude, since: day, until: day, now: day, options: options, checkCancellation: nil)
        #expect(report.summary?.totalInputTokens == 17)
        let cache = CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: options.cacheRoot)
        #expect(cache.sourceFileIDs.count == 1)
        #expect(cache.windowsReadProofs.count == 1)
    }

    @Test
    func `parent session discovery resumes a cyclic directory graph without growing alias paths`() throws {
        let fixture = try TraversalFixture()
        defer { fixture.cleanup() }
        let project = try fixture.directory("project")
        try Data(#"{"type":"session_meta","payload":{"id":"parent"}}"#.utf8)
            .write(to: project.appendingPathComponent("session.jsonl"))
        try fixture.junction(fixture.logs.appendingPathComponent("alias", isDirectory: true), to: project)
        try fixture.junction(project.appendingPathComponent("back", isDirectory: true), to: fixture.logs)
        let first = CostUsageScanner.CodexSessionFileIndex(
            files: [], roots: [fixture.logs],
            scanBudget: .init(maxFileBytes: 2, maxBytesPerRefresh: 2))
        guard case .deferred = try first.lookup(sessionId: "absent") else {
            Issue.record("Expected the small first budget to defer discovery")
            return
        }
        let checkpoint = try JSONDecoder().decode(
            CostUsageCodexSessionDiscovery.self, from: JSONEncoder().encode(first.persistedState))
        var checks = 0
        enum Loop: Error { case exceeded }
        let observations = CostUsagePublicationObservations()
        let resumed = CostUsageScanner.CodexSessionFileIndex(
            files: [], roots: [fixture.logs], cachedDiscovery: checkpoint,
            checkCancellation: {
                checks += 1
                if checks > 1000 { throw Loop.exceeded }
            }, publicationObservations: observations)
        guard case .missing = try resumed.lookup(sessionId: "absent") else {
            Issue.record("Expected completed negative discovery after restart")
            return
        }
        #expect(resumed.persistedState.isComplete)
        #expect(resumed.persistedState.directoryPaths.count == 4)
        #expect(resumed.persistedState.filePaths.count == 1)
        guard case .found = try resumed.lookup(sessionId: "parent") else {
            Issue.record("Expected the parent reached through the linked directory")
            return
        }
        try observations.freeze().check()
    }
}
#endif
