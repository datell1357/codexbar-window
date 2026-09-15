import Foundation

/// Source windows for persisted plan utilization, before UI caps or remaining-percent rendering.
public struct PlanUtilizationHistoryProjection: Sendable {
    public let samples: [PlanUtilizationHistoryCore.Series]
    public let identityTransition: PlanUtilizationHistoryCore.IdentityTransition

    public struct ForecastWindows: Sendable {
        public let session: RateWindow
        public let weekly: RateWindow
        public let weeklyWindowID: String?
        public let historyIdentity: String?
    }

    /// Uses the same source identity as history collection. A mixed or ambiguous pair
    /// must not borrow a burn estimate from a different quota family.
    public static func forecastWindows(provider: UsageProvider, snapshot: UsageSnapshot) -> ForecastWindows? {
        switch provider {
        case .codex:
            let lanes = self.codexWindows(snapshot)
            guard let session = lanes["session"], let weekly = lanes["weekly"] else { return nil }
            return ForecastWindows(session: session, weekly: weekly, weeklyWindowID: nil, historyIdentity: nil)
        case .claude:
            guard let session = snapshot.primary,
                  session.windowMinutes.map({ PlanUtilizationHistoryCore.canonicalMinutes($0, name: "session") }) == 300,
                  let weekly = snapshot.secondary,
                  weekly.windowMinutes.map({ PlanUtilizationHistoryCore.canonicalMinutes($0, name: "weekly") }) == 10080 else { return nil }
            return ForecastWindows(session: session, weekly: weekly, weeklyWindowID: nil, historyIdentity: nil)
        case .antigravity:
            guard let pair = self.antigravityWindows(snapshot) else { return nil }
            return ForecastWindows(session: pair.session.window, weekly: pair.weekly.window,
                weeklyWindowID: pair.weekly.id, historyIdentity: nil)
        default:
            let session = self.resolve(snapshot: snapshot, minutes: 300)
            let weekly = self.resolve(snapshot: snapshot, minutes: 10080)
            guard case let .genericResolved(sessionID, weeklyID) = self.transition(session: session, weekly: weekly),
                  let sessionWindow = session.window, let weeklyWindow = weekly.window else { return nil }
            let namedID = weeklyID.hasPrefix("named:") ? String(weeklyID.dropFirst(6)) : nil
            return ForecastWindows(session: sessionWindow, weekly: weeklyWindow, weeklyWindowID: namedID,
                historyIdentity: PlanUtilizationHistoryCore.pairIdentity(session: sessionID, weekly: weeklyID))
        }
    }

    public static func make(provider: UsageProvider, snapshot: UsageSnapshot, capturedAt: Date) -> Self {
        typealias Series = PlanUtilizationHistoryCore.Series
        struct Key: Hashable { let name: String; let minutes: Int }
        var samples: [Key: Series] = [:]
        let session = Self.resolve(snapshot: snapshot, minutes: 300)
        let weekly = Self.resolve(snapshot: snapshot, minutes: 10080)
        var transition = Self.transition(session: session, weekly: weekly)

        func append(_ window: RateWindow?, name: String) {
            guard let window, !window.isSyntheticPlaceholder,
                  let minutes = window.windowMinutes, minutes > 0,
                  capturedAt.timeIntervalSince1970.isFinite, window.usedPercent.isFinite,
                  window.resetsAt?.timeIntervalSince1970.isFinite ?? true else { return }
            let canonical: Int
            if name == "session", (295...305).contains(minutes) { canonical = 300 }
            else if name == "weekly", (10070...10090).contains(minutes) { canonical = 10080 }
            else { canonical = minutes }
            samples[Key(name: name, minutes: canonical)] = Series(name: name, windowMinutes: canonical,
                entries: [.init(capturedAt: capturedAt, usedPercent: max(0, min(100, window.usedPercent)),
                    resetsAt: window.resetsAt)])
        }
        func appendGeneric() {
            append(session.window, name: "session")
            append(weekly.window, name: "weekly")
        }

        switch provider {
        case .codex:
            transition = .fixed
            let lanes = Self.codexWindows(snapshot)
            for name in ["session", "weekly", "monthly"] { append(lanes[name], name: name) }
        case .claude:
            transition = .fixed
            append(snapshot.primary, name: "session")
            append(snapshot.secondary, name: "weekly")
            append(snapshot.tertiary, name: "opus")
        case .opencodego:
            append(snapshot.primary, name: "session")
            append(snapshot.secondary, name: "weekly")
            append(snapshot.tertiary, name: "monthly")
        case .mimo, .stepfun, .ollama:
            if snapshot.primary?.windowMinutes == ProviderPaceCapability.monthlyWindowSentinelMinutes {
                append(snapshot.primary, name: "monthly")
                if provider == .ollama { append(snapshot.secondary, name: "weekly") }
            } else { appendGeneric() }
        case .antigravity:
            transition = .antigravityGemini
            // Persistence uses the complete Gemini pair, not a provider-wide weekly maximum.
            if let pair = Self.antigravityWindows(snapshot) {
                append(pair.session.window, name: "session")
                append(pair.weekly.window, name: "weekly")
            }
        default: appendGeneric()
        }
        return Self(samples: samples.values.sorted {
            $0.windowMinutes == $1.windowMinutes ? $0.name < $1.name : $0.windowMinutes < $1.windowMinutes
        }, identityTransition: transition)
    }

