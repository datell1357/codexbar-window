#if os(Windows)
import Foundation
import CodexBarCore

/// Text projection for the native read-only summary; currency groups stay separate.
enum WindowsSpendSummary {
    static func text(snapshot: WindowsSpendDashboardController.Snapshot) -> String {
        let model = snapshot.model
        var rows = ["Cost summary · last \(model.requestedDays) days",
                    "Costs are estimates unless reported as metered by the source.",
                    "Currency conversion may use cached or approximate fallback exchange rates."]
        if let loadedAt = snapshot.loadedAt {
            rows.append("Collected: " + loadedAt.formatted(date: .abbreviated, time: .shortened))
        }
        if snapshot.stale { rows.append("Stale data: a new collection has not completed.") }
        if !snapshot.sourceFailures.isEmpty {
            rows.append("Partial collection: \(snapshot.sourceFailures.count) source(s) failed. Totals exclude those sources.")
            for failure in snapshot.sourceFailures {
                rows.append("Unavailable: " + ProviderDescriptorRegistry.descriptor(for: failure.provider).metadata.displayName)
            }
        }
        if model.groups.isEmpty { rows.append("No cost groups are available for this period and source selection.") }
        for group in model.groups {
            rows.append("")
            rows.append("Currency: " + safe(group.currencyCode))
            rows.append("Estimated cost: " + cost(group.totalCost, currency: group.currencyCode))
            rows.append("Tokens: " + tokens(group.totalTokens))
            rows.append("Covered days: \(group.coveredDayCount) / \(model.requestedDays)")
            rows.append("Bucket time zone: " + group.timeZone.identifier)
            if group.modelHistoryCompleteness == .incomplete {
                rows.append("Model history is incomplete; the model breakdown may not explain the entire total.")
            }
            rows.append("Providers")
            for provider in group.providers {
                rows.append("  " + safe(provider.displayName) + " · " + cost(provider.totalCost, currency: group.currencyCode)
                    + " · " + tokens(provider.totalTokens) + " tokens · \(provider.coveredDayCount) covered days")
            }
            rows.append("Models")
            for model in group.models.prefix(100) {
                rows.append("  " + safe(model.providerName) + " / " + safe(model.modelName) + " · "
                    + cost(model.totalCost, currency: group.currencyCode) + " · " + tokens(model.totalTokens) + " tokens")
            }
            if group.models.count > 100 { rows.append("  \(group.models.count - 100) additional models are not shown in this summary.") }
        }
        rows.append("")
        rows.append("Unknown values mean missing coverage, not zero usage. Refresh all and reopen to update this snapshot.")
        return rows.joined(separator: "\r\n")
    }

    private static func tokens(_ value: Int?) -> String {
        value.map { WindowsShareStatsFormatting.compactCount($0) } ?? "Unknown"
    }

    private static func cost(_ value: Double?, currency: String) -> String {
        guard let value, value.isFinite else { return "Unknown" }
        return WindowsShareStatsFormatting.currency(value, code: currency)
    }

    private static func safe(_ text: String) -> String {
        String(LogRedactor.redact(text).unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }
            .map(String.init).joined().prefix(180))
    }
}
#endif
