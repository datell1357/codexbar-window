#if os(Windows)
import Foundation
import CodexBarCore

extension WindowsAppSpendProjection {
    struct CodexModelSelection: Codable, Sendable {
        let index: Int
        let revision: String
        var isValid: Bool {
            (0...1_000_000).contains(self.index) && self.revision.utf8.count == 64
                && self.revision.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        }
    }
    static func acceptsCodexModel(_ selection: CodexModelSelection?, analysis: WindowsCodexModelAnalysis.Snapshot?,
                                 revision: String) -> Bool {
        guard let selection else { return true }
        guard selection.isValid, selection.revision == revision, let analysis else { return false }
        return analysis.modelKeys.indices.contains(selection.index)
    }
    static func codexTimeline(_ value: WindowsCodexModelAnalysis.Snapshot, model: String?,
                             granularity: String, metric: String, stale: Bool, calendar: Calendar,
                             text: (String, Int) -> String) -> [Point] {
        let samples = WindowsCodexModelTimeline.build(value, model: model, granularity: granularity, calendar: calendar)
        let collected = value.collectionComplete && !stale
        func count(_ value: Int?, _ complete: Bool) -> String {
            value.map { (collected && complete ? "" : "~") + $0.formatted() } ?? "Unknown"
        }
        func cost(_ amount: Double?, _ complete: Bool) -> String {
            guard let amount, let currency = value.currency else { return "Unknown" }
            return (collected && complete ? "" : "~") + WindowsShareStatsFormatting.currency(amount, code: currency)
        }
        return samples.enumerated().map { index, sample in
            let first = Self.dayKey(sample.interval.start, calendar: calendar)
            let last = Self.dayKey(sample.interval.end.addingTimeInterval(-1), calendar: calendar)
            let label = first == last ? first : first + " – " + last
            let amount: Double? = metric == "cost" ? sample.cost
                : metric == "sessionReferences" ? sample.sessionReferences.map(Double.init) : sample.tokens.map(Double.init)
            let detail = label + (sample.clipped ? " · clipped \(granularity) interval" : "")
                + "\nTokens: \(count(sample.tokens, sample.tokensComplete))"
                + " · Cost: \(cost(sample.cost, sample.costComplete))"
                + "\nSession refs: \(count(sample.sessionReferences, sample.sessionsComplete))"
            return Point(label: text(label, 64), detail: text(detail, 384), value: amount,
                level: 0, row: 0, column: index, dayKey: first)
        }
    }
}
#endif
