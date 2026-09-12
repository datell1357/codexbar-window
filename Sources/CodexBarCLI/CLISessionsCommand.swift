import CodexBarCore
import Commander
import Foundation

extension CodexBarCLI {
    static func runSessions(_ values: ParsedValues) async {
        let sessions = await Self.scanSessionsForCommand(values: values)
        if let jsonVersion = Self.sessionsJSONProtocolVersion(from: values) {
            Self.printJSON(
                Self.sessionsForJSON(sessions, includePiFamily: jsonVersion == 2),
                pretty: values.flags.contains("pretty"))
        } else {
            print(Self.renderSessionsTable(sessions))
        }
    }

    private static func scanSessionsForCommand(values: ParsedValues) async -> [AgentSession] {
        #if os(Windows)
        let roots: WindowsSessionMetadataRoots
        do {
            roots = try WindowsSessionMetadataRoots.load(
                codexOverride: values.options["codexSessionRoot"]?.last,
                claudeOverride: values.options["claudeProjectRoot"]?.last,
                allowNewSessions: values.flags.contains("inferNewSessions"),
                codexTitleIndexOverride: values.options["codexTitleIndex"]?.last)
        } catch {
            Self.writeStderr("Invalid Windows session metadata root. Use an absolute local drive path.\n")
            Self.platformExit(64)
        }
        let outcome = await WindowsAgentSessionScanner.scanOutcome(
            nativeDirectoryReadEnabled: values.flags.contains("nativeCwd"), metadataRoots: roots)
        switch outcome.status {
        case .failed, .cancelled:
            Self.writeStderr((outcome.message ?? "Session scan cancelled.") + "\n")
            Self.platformExit(1)
        case .partial:
            Self.writeStderr((outcome.message ?? "Partial session list.") + "\n")
        case .complete:
            break
        }
        return outcome.sessions
        #else
        return await LocalAgentSessionScanner().scan()
        #endif
    }

    static func sessionsJSONProtocolVersion(from values: ParsedValues) -> Int? {
        if values.flags.contains("jsonV2") {
            return 2
        }
        if values.flags.contains("jsonShortcut") {
            return 1
        }
        return nil
    }

    static func sessionsForJSON(_ sessions: [AgentSession], includePiFamily: Bool) -> [AgentSession] {
        guard !includePiFamily else { return sessions }
        // Provider-specific by design: the legacy sessions JSON contract includes only native Codex/Claude scans.
        return sessions.filter { $0.provider == .codex || $0.provider == .claude }
    }

    static func runSessionsFocus(_ values: ParsedValues) async {
        guard let sessionID = values.positional.first, !sessionID.isEmpty else {
            writeStderr("Missing session id.\n")
            platformExit(1)
        }
        let sessions = await Self.scanSessionsForCommand(values: values)
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            Self.writeStderr("Unknown session: \(sessionID)\n")
            Self.platformExit(1)
        }

        #if os(macOS) || os(Windows)
        let result = await MainActor.run {
            SessionWindowFocuser.focus(session)
        }
        switch result {
        case .focused, .activatedApplicationOnly:
            Self.platformExit(0)
        case .failed:
            Self.writeStderr("Could not focus session: \(sessionID)\n")
            Self.platformExit(2)
        }
        #else
        Self.writeStderr("Session focus is not supported on this platform.\n")
        Self.platformExit(2)
        #endif
    }

    static func renderSessionsTable(_ sessions: [AgentSession], now: Date = Date()) -> String {
        guard !sessions.isEmpty else { return "No agent sessions found." }
        let rows = sessions.map { session in
            [
                session.state == .active ? "active" : "idle",
                session.provider.rawValue,
                session.dialect?.rawValue ?? "—",
                session.source.rawValue,
                session.projectName ?? "—",
                Self.sessionAge(session, now: now),
                session.id,
            ]
        }
        let headers = ["STATE", "PROVIDER", "DIALECT", "SOURCE", "PROJECT", "ACTIVITY", "ID"]
        let widths = headers.indices.map { index in
            ([headers[index]] + rows.map { $0[index] }).map(\ .count).max() ?? headers[index].count
        }
        let render: ([String]) -> String = { columns in
            columns.indices.map { index in
                columns[index].padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
        }
        return ([render(headers)] + rows.map(render)).joined(separator: "\n")
    }

    private static func sessionAge(_ session: AgentSession, now: Date) -> String {
        guard let date = session.lastActivityAt ?? session.startedAt else { return "now" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 {
            return "\(seconds)s"
        }
        if seconds < 3600 {
            return "\(seconds / 60)m"
        }
        if seconds < 86400 {
            return "\(seconds / 3600)h"
        }
        return "\(seconds / 86400)d"
    }
}

struct SessionsOptions: CommanderParsable {
    #if os(Windows)
    @Flag(name: .long("native-cwd"), help: "Opt in to experimental native 64-bit process directory reads")
    var nativeCwd: Bool = false
    @Flag(name: .long("infer-new-sessions"), help: "Opt in to heuristic new-session metadata matching within explicit roots")
    var inferNewSessions: Bool = false
    @Option(name: .long("codex-session-root"), help: "Explicit Codex sessions folder for selected UUID metadata matching")
    var codexSessionRoot: String?
    @Option(name: .long("codex-title-index"), help: "Explicit Codex session_index.jsonl for selected UUID titles (maximum 1 MiB)")
    var codexTitleIndex: String?
    @Option(name: .long("claude-project-root"), help: "Explicit Claude projects folder for selected UUID metadata matching")
    var claudeProjectRoot: String?
    #endif

    @Flag(name: .long("json"), help: "Emit legacy JSON compatible with older clients")
    var jsonShortcut: Bool = false

    @Flag(name: .long("json-v2"), help: "Emit complete JSON, including Pi-family sessions")
    var jsonV2: Bool = false

    @Flag(name: .long("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false
}

struct SessionsFocusOptions: CommanderParsable {
    @Argument(help: "Session identifier")
    var id: String = ""
}
