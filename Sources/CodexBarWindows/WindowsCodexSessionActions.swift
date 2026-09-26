#if os(Windows)
import Foundation
import CodexBarCore

/// Identity stays in the backend. The UI sends only a revision-bound model/reference selection.
enum WindowsCodexSessionActions {
    struct Availability: Codable, Sendable {
        let canCopyID: Bool
        let canCopyResume: Bool
        let canFocus: Bool
    }
    static func availability(_ session: WindowsCodexActivityAnalysis.Session,
                             stale: Bool, hidePersonalInfo: Bool) -> Availability {
        let id = CodexModelActivityEvidence.normalizedSessionID(session.sessionID)
        let uuid = id.flatMap(UUID.init(uuidString:))
        return .init(canCopyID: !stale && !hidePersonalInfo && id != nil,
            canCopyResume: !stale && !hidePersonalInfo && uuid != nil, canFocus: !stale && uuid != nil)
    }
    static func clipboard(kind: String, session: WindowsCodexActivityAnalysis.Session,
                          stale: Bool, hidePersonalInfo: Bool) -> String? {
        let enabled = self.availability(session, stale: stale, hidePersonalInfo: hidePersonalInfo)
        guard let id = CodexModelActivityEvidence.normalizedSessionID(session.sessionID) else { return nil }
        if kind == "copyCodexSessionID", enabled.canCopyID { return id }
        if kind == "copyCodexResume", enabled.canCopyResume, let uuid = UUID(uuidString: id) {
            // UUID-only command arguments. No paths, shell fragments, profile guesses or automatic execution.
            return "codex resume " + uuid.uuidString.lowercased()
        }
        return nil
    }
    static func matchingProcess(sessionID: String, sessions: [AgentSession],
                                explicitSessionIDs: [String: String]) -> AgentSession? {
        guard let id = UUID(uuidString: sessionID) else { return nil }
        let matches = sessions.filter {
            $0.provider == .codex && $0.source == .cli && ($0.pid ?? 0) > 0
                && explicitSessionIDs[$0.id].flatMap(UUID.init(uuidString:)) == id
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
#endif
