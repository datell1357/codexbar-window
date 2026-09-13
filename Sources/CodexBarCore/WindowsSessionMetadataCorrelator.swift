#if os(Windows)
import Foundation
import WinSDK
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

/// Explicitly selected source roots. These are not inferred from the target process's environment.
public struct WindowsSessionMetadataRoots: Equatable, Sendable {
    public let codexSessions: String?
    public let claudeProjects: String?
    public let codexTitleDatabase: String?
    public let codexTitleIndex: String?
    public let readClaudeTitles: Bool
    public let allowNewSessions: Bool
    public static let none = Self(codex: nil, claude: nil)
    public var isEmpty: Bool { self.codexSessions == nil && self.claudeProjects == nil }

    public init(codexSessions: String?, claudeProjects: String?, allowNewSessions: Bool = false,
                codexTitleIndex: String? = nil, readClaudeTitles: Bool = false, codexTitleDatabase: String? = nil) throws {
        func normalize(_ raw: String?) throws -> String? {
            guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            guard let path = WindowsSessionLaunchHints.absolutePath(raw) else { throw ConfigurationError.invalidPath }
            return path
        }
        self.codexSessions = try normalize(codexSessions)
        self.claudeProjects = try normalize(claudeProjects)
        self.codexTitleDatabase = try normalize(codexTitleDatabase)
        self.codexTitleIndex = try normalize(codexTitleIndex)
        self.readClaudeTitles = readClaudeTitles
        self.allowNewSessions = allowNewSessions
    }
    private init(codex: String?, claude: String?) { self.codexSessions = codex; self.claudeProjects = claude; self.allowNewSessions = false; self.codexTitleIndex = nil; self.readClaudeTitles = false; self.codexTitleDatabase = nil }

