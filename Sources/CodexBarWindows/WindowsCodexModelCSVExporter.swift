#if os(Windows)
import Foundation
import CodexBarCore

/// A versioned, long-form export of captured native Codex analysis. No source reads or UI text scraping.
enum WindowsCodexModelCSVExporter {
    enum Failure: Error, Equatable { case unavailable, tooLarge }
    static let maximumBytes = 16 * 1024 * 1024
    static let maximumRows = 100_000
    static let header = [
        "schema_version", "scope", "record_kind", "period", "interval_start", "interval_end_exclusive",
        "timezone", "currency", "model_index", "model", "dimension", "metric", "value", "value_status",
        "comparison_state", "selected_metric", "granularity", "selected_model_count", "selection_mode", "catalog_model_count", "collection_status",
        "covered_sources", "included_sources", "boundary_aligned", "notes",
    ]

    static func make(analysis: WindowsCodexModelAnalysis.Snapshot?, query: WindowsAppSpendProjection.Query,
                     selectionRevision: String, stale: Bool, hidePersonalInfo: Bool, calendar: Calendar,
                     copy: Bool) -> WindowsUsageRuntime.ShareStatsCopyResult {
        guard let analysis else { return .unavailable("Native Codex model analysis is unavailable. Reload costs.") }
        do {
            let data = try Self.encodedData(analysis: analysis, query: query, selectionRevision: selectionRevision,
                stale: stale, hidePersonalInfo: hidePersonalInfo, calendar: calendar)
            if copy, String(decoding: data, as: UTF8.self).utf16.count > 65536 {
                return .unavailable("The model CSV is too large for the clipboard. Use Save model CSV.")
            }
            return .csv(data, filename: "codexbar-models-last-\(query.days)-days-\(analysis.currency ?? "unknown").csv", copy: copy)
        } catch Failure.tooLarge {
            return .unavailable("The complete model CSV exceeds its export limits. Select fewer models or a shorter period; no partial file was produced.")
        } catch {
            return .unavailable("The model selection or analysis is unavailable. Reload costs before exporting.")
        }
    }

