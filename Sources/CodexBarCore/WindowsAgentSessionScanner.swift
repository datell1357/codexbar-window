#if os(Windows)
import Foundation
import WinSDK

/// Windows CLI scan outcomes. Enrichment uses only explicit target argv paths; unrelated recent
/// files, CodexBar's cwd and another process's environment are never used as a correlation shortcut.
public struct WindowsSessionScanOutcome: Sendable {
    public enum Status: Sendable { case complete, partial, failed, cancelled }
    public let status: Status
    public let sessions: [AgentSession]
    public let message: String?
}

public enum WindowsAgentSessionScanner {
    static func scan(config: SessionScanConfig, now: Date) async -> [AgentSession] {
        await self.scanOutcome(config: config, now: now).sessions
    }

    public static func scanOutcome(
        config: SessionScanConfig = SessionScanConfig(),
        now: Date = Date(),
        nativeDirectoryReadEnabled: Bool = false,
        metadataRoots: WindowsSessionMetadataRoots = .none,
        titleCache: WindowsSessionTitleCache? = nil) async -> WindowsSessionScanOutcome
    {
        guard !Task.isCancelled else { return .init(status: .cancelled, sessions: [], message: nil) }
        guard config.maxProcessCount > 0 else {
            return .init(status: .partial, sessions: [], message: "Session scan limit is zero.")
        }
        let deadline = Date().addingTimeInterval(2)
        let snapshots: [WindowsProcessSnapshot]
        do {
            snapshots = try await WindowsProcessEnumerator.snapshots(
                deadline: deadline, scope: .agentSessions)
        } catch is CancellationError {
            return .init(status: .cancelled, sessions: [], message: nil)
        } catch WindowsProcessEnumerator.ProcessEnumeratorError.timedOut {
            return .init(status: .failed, sessions: [], message: "Windows process discovery timed out.")
        } catch {
            return .init(status: .failed, sessions: [], message: "Windows process discovery failed.")
        }
        var sessions: [AgentSession] = []
        var requestedIDs: [String: String] = [:]
        var newSessionIDs: Set<String> = []
        var partialMessage: String?
        var unavailableExplicitMetadata = false
        var unavailableNativeDirectories = 0
        for process in snapshots.sorted(by: { $0.creationTime > $1.creationTime }) {
            guard !Task.isCancelled else { return .init(status: .cancelled, sessions: [], message: nil) }
            guard sessions.count < config.maxProcessCount else {
                partialMessage = "Session result limit reached; this list may be incomplete."
                break
            }
            guard Date() < deadline else {
                partialMessage = "Session scan time budget reached; this list may be incomplete."
                break
            }
            guard let pid = Int32(exactly: process.pid), process.creationTicks > 0,
                  self.isConsoleImage(process.imagePath),
                  let identity = self.identity(imagePath: process.imagePath, arguments: self.arguments(process.commandLine))
            else { continue }
            let hints = WindowsSessionLaunchHints.parse(provider: identity.provider, arguments: identity.arguments)
            let processSessionID = "pid:\(process.pid):\(process.creationTicks)"
            requestedIDs[processSessionID] = hints.requestedSessionID
            if hints.allowsNewSessionCorrelation { newSessionIDs.insert(processSessionID) }
            var nativeDirectory: String?
            if nativeDirectoryReadEnabled {
                switch WindowsProcessWorkingDirectory.read(process: process, deadline: deadline) {
                case let .available(path): nativeDirectory = path
                case .unavailable: unavailableNativeDirectories += 1
                }
            }
            let metadata: WindowsExplicitSessionMetadata?
            if identity.provider == .pi, let dialect = identity.dialect, let path = hints.sessionFile {
                metadata = WindowsExplicitSessionMetadataReader.read(
                    path: path, dialect: dialect, now: now, deadline: deadline)
                unavailableExplicitMetadata = unavailableExplicitMetadata || metadata == nil
            } else {
                metadata = nil
            }
            // A selected file's saved cwd can label that session, but is not a live process-cwd observation.
            // An explicit provider workspace override remains authoritative (it may not call chdir).
            let cwd = hints.workingDirectory ?? nativeDirectory
            let projectPath = cwd ?? metadata?.cwd
            sessions.append(AgentSession(
                id: processSessionID,
                provider: identity.provider,
                dialect: identity.dialect,
                source: .cli,
                state: config.state(lastActivityAt: metadata?.modifiedAt, now: now, hasLiveProcess: true),
                pid: pid,
                cwd: cwd,
                projectName: WindowsSessionLaunchHints.projectName(projectPath),
                sessionName: metadata?.title,
                startedAt: process.creationTime,
                lastActivityAt: metadata?.modifiedAt,
                transcriptPath: metadata?.path,
                host: ProcessInfo.processInfo.hostName))
            if metadata != nil {
                sessions[sessions.count - 1].metadataMatch = "explicit_file"
                if metadata?.title != nil { sessions[sessions.count - 1].metadataTitleSource = "session_header" }
            }
        }
        guard !Task.isCancelled else { return .init(status: .cancelled, sessions: [], message: nil) }
        if unavailableExplicitMetadata {
            partialMessage = [partialMessage, "Some explicitly selected session headers were unavailable; PID labels are retained."]
                .compactMap { $0 }.joined(separator: " ")
        }
        if unavailableNativeDirectories > 0 {
            partialMessage = [partialMessage,
                              "Native directories were unavailable for \(unavailableNativeDirectories) processes; existing path/PID fallback is retained."]
                .compactMap { $0 }.joined(separator: " ")
        }
        let correlated = WindowsSessionMetadataCorrelator.enrich(
            sessions: sessions, requestedIDs: requestedIDs, roots: metadataRoots, config: config, now: now,
            newSessionIDs: partialMessage == nil ? newSessionIDs : [], titleCache: titleCache)
        if let notice = correlated.message {
            partialMessage = [partialMessage, notice].compactMap { $0 }.joined(separator: " ")
        }
        guard !Task.isCancelled else { return .init(status: .cancelled, sessions: [], message: nil) }
        return .init(status: partialMessage == nil ? .complete : .partial, sessions: correlated.sessions, message: partialMessage)
    }

