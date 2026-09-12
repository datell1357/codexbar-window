#if os(Windows)
import Foundation
import WinSDK

/// Explicitly selected source roots. These are not inferred from the target process's environment.
public struct WindowsSessionMetadataRoots: Equatable, Sendable {
    public let codexSessions: String?
    public let claudeProjects: String?
    public static let none = Self(codex: nil, claude: nil)
    public var isEmpty: Bool { self.codexSessions == nil && self.claudeProjects == nil }

    public init(codexSessions: String?, claudeProjects: String?) throws {
        func normalize(_ raw: String?) throws -> String? {
            guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            guard let path = WindowsSessionLaunchHints.absolutePath(raw) else { throw ConfigurationError.invalidPath }
            return path
        }
        self.codexSessions = try normalize(codexSessions)
        self.claudeProjects = try normalize(claudeProjects)
    }
    private init(codex: String?, claude: String?) { self.codexSessions = codex; self.claudeProjects = claude }

    public static func load(
        codexOverride: String? = nil, claudeOverride: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self
    {
        try Self(
            codexSessions: codexOverride ?? CodexBarPlatformPaths.environmentValue(
                "CODEXBAR_WINDOWS_CODEX_SESSIONS_ROOT", environment: environment),
            claudeProjects: claudeOverride ?? CodexBarPlatformPaths.environmentValue(
                "CODEXBAR_WINDOWS_CLAUDE_PROJECTS_ROOT", environment: environment))
    }
    enum ConfigurationError: LocalizedError {
        case invalidPath
        var errorDescription: String? { "Session metadata roots must be absolute Windows drive paths." }
    }
}

/// Conservative enrichment for explicitly selected resume/session UUIDs. No file-only rows are
/// produced, and native process birth IDs remain the focus authority rather than transcript IDs.
enum WindowsSessionMetadataCorrelator {
    struct Result {
        let sessions: [AgentSession]
        let message: String?
    }

    static func enrich(
        sessions: [AgentSession], requestedIDs: [String: String], roots: WindowsSessionMetadataRoots,
        config: SessionScanConfig, now: Date) -> Result
    {
        guard !roots.isEmpty else { return Result(sessions: sessions, message: nil) }
        let duration = config.directoryScanBudget.isFinite ? max(0, min(config.directoryScanBudget, 1)) : 0
        let budget = Budget(entries: max(0, config.maxDirectoryEntryCount), deadline: Date().addingTimeInterval(duration))
        func selectionKey(_ session: AgentSession) -> String? {
            guard let cwd = session.cwd, let id = requestedIDs[session.id] else { return nil }
            return session.provider.rawValue + "\u{1F}" + cwd + "\u{1F}" + id
        }
        let selectionCounts = Dictionary(grouping: sessions.compactMap(selectionKey), by: { $0 }).mapValues(\.count)
        var output = sessions
        var unresolved = false
        let selectedCodexIDs = Set(sessions.filter { $0.provider == .codex && $0.cwd != nil }
            .compactMap { requestedIDs[$0.id] })
        let codexFiles: [String]
        if let root = roots.codexSessions, !selectedCodexIDs.isEmpty {
            codexFiles = self.codexCandidates(root: root, ids: selectedCodexIDs, budget: budget)
        } else { codexFiles = [] }
        let codexEnumerationComplete = !budget.exhausted && !budget.rootUnavailable
        for index in output.indices {
            guard budget.hasTime else { unresolved = true; break }
            let session = output[index]
            let configured = session.provider == .codex ? roots.codexSessions != nil :
                (session.provider == .claude && roots.claudeProjects != nil)
            guard configured else { continue }
            guard let cwd = session.cwd, let id = requestedIDs[session.id], UUID(uuidString: id) != nil else {
                unresolved = true; continue
            }
            guard let key = selectionKey(session), selectionCounts[key] == 1 else { unresolved = true; continue }
            if session.provider == .codex {
                guard codexEnumerationComplete else { unresolved = true; continue }
                let paths = codexFiles.filter { $0.lowercased().contains(id.lowercased()) }
                // Multiple copies of a selected UUID in the configured root are ambiguous.
                guard paths.count == 1, let path = paths.first, budget.consume(),
                      let before = self.fileInfo(path),
                      let metadata = CodexRolloutFirstLineParser.read(from: URL(fileURLWithPath: path)),
                      metadata.sessionID.lowercased() == id.lowercased(),
                      metadata.sessionSource == .cli || metadata.sessionSource == .unknown,
                      metadata.cwd.flatMap(WindowsSessionLaunchHints.absolutePath) == WindowsSessionLaunchHints.absolutePath(cwd),
                      budget.hasTime, let after = self.fileInfo(path), before == after
                else { unresolved = true; continue }
                output[index].transcriptPath = path
                output[index].lastActivityAt = min(after.modifiedAt, now)
            } else if session.provider == .claude, let root = roots.claudeProjects {
                let folder = self.join(root, ClaudeSessionProjectMapper.escapedCWD(cwd))
                let path = self.join(folder, id.lowercased() + ".jsonl")
                guard budget.consume(), self.directoryAllowed(folder), let info = self.fileInfo(path) else {
                    unresolved = true; continue
                }
                // Only filename, UUID, parent project mapping and file metadata; no Claude body read.
                output[index].transcriptPath = path
                output[index].lastActivityAt = min(info.modifiedAt, now)
            }
            output[index].state = config.state(lastActivityAt: output[index].lastActivityAt, now: now, hasLiveProcess: true)
        }
        return Result(sessions: output, message: unresolved || budget.exhausted || budget.rootUnavailable ?
            "Some metadata matches are unresolved or budget-limited. A known cwd and explicit session UUID are required; PID identity is retained." : nil)
    }

