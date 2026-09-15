#if os(Windows)
import CodexBarCore
import Foundation

public enum WindowsWidgetUsage {
    public struct Row: Sendable {
        public let id: String
        public let title: String
        public let remainingPercent: Double?
        public let displayedPercent: Double?
        public let barFraction: Double?
        public let resetsAt: Date?
        public let isStale: Bool
    }
    public enum Failure: Error, Sendable { case tooManyRows, invalidRow, duplicateRow, invalidClock }

    public static func rows(from content: WindowsWidgetContentResolver.Content, now: Date = Date()) throws -> [Row] {
        guard now.timeIntervalSince1970.isFinite else { throw Failure.invalidClock }
        guard let entry = content.entry else { return [] }
        let source: [WidgetSnapshot.WidgetUsageRowSnapshot]
        if let supplied = entry.usageRows {
            source = supplied
        } else {
            let metadata = ProviderDescriptorRegistry.descriptor(for: content.provider).metadata
            var fallback = [WidgetSnapshot.WidgetUsageRowSnapshot]()
            if let window = entry.primary {
                fallback.append(.init(id: "primary", title: metadata.sessionLabel, percentLeft: nil, window: window))
            }
            if let window = entry.secondary {
                fallback.append(.init(id: "secondary", title: metadata.weeklyLabel, percentLeft: nil, window: window))
            }
            if metadata.supportsOpus, let window = entry.tertiary {
                fallback.append(.init(id: "tertiary", title: metadata.opusLabel ?? "Opus", percentLeft: nil, window: window))
            }
            source = fallback
        }
        guard source.count <= 64 else { throw Failure.tooManyRows }
        let resolved = source.map { row -> WidgetSnapshot.WidgetUsageRowSnapshot in
            guard row.window == nil, content.provider == .codex,
                  let window = legacyCodexWindow(id: row.id, entry: entry) else { return row }
            return .init(id: row.id, title: row.title, percentLeft: row.percentLeft, window: window)
        }
        var seen = Set<String>()
        let rows = try resolved.map { row in
            guard !row.id.isEmpty, row.id.utf8.count <= 256, row.title.utf8.count <= 1024,
                  !row.id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  !row.title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else { throw Failure.invalidRow }
            guard seen.insert(row.id).inserted else { throw Failure.duplicateRow }
            let remaining = row.window?.remainingPercent ?? row.percentLeft
            guard remaining?.isFinite ?? true, row.window?.usedPercent.isFinite ?? true,
                  row.window?.resetsAt?.timeIntervalSince1970.isFinite ?? true else {
                throw Failure.invalidRow
            }
            let displayed = remaining.map { content.showUsed ? 100 - $0 : $0 }
            return Row(id: row.id, title: row.title, remainingPercent: remaining, displayedPercent: displayed,
                barFraction: displayed.map { min(1, max(0, $0 / 100)) }, resetsAt: row.window?.resetsAt,
                isStale: content.state == .stale)
        }
        // Match the original explicit Codex session/weekly row pairing only.
        guard content.provider == .codex,
              let weekly = resolved.first(where: { $0.id == "weekly" })?.window,
              weekly.remainingPercent <= 0, weekly.resetsAt.map({ $0 > now }) ?? true else { return rows }
        return rows.map { row in
            guard row.id == "session" else { return row }
            return Row(id: row.id, title: row.title, remainingPercent: 0,
                displayedPercent: content.showUsed ? 100 : 0, barFraction: content.showUsed ? 1 : 0,
                resetsAt: row.resetsAt, isStale: row.isStale)
        }
    }

    /// Uses the original provider size policy; the Windows host maps its supported sizes to this family.
    public static func rows(from content: WindowsWidgetContentResolver.Content,
                            family: ProviderWidgetFamily, now: Date = Date()) throws -> [Row] {
        let all = try self.rows(from: content, now: now)
        let policy = ProviderDescriptorRegistry.descriptor(for: content.provider).presentation
        guard let requestedLimit = policy.widgetRowLimit(rows: content.entry?.usageRows, family: family) else { return all }
        let limit = min(all.count, max(0, requestedLimit))
        guard content.provider == .antigravity, limit >= 2,
              all.contains(where: { $0.id.hasPrefix("antigravity-quota-summary-") }) else {
            return Array(all.prefix(limit))
        }
        let ranked = all.enumerated().sorted { left, right in
            switch (left.element.remainingPercent, right.element.remainingPercent) {
            case let (.some(lhs), .some(rhs)): return lhs == rhs ? left.offset < right.offset : lhs < rhs
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return left.offset < right.offset
            }
        }.map(\.element)
        var selected = [0, 1].compactMap { family in ranked.first { antigravityFamily($0) == family } }
        let ids = Set(selected.map(\.id))
        selected.append(contentsOf: ranked.filter { !ids.contains($0.id) }.prefix(max(0, limit - selected.count)))
        return selected
    }

    private static func antigravityFamily(_ row: Row) -> Int? {
        guard row.id.hasPrefix("antigravity-quota-summary-") else { return nil }
        let id = row.id.lowercased()
        if id.contains("gemini") { return 0 }
        if id.contains("3p") || id.contains("third-party") { return 1 }
        let title = row.title.lowercased()
        if title.contains("gemini") { return 0 }
        if title.contains("claude") || title.contains("gpt") { return 1 }
        return nil
    }

    private static func legacyCodexWindow(id: String, entry: WidgetSnapshot.ProviderEntry) -> RateWindow? {
        for (window, fallback) in [(entry.primary, "session"), (entry.secondary, "weekly")] {
            guard let window else { continue }
            let classified: String
            switch window.windowMinutes {
            case 300: classified = "session"
            case 10080: classified = "weekly"
            default: classified = fallback
            }
            if classified == id { return window }
        }
        return nil
    }
}
#endif