    private static func identity(
        imagePath: String,
        arguments: [String]) -> (provider: AgentSession.Provider, dialect: AgentSession.Dialect?, arguments: [String])?
    {
        guard !arguments.isEmpty else { return nil }
        var name = URL(fileURLWithPath: imagePath).lastPathComponent.lowercased()
        if name.hasSuffix(".exe") { name.removeLast(4) }
        var commandArguments = Array(arguments.dropFirst())
        if name == "node" || name == "bun" {
            // Only a direct, recognized package entry point is accepted. Runtime preloads and
            // arbitrary scripts mentioning a provider in their prompt are not session evidence.
            guard let script = commandArguments.first, !script.hasPrefix("-") else { return nil }
            let path = script.replacingOccurrences(of: "\\", with: "/").lowercased()
            if path.contains("/@openai/codex/") { name = "codex" }
            else if path.contains("/@anthropic-ai/claude-code/") { name = "claude" }
            else if path.contains("/@mariozechner/pi-coding-agent/") { name = "pi" }
            else if path.contains("/@oh-my-pi/pi-coding-agent/") { name = "omp" }
            else { return nil }
            commandArguments.removeFirst()
        }
        if commandArguments.prefix(while: { $0 != "--" }).contains(where: {
            ["--version", "-v", "--help", "-h"].contains($0) || $0.hasPrefix("--type=")
        }) { return nil }
        if let first = commandArguments.first,
           ["login", "logout", "auth", "completion", "completions", "app-server", "mcp-server", "mcp"].contains(first)
        { return nil }
        if name == "codex" || name.hasPrefix("codex-x86_64-") || name.hasPrefix("codex-aarch64-") {
            return (.codex, nil, commandArguments)
        }
        if name == "claude" || name == "claude-code" { return (.claude, nil, commandArguments) }
        if name == "pi" { return (.pi, .pi, commandArguments) }
        if name == "omp" { return (.pi, .omp, commandArguments) }
        return nil
    }

    private static func arguments(_ commandLine: String) -> [String] {
        var count: Int32 = 0
        let units = Array(commandLine.utf16) + [0]
        guard let argv = units.withUnsafeBufferPointer({ CommandLineToArgvW($0.baseAddress, &count) }) else { return [] }
        defer { _ = LocalFree(UnsafeMutableRawPointer(argv)) }
        guard count > 0, count <= 4096 else { return [] }
        var result: [String] = []
        for index in 0..<Int(count) {
            guard let argument = argv[index] else { return [] }
            result.append(String(decodingCString: argument, as: UTF16.self))
        }
        return result
    }

    /// PE subsystem 3 is a console image. Avoid treating the GUI Codex/Claude executables as CLI
    /// sessions just because their basenames match. Read only bounded PE headers, never execute them.
    private static func isConsoleImage(_ path: String) -> Bool {
        guard let file = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return false }
        defer { try? file.close() }
        do {
            guard let dos = try file.read(upToCount: 64), dos.count == 64, dos[0] == 0x4D, dos[1] == 0x5A else {
                return false
            }
            let offset = (0..<4).reduce(UInt32(0)) { $0 | (UInt32(dos[60 + $1]) << ($1 * 8)) }
            guard offset >= 64, offset <= 1024 * 1024 else { return false }
            try file.seek(toOffset: UInt64(offset))
            guard let pe = try file.read(upToCount: 96), pe.count == 96,
                  Array(pe.prefix(4)) == [0x50, 0x45, 0, 0]
            else { return false }
            let optionalSize = UInt16(pe[20]) | (UInt16(pe[21]) << 8)
            let magic = UInt16(pe[24]) | (UInt16(pe[25]) << 8)
            guard optionalSize >= 70, magic == 0x10B || magic == 0x20B else { return false }
            return (UInt16(pe[92]) | (UInt16(pe[93]) << 8)) == 3
        } catch {
            return false
        }
    }
}
#endif
