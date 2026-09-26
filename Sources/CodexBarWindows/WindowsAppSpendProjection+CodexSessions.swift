#if os(Windows)
import Foundation
import CodexBarCore

extension WindowsAppSpendProjection {
    struct CodexSessionQuery: Codable, Sendable {
        let modelIndex: Int
        let period: String
        let revision: String
        var referenceIndex: Int? = nil
        var page = 0
        var isValid: Bool {
            CodexModelSelection(index: self.modelIndex, revision: self.revision).isValid
                && ["current", "previous"].contains(self.period) && (0...100000).contains(self.page)
                && (self.referenceIndex.map { (0...1000000).contains($0) } ?? true)
        }
    }

    static func acceptsCodexSessions(_ query: CodexSessionQuery?, analysis: WindowsCodexModelAnalysis.Snapshot?,
                                    revision: String) -> Bool {
        guard let query else { return true }
        guard query.isValid, query.revision == revision, let analysis,
              analysis.modelKeys.indices.contains(query.modelIndex) else { return false }
        let period = query.period == "current" ? analysis.current : analysis.previous
        let refs = Self.codexSessionReferences(period, model: analysis.modelKeys[query.modelIndex])
        guard let selected = query.referenceIndex else { return true }
        return refs.indices.contains(selected) && period.activity.sessions[refs[selected]] != nil
    }
    private static func codexSessionReferences(_ period: WindowsCodexModelAnalysis.Period,
                                               model: String) -> [WindowsCodexActivityAnalysis.Reference] {
        (period.activity.models[model]?.sessions ?? []).filter { period.activity.sessions[$0]?.models[model] != nil }.sorted {
            $0.source == $1.source ? $0.number < $1.number : $0.source < $1.source
        }
    }

