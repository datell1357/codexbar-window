#if os(Windows)
import Foundation
import CodexBarCore

extension WindowsAppSpendProjection {
    static func acceptsDetail(_ query: Query, snapshot: WindowsSpendDashboardController.Snapshot,
                              calendar: Calendar, revision: String) -> Bool {
        guard query.isValid else { return false }
        guard let detail = query.detail else { return true }
        guard detail.revision == revision,
              let group = query.currency.flatMap({ code in snapshot.model.groups.prefix(256).first { $0.currencyCode == code } }) else { return false }
        switch detail.kind {
        case "project": return query.section == "projects" && detail.index.map { group.projects.indices.contains($0) } == true
        case "session": return query.section == "sessions" && detail.index.map { group.sessions.indices.contains($0) } == true
        case "hourly":
            guard query.chart == "cost", let raw = detail.day, let day = Self.selectedDay(raw, calendar: calendar) else { return false }
            return day >= group.chartDomain.lowerBound && day < group.chartDomain.upperBound
        default: return false
        }
    }

    static func detail(snapshot: WindowsSpendDashboardController.Snapshot, query: Query,
                       hourlySnapshot: WindowsSpendDashboardController.Snapshot?, hidePersonalInfo: Bool,
                       calendar: Calendar, revision: String, text: (String, Int) -> String) -> DetailPage? {
        guard let selection = query.detail, Self.acceptsDetail(query, snapshot: snapshot, calendar: calendar, revision: revision),
              let group = snapshot.model.groups.first(where: { $0.currencyCode == query.currency }) else { return nil }
        func cost(_ value: Double?) -> String {
            guard let value, value.isFinite, value >= 0 else { return "Unknown" }
            return WindowsShareStatsFormatting.currency(value, code: group.currencyCode)
        }
        func tokens(_ value: Int?) -> String { value.map { $0.formatted() } ?? "Unknown" }
        func mix(_ value: CostUsageTokenMix) -> String {
            "Input: \(tokens(value.inputTokens)) · Output: \(tokens(value.outputTokens)) · Cache read: \(tokens(value.cacheReadTokens))"
                + " · Cache write: \(tokens(value.cacheCreationTokens)) · Reasoning: \(tokens(value.reasoningTokens))"
        }
        let title: String
        var context: [String] = ["Currency: \(group.currencyCode) · \(group.timeZone.identifier)",
                                 "Missing values are unknown. Model rows and daily/hourly subtotals can be incomplete."]
        let models: [WindowsSpendDashboardModel.ModelRow]
        var projectDays: [WindowsSpendDashboardModel.ProjectDayRow] = []
        var hourlyRows: [WindowsSpendDashboardModel.HourlyPoint] = []
        var points: [Point] = []
        if selection.kind == "project", let index = selection.index {
            let project = group.projects[index]
            title = hidePersonalInfo ? "Project \(index + 1)" : project.projectName
            models = project.models
            projectDays = project.daily
            context.append("Period cost: \(cost(project.totalCost)) · Tokens: \(tokens(project.totalTokens))")
            if project.modelHistoryCompleteness == .incomplete { context.append("Project model history is incomplete.") }
        } else if selection.kind == "session", let index = selection.index {
            let session = group.sessions[index]
            title = "Session \(index + 1)" + (hidePersonalInfo ? "" : " · " + session.displayName)
            models = session.models
            context.append("Session cost: \(cost(session.totalCost)) · Tokens: \(tokens(session.totalTokens))")
            context.append("Session totals may include activity before the selected period. Requests: \(tokens(session.requestCount))")
            context.append(mix(session.tokenMix))
        } else if let raw = selection.day, let day = Self.selectedDay(raw, calendar: calendar),
                  let hourlySnapshot, hourlySnapshot.publicationSequence == snapshot.publicationSequence,
                  hourlySnapshot.model.requestedDays == snapshot.model.requestedDays,
                  let hourlyGroup = hourlySnapshot.model.groups.first(where: { $0.currencyCode == group.currencyCode }),
                  hourlyGroup.selectedDay == day, hourlyGroup.timeZone == group.timeZone {
            title = "Hourly cost · " + raw
            models = []
            hourlyRows = hourlyGroup.hourlyPoints.filter { calendar.isDate($0.hour, inSameDayAs: day) }.sorted {
                $0.hour == $1.hour ? $0.sourceID < $1.sourceID : $0.hour < $1.hour
            }
            let series = WindowsSpendHistorySnapshot.hourly(hourlySnapshot, day: day).series.first { $0.code == group.currencyCode }
            for (index, hour) in (series?.days ?? []).enumerated() {
                let known = hour.segments.map(\.end).filter { $0.isFinite && $0 >= 0 }.max()
                let detail = known.map { "Known subtotal: " + cost($0) } ?? "No known hourly sample; not a confirmed zero."
                points.append(.init(label: text(hour.label, 96), detail: text(hour.label + "\n" + detail, 256),
                    value: known, level: 0, row: 0, column: index))
            }
            context.append("Local-hour buckets use UTC offsets to distinguish repeated clock hours. Missing hours are not zero.")
            context.append("Hourly samples may not explain the entire daily cost.")
        } else { return nil }
        if snapshot.stale { context.append("Stale collection: values may belong to the previous successful collection.") }
        if !snapshot.sourceFailures.isEmpty { context.append("Partial collection: pending/failed sources may be absent.") }
        if snapshot.openCodexObservation == .unavailable { context.append("OpenCodeX logs are unavailable.") }
        let totalRows = selection.kind == "hourly" ? hourlyRows.count : models.count
        let pageCount = max(1, (totalRows + 39) / 40)
        let page = min(selection.page, pageCount - 1)
        var rows: [Row] = []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = calendar
        formatter.timeZone = group.timeZone; formatter.dateFormat = "HH:mm XXX"
        for index in (page * 40)..<min(totalRows, page * 40 + 40) {
            if selection.kind == "hourly" {
                let row = hourlyRows[index]
                let name = hidePersonalInfo ? ProviderDescriptorRegistry.descriptor(for: row.provider).metadata.displayName : row.providerName
                rows.append(.init(title: text(name, 512), subtitle: text(formatter.string(from: row.hour), 96),
                    cost: text(cost(row.cost), 128), tokens: "Unknown", details: "Known source contribution in this local-hour bucket."))
            } else {
                let row = models[index]
                let name = hidePersonalInfo ? ProviderDescriptorRegistry.descriptor(for: row.provider).metadata.displayName : row.providerName
                rows.append(.init(title: text(Self.modelTitle(row.modelName, index: index, hidePersonalInfo: hidePersonalInfo), 512),
                    subtitle: text(name, 512),
                    cost: text(cost(row.totalCost), 128), tokens: text(tokens(row.totalTokens), 128), details: text(mix(row.tokenMix), 1024)))
            }
        }
        if selection.kind == "project" {
            var bucketCalendar = Calendar(identifier: .gregorian)
            bucketCalendar.timeZone = group.timeZone
            let daily = Dictionary(grouping: projectDays) { bucketCalendar.startOfDay(for: $0.day) }
            for offset in 0..<snapshot.model.requestedDays {
                guard let day = bucketCalendar.date(byAdding: .day, value: offset, to: group.chartDomain.lowerBound) else { continue }
                // A duplicate day is ambiguous, rather than a reason to invent another sum.
                let available = daily[bucketCalendar.startOfDay(for: day)] ?? []
                let row = available.count == 1 ? available.first : nil
                let label = Self.dayKey(day, calendar: bucketCalendar)
                let value: Double?
                if let amount = row?.totalCost, amount.isFinite, amount >= 0 { value = amount }
                else { value = nil }
                let detail = row.map { "Cost: \(cost($0.totalCost)) · Tokens: \(tokens($0.totalTokens))" }
                    ?? "No unambiguous project sample. This is not a confirmed zero."
                points.append(.init(label: text(label, 96), detail: text(label + "\n" + detail, 256),
                    value: value, level: 0, row: 0, column: offset))
            }
        }
        return .init(kind: selection.kind, title: text(title, 512), context: text(context.joined(separator: "\n"), 4096),
            page: page, pageCount: pageCount, totalRows: totalRows, rows: rows, points: points)
    }
}
#endif