    private struct FileInfo: Equatable {
        let volume: UInt32
        let index: UInt64
        let size: UInt64
        let modifiedTicks: UInt64
        var modifiedAt: Date { Date(timeIntervalSince1970: Double(self.modifiedTicks) / 10_000_000 - 11_644_473_600) }
    }

    private final class Budget {
        var remaining: Int
        let deadline: Date
        var exhausted = false
        var rootUnavailable = false
        init(entries: Int, deadline: Date) { self.remaining = entries; self.deadline = deadline }
        var hasTime: Bool { !Task.isCancelled && Date() < self.deadline }
        func consume() -> Bool {
            guard self.remaining > 0, self.hasTime else { self.exhausted = true; return false }
            self.remaining -= 1; return true
        }
    }

    private static func codexCandidates(root: String, ids: Set<String>, budget: Budget) -> [String] {
        guard self.directoryAllowed(root) else { budget.rootUnavailable = true; return [] }
        var stack: [(String, Int)] = [(root, 0)]
        var candidates: [String] = []
        while let (directory, depth) = stack.popLast() {
            guard budget.hasTime else { budget.exhausted = true; break }
            guard self.directoryAllowed(directory) else { budget.rootUnavailable = true; continue }
            var data = WIN32_FIND_DATAW()
            let pattern = Array(self.join(directory, "*").utf16) + [0]
            let handle = pattern.withUnsafeBufferPointer { FindFirstFileW($0.baseAddress, &data) }
            guard let handle, handle != INVALID_HANDLE_VALUE else {
                if GetLastError() != ERROR_FILE_NOT_FOUND { budget.rootUnavailable = true }
                continue
            }
            defer { FindClose(handle) }
            var found = true
            while found {
                guard budget.consume() else { break }
                let name = withUnsafeBytes(of: data.cFileName) { raw -> String in
                    let units = raw.bindMemory(to: UInt16.self)
                    return String(decoding: units.prefix(while: { $0 != 0 }), as: UTF16.self)
                }
                if name != ".", name != "..", !name.contains("\\"), !name.contains("/"), data.dwFileAttributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) == 0 {
                    let path = self.join(directory, name)
                    if data.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0 {
                        // The canonical root layout is sessions/year/month/day/*.jsonl.
                        if depth < 3 { stack.append((path, depth + 1)) }
                        else { budget.rootUnavailable = true }
                    } else if name.lowercased().hasSuffix(".jsonl"), ids.contains(where: { name.lowercased().contains($0) }) {
                        candidates.append(path)
                    }
                }
                found = FindNextFileW(handle, &data) != 0
                if !found, GetLastError() != ERROR_NO_MORE_FILES { budget.rootUnavailable = true }
            }
            if budget.exhausted { break }
        }
        return candidates
    }

    private static func directoryAllowed(_ path: String) -> Bool {
        guard let normalized = WindowsSessionLaunchHints.absolutePath(path) else { return false }
        let root = Array(String(normalized.prefix(3)).utf16) + [0]
        let type = root.withUnsafeBufferPointer { GetDriveTypeW($0.baseAddress) }
        guard type == UINT(DRIVE_FIXED) || type == UINT(DRIVE_REMOVABLE) || type == UINT(DRIVE_RAMDISK) else { return false }
        let units = Array(normalized.utf16) + [0]
        let attrs = units.withUnsafeBufferPointer { GetFileAttributesW($0.baseAddress) }
        return attrs != INVALID_FILE_ATTRIBUTES && attrs & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0 &&
            attrs & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) == 0
    }

    private static func fileInfo(_ path: String) -> FileInfo? {
        let units = Array(path.utf16) + [0]
        let handle = units.withUnsafeBufferPointer {
            CreateFileW($0.baseAddress, DWORD(FILE_READ_ATTRIBUTES), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE),
                        nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { return nil }
        defer { CloseHandle(handle) }
        var info = BY_HANDLE_FILE_INFORMATION()
        guard GetFileInformationByHandle(handle, &info) != 0,
              info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) == 0
        else { return nil }
        return FileInfo(volume: info.dwVolumeSerialNumber,
                        index: (UInt64(info.nFileIndexHigh) << 32) | UInt64(info.nFileIndexLow),
                        size: (UInt64(info.nFileSizeHigh) << 32) | UInt64(info.nFileSizeLow),
                        modifiedTicks: (UInt64(info.ftLastWriteTime.dwHighDateTime) << 32) | UInt64(info.ftLastWriteTime.dwLowDateTime))
    }

    private static func join(_ base: String, _ component: String) -> String {
        base.hasSuffix("\\") ? base + component : base + "\\" + component
    }
}
#endif
