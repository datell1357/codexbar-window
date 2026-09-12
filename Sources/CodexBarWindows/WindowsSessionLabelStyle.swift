#if os(Windows)
import CodexBarCore
import Foundation

/// The same persisted choices as the original session label setting. Privacy wins over the style.
enum WindowsSessionLabelStyle: String, CaseIterable {
    case project
    case descriptive
    case descriptiveAndProject

    var title: String {
        switch self {
        case .project: "Project"
        case .descriptive: "Session title"
        case .descriptiveAndProject: "Session title and project"
        }
    }

    static func load(_ defaults: UserDefaults) -> Self {
        Self(rawValue: defaults.string(forKey: "agentSessionLabelStyle") ?? "") ?? .project
    }

    func label(_ session: AgentSession, hidePersonalInfo: Bool) -> String? {
        guard !hidePersonalInfo else { return nil }
        let project = Self.clean(session.projectName)
        let descriptive = Self.clean(session.sessionName)
        switch self {
        case .project: return project
        case .descriptive: return descriptive ?? project
        case .descriptiveAndProject:
            guard let descriptive else { return project }
            guard let project, descriptive.caseInsensitiveCompare(project) != .orderedSame else { return descriptive }
            return "\(descriptive) · \(project)"
        }
    }

    private static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let filtered = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            .prefix(128).map { String($0) }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return filtered.isEmpty ? nil : filtered
    }
}
#endif
