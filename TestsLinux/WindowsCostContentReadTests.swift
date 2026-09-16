#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

/// Source only. These fixtures have not been executed on the macOS implementation host.
extension WindowsCostPublicationTests {
    private func withContentSource(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-content-read-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root, root.appendingPathComponent("source.jsonl"))
    }

    private func rewriteContent(_ data: Data, file: URL, time: Date) throws {
        let writer = try FileHandle(forWritingTo: file)
        try writer.write(contentsOf: data)
        try writer.close()
        try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
    }

    private func contentProgress(
        file: URL,
        limit: Int64? = nil,
        previous: CostUsageJsonl.ScanProgress? = nil,
        onLine: (CostUsageJsonl.Line) -> Void = { _ in }) throws -> CostUsageJsonl.ScanProgress
    {
        let snapshot = try #require(CostUsageFileReadSnapshot.capture(at: file))
        return try CostUsageJsonl.scanBounded(
            fileURL: file, offset: previous?.readOffset ?? 0, maxLineBytes: 256 * 1024,
            prefixBytes: 256 * 1024, maxBytesToRead: limit, resumeState: previous?.resumeState,
            expectedFile: snapshot, captureWindowsContent: true,
            expectedPrefixAnchor: previous?.windowsReadAnchor, onLine: onLine)
    }

    @Test
    func `parser digest retains the consumed bytes after a same stamp rewrite`() throws {
        try self.withContentSource { _, file in
            let original = Data("{\"id\":1}\n".utf8)
            let replacement = Data("{\"id\":2}\n".utf8)
            let time = Date(timeIntervalSince1970: 1_700_000_000)
            try original.write(to: file)
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
            let expected = try #require(CostUsageFileReadSnapshot.capture(at: file))
            let originalAnchor = try #require(CostUsageScanner.codexTokenIndexAnchor(
                fileURL: file, indexedBytes: expected.size, expectedFile: expected))
            var mutationError: (any Error)?
            var parsedLine: Data?
            let progress = try self.contentProgress(file: file) { line in
                parsedLine = line.bytes
                do { try self.rewriteContent(replacement, file: file, time: time) }
                catch { mutationError = error }
            }
            #expect(mutationError == nil)
            #expect(parsedLine == Data("{\"id\":1}".utf8))
            #expect(try CostUsageFileReadSnapshot.capture(at: file) == expected)
            #expect(progress.windowsReadAnchor == originalAnchor)
            let observations = CostUsagePublicationObservations()
            try observations.content(file, snapshot: expected, anchor: originalAnchor)
            #expect(throws: CostUsageSourcePublication.Failure.self) { try observations.freeze().check() }
        }
    }

    @Test
    func `partial JSON lines retain separate read and committed proofs across resume`() throws {
        try self.withContentSource { _, file in
            let firstLine = Data("{\"first\":1}\n".utf8)
            var source = firstLine
            source.append(Data("{\"second\":22}\n".utf8))
            try source.write(to: file)
            let first = try self.contentProgress(file: file, limit: Int64(firstLine.count + 5))
            #expect(first.resumeState != nil)
            #expect(first.windowsReadAnchor?.indexedBytes == first.readOffset)
            #expect(first.windowsCommittedAnchor?.indexedBytes == Int64(firstLine.count))
            #expect(first.windowsCommittedAnchor == CostUsageScanner.codexTokenIndexAnchor(
                fileURL: file, indexedBytes: Int64(firstLine.count)))
            let second = try self.contentProgress(file: file, previous: first)
            #expect(second.resumeState == nil)
            #expect(second.readOffset == Int64(source.count))
            #expect(second.windowsReadAnchor == CostUsageScanner.codexTokenIndexAnchor(
                fileURL: file, indexedBytes: Int64(source.count)))
            #expect(second.windowsReadAnchor == second.windowsCommittedAnchor)
        }
    }

    @Test
    func `resume refuses a changed inherited prefix before delivering a line`() throws {
        try self.withContentSource { _, file in
            let time = Date(timeIntervalSince1970: 1_700_000_000)
            let source = Data("{\"id\":1}\n{\"tail\":22}\n".utf8)
            try source.write(to: file)
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
            let first = try self.contentProgress(file: file, limit: 13)
            try self.rewriteContent(Data("{\"id\":9}\n{\"tail\":22}\n".utf8), file: file, time: time)
            var delivered = 0
            #expect(throws: CostUsageSourcePublication.Failure.self) {
                _ = try self.contentProgress(file: file, previous: first) { _ in delivered += 1 }
            }
            #expect(delivered == 0)
        }
    }

    @Test
    func `Codex discards an unfinished tail with its matching committed proof`() throws {
        try self.withContentSource { _, file in
            let header = Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"synthetic\"}}\n".utf8)
            var source = header
            source.append(Data("{\"type\":\"event_msg\",\"payload\":".utf8))
            try source.write(to: file)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
            let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
            let parsed = try CostUsageScanner.parseCodexFileCancellable(
                fileURL: file, range: .init(since: day, until: day, calendar: calendar))
            #expect(parsed.parsedBytes == Int64(header.count))
            #expect(parsed.scanTargetSize == Int64(header.count))
            #expect(parsed.jsonlResumeState == nil)
            #expect(parsed.windowsReadAnchor == CostUsageScanner.codexTokenIndexAnchor(
                fileURL: file, indexedBytes: Int64(header.count)))
            #expect(parsed.windowsAuxiliaryAnchors.first?.indexedBytes == Int64(source.count))
        }
    }

    @Test
    func `later content observations cannot replace an earlier prefix proof`() throws {
        try self.withContentSource { _, file in
            try Data("{\"id\":1}\n".utf8).write(to: file)
            let firstMetadata = try #require(CostUsageFileReadSnapshot.capture(at: file))
            let first = try self.contentProgress(file: file)
            let oldAnchor = try #require(first.windowsReadAnchor)
            let observations = CostUsagePublicationObservations()
            try observations.content(file, snapshot: firstMetadata, anchor: oldAnchor)
            let writer = try FileHandle(forWritingTo: file)
            _ = try writer.seekToEnd()
            try writer.write(contentsOf: Data("{\"tail\":2}\n".utf8))
            try writer.close()
            let appended = try self.contentProgress(file: file)
            let newMetadata = try #require(CostUsageFileReadSnapshot.capture(at: file))
            try observations.content(file, snapshot: newMetadata, anchor: #require(appended.windowsReadAnchor))
            try observations.freeze().check()
            #expect(observations.freeze().entries.first?.contentAnchors.count == 2)
            var conflict = oldAnchor
            conflict.sha256 = String(repeating: "0", count: 64)
            #expect(throws: CostUsageSourcePublication.Failure.self) {
                try observations.content(file, snapshot: newMetadata, anchor: conflict)
            }
            // The older observation is still enforced even if a later full read sees the rewrite.
            try self.rewriteContent(Data("{\"id\":9}\n".utf8), file: file,
                                    time: Date(timeIntervalSince1970: 1_700_000_001))
            #expect(throws: CostUsageSourcePublication.Failure.self) { try observations.freeze().check() }
        }
    }

    @Test
    func `metadata read beyond a partial body remains part of cached source validation`() throws {
        try self.withContentSource { _, file in
            let time = Date(timeIntervalSince1970: 1_700_000_000)
            let prefix = Data("{\"id\":1}\n".utf8)
            var source = prefix
            source.append(Data("{\"meta\":2}\n".utf8))
            try source.write(to: file)
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
            let metadata = try CostUsageScanner.requiredCodexFileMetadata(fileURL: file)
            var usage = CostUsageFileUsage(mtimeUnixMs: metadata.mtimeUnixMs, size: metadata.size, days: [:])
            usage.parsedBytes = Int64(prefix.count)
            usage.codexScanFileId = metadata.fileId
            usage.codexWindowsSource = metadata.readSnapshot
            usage.codexWindowsContentGeneration = UUID().uuidString
            usage.codexWindowsReadProofVersion = CostUsageScanner.windowsCodexReadProofVersion
            usage.codexTokenIndexAnchor = CostUsageScanner.codexTokenIndexAnchor(
                fileURL: file, indexedBytes: Int64(prefix.count))
            usage.codexWindowsAuxiliaryAnchors = [try #require(CostUsageScanner.codexTokenIndexAnchor(
                fileURL: file, indexedBytes: metadata.size))]
            #expect(CostUsageScanner.windowsCodexPrefixMatches(usage, metadata: metadata))
            var replacement = prefix
            replacement.append(Data("{\"meta\":9}\n".utf8))
            try self.rewriteContent(replacement, file: file, time: time)
            let current = try CostUsageScanner.requiredCodexFileMetadata(fileURL: file)
            #expect(CostUsageScanner.windowsCodexSourceMatches(usage, metadata: current))
            #expect(!CostUsageScanner.windowsCodexPrefixMatches(usage, metadata: current))
        }
    }

    @Test
    func `same stamp content mutation before SQLite commit preserves the previous cache`() throws {
        try self.withContentSource { root, file in
            let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
            var initial = CostUsageCache()
            initial.lastScanUnixMs = 1000
            initial.scanSinceKey = "2026-08-01"
            initial.scanUntilKey = "2026-08-01"
            initial.timeZoneIdentifier = calendar.timeZone.identifier
            initial.roots = ["synthetic-root": 1]
            try #require(!CostUsageStoreAccess.replace(
                cacheRoot: cacheRoot, cache: initial, calendar: calendar).catchUpRequired)
            for identical in [false, true] {
                let time = Date(timeIntervalSince1970: 1_700_000_000)
                try Data("{\"id\":1}\n".utf8).write(to: file)
                try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
                let snapshot = try #require(CostUsageFileReadSnapshot.capture(at: file))
                let progress = try self.contentProgress(file: file)
                let observations = CostUsagePublicationObservations()
                try observations.content(file, snapshot: snapshot, anchor: #require(progress.windowsReadAnchor))
                let loaded = CostUsageStoreAccess.load(cacheRoot: cacheRoot, calendar: calendar)
                defer { loaded.release() }
                var candidate = loaded.cache
                candidate.lastScanUnixMs = 2000
                if !identical { candidate.roots = ["synthetic-root": 2] }
                var reached = false
                var mutationError: (any Error)?
                CostUsageStore.identicalContentPreLockCheckpointForTesting = (loaded.store.databaseURL, {
                    reached = true
                    do { try self.rewriteContent(Data("{\"id\":9}\n".utf8), file: file, time: time) }
                    catch { mutationError = error }
                })
                defer { CostUsageStore.identicalContentPreLockCheckpointForTesting = nil }
                let result = CostUsageStoreAccess.save(
                    store: loaded.store, cache: candidate, calendar: calendar,
                    requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
                    skipIdenticalContent: identical, receipt: loaded.receipt, sourcePublication: observations.freeze())
                #expect(reached)
                #expect(mutationError == nil)
                #expect(try CostUsageFileReadSnapshot.capture(at: file) == snapshot)
                #expect(result.sourceValidationFailed)
                #expect(result.catchUpRequired)
                #expect(CostUsageStoreAccess.read(cacheRoot: cacheRoot, calendar: calendar).lastScanUnixMs == 1000)
            }
        }
    }
}
#endif