    static func encodedData(analysis: WindowsCodexModelAnalysis.Snapshot, query: WindowsAppSpendProjection.Query,
                            selectionRevision: String, stale: Bool, hidePersonalInfo: Bool, calendar: Calendar,
                            maximumBytes: Int = Self.maximumBytes) throws -> Data {
        guard query.isValid, query.codexModelsPage != nil, query.currency == analysis.currency,
              let currency = analysis.currency, query.detail == nil, query.comparePeriods != true,
              calendar.date(byAdding: .day, value: -query.days, to: analysis.current.interval.end) == analysis.current.interval.start,
              WindowsAppSpendProjection.acceptsCodexModel(query.codexModel, analysis: analysis, revision: selectionRevision)
        else { throw Failure.unavailable }
        let keys = analysis.modelKeys
        let indices = query.codexModel?.resolvedIndices(count: keys.count) ?? Array(keys.indices)
        let metric = query.codexMetric ?? "tokens"
        let granularity = query.codexGranularity ?? "daily"
        let collected = analysis.collectionComplete && !stale
        let collectionStatus = stale ? "stale" : analysis.collectionComplete ? "complete" : "partial"
        let dates = ISO8601DateFormatter() // UTC instants; the separate timezone identifies bucket boundaries.
        var writer = Writer(limit: min(max(0, maximumBytes), Self.maximumBytes))
        try writer.append(Self.header)

        func record(_ kind: String, period name: String, value: WindowsCodexModelAnalysis.Period,
                    interval: DateInterval? = nil, index: Int? = nil, dimension: String = "",
                    metric: String = "", number: String? = nil, complete: Bool = false,
                    comparison: String = "", notes: String = "") throws {
            let range = interval ?? value.interval
            let label = index.map { WindowsAppSpendProjection.modelTitle(keys[$0], index: $0, hidePersonalInfo: hidePersonalInfo) } ?? ""
            let status = number == nil ? "unknown" : complete ? "complete" : "partial"
            try writer.append(["1", "native_codex_selected_models", kind, name,
                dates.string(from: range.start), dates.string(from: range.end), calendar.timeZone.identifier,
                currency, index.map(String.init) ?? "", label, dimension, metric, number ?? "", status, comparison,
                query.codexMetric ?? "tokens", granularity, String(indices.count), query.codexModel?.mode ?? "all",
                String(keys.count), collectionStatus,
                String(value.fullSources), String(analysis.sourceCount), String(value.boundaryAligned), notes])
        }
        let scopeNotes = "Only the selected native Codex models and included sources in this currency are exported. "
            + "Coverage counts describe all included native Codex sources, not just selected models. "
            + "Intervals are start-inclusive/end-exclusive. Numeric values are invariant decimal strings; blank means unknown. "
            + "Model, component, tier, effort and timeline records overlap and must not be added together. "
            + "Costs are local estimates, not bills; currency conversion may use cached or approximate rates. "
            + "Session references deduplicate per model/source/interval, not across models or intervals. "
            + "Effort is recorded context, not proof of server-applied effort; effort costs and raw session navigation are unavailable. "
            + "Text is redacted and spreadsheet formula prefixes are escaped. This Windows schema differs from the original Mac CSV."
        for (name, period) in [("current", analysis.current), ("previous", analysis.previous)] {
            try record("scope", period: name, value: period, notes: scopeNotes)
            let tokensComplete = collected && period.tokensComplete
            let costComplete = collected && period.costComplete
            let activityComplete = tokensComplete && period.activity.complete
            for index in indices {
                let key = keys[index]
                let totals = period.models[key]
                let tokens = totals?.tokens.value ?? (totals == nil && tokensComplete ? 0 : nil)
                let cost = totals?.cost.value ?? (totals == nil && costComplete ? 0 : nil)
                let sessions = Self.sessions(key, period: period, collected: collected)
                try record("model", period: name, value: period, index: index, metric: "tokens",
                    number: tokens.map(String.init), complete: tokensComplete)
                try record("model", period: name, value: period, index: index, metric: "estimated_cost",
                    number: cost.map { String($0) }, complete: costComplete)
                try record("model", period: name, value: period, index: index, metric: "session_references",
                    number: sessions.0.map(String.init), complete: sessions.1)
                let components: [(String, WindowsCodexModelAnalysis.Count?)] = [
                    ("input_tokens", totals?.input), ("output_tokens", totals?.output),
                    ("cache_read_tokens", totals?.cached), ("cache_creation_tokens", totals?.cacheCreation),
                    ("reasoning_tokens", totals?.reasoning),
                ]
                for (label, count) in components {
                    try record("component", period: name, value: period, index: index, metric: label,
                        number: (count?.value).map(String.init), complete: tokensComplete && count?.complete == true)
                }
                let tiers: [(String, WindowsCodexModelAnalysis.Count?, WindowsCodexModelAnalysis.Amount?)] = [
                    ("standard", totals?.standardTokens, totals?.standardCost),
                    ("priority", totals?.priorityTokens, totals?.priorityCost),
                ]
                for (tier, count, amount) in tiers {
                    try record("tier", period: name, value: period, index: index, dimension: tier, metric: "tokens",
                        number: (count?.value).map(String.init), complete: tokensComplete && count?.complete == true)
                    try record("tier", period: name, value: period, index: index, dimension: tier, metric: "estimated_cost",
                        number: (amount?.value).map { String($0) }, complete: costComplete && amount?.complete == true)
                }
                let efforts = try Self.efforts(period.activity.models[key]?.effortTokens ?? [:], hidePersonalInfo: hidePersonalInfo)
                if efforts.isEmpty {
                    try record("effort", period: name, value: period, index: index, metric: "recorded_effort_tokens",
                        number: activityComplete ? "0" : nil, complete: activityComplete,
                        notes: activityComplete ? "No recorded activity in this interval." : "Recorded effort evidence is unavailable.")
                } else {
                    for label in efforts.keys.sorted() {
                        try record("effort", period: name, value: period, index: index, dimension: label,
                            metric: "recorded_effort_tokens", number: efforts[label].map(String.init), complete: activityComplete)
                    }
                }
            }
        }
        // Keep comparison states (new/ended/unchanged) distinct from numeric changes and missing evidence.
        for index in indices {
            let key = keys[index]
            let current = analysis.current, previous = analysis.previous
            let ct = current.models[key]?.tokens.value ?? (current.models[key] == nil && collected && current.tokensComplete ? 0 : nil)
            let pt = previous.models[key]?.tokens.value ?? (previous.models[key] == nil && collected && previous.tokensComplete ? 0 : nil)
            let cc = current.models[key]?.cost.value ?? (current.models[key] == nil && collected && current.costComplete ? 0 : nil)
            let pc = previous.models[key]?.cost.value ?? (previous.models[key] == nil && collected && previous.costComplete ? 0 : nil)
            let cs = Self.sessions(key, period: current, collected: collected)
            let ps = Self.sessions(key, period: previous, collected: collected)
            let changes: [(String, Double?, Double?, Bool)] = [
                ("tokens", ct.map { Double($0) }, pt.map { Double($0) }, collected && current.tokensComplete && previous.tokensComplete),
                ("estimated_cost", cc, pc, collected && current.costComplete && previous.costComplete),
                ("session_references", cs.0.map { Double($0) }, ps.0.map { Double($0) }, cs.1 && ps.1),
            ]
            for (label, now, before, complete) in changes {
                let change = Self.change(now, before, complete: complete)
                try record("comparison", period: "current_vs_previous", value: current, index: index, metric: label,
                    number: change.0, complete: complete, comparison: change.1,
                    notes: "Numeric value is a fractional change, not percent. New/ended/unchanged/unavailable are explicit states.")
            }
        }
        let models = query.codexModel == nil ? nil : Set(indices.map { keys[$0] })
        for sample in WindowsCodexModelTimeline.build(analysis, models: models, granularity: granularity, calendar: calendar) {
            let number: String?
            let complete: Bool
            switch metric {
            case "cost": number = sample.cost.map { String($0) }; complete = collected && sample.costComplete
            case "sessionReferences": number = sample.sessionReferences.map(String.init); complete = collected && sample.sessionsComplete
            default: number = sample.tokens.map(String.init); complete = collected && sample.tokensComplete
            }
            try record("timeline", period: "current", value: analysis.current, interval: sample.interval,
                metric: metric == "cost" ? "estimated_cost" : metric == "sessionReferences" ? "session_references" : "tokens",
                number: number, complete: complete,
                notes: "Combined selected models; clipped_calendar_bucket=\(sample.clipped). Weeks start Monday.")
        }
        return writer.data
    }

