#if os(Windows)
import Foundation
import CodexBarCore

extension WindowsAppSpendProjection {
    struct CodexModelSelection: Codable, Sendable {
        let indices: [Int]
        let revision: String
        let mode: String
        var index: Int? { self.mode == "include" && self.indices.count == 1 ? self.indices.first : nil }
        init(index: Int, revision: String) { self.init(indices: [index], revision: revision) }
        init(indices: [Int], revision: String, mode: String = "include") {
            self.indices = indices
            self.revision = revision
            self.mode = mode
        }
        private enum CodingKeys: String, CodingKey { case index, indices, revision, mode }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            guard !(values.contains(.index) && values.contains(.indices)) else {
                throw DecodingError.dataCorruptedError(forKey: .indices, in: values, debugDescription: "Ambiguous model selection.")
            }
            if let indices = try values.decodeIfPresent([Int].self, forKey: .indices) { self.indices = indices }
            else { self.indices = [try values.decode(Int.self, forKey: .index)] }
            self.revision = try values.decode(String.self, forKey: .revision)
            self.mode = try values.decodeIfPresent(String.self, forKey: .mode) ?? "include"
        }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(self.indices, forKey: .indices)
            try values.encode(self.revision, forKey: .revision)
            try values.encode(self.mode, forKey: .mode)
        }
        var isValid: Bool {
            self.indices.count <= 256 && self.indices == self.indices.sorted()
                && Set(self.indices).count == self.indices.count
                && self.indices.allSatisfy({ (0...1_000_000).contains($0) })
                && ["include", "exclude"].contains(self.mode) && self.revision.utf8.count == 64
                && self.revision.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        }
        func resolvedIndices(count: Int) -> [Int] {
            if self.mode == "include" { return self.indices }
            let excluded = Set(self.indices)
            return (0..<count).filter { !excluded.contains($0) }
        }
    }
    static func acceptsCodexModel(_ selection: CodexModelSelection?, analysis: WindowsCodexModelAnalysis.Snapshot?,
                                 revision: String) -> Bool {
        guard let selection else { return true }
        guard selection.isValid, selection.revision == revision, let analysis else { return false }
        let count = analysis.modelKeys.count
        return selection.indices.allSatisfy { $0 < count }
    }
    static func codexTimeline(_ value: WindowsCodexModelAnalysis.Snapshot, model: String?,
                             granularity: String, metric: String, stale: Bool, calendar: Calendar,
                             text: (String, Int) -> String) -> [Point] {
        Self.codexTimeline(value, models: model.map { Set([$0]) }, granularity: granularity,
            metric: metric, stale: stale, calendar: calendar, text: text)
    }
    static func codexTimeline(_ value: WindowsCodexModelAnalysis.Snapshot, models: Set<String>?,
                             granularity: String, metric: String, stale: Bool, calendar: Calendar,
                             text: (String, Int) -> String) -> [Point] {
        let samples = WindowsCodexModelTimeline.build(value, models: models, granularity: granularity, calendar: calendar)
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
