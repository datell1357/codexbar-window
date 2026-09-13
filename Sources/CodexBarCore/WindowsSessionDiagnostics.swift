#if os(Windows)
import Foundation

/// Counts describe returned rows only, never all running processes or successful source ownership.
/// No identities, paths, titles, or provider error strings are retained in this projection.
public struct WindowsSessionDiagnostics: Codable, Equatable, Sendable {
    public struct ProviderCounts: Codable, Equatable, Sendable {
        public let provider: AgentSession.Provider
        public let returned: Int
        public let knownDirectory: Int
        public let explicitMetadata: Int
        public let inferredMetadata: Int
        public let withoutClassifiedMetadata: Int
        public let named: Int
    }
    public let providers: [ProviderCounts]
    public let partial: Bool

    public init(sessions: [AgentSession], partial: Bool) {
        self.partial = partial
        self.providers = [AgentSession.Provider.codex, .claude, .pi].map { provider in
            let rows = sessions.filter { $0.provider == provider }
            let explicit = rows.filter { $0.metadataMatch == "explicit_uuid" || $0.metadataMatch == "explicit_file" }.count
            let inferred = rows.filter { $0.metadataMatch == "inferred_cwd_time" }.count
            return ProviderCounts(
                provider: provider, returned: rows.count,
                knownDirectory: rows.filter { $0.cwd?.isEmpty == false }.count,
                explicitMetadata: explicit, inferredMetadata: inferred,
                withoutClassifiedMetadata: rows.count - explicit - inferred,
                named: rows.filter { $0.sessionName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }.count)
        }
    }
}
#endif
