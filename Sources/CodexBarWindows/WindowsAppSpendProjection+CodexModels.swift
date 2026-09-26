#if os(Windows)
import Foundation
import CodexBarCore

extension WindowsAppSpendProjection {
    struct CodexModelRow: Codable, Sendable {
        let title: String
        let currentTokens: String
        let previousTokens: String
        let tokenChange: String
        let currentCost: String
        let previousCost: String
        let costChange: String
        let details: String
        var selectionIndex: Int = 0
    }
    struct CodexModelChoice: Codable, Sendable {
        let title: String
        let index: Int
        let selected: Bool
    }
    struct CodexModelsPage: Codable, Sendable {
        let context: String
        let currentRange: String
        let previousRange: String
        let page: Int
        let pageCount: Int
        let totalRows: Int
        let rows: [CodexModelRow]
        var selectionRevision: String = ""
        var selectedIndex: Int? = nil
        var selectedLabel: String = "All models"
        var granularity: String = "daily"
        var metric: String = "tokens"
        var timelineContext: String = ""
        var timeline: [Point] = []
        var modelSelection: CodexModelSelection? = nil
        var catalogPage: Int = 0
        var catalogPageCount: Int = 1
        var catalogTotal: Int = 0
        var choices: [CodexModelChoice] = []
    }