    public static func load(
        codexOverride: String? = nil, claudeOverride: String? = nil,
        allowNewSessions: Bool = false, codexTitleIndexOverride: String? = nil,
        readClaudeTitles: Bool = false, codexTitleDatabaseOverride: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self
    {
        try Self(
            codexSessions: codexOverride ?? CodexBarPlatformPaths.environmentValue(
                "CODEXBAR_WINDOWS_CODEX_SESSIONS_ROOT", environment: environment),
            claudeProjects: claudeOverride ?? CodexBarPlatformPaths.environmentValue(
                "CODEXBAR_WINDOWS_CLAUDE_PROJECTS_ROOT", environment: environment),
            allowNewSessions: allowNewSessions,
            codexTitleIndex: codexTitleIndexOverride ?? CodexBarPlatformPaths.environmentValue(
                "CODEXBAR_WINDOWS_CODEX_TITLE_INDEX", environment: environment),
            readClaudeTitles: readClaudeTitles,
            codexTitleDatabase: codexTitleDatabaseOverride ?? CodexBarPlatformPaths.environmentValue(
                "CODEXBAR_WINDOWS_CODEX_TITLE_DATABASE", environment: environment))
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
        config: SessionScanConfig, now: Date, newSessionIDs: Set<String> = []) -> Result
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
        var claudeTitleFailures: Set<TitleReadFailure> = []
        let selectedCodexIDs = Set(sessions.filter { $0.provider == .codex && $0.cwd != nil }
            .compactMap { requestedIDs[$0.id] })
        let codexFiles: [String]
        if let root = roots.codexSessions, !selectedCodexIDs.isEmpty {
            codexFiles = self.codexCandidates(root: root, ids: selectedCodexIDs, budget: budget)
        } else { codexFiles = [] }
        let codexEnumerationComplete = !budget.exhausted && !budget.rootUnavailable
        var matchedHeaders: [Int: CodexRolloutMetadata] = [:]
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
                      let read = self.codexHeader(path, deadline: budget.deadline), before == read.info,
                      case let metadata = read.metadata,
                      metadata.sessionID.lowercased() == id.lowercased(),
                      metadata.sessionSource == .cli || metadata.sessionSource == .unknown,
                      metadata.cwd.flatMap(WindowsSessionLaunchHints.absolutePath) == WindowsSessionLaunchHints.absolutePath(cwd),
                      budget.hasTime, let after = self.fileInfo(path), before == after
                else { unresolved = true; continue }
                output[index].metadataMatch = "explicit_uuid"
                output[index].transcriptPath = path
                matchedHeaders[index] = metadata
                output[index].sessionName = metadata.descriptiveName(threadMetadata: nil).map(WindowsSessionLaunchHints.label)
                if output[index].sessionName != nil { output[index].metadataTitleSource = "rollout_role" }
                output[index].lastActivityAt = min(after.modifiedAt, now)
            } else if session.provider == .claude, let root = roots.claudeProjects {
                let folder = self.join(root, ClaudeSessionProjectMapper.escapedCWD(cwd))
                let path = self.join(folder, id.lowercased() + ".jsonl")
                guard budget.consume(), self.directoryAllowed(folder), let info = self.fileInfo(path) else {
                    unresolved = true; continue
                }
                // Base matching uses only filename, UUID, parent project mapping and file metadata.
                output[index].metadataMatch = "explicit_uuid"
                output[index].transcriptPath = path
                output[index].lastActivityAt = min(info.modifiedAt, now)
                if roots.readClaudeTitles {
                    do {
                        let names = try self.stableTitleNames(path, ids: [id.lowercased()], deadline: budget.deadline, claude: true)
                        guard let latest = self.fileInfo(path), latest == info else { throw TitleReadFailure.changed }
                        databaseIDs = ids.subtracting(names.seenIDs).subtracting(names.unresolvedIDs)
                if !names.unresolvedIDs.isEmpty { claudeTitleFailures.insert(.outsideWindow) }
                        output[index].sessionName = names[id.lowercased()]
                        output[index].metadataTitleSource = output[index].sessionName == nil ? nil : "claude_custom_title"
                    } catch {
                        claudeTitleFailures.insert((error as? TitleReadFailure) ?? .unavailable)
                    }
                }
            }
            output[index].state = config.state(lastActivityAt: output[index].lastActivityAt, now: now, hasLiveProcess: true)
        }
        var notices: [String] = []
        for failure in TitleReadFailure.allCases where claudeTitleFailures.contains(failure) {
            notices.append("Claude titles: \(failure.message) Project labels are retained.")
        }
        var databaseIDs = roots.codexTitleIndex == nil ? Set(matchedHeaders.values.map { $0.sessionID.lowercased() }) : []
        if let titlePath = roots.codexTitleIndex, !matchedHeaders.isEmpty {
            let ids = Set(matchedHeaders.values.map { $0.sessionID.lowercased() })
            do {
                let names = try self.stableTitleNames(titlePath, ids: ids, deadline: budget.deadline)
                if !names.unresolvedIDs.isEmpty {
                    notices.append("Codex titles: \(TitleReadFailure.outsideWindow.message)")
                }
                for (index, header) in matchedHeaders {
                    output[index].sessionName = header.descriptiveName(
                        threadMetadata: names[header.sessionID.lowercased()].map {
                            CodexThreadMetadata(title: $0, agentPath: nil)
                        }).map(WindowsSessionLaunchHints.label)
                    if names[header.sessionID.lowercased()] != nil { output[index].metadataTitleSource = "codex_title_index" }
                }
            } catch {
                let failure = (error as? TitleReadFailure) ?? .unavailable
                notices.append("Codex titles: \(failure.message) Header/project labels are retained.")
            }
        }
        if let path = roots.codexTitleDatabase, !databaseIDs.isEmpty {
            do {
                let titles = try self.databaseTitles(path, ids: databaseIDs, deadline: budget.deadline)
                for (index, header) in matchedHeaders {
                    guard let title = titles[header.sessionID.lowercased()] else { continue }
                    output[index].sessionName = header.descriptiveName(
                        threadMetadata: CodexThreadMetadata(title: title, agentPath: nil)).map(WindowsSessionLaunchHints.label)
                    output[index].metadataTitleSource = "codex_title_database"
                }
            } catch {
                let reason = (error as? DatabaseReadFailure)?.message ?? (error as? TitleReadFailure)?.message ?? DatabaseReadFailure.query.message
                notices.append("Codex title database: \(reason) Existing labels are retained.")
            }
        }
        if unresolved || budget.exhausted || budget.rootUnavailable {
            notices.append("Some metadata matches are unresolved or budget-limited; PID identity is retained.")
        }
        if roots.allowNewSessions {
            let inferred = self.inferNewSessions(
                sessions: output, eligibleIDs: newSessionIDs, roots: roots, config: config, now: now, budget: budget)
            output = inferred.sessions
            if let message = inferred.message { notices.append(message) }
        }
        return Result(sessions: output, message: notices.isEmpty ? nil : notices.joined(separator: " "))
    }

    /// An opt-in heuristic, never proof of process ownership. Unknown peer directories or an
    /// incomplete candidate set prevent inference. File metadata never replaces PID birth identity.
    private static func inferNewSessions(
        sessions: [AgentSession], eligibleIDs: Set<String>, roots: WindowsSessionMetadataRoots,
        config: SessionScanConfig, now: Date, budget: Budget) -> Result
    {
        var output = sessions
        var inferredCount = 0
        func directoryKey(_ session: AgentSession) -> String? {
            guard let cwd = session.cwd.flatMap(WindowsSessionLaunchHints.absolutePath) else { return nil }
            return (session.provider == .claude ? ClaudeSessionProjectMapper.escapedCWD(cwd) : cwd).lowercased()
        }
        for provider in [AgentSession.Provider.codex, .claude] {
            let peers = sessions.filter { $0.provider == provider }
            // A peer with unknown cwd could be using the same project. Do not infer around it.
            guard !peers.contains(where: { directoryKey($0) == nil }) else { continue }
            let counts = Dictionary(grouping: peers.compactMap(directoryKey), by: { $0 }).mapValues(\.count)
            let eligible = output.indices.filter {
                let session = output[$0]
                guard session.provider == provider, eligibleIDs.contains(session.id), session.transcriptPath == nil,
                      let birth = session.startedAt, birth <= now, let key = directoryKey(session)
                else { return false }
                return counts[key] == 1
            }
            guard !eligible.isEmpty, let root = provider == .codex ? roots.codexSessions : roots.claudeProjects,
                  let earliest = eligible.compactMap({ output[$0].startedAt }).min(),
                  !budget.exhausted, !budget.rootUnavailable, budget.hasTime
            else { continue }
            if provider == .codex {
                let paths = self.codexCandidates(root: root, ids: [], budget: budget, freshSince: earliest)
                guard !budget.exhausted, !budget.rootUnavailable, budget.hasTime else { continue }
                var records: [(path: String, cwd: String, info: FileInfo, name: String?)] = []
                var complete = true
                for path in paths {
                    guard budget.consume(), let before = self.fileInfo(path), before.createdAt >= earliest,
                          let read = self.codexHeader(path, deadline: budget.deadline), before == read.info,
                          case let header = read.metadata,
                          UUID(uuidString: header.sessionID) != nil,
                          path.lowercased().contains(header.sessionID.lowercased()),
                          let cwd = header.cwd.flatMap(WindowsSessionLaunchHints.absolutePath),
                          budget.hasTime, let after = self.fileInfo(path), before == after
                    else { complete = false; break }
                    guard header.sessionSource == .cli || header.sessionSource == .unknown else { continue }
                    records.append((path, cwd.lowercased(), after,
                                    header.descriptiveName(threadMetadata: nil).map(WindowsSessionLaunchHints.label)))
                }
                guard complete else { continue }
                for index in eligible {
                    guard let birth = output[index].startedAt, let key = directoryKey(output[index]) else { continue }
                    let candidates = records.filter {
                        $0.cwd == key && $0.info.createdAt >= birth && $0.info.createdAt <= now &&
                            $0.info.modifiedAt >= birth && $0.info.modifiedAt <= now
                    }
                    guard candidates.count == 1, let match = candidates.first, budget.hasTime,
                          let latest = self.fileInfo(match.path), latest == match.info else { continue }
                    output[index].metadataMatch = "inferred_cwd_time"
                    output[index].transcriptPath = match.path
                    output[index].sessionName = match.name
                    if match.name != nil { output[index].metadataTitleSource = "rollout_role" }
                    output[index].lastActivityAt = match.info.modifiedAt
                    output[index].state = config.state(lastActivityAt: match.info.modifiedAt, now: now, hasLiveProcess: true)
                    inferredCount += 1
                }
            } else {
                for index in eligible {
                    guard let birth = output[index].startedAt, let cwd = output[index].cwd,
                          !budget.exhausted, !budget.rootUnavailable, budget.hasTime else { continue }
                    let folder = self.join(root, ClaudeSessionProjectMapper.escapedCWD(cwd))
                    let paths = self.codexCandidates(root: folder, ids: [], budget: budget, freshSince: birth, directOnly: true)
                    guard !budget.exhausted, !budget.rootUnavailable, budget.hasTime else { continue }
                    var candidates: [(path: String, info: FileInfo)] = []
                    var complete = true
                    for path in paths {
                        let filename = path.split(separator: "\\").last.map(String.init) ?? ""
                        guard UUID(uuidString: String(filename.dropLast(6))) != nil,
                              budget.consume(), let info = self.fileInfo(path), info.createdAt >= birth
                        else { complete = false; break }
                        if info.createdAt <= now, info.modifiedAt >= birth, info.modifiedAt <= now {
                            candidates.append((path, info))
                        }
                    }
                    guard complete, candidates.count == 1, let match = candidates.first, budget.hasTime,
                          let latest = self.fileInfo(match.path), latest == match.info else { continue }
                    output[index].metadataMatch = "inferred_cwd_time"
                    output[index].transcriptPath = match.path
                    output[index].lastActivityAt = match.info.modifiedAt
                    output[index].state = config.state(lastActivityAt: match.info.modifiedAt, now: now, hasLiveProcess: true)
                    inferredCount += 1
                }
            }
        }
        return Result(sessions: output, message: inferredCount > 0 ?
            "\(inferredCount) new-session metadata matches are inferred from cwd and file times, not verified ownership." :
            "New-session inference found no unambiguous match within the available source and scan budget.")
    }

    private struct FileInfo: Equatable {
        let volume: UInt32
        let index: UInt64
        let size: UInt64
        let createdTicks: UInt64
        let modifiedTicks: UInt64
        var createdAt: Date { Date(timeIntervalSince1970: Double(self.createdTicks) / 10_000_000 - 11_644_473_600) }
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

    private static func codexCandidates(
        root: String, ids: Set<String>, budget: Budget, freshSince: Date? = nil, directOnly: Bool = false) -> [String] {
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
                if freshSince != nil, data.dwFileAttributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) != 0 {
                    budget.rootUnavailable = true
                }
                if name != ".", name != "..", !name.contains("\\"), !name.contains("/"), data.dwFileAttributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) == 0 {
                    let path = self.join(directory, name)
                    if data.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0 {
                        // The canonical root layout is sessions/year/month/day/*.jsonl.
                        if directOnly { /* Claude subagent directories do not represent top-level sessions. */ }
                        else if depth < 3 { stack.append((path, depth + 1)) }
                        else { budget.rootUnavailable = true }
                    } else if name.lowercased().hasSuffix(".jsonl") {
                        let ticks = (UInt64(data.ftCreationTime.dwHighDateTime) << 32) | UInt64(data.ftCreationTime.dwLowDateTime)
                        let created = Date(timeIntervalSince1970: Double(ticks) / 10_000_000 - 11_644_473_600)
                        if ids.contains(where: { name.lowercased().contains($0) }) || freshSince.map({ created >= $0 }) == true {
                            candidates.append(path)
                        }
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
        return self.fileInfo(handle: handle)
    }

    private static func fileInfo(handle: HANDLE) -> FileInfo? {
        guard GetFileType(handle) == DWORD(FILE_TYPE_DISK) else { return nil }
        var info = BY_HANDLE_FILE_INFORMATION()
        guard GetFileInformationByHandle(handle, &info) != 0,
              info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) == 0
        else { return nil }
        return FileInfo(volume: info.dwVolumeSerialNumber,
                        index: (UInt64(info.nFileIndexHigh) << 32) | UInt64(info.nFileIndexLow),
                        size: (UInt64(info.nFileSizeHigh) << 32) | UInt64(info.nFileSizeLow),
                        createdTicks: (UInt64(info.ftCreationTime.dwHighDateTime) << 32) | UInt64(info.ftCreationTime.dwLowDateTime),
                        modifiedTicks: (UInt64(info.ftLastWriteTime.dwHighDateTime) << 32) | UInt64(info.ftLastWriteTime.dwLowDateTime))
    }

    /// Reads the first complete JSONL record only. Header bytes and identity are observed through
    /// one retained non-reparse disk handle; caller also checks the path before accepting the result.
    private static func codexHeader(
        _ path: String, deadline: Date) -> (metadata: CodexRolloutMetadata, info: FileInfo)?
    {
        guard !Task.isCancelled, Date() < deadline,
              let absolute = WindowsSessionLaunchHints.absolutePath(path) else { return nil }
        let units = Array(absolute.utf16) + [0]
        let handle = units.withUnsafeBufferPointer {
            CreateFileW($0.baseAddress, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE),
                        nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { return nil }
        defer { CloseHandle(handle) }
        guard let before = self.fileInfo(handle: handle) else { return nil }
        let maximumBytes = 256 * 1024
        var data = Data()
        var complete = false
        while data.count < maximumBytes, !Task.isCancelled, Date() < deadline {
            var chunk = [UInt8](repeating: 0, count: min(4096, maximumBytes - data.count))
            var count: DWORD = 0
            let success = chunk.withUnsafeMutableBytes {
                ReadFile(handle, $0.baseAddress, DWORD($0.count), &count, nil)
            }
            guard success != 0 else { return nil }
            if count == 0 { complete = true; break }
            let bytes = chunk.prefix(Int(count))
            if let newline = bytes.firstIndex(of: 10) {
                data.append(contentsOf: bytes.prefix(upTo: newline))
                complete = true
                break
            }
            data.append(contentsOf: bytes)
        }
        // A record cut off at the byte limit is never accepted as a complete header.
        guard complete, !Task.isCancelled, Date() < deadline,
              let line = String(data: data, encoding: .utf8),
              let metadata = CodexRolloutFirstLineParser.parse(line),
              let after = self.fileInfo(handle: handle), before == after,
              !Task.isCancelled, Date() < deadline else { return nil }
        return (metadata, after)
    }

    /// Explicit source only: never derive CODEX_HOME or a title index from another account.
    /// Reads through a stable EOF so accepted records cannot have a later unseen rename.
    private enum TitleReadFailure: Error, Hashable, CaseIterable {
        case unavailable, fileLimit, lineLimit, format, changed, deadline, cancelled, outsideWindow
        var message: String {
            switch self {
            case .unavailable: "The configured source cannot be read as a local regular file. Check its location and access."
            case .fileLimit: "The source grew beyond the 1 MiB read window; a later refresh can retry."
            case .lineLimit: "A record exceeds the current 64 KiB line limit."
            case .format: "The source contains incomplete or unsupported title records."
            case .changed: "The source changed during reading; a later refresh can retry."
            case .deadline: "The metadata scan time budget was exhausted."
            case .cancelled: "Title reading was cancelled."
            case .outsideWindow: "Some titles were not found in the last 1 MiB; earlier title records remain unresolved."
            }
        }
    }

    private static func checkTitleDeadline(_ deadline: Date) throws {
        if Task.isCancelled { throw TitleReadFailure.cancelled }
        if Date() >= deadline { throw TitleReadFailure.deadline }
    }

    private struct TitleNames {
        let names: [String: String]
        let seenIDs: Set<String>
        let unresolvedIDs: Set<String>
        subscript(_ id: String) -> String? { self.names[id] }
    }

    private static func stableTitleNames(
        _ path: String, ids: Set<String>, deadline: Date, claude: Bool = false) throws -> TitleNames {
        try self.checkTitleDeadline(deadline)
        guard let absolute = WindowsSessionLaunchHints.absolutePath(path),
              let separator = absolute.lastIndex(of: "\\"),
              self.directoryAllowed(String(absolute[..<separator])) else { throw TitleReadFailure.unavailable }
        let units = Array(absolute.utf16) + [0]
        let handle = units.withUnsafeBufferPointer {
            CreateFileW($0.baseAddress, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE),
                        nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { throw TitleReadFailure.unavailable }
        defer { CloseHandle(handle) }
        let maximumBytes = 1024 * 1024
        guard let before = self.fileInfo(handle: handle) else { throw TitleReadFailure.unavailable }
        let startOffset = before.size > UInt64(maximumBytes) ? before.size - UInt64(maximumBytes) : 0
        if startOffset > 0 {
            guard let offset = Int64(exactly: startOffset) else { throw TitleReadFailure.unavailable }
            var distance = LARGE_INTEGER()
            distance.QuadPart = offset
            guard SetFilePointerEx(handle, distance, nil, DWORD(FILE_BEGIN)) != 0 else { throw TitleReadFailure.unavailable }
        }
        var data = Data()
        var reachedEOF = false
        while data.count <= maximumBytes, !Task.isCancelled, Date() < deadline {
            var chunk = [UInt8](repeating: 0, count: min(4096, maximumBytes + 1 - data.count))
            var count: DWORD = 0
            let success = chunk.withUnsafeMutableBytes {
                ReadFile(handle, $0.baseAddress, DWORD($0.count), &count, nil)
            }
            guard success != 0 else { throw TitleReadFailure.unavailable }
            if count == 0 { reachedEOF = true; break }
            data.append(contentsOf: chunk.prefix(Int(count)))
        }
        try self.checkTitleDeadline(deadline)
        guard data.count <= maximumBytes else { throw TitleReadFailure.fileLimit }
        guard reachedEOF, UInt64(data.count) == before.size - startOffset else { throw TitleReadFailure.changed }
        if startOffset > 0 {
            // The offset may fall inside a UTF-8 scalar or JSON token. Discard through the first
            // newline even if it happened to start on a record boundary; never parse a fragment.
            guard let newline = data.firstIndex(of: 10) else { throw TitleReadFailure.outsideWindow }
            data.removeSubrange(...newline)
        }
        var seenIDs: Set<String> = []
        var names: [String: String] = [:]
        for line in data.split(separator: 10) {
            try self.checkTitleDeadline(deadline)
            guard line.count <= 64 * 1024 else { throw TitleReadFailure.lineLimit }
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else { throw TitleReadFailure.format }
            // Transcript bytes may include conversation records; only typed title metadata is used.
            // Never derive a title from prompts, assistant messages, summaries or tool output.
            if claude, object["type"] as? String != "custom-title" { continue }
            guard let rawID = object[claude ? "sessionId" : "id"] as? String,
                  let uuid = UUID(uuidString: rawID),
                  let title = object[claude ? "customTitle" : "thread_name"] as? String else { throw TitleReadFailure.format }
            let id = uuid.uuidString.lowercased()
            guard ids.contains(id) else { continue }
            seenIDs.insert(id)
            let clean = WindowsSessionLaunchHints.label(title)
            // Append order follows the original index reader; an empty rename removes stale text.
            names[id] = clean.isEmpty ? nil : clean
        }
        try self.checkTitleDeadline(deadline)
        guard let after = self.fileInfo(handle: handle), let current = self.fileInfo(absolute)
        else { throw TitleReadFailure.unavailable }
        guard before == after, current == after else { throw TitleReadFailure.changed }
        return TitleNames(names: names, seenIDs: seenIDs, unresolvedIDs: startOffset > 0 ? ids.subtracting(seenIDs) : [])
    }

    private enum DatabaseReadFailure: Error {
        case module, access, busy, schema, invalidDatabase, limit, duplicate, interrupted, query
        var message: String {
            switch self {
            case .module: "This build has no SQLite module. Use the title index or a build with SQLite support."
            case .access: "The selected database could not be opened read-only. Check the source path and permissions."
            case .busy: "The database is busy or locked. Refresh later; no lock was bypassed."
            case .schema: "The selected database does not support the expected title query. Check the selected Codex database."
            case .invalidDatabase: "SQLite reported an invalid or damaged database. Select another source; no repair was attempted."
            case .limit: "SQLite reported a size or resource limit while reading titles."
            case .duplicate: "The database returned multiple rows for one session UUID; the title is ambiguous."
            case .interrupted: "The SQLite query was interrupted."
            case .query: "The SQLite title query could not complete."
            }
        }
    }

    #if canImport(SQLite3) || canImport(CSQLite3)
    private static func databaseFailure(_ status: Int32, deadline: Date) -> Error {
        if Task.isCancelled { return TitleReadFailure.cancelled }
        if Date() >= deadline { return TitleReadFailure.deadline }
        switch status & 0xFF {
        case SQLITE_BUSY, SQLITE_LOCKED: return DatabaseReadFailure.busy
        case SQLITE_CANTOPEN, SQLITE_PERM, SQLITE_AUTH, SQLITE_READONLY: return DatabaseReadFailure.access
        case SQLITE_NOTADB, SQLITE_CORRUPT: return DatabaseReadFailure.invalidDatabase
        case SQLITE_TOOBIG, SQLITE_NOMEM, SQLITE_FULL: return DatabaseReadFailure.limit
        case SQLITE_SCHEMA, SQLITE_ERROR: return DatabaseReadFailure.schema
        case SQLITE_INTERRUPT, SQLITE_ABORT: return DatabaseReadFailure.interrupted
        default: return DatabaseReadFailure.query
        }
    }
    #endif

    #if canImport(SQLite3) || canImport(CSQLite3)
    private final class DatabaseDeadline {
        let date: Date
        init(_ date: Date) { self.date = date }
    }
    #endif

    private static func databaseTitles(_ path: String, ids: Set<String>, deadline: Date) throws -> [String: String] {
        try self.checkTitleDeadline(deadline)
        guard let absolute = WindowsSessionLaunchHints.absolutePath(path),
              let separator = absolute.lastIndex(of: "\\"),
              self.directoryAllowed(String(absolute[..<separator])), let before = self.fileInfo(absolute)
        else { throw TitleReadFailure.unavailable }
        #if canImport(SQLite3) || canImport(CSQLite3)
        var database: OpaquePointer?
        let opened = sqlite3_open_v2(absolute, &database, SQLITE_OPEN_READONLY, nil)
        guard opened == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw self.databaseFailure(opened, deadline: deadline)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 0)
        sqlite3_limit(database, SQLITE_LIMIT_LENGTH, 64 * 1024)
        let clock = DatabaseDeadline(deadline)
        let context = Unmanaged.passRetained(clock).toOpaque()
        defer { sqlite3_progress_handler(database, 0, nil, nil); Unmanaged<DatabaseDeadline>.fromOpaque(context).release() }
        sqlite3_progress_handler(database, 1000, { pointer in
            guard let pointer else { return 1 }
            let deadline = Unmanaged<DatabaseDeadline>.fromOpaque(pointer).takeUnretainedValue().date
            return Task.isCancelled || Date() >= deadline ? 1 : 0
        }, context)
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(database, "SELECT title FROM threads WHERE id = ?1 LIMIT 2", -1, &statement, nil)
        defer { if let statement { sqlite3_finalize(statement) } }
        guard prepared == SQLITE_OK, let statement else { throw self.databaseFailure(prepared, deadline: deadline) }
        var titles: [String: String] = [:]
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for id in ids.sorted() {
            try self.checkTitleDeadline(deadline)
            guard UUID(uuidString: id) != nil else { throw TitleReadFailure.format }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            let bound = sqlite3_bind_text(statement, 1, id, -1, transient)
            guard bound == SQLITE_OK else { throw self.databaseFailure(bound, deadline: deadline) }
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { continue }
            guard status == SQLITE_ROW else { throw self.databaseFailure(status, deadline: deadline) }
            if sqlite3_column_type(statement, 0) == SQLITE_TEXT, let raw = sqlite3_column_text(statement, 0) {
                let title = WindowsSessionLaunchHints.label(String(cString: raw))
                if !title.isEmpty { titles[id] = title }
            }
            let next = sqlite3_step(statement)
            if next == SQLITE_ROW { throw DatabaseReadFailure.duplicate }
            guard next == SQLITE_DONE else { throw self.databaseFailure(next, deadline: deadline) }
        }
        try self.checkTitleDeadline(deadline)
        guard let after = self.fileInfo(absolute), before == after else { throw TitleReadFailure.changed }
        return titles
        #else
        throw DatabaseReadFailure.module
        #endif
    }

    private static func join(_ base: String, _ component: String) -> String {
        base.hasSuffix("\\") ? base + component : base + "\\" + component
    }
}
#endif
