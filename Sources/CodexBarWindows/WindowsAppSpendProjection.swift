#if os(Windows)
import Foundation
import CodexBarCore

/// Bounded, display-only projection. No account identifiers, credential material or raw source paths are sent.
enum WindowsAppSpendProjection {
    struct Query: Codable, Sendable {
        var days = 30
        var currency: String?
        var section = "providers"
        var chart = "cost"
        var page = 0
        var detail: DetailQuery?
        var isValid: Bool {
            (1...WindowsSpendHistoryPolicy.scanDays).contains(self.days) && self.page >= 0 && self.page <= 100000 &&
                ["providers", "models", "projects", "sessions"].contains(self.section) &&
                ["cost", "tokens"].contains(self.chart) &&
                (self.currency == nil || (self.currency!.utf8.count == 3 && self.currency!.utf8.allSatisfy { (65...90).contains($0) })) &&
                (self.detail?.isValid ?? true)
        }
    }
    struct DetailQuery: Codable, Sendable {
        let kind: String
        let index: Int?
        let day: String?
        let revision: String
        var page = 0
        var isValid: Bool {
            guard (0...100000).contains(self.page), self.revision.utf8.count == 64,
                  self.revision.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return false }
            if self.kind == "hourly" {
                return self.index == nil && self.day?.utf8.count == 10
                    && self.day?.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil
            }
            return ["project", "session"].contains(self.kind) && self.day == nil &&
                self.index.map { (0...1000000).contains($0) } == true
        }
    }
    struct Row: Codable, Sendable {
        let title: String
        let subtitle: String
        let cost: String
        let tokens: String
        let details: String
        var selectionIndex: Int? = nil
    }
    struct Point: Codable, Sendable {
        let label: String
        let detail: String
        let value: Double?
        let level: Int
        let row: Int
        let column: Int
        var dayKey: String? = nil
    }
    struct DetailPage: Codable, Sendable {
        let kind: String
        let title: String
        let context: String
        let page: Int
        let pageCount: Int
        let totalRows: Int
        let rows: [Row]
        let points: [Point]
    }
    struct Page: Codable, Sendable {
        let days: Int
        let currencies: [String]
        let currency: String?
        let section: String
        let chart: String
        let page: Int
        let pageCount: Int
        let totalRows: Int
        let totalCost: String
        let totalTokens: String
        let context: String
        let stale: Bool
        let partial: Bool
        let truncated: Bool
        let rows: [Row]
        let points: [Point]
        let selectionRevision: String
        var detail: DetailPage? = nil
    }

    static func make(snapshot: WindowsSpendDashboardController.Snapshot, query: Query,
                     hidePersonalInfo: Bool, calendar: Calendar, selectionRevision: String,
                     hourlySnapshot: WindowsSpendDashboardController.Snapshot? = nil) -> Page {
        let model = snapshot.model
        // At most six JSON bytes per ASCII control byte; leave room for numeric/structural overhead.
        var remaining = 128 * 1024
        var truncated = false
        func text(_ raw: String, limit: Int = 512) -> String {
            let result = WindowsAppProtocol.boundedText(LogRedactor.redact(raw).replacingOccurrences(of: "\0", with: ""),
                maximumUTF8Bytes: min(limit, remaining))
            remaining -= result.text.utf8.count
            truncated = truncated || result.truncated
            return result.text
        }
        func cost(_ value: Double?, _ code: String) -> String {
            guard let value, value.isFinite else { return "Unknown" }
            return WindowsShareStatsFormatting.currency(value, code: code)
        }
        func tokens(_ value: Int?) -> String { value.map { $0.formatted() } ?? "Unknown" }
        func provider(_ value: UsageProvider, _ name: String) -> String {
            hidePersonalInfo ? ProviderDescriptorRegistry.descriptor(for: value).metadata.displayName : name
        }
        func mix(_ value: CostUsageTokenMix) -> String {
            "Input: \(tokens(value.inputTokens)) · Output: \(tokens(value.outputTokens)) · Cache read: \(tokens(value.cacheReadTokens))"
                + " · Cache write: \(tokens(value.cacheCreationTokens)) · Reasoning: \(tokens(value.reasoningTokens))"
        }
        let currencies = model.groups.prefix(256).map(\.currencyCode)
        truncated = model.groups.count > currencies.count
        let group = query.currency.flatMap { code in model.groups.first { $0.currencyCode == code && currencies.contains(code) } }
            ?? (query.currency == nil ? model.groups.first : nil)
        let totalRows: Int
        switch query.section {
        case "models": totalRows = group?.models.count ?? 0
        case "projects": totalRows = group?.projects.count ?? 0
        case "sessions": totalRows = group?.sessions.count ?? 0
        default: totalRows = group?.providers.count ?? 0
        }
        let pageCount = max(1, (totalRows + 39) / 40)
        let page = min(max(0, query.page), pageCount - 1)
        let range = (page * 40)..<min(totalRows, page * 40 + 40)
        var rows: [Row] = []
        var points: [Point] = []
        var context = ["Costs may be metered or estimated. Currency conversion can use cached or approximate rates.",
                       "Unknown values are missing coverage, not zero.",
                       "Period changes use the captured scan; they do not fetch older history.",
                       "Project and session breakdowns may not sum to the period total. Session totals may include earlier activity."]
        if snapshot.stale { context.append("Stale: some values are from a previous collection.") }
        if !snapshot.sourceFailures.isEmpty {
            let pending = snapshot.sourceFailures.filter(\.localInventoryPending).count
            context.append("Partial collection: \(pending) source(s) collecting; \(snapshot.sourceFailures.count - pending) unavailable.")
        }
        if snapshot.openCodexObservation == .unavailable { context.append("OpenCodeX logs are unavailable.") }
        if let loaded = snapshot.loadedAt {
            context.append("Collected: " + loaded.formatted(date: .abbreviated, time: .shortened))
        }
        if query.chart == "tokens" {
            context.append("Token activity covers the captured year, independent of the cost period. Rows are Monday–Sunday; columns are weeks.")
            context.append("Unscanned, scanned-unknown and confirmed-zero cells are distinct. Select a day for its exact status.")
        }
        if let group {
            context.append("Covered days: \(group.coveredDayCount) / \(model.requestedDays) · \(group.timeZone.identifier)")
            context.append(contentsOf: WindowsSpendSummary.accountingDetails(group))
            if group.modelHistoryCompleteness == .incomplete { context.append("Model history is incomplete.") }
        } else { context.append("No cost group is available for this selection.") }
        let contextText = text(context.joined(separator: "\n"), limit: 8192)
        if let group {
            for index in range {
                let title: String
                let subtitle: String
                let amount: Double?
                let count: Int?
                let details: String
                switch query.section {
                case "models":
                    let row = group.models[index]
                    title = row.modelName; subtitle = provider(row.provider, row.providerName)
                    amount = row.totalCost; count = row.totalTokens; details = mix(row.tokenMix)
                case "projects":
                    let row = group.projects[index]
                    title = hidePersonalInfo ? "Project \(index + 1)" : row.projectName
                    subtitle = provider(row.provider, row.providerName)
                    amount = row.totalCost; count = row.totalTokens
                    details = "Available daily rows: \(row.daily.count) · Models: \(row.models.count)"
                        + (row.modelHistoryCompleteness == .incomplete ? " · Incomplete model coverage" : "")
                case "sessions":
                    let row = group.sessions[index]
                    title = "Session \(index + 1)"
                    subtitle = hidePersonalInfo ? "Tracked session" : row.displayName
                    amount = row.totalCost; count = row.totalTokens
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium; formatter.timeStyle = .short; formatter.timeZone = group.timeZone
                    details = "Last activity: " + formatter.string(from: row.lastActivity)
                        + " · Requests: \(tokens(row.requestCount))\n" + mix(row.tokenMix)
                default:
                    let row = group.providers[index]
                    title = provider(row.provider, row.displayName); subtitle = "Source \(index + 1)"
                    amount = row.totalCost; count = row.totalTokens
                    details = "Covered days: \(row.coveredDayCount) / \(model.requestedDays)"
                }
                rows.append(Row(title: text(title), subtitle: text(subtitle),
                    cost: text(cost(amount, group.currencyCode)), tokens: text(tokens(count)), details: text(details, limit: 1024),
                    selectionIndex: ["projects", "sessions"].contains(query.section) ? index : nil))
            }
        }
        if query.chart == "tokens" {
            // Reuse the original activity semantics: unscanned, scanned-unknown and confirmed zero remain distinct.
            let history = WindowsSpendHistorySnapshot.tokenActivity(snapshot, calendar: calendar)
            for day in (history.series.first?.days ?? []).suffix(WindowsSpendHistoryPolicy.activityDays) {
                guard let cell = day.activity else { continue }
                points.append(.init(label: text(day.label, limit: 96), detail: text(day.details, limit: 256),
                    value: nil, level: cell.level, row: cell.row, column: cell.column))
            }
        } else if let group {
            var bucketCalendar = Calendar(identifier: .gregorian)
            bucketCalendar.timeZone = group.timeZone
            let grouped = Dictionary(grouping: group.dailyPoints) { bucketCalendar.startOfDay(for: $0.day) }
            for offset in 0..<model.requestedDays {
                guard let day = bucketCalendar.date(byAdding: .day, value: offset, to: group.chartDomain.lowerBound) else { continue }
                let samples = grouped[bucketCalendar.startOfDay(for: day)] ?? []
                let known = samples.map(\.stackEnd).filter { $0.isFinite && $0 >= 0 }.max()
                let label = WindowsShareStatsFormatting.dataThrough(day, calendar: bucketCalendar)
                let detail = known.map { "Known subtotal: " + cost($0, group.currencyCode) }
                    ?? "No known samples. This is not a confirmed zero."
                points.append(.init(label: text(label, limit: 96),
                    detail: text(label + "\n" + detail + "\nDaily bars can be incomplete.", limit: 256),
                    value: known, level: 0, row: 0, column: offset, dayKey: Self.dayKey(day, calendar: bucketCalendar)))
            }
        }
        let detail = Self.detail(snapshot: snapshot, query: query, hourlySnapshot: hourlySnapshot,
            hidePersonalInfo: hidePersonalInfo, calendar: calendar, revision: selectionRevision, text: { text($0, limit: $1) })
        let totalCost = group.map { ($0.hasPartialCost ? "~" : "") + cost($0.totalCost, $0.currencyCode) } ?? "Unknown"
        let totalTokens = group.map { ($0.hasPartialTokens ? "~" : "") + tokens($0.totalTokens) } ?? "Unknown"
        let costText = text(totalCost)
        let tokenText = text(totalTokens)
        return .init(days: model.requestedDays, currencies: Array(currencies), currency: group?.currencyCode,
            section: query.section, chart: query.chart, page: page, pageCount: pageCount, totalRows: totalRows,
            totalCost: costText, totalTokens: tokenText, context: contextText, stale: snapshot.stale,
            partial: !snapshot.sourceFailures.isEmpty || snapshot.openCodexObservation == .unavailable
                || group?.hasPartialCost == true || group?.hasPartialTokens == true,
            truncated: truncated, rows: rows, points: points, selectionRevision: selectionRevision, detail: detail)
    }

    static func dayKey(_ day: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }

    static func selectedDay(_ raw: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let day = formatter.date(from: raw), Self.dayKey(day, calendar: calendar) == raw else { return nil }
        return calendar.startOfDay(for: day)
    }
}
#endif