    /// Shares the enclosing response's text budget; IDs, account labels and raw sessions stay local.
    static func codexModels(_ value: WindowsCodexModelAnalysis.Snapshot, page requestedPage: Int,
                            hidePersonalInfo: Bool, stale: Bool, calendar: Calendar,
                            text: (String, Int) -> String,
                            selectionRevision: String = "", selection: CodexModelSelection? = nil,
                            granularity: String = "daily", metric: String = "tokens",
                            catalogPage requestedCatalogPage: Int = 0) -> CodexModelsPage {
        let collected = value.collectionComplete && !stale
        let currentTokensComplete = collected && value.current.tokensComplete
        let previousTokensComplete = collected && value.previous.tokensComplete
        let currentCostComplete = collected && value.current.costComplete
        let previousCostComplete = collected && value.previous.costComplete
        let allKeys = value.modelKeys
        let selectionValid = Self.acceptsCodexModel(selection, analysis: value, revision: selectionRevision)
        let indices = selectionValid ? selection?.resolvedIndices(count: allKeys.count) ?? Array(allKeys.indices) : []
        let keys = indices.map { allKeys[$0] }
        let selectedIndices = Set(indices)
        let catalogPages = max(1, (allKeys.count + 39) / 40)
        let catalogPage = min(max(0, requestedCatalogPage), catalogPages - 1)
        let choices = ((catalogPage * 40)..<min(allKeys.count, catalogPage * 40 + 40)).map { index in
            CodexModelChoice(title: text(Self.modelTitle(allKeys[index], index: index, hidePersonalInfo: hidePersonalInfo), 512),
                index: index, selected: selectedIndices.contains(index))
        }
        let pages = max(1, (keys.count + 39) / 40)
        let page = min(max(0, requestedPage), pages - 1)
        let selectedLabel: String
        if selection == nil { selectedLabel = "All models" }
        else if let index = indices.first, indices.count == 1 {
            selectedLabel = Self.modelTitle(allKeys[index], index: index, hidePersonalInfo: hidePersonalInfo)
        } else { selectedLabel = indices.isEmpty ? "No models selected" : "\(indices.count) models selected" }
        let timeline = selectionValid ? Self.codexTimeline(value, models: selection == nil ? nil : Set(keys), granularity: granularity,
            metric: metric, stale: stale, calendar: calendar, text: text) : []
        func tokens(_ count: Int?, complete: Bool) -> String {
            guard let count, count >= 0 else { return "Unknown" }
            return (complete ? "" : "~") + count.formatted()
        }
        func cost(_ amount: Double?, complete: Bool) -> String {
            guard let amount, amount.isFinite, amount >= 0, let code = value.currency else { return "Unknown" }
            return (complete ? "" : "~") + WindowsShareStatsFormatting.currency(amount, code: code)
        }
        func change(_ current: Double?, _ previous: Double?, complete: Bool) -> String {
            guard complete, let current, let previous else { return "Unavailable" }
            switch CodexModelsComparison.make(current: current, previous: previous) {
            case .unavailable: return "Unavailable"
            case .new: return "New"
            case .ended: return "Ended"
            case .unchanged: return "Unchanged"
            case let .percent(fraction):
                let percent = fraction * 100
                guard percent.isFinite else { return "Unavailable" }
                return (percent > 0 ? "+" : "") + percent.formatted(.number.precision(.fractionLength(1))) + "%"
            }
        }
        func tier(_ name: String, _ row: WindowsCodexModelAnalysis.Totals?,
                  tokensComplete: Bool, costComplete: Bool) -> String {
            let standardTokens = tokens(row?.standardTokens.value, complete: tokensComplete && row?.standardTokens.complete == true)
            let priorityTokens = tokens(row?.priorityTokens.value, complete: tokensComplete && row?.priorityTokens.complete == true)
            let standardCost = cost(row?.standardCost.value, complete: costComplete && row?.standardCost.complete == true)
            let priorityCost = cost(row?.priorityCost.value, complete: costComplete && row?.priorityCost.complete == true)
            return "\(name) standard: \(standardTokens) tokens · \(standardCost)"
                + "\n\(name) priority: \(priorityTokens) tokens · \(priorityCost)"
        }
        func activityComplete(_ period: WindowsCodexModelAnalysis.Period) -> Bool {
            collected && period.tokensComplete && period.activity.complete
        }
        func sessions(_ model: String, _ period: WindowsCodexModelAnalysis.Period) -> (Int?, Bool) {
            guard let value = period.activity.models[model] else {
                return activityComplete(period) ? (0, true) : (nil, false)
            }
            let known = value.sessions.isEmpty && !value.sessionsComplete ? nil : value.sessions.count
            return (known, activityComplete(period) && value.sessionsComplete)
        }
        func efforts(_ name: String, _ model: String, _ period: WindowsCodexModelAnalysis.Period) -> String {
            guard let value = period.activity.models[model] else {
                return "\(name) recorded effort: " + (activityComplete(period) ? "No usage" : "Unknown")
            }
            let publicLabels: Set<String> = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra", "persistent"]
            var displayed: [String: Int] = [:]
            for (label, count) in value.effortTokens {
                let title = label.isEmpty ? "Unrecorded" : hidePersonalInfo && !publicLabels.contains(label) ? "Custom" : label
                let sum = (displayed[title] ?? 0).addingReportingOverflow(count)
                guard !sum.overflow else { return "\(name) recorded effort: Unknown" }
                displayed[title] = sum.partialValue
            }
            let sorted = displayed.sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key < $1.key
            }
            let rows = sorted.prefix(12).map { label, count in
                "\(label): \(tokens(count, complete: activityComplete(period)))"
            }
            let more = sorted.count > 12 ? " · \(sorted.count - 12) additional effort labels" : ""
            return "\(name) recorded effort tokens — " + rows.joined(separator: " · ") + more
        }
        var rows: [CodexModelRow] = []
        for index in (page * 40)..<min(keys.count, page * 40 + 40) {
            let key = keys[index]
            let originalIndex = indices[index]
            let current = value.current.models[key]
            let previous = value.previous.models[key]
            // Absence is a zero only when every included source has complete model coverage.
            let ct = current?.tokens.value ?? (current == nil && currentTokensComplete ? 0 : nil)
            let pt = previous?.tokens.value ?? (previous == nil && previousTokensComplete ? 0 : nil)
            let cc = current?.cost.value ?? (current == nil && currentCostComplete ? 0 : nil)
            let pc = previous?.cost.value ?? (previous == nil && previousCostComplete ? 0 : nil)
            let label = Self.modelTitle(key, index: originalIndex, hidePersonalInfo: hidePersonalInfo)
            func component(_ count: WindowsCodexModelAnalysis.Count?) -> String {
                tokens(count?.value, complete: currentTokensComplete && count?.complete == true)
            }
            let cs = sessions(key, value.current), ps = sessions(key, value.previous)
            let details = tier("Current", current, tokensComplete: currentTokensComplete, costComplete: currentCostComplete)
                + "\n" + tier("Previous", previous, tokensComplete: previousTokensComplete, costComplete: previousCostComplete)
                + "\nCurrent token mix — Input: \(component(current?.input)) · Output: \(component(current?.output))"
                + " · Cache read: \(component(current?.cached)) · Cache write: \(component(current?.cacheCreation))"
                + " · Reasoning: \(component(current?.reasoning))"
                + "\nSession refs — Current: \(tokens(cs.0, complete: cs.1))"
                + " · Previous: \(tokens(ps.0, complete: ps.1))"
                + " · Change: \(change(cs.0.map { Double($0) }, ps.0.map { Double($0) }, complete: cs.1 && ps.1))"
                + "\n" + efforts("Current", key, value.current)
                + "\n" + efforts("Previous", key, value.previous)
            rows.append(.init(title: text(label, 512),
                currentTokens: text(tokens(ct, complete: currentTokensComplete), 128),
                previousTokens: text(tokens(pt, complete: previousTokensComplete), 128),
                tokenChange: text(change(ct.map { Double($0) }, pt.map { Double($0) },
                    complete: currentTokensComplete && previousTokensComplete), 128),
                currentCost: text(cost(cc, complete: currentCostComplete), 128),
                previousCost: text(cost(pc, complete: previousCostComplete), 128),
                costChange: text(change(cc, pc, complete: currentCostComplete && previousCostComplete), 128),
                details: text(details, 3072), selectionIndex: originalIndex))
        }
        var context = [
            "Native Codex models only, within the selected currency and included sources. Other providers and OpenCodeX are excluded.",
            "Current and previous periods are adjacent and have equal elapsed duration. The current period ends on the collection date.",
            "Full-period source coverage — Current: \(value.current.fullSources) / \(value.sourceCount)"
                + " · Previous: \(value.previous.fullSources) / \(value.sourceCount)",
            "Known model totals — Current: \(tokens(value.current.tokens.value, complete: currentTokensComplete)) tokens"
                + " · \(cost(value.current.cost.value, complete: currentCostComplete))"
                + "\nPrevious: \(tokens(value.previous.tokens.value, complete: previousTokensComplete)) tokens"
                + " · \(cost(value.previous.cost.value, complete: previousCostComplete))",
            "Costs are local estimates, not a bill. Conversion may use cached or approximate exchange rates.",
            "~ marks incomplete known data. Unknown is not zero; changes require complete model totals in both periods.",
            "Service tiers require recorded standard/priority totals. Effort shows tokens attributed to a recorded rollout context, not verified server settings; Unrecorded differs from none.",
            "Session refs count distinct local sessions per model and source across the period. One session can occur under several models; these are not request counts.",
            "Legacy or bounded event evidence may be unavailable. Effort and session refs require agreement with the same daily model totals. Detailed session navigation and effort cost allocation are not included."
        ]
        if value.sourceCount == 0 { context.append("No included native Codex source is available for this currency.") }
        if !selectionValid { context.append("The model selection changed. Select a model from the current collection.") }
        if !collected { context.append("Collection is stale or incomplete; period changes are unavailable.") }
        if !value.current.boundaryAligned || !value.previous.boundaryAligned {
            context.append("A time-zone offset change cuts through a daily bucket. Only whole-day subtotals are shown; period changes are unavailable.")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm XXX"
        func range(_ interval: DateInterval) -> String {
            formatter.string(from: interval.start) + " ≤ time < " + formatter.string(from: interval.end)
                + " · " + calendar.timeZone.identifier
        }
        return .init(context: text(context.joined(separator: "\n"), 4096),
            currentRange: text(range(value.current.interval), 256), previousRange: text(range(value.previous.interval), 256),
            page: page, pageCount: pages, totalRows: keys.count, rows: rows,
            selectionRevision: selectionRevision,
            selectedIndex: selection != nil && indices.count == 1 ? indices.first : nil,
            selectedLabel: text(selectionValid ? selectedLabel : "Selection changed", 512),
            granularity: granularity, metric: metric,
            timelineContext: text("Current-period timeline for \(selectionValid ? selectedLabel : "an unavailable selection"). Weeks start Monday in \(calendar.timeZone.identifier). Edge weeks/months are clipped to the selected period. Session refs deduplicate within each model and interval; adding intervals can count the same session again. ~ marks incomplete known data; Unknown is not zero. Cost bars use the selected currency. The coverage and total summary above describes all included native Codex models.", 1536),
            timeline: timeline, modelSelection: selectionValid ? selection : nil,
            catalogPage: catalogPage, catalogPageCount: catalogPages, catalogTotal: allKeys.count, choices: choices)
    }
}
#endif