    private static func sessions(_ key: String, period: WindowsCodexModelAnalysis.Period, collected: Bool) -> (Int?, Bool) {
        let complete = collected && period.tokensComplete && period.activity.complete
        guard let value = period.activity.models[key] else { return complete ? (0, true) : (nil, false) }
        return (value.sessions.isEmpty && !value.sessionsComplete ? nil : value.sessions.count, complete && value.sessionsComplete)
    }
    private static func efforts(_ values: [String: Int], hidePersonalInfo: Bool) throws -> [String: Int] {
        let publicLabels: Set<String> = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra", "persistent"]
        var result: [String: Int] = [:]
        for (label, count) in values {
            let title = label.isEmpty ? "Unrecorded" : hidePersonalInfo && !publicLabels.contains(label) ? "Custom" : label
            let sum = (result[title] ?? 0).addingReportingOverflow(count)
            guard count >= 0, !sum.overflow else { throw Failure.unavailable }
            result[title] = sum.partialValue
        }
        return result
    }
    private static func change(_ current: Double?, _ previous: Double?, complete: Bool) -> (String?, String) {
        guard complete, let current, let previous else { return (nil, "unavailable") }
        switch CodexModelsComparison.make(current: current, previous: previous) {
        case .unavailable: return (nil, "unavailable")
        case .new: return (nil, "new")
        case .ended: return (nil, "ended")
        case .unchanged: return ("0", "unchanged")
        case let .percent(value): return value.isFinite ? (String(value), "changed") : (nil, "unavailable")
        }
    }
    /// Text cells are distinct from generated numeric cells: negative comparison ratios remain numbers.
    static func cell(_ value: String, text: Bool) throws -> String {
        guard value.utf8.count <= 16 * 1024 else { throw Failure.tooLarge }
        let redacted = text ? LogRedactor.redact(value) : value
        var escaped = ""
        for scalar in redacted.unicodeScalars where scalar.value >= 32 || [9, 10, 13].contains(scalar.value) {
            escaped.unicodeScalars.append(scalar)
        }
        if text, let first = escaped.trimmingCharacters(in: .whitespacesAndNewlines).first,
           "=+-@".contains(first) { escaped = "'" + escaped }
        return "\"" + escaped.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    private struct Writer {
        let limit: Int
        var data = Data()
        var rows = 0
        mutating func append(_ values: [String]) throws {
            guard self.rows < WindowsCodexModelCSVExporter.maximumRows else { throw Failure.tooLarge }
            let cells = try values.enumerated().map { index, value in
                try WindowsCodexModelCSVExporter.cell(value, text: index != 12 || self.rows == 0)
            }
            let bytes = Data((cells.joined(separator: ",") + "\r\n").utf8)
            guard bytes.count <= self.limit - self.data.count else { throw Failure.tooLarge }
            self.data.append(bytes)
            self.rows += 1
        }
    }
}
#endif