    private static func codexWindows(_ snapshot: UsageSnapshot) -> [String: RateWindow] {
        var lanes: [String: RateWindow] = [:]
        for (window, fallback) in [(snapshot.primary, "session"), (snapshot.secondary, "weekly")] {
            guard let window else { continue }
            let role: String
            switch window.windowMinutes {
            case 300: role = "session"
            case 10080: role = "weekly"
            case 43200: role = "monthly"
            default: role = fallback
            }
            lanes[role] = window
        }
        return lanes
    }

    private static func antigravityWindows(_ snapshot: UsageSnapshot) -> (session: NamedRateWindow, weekly: NamedRateWindow)? {
        let windows = snapshot.extraRateWindows?.filter {
            $0.usageKnown && $0.id.hasPrefix("antigravity-quota-summary-") && self.antigravityFamily($0.id) == "gemini"
        } ?? []
        let sessions = windows.filter { $0.window.windowMinutes == 300 }
        let weeklies = windows.filter { $0.window.windowMinutes == 10080 }
        guard sessions.count == 1, weeklies.count == 1 else { return nil }
        return (sessions[0], weeklies[0])
    }

    private enum Component {
        case resolved(RateWindow, identity: String)
        case incomplete, ambiguous
        var window: RateWindow? { if case let .resolved(window, _) = self { return window }; return nil }
        var identity: String? { if case let .resolved(_, identity) = self { return identity }; return nil }
        var isAmbiguous: Bool { if case .ambiguous = self { return true }; return false }
    }

    private static func resolve(snapshot: UsageSnapshot, minutes: Int) -> Component {
        let candidates = [(snapshot.primary, "standard:primary"), (snapshot.secondary, "standard:secondary"),
                          (snapshot.tertiary, "standard:tertiary")].compactMap { window, identity -> (RateWindow, String)? in
            guard let window, window.windowMinutes == minutes else { return nil }
            return (window, identity)
        }
        if candidates.count == 1 { return .resolved(candidates[0].0, identity: candidates[0].1) }
        guard candidates.isEmpty else { return .ambiguous }
        // An unknown named measurement still participates in ambiguity detection.
        let named = snapshot.extraRateWindows?.filter { $0.window.windowMinutes == minutes } ?? []
        guard named.count <= 1 else { return .ambiguous }
        guard let candidate = named.first, candidate.usageKnown else { return .incomplete }
        return .resolved(candidate.window, identity: "named:" + candidate.id)
    }

    private static func transition(session: Component, weekly: Component) -> PlanUtilizationHistoryCore.IdentityTransition {
        if session.isAmbiguous || weekly.isAmbiguous { return .genericAmbiguous(weekly: weekly.identity) }
        guard let sessionID = session.identity, let weeklyID = weekly.identity else {
            return .genericIncomplete(weekly: weekly.identity)
        }
        if sessionID.hasPrefix("standard:"), weeklyID.hasPrefix("standard:") {
            return .genericResolved(session: sessionID, weekly: weeklyID)
        }
        if sessionID.hasPrefix("named:"), weeklyID.hasPrefix("named:"),
           let sessionFamily = self.family(String(sessionID.dropFirst(6)),
               suffixes: ["-session", "_session", " session", "-5h", "_5h", " 5h"]),
           let weeklyFamily = self.family(String(weeklyID.dropFirst(6)), suffixes: ["-weekly", "_weekly", " weekly"]),
           sessionFamily == weeklyFamily {
            return .genericResolved(session: sessionID, weekly: weeklyID)
        }
        return .genericAmbiguous(weekly: weeklyID)
    }

    private static func family(_ id: String, suffixes: [String]) -> String? {
        let normalized = id.lowercased()
        guard let suffix = suffixes.first(where: { normalized.hasSuffix($0) }) else { return nil }
        let family = String(normalized.dropLast(suffix.count))
        return family.isEmpty ? nil : family
    }

    private static func antigravityFamily(_ id: String) -> String {
        var value = String(id.dropFirst("antigravity-quota-summary-".count)).lowercased()
        let suffixes = ["-5h limit", "_5h_limit", "-weekly", "_weekly", " weekly", "-session", "_session", " session", "-5h", "_5h", " 5h"]
        if let suffix = suffixes.first(where: { value.hasSuffix($0) }) { value.removeLast(suffix.count) }
        else if ["weekly", "session", "5h"].contains(value) { value = "" }
        return value
    }
}
