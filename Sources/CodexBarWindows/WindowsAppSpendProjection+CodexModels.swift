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
    }
    struct CodexModelsPage: Codable, Sendable {
        let context: String
        let currentRange: String
        let previousRange: String
        let page: Int
        let pageCount: Int
        let totalRows: Int
        let rows: [CodexModelRow]
    }

    /// Shares the enclosing response's text budget; IDs, account labels and raw sessions stay local.
    static func codexModels(_ value: WindowsCodexModelAnalysis.Snapshot, page requestedPage: Int,
                            hidePersonalInfo: Bool, stale: Bool, calendar: Calendar,
                            text: (String, Int) -> String) -> CodexModelsPage {
        let collected = value.collectionComplete && !stale
        let currentTokensComplete = collected && value.current.tokensComplete
        let previousTokensComplete = collected && value.previous.tokensComplete
        let currentCostComplete = collected && value.current.costComplete
        let previousCostComplete = collected && value.previous.costComplete
        let keys = Set(value.current.models.keys).union(value.previous.models.keys).sorted()
        let pages = max(1, (keys.count + 39) / 40)
        let page = min(max(0, requestedPage), pages - 1)
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
        var rows: [CodexModelRow] = []
        for index in (page * 40)..<min(keys.count, page * 40 + 40) {
            let key = keys[index]
            let current = value.current.models[key]
            let previous = value.previous.models[key]
            // Absence is a zero only when every included source has complete model coverage.
            let ct = current?.tokens.value ?? (current == nil && currentTokensComplete ? 0 : nil)
            let pt = previous?.tokens.value ?? (previous == nil && previousTokensComplete ? 0 : nil)
            let cc = current?.cost.value ?? (current == nil && currentCostComplete ? 0 : nil)
            let pc = previous?.cost.value ?? (previous == nil && previousCostComplete ? 0 : nil)
            let label = Self.modelTitle(key, index: index, hidePersonalInfo: hidePersonalInfo)
            func component(_ count: WindowsCodexModelAnalysis.Count?) -> String {
                tokens(count?.value, complete: currentTokensComplete && count?.complete == true)
            }
            let details = tier("Current", current, tokensComplete: currentTokensComplete, costComplete: currentCostComplete)
                + "\n" + tier("Previous", previous, tokensComplete: previousTokensComplete, costComplete: previousCostComplete)
                + "\nCurrent token mix — Input: \(component(current?.input)) · Output: \(component(current?.output))"
                + " · Cache read: \(component(current?.cached)) · Cache write: \(component(current?.cacheCreation))"
                + " · Reasoning: \(component(current?.reasoning))"
            rows.append(.init(title: text(label, 512),
                currentTokens: text(tokens(ct, complete: currentTokensComplete), 128),
                previousTokens: text(tokens(pt, complete: previousTokensComplete), 128),
                tokenChange: text(change(ct.map { Double($0) }, pt.map { Double($0) },
                    complete: currentTokensComplete && previousTokensComplete), 128),
                currentCost: text(cost(cc, complete: currentCostComplete), 128),
                previousCost: text(cost(pc, complete: previousCostComplete), 128),
                costChange: text(change(cc, pc, complete: currentCostComplete && previousCostComplete), 128),
                details: text(details, 1536)))
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
            "Service tiers require recorded standard/priority totals. Historical effort and session-reference analytics are not yet available."
        ]
        if value.sourceCount == 0 { context.append("No included native Codex source is available for this currency.") }
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
            page: page, pageCount: pages, totalRows: keys.count, rows: rows)
    }
}
#endif