    static func codexSessionsDetail(_ analysis: WindowsCodexModelAnalysis.Snapshot, query: CodexSessionQuery,
                                   revision: String, stale: Bool, hidePersonalInfo: Bool, calendar: Calendar,
                                   text: (String, Int) -> String) -> DetailPage? {
        guard Self.acceptsCodexSessions(query, analysis: analysis, revision: revision) else { return nil }
        let keys = analysis.modelKeys
        let key = keys[query.modelIndex]
        let period = query.period == "current" ? analysis.current : analysis.previous
        let refs = Self.codexSessionReferences(period, model: key)
        let complete = analysis.collectionComplete && !stale && period.tokensComplete && period.activity.complete
        let costComplete = complete && period.costComplete
        let label = Self.modelTitle(key, index: query.modelIndex, hidePersonalInfo: hidePersonalInfo)
        let prefix = query.period == "current" ? "Current" : "Previous"
        func tokens(_ value: Int?) -> String { value.map { (complete ? "" : "~") + $0.formatted() } ?? "Unknown" }
        func pricing(_ value: WindowsCodexActivityAnalysis.Model) -> WindowsCodexEffortPricing.Value {
            var result = WindowsCodexEffortPricing.Value()
            for amount in value.effortPricing.values { result.merge(amount) }
            return result
        }
        func total(_ value: WindowsCodexActivityAnalysis.Model) -> Int? {
            var result = WindowsCodexModelAnalysis.Count()
            for amount in value.effortTokens.values { result.add(amount) }
            return result.value
        }
        func cost(_ price: WindowsCodexEffortPricing.Value) -> String {
            guard let value = price.cost.value, let currency = analysis.currency else { return "Unknown" }
            return (costComplete && price.costComplete ? "" : "~") + WindowsShareStatsFormatting.currency(value, code: currency)
        }
        func efforts(_ value: WindowsCodexActivityAnalysis.Model) -> String {
            var displayed: [String: WindowsCodexModelAnalysis.Count] = [:]
            for (raw, amount) in value.effortTokens {
                displayed[WindowsCodexEffortPricing.displayLabel(raw, hidePersonalInfo: hidePersonalInfo), default: .init()].add(amount)
            }
            let prices = WindowsCodexEffortPricing.displayed(value.effortPricing, hidePersonalInfo: hidePersonalInfo)
            let ordered = displayed.keys.sorted()
            let lines = ordered.prefix(12).map { name in
                "\(name): \(tokens(displayed[name]?.value)) tokens · \(cost(prices[name] ?? .init()))"
            }
            return lines.joined(separator: "\n") + (ordered.count > 12 ? "\n\(ordered.count - 12) additional effort labels." : "")
        }
        let selected = query.referenceIndex.flatMap { period.activity.sessions[refs[$0]] }
        let models = selected?.models.keys.sorted() ?? []
        let totalRows = selected == nil ? refs.count : models.count
        let pageCount = max(1, (totalRows + 39) / 40)
        let page = min(query.page, pageCount - 1)
        var rows: [Row] = []
        var points: [Point] = []
        for index in (page * 40)..<min(totalRows, page * 40 + 40) {
            if let selected {
                let name = models[index]
                guard let value = selected.models[name], let globalIndex = keys.firstIndex(of: name) else { continue }
                rows.append(.init(title: text(Self.modelTitle(name, index: globalIndex, hidePersonalInfo: hidePersonalInfo), 512),
                    subtitle: "Recorded in this session and period", cost: text(cost(pricing(value)), 128),
                    tokens: text(tokens(total(value)), 128), details: text(efforts(value), 1536)))
            } else {
                guard let session = period.activity.sessions[refs[index]], let value = session.models[key] else { continue }
                rows.append(.init(title: "Session reference \(index + 1)", subtitle: text(label, 512),
                    cost: text(cost(pricing(value)), 128), tokens: text(tokens(total(value)), 128),
                    details: text("Selected-model usage only. \(session.models.count) recorded model(s) in this session during the period.\n"
                        + efforts(value), 1536), selectionIndex: index))
            }
        }
        if let selected, period.boundaryAligned {
            var day = period.interval.start
            while day < period.interval.end && points.count < WindowsSpendHistoryPolicy.scanDays {
                guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
                let key = Self.dayKey(day, calendar: calendar)
                let models = selected.byDay[key] ?? [:]
                var count = WindowsCodexModelAnalysis.Count()
                var price = WindowsCodexEffortPricing.Value()
                for model in models.values {
                    count.add(total(model)); price.merge(pricing(model))
                }
                let known = count.value ?? (models.isEmpty && complete ? 0 : nil)
                points.append(.init(label: key, detail: text(key + "\nAll recorded models in this session: "
                    + tokens(known) + " tokens · " + cost(price), 512),
                    value: known.map { Double($0) }, level: 0, row: 0, column: points.count, dayKey: key))
                day = next
            }
        }
        let dates = DateFormatter()
        dates.locale = Locale(identifier: "en_US_POSIX"); dates.calendar = calendar
        dates.timeZone = calendar.timeZone; dates.dateFormat = "yyyy-MM-dd HH:mm XXX"
        let range = dates.string(from: period.interval.start) + " ≤ time < " + dates.string(from: period.interval.end)
        var context = [
            "\(prefix) period · \(range) · \(calendar.timeZone.identifier)",
            "Native Codex recorded activity only. Values cover this period, not the full lifetime of a session.",
            selected == nil ? "Rows show \(label) usage. Open a reference to see its other recorded models."
                : "Rows and the daily token chart show all recorded models in this session during the period.",
            "References are local to the captured report and included source. Missing session identity cannot be linked; reference totals may differ from total model usage.",
            "Costs use reconciled event pricing and the selected currency. Missing values are Unknown; ~ marks incomplete known values.",
        ]
        if !complete || period.activity.models[key]?.sessionsComplete == false {
            context.append("The session list or its usage evidence is incomplete. Unlisted activity is not a confirmed zero.")
        }
        let title = query.referenceIndex.map { "\(prefix) session reference \($0 + 1) · \(label)" }
            ?? "\(prefix) session references · \(label)"
        return .init(kind: selected == nil ? "codexSessions" : "codexSession",
            title: text(title, 512), context: text(context.joined(separator: "\n"), 4096),
            page: page, pageCount: pageCount, totalRows: totalRows, rows: rows, points: points)
    }
}
#endif
