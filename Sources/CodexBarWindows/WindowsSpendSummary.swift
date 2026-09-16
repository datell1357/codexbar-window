#if os(Windows)
import Foundation
import CodexBarCore

struct WindowsSnapshotSection: Sendable {
    let title: String
    let text: String
}

/// Text projection for the native read-only summary; currency groups stay separate.
enum WindowsSpendSummary {
    static func text(snapshot: WindowsSpendDashboardController.Snapshot, hidePersonalInfo: Bool, expanded: Bool = false) -> String {
        let model = snapshot.model
        var rows = ["Cost summary · last \(model.requestedDays) days",
                    "Costs are estimates unless reported as metered by the source.",
                    "Currency conversion may use cached or approximate fallback exchange rates."]
        if let loadedAt = snapshot.loadedAt {
            rows.append("Collected: " + loadedAt.formatted(date: .abbreviated, time: .shortened))
        }
        switch snapshot.openCodexObservation {
        case .disabled: break
        case .available: rows.append("OpenCodeX usage logs are included using subscription routing.")
        case .confirmedEmpty: rows.append("OpenCodeX has no publishable subscription usage in the captured log.")
        case .unavailable: rows.append("Partial collection: OpenCodeX logs could not be read. Sharing is unavailable.")
        }
        if snapshot.stale { rows.append("Stale data: a new collection has not completed.") }
        if !snapshot.sourceFailures.isEmpty {
            let pending = snapshot.sourceFailures.filter(\.localInventoryPending).count
            let failed = snapshot.sourceFailures.count - pending
            rows.append("Partial collection: \(pending) source(s) still collecting local data; \(failed) failed. Sources without retained values are excluded.")
            for failure in snapshot.sourceFailures {
                rows.append((failure.localInventoryPending ? "Collecting local data: " : "Unavailable: ")
                    + ProviderDescriptorRegistry.descriptor(for: failure.provider).metadata.displayName)
                if failure.localInventoryPending {
                    rows.append(snapshot.continuingLocalDiscovery
                        ? "Local collection is continuing automatically; completed sources are not fetched again."
                        : "Collection progress is saved. Refresh to continue.")
                    if let completed = failure.completedFiles, let total = failure.discoveredFiles {
                        rows.append("Files read: \(completed) / \(total).")
                    } else if let count = failure.discoveredFiles {
                        rows.append("Files discovered so far: \(count).")
                    }
                    if let captured = snapshot.retainedSourceDates[failure.sourceID] {
                        rows.append("Previous value retained (stale), captured: "
                            + captured.formatted(date: .abbreviated, time: .shortened))
                    } else {
                        rows.append("No current total is available for this source; it is excluded from the displayed total.")
                    }
                }
                if failure.accountIdentityUnconfirmed {
                    rows.append("Account identity could not be confirmed. Import the intended account again; this source is excluded.")
                }
            }
        }
        if model.groups.isEmpty { rows.append("No cost groups are available for this period and source selection.") }
        for group in model.groups {
            rows.append("")
            rows.append("Currency: " + safe(group.currencyCode))
            rows.append("Estimated cost: " + (group.hasPartialCost ? "~" : "") + cost(group.totalCost, currency: group.currencyCode))
            rows.append("Tokens: " + (group.hasPartialTokens ? "~" : "") + tokens(group.totalTokens))
            rows.append(contentsOf: accountingDetails(group))
            rows.append("Covered days: \(group.coveredDayCount) / \(model.requestedDays)")
            rows.append("Bucket time zone: " + group.timeZone.identifier)
            if group.modelHistoryCompleteness == .incomplete {
                rows.append("Model history is incomplete; the model breakdown may not explain the entire total.")
            }
            rows.append("Providers")
            for provider in group.providers {
                rows.append("  #\(provider.rank) " + safe(provider.displayName) + " · " + cost(provider.totalCost, currency: group.currencyCode)
                    + " · " + tokens(provider.totalTokens) + " tokens · \(provider.coveredDayCount) covered days")
            }
            rows.append("Models")
            if group.models.isEmpty {
                rows.append(group.modelHistoryCompleteness == .incomplete
                    ? "  Model breakdown unavailable." : "  No model-level history.")
            }
            for model in group.models.prefix(expanded ? group.models.count : 8) {
                let rank = group.modelHistoryCompleteness == .complete ? "#\(model.rank) " : "Partial · "
                rows.append("  " + rank + safe(model.providerName) + " / " + safe(model.modelName) + " · "
                    + cost(model.totalCost, currency: group.currencyCode) + " · " + tokens(model.totalTokens) + " tokens")
                rows.append("    " + tokenMixDetails(model.tokenMix))
            }
            if !expanded, group.models.count > 8 { rows.append("  \(group.models.count - 8) more models. Choose Show all rows to expand.") }
            rows.append("Projects")
            if group.projects.isEmpty { rows.append("  No project breakdown is available for this period.") }
            for (index, project) in group.projects.prefix(expanded ? group.projects.count : 8).enumerated() {
                let name = hidePersonalInfo ? "Project \(index + 1)" : safe(project.projectName)
                rows.append("  #\(project.rank) " + name + " · " + safe(project.providerName) + " · "
                    + cost(project.totalCost, currency: group.currencyCode) + " · " + tokens(project.totalTokens) + " tokens")
            }
            if !expanded, group.projects.count > 8 { rows.append("  \(group.projects.count - 8) more projects. Choose Show all rows to expand.") }
            rows.append(expanded ? "Sessions (available model window)" : "Recent sessions (available model window)")
            if group.sessions.isEmpty { rows.append("  No session breakdown is available for this period.") }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.timeZone = group.timeZone
            for (index, session) in group.sessions.prefix(expanded ? group.sessions.count : 12).enumerated() {
                rows.append("  Session \(index + 1) · " + safe(session.displayName) + " · "
                    + cost(session.totalCost, currency: group.currencyCode) + " · " + tokens(session.totalTokens) + " tokens")
                rows.append("    Last activity: " + formatter.string(from: session.lastActivity)
                    + (session.modelName.map { " · " + safe($0) } ?? ""))
                if expanded {
                    rows.append("    Requests: " + (session.requestCount.map { $0.formatted() } ?? "Unknown"))
                    rows.append("    " + tokenMixDetails(session.tokenMix))
                    if session.models.isEmpty { rows.append("    No per-model session breakdown is available.") }
                    for breakdown in session.models {
                        rows.append("      " + safe(breakdown.modelName) + " · "
                            + cost(breakdown.totalCost, currency: group.currencyCode)
                            + " · " + tokens(breakdown.totalTokens) + " tokens")
                        rows.append("        " + tokenMixDetails(breakdown.tokenMix))
                    }
                }
            }
            if !expanded, group.sessions.count > 12 {
                rows.append("  \(group.sessions.count - 12) more sessions. Choose Show all rows to expand.")
            }
            rows.append("Session totals describe the captured sessions whose last activity falls in this window; they may include activity before the window.")
            rows.append("Project and session breakdowns can be incomplete and need not sum to the period total.")
        }
        rows.append("")
        rows.append("Unknown values mean missing coverage, not zero usage. Refresh all and reopen to update this snapshot.")
        return rows.joined(separator: "\r\n")
    }

    static func sections(snapshot: WindowsSpendDashboardController.Snapshot,
                         hidePersonalInfo: Bool) -> [WindowsSnapshotSection] {
        var sections: [WindowsSnapshotSection] = []
        for group in snapshot.model.groups {
            var context = ["Currency: " + safe(group.currencyCode),
                           "Bucket time zone: " + group.timeZone.identifier,
                           "Captured snapshot; refresh and reopen to update.",
                           "Breakdowns can be incomplete and need not sum to the period total.",
                           "Token classes may overlap; do not add them to infer the total."]
            if !snapshot.sourceFailures.isEmpty {
                context.append("Partial collection: sources without retained values are excluded; retained values are stale. Return to Summary for details.")
            }
            for (index, project) in group.projects.enumerated() {
                let name = hidePersonalInfo ? "Project \(index + 1)" : safe(project.projectName)
                let title = "Project · " + name + " · " + safe(project.providerName) + " · " + safe(group.currencyCode)
                var rows = context + [title,
                    "Cost: " + cost(project.totalCost, currency: group.currencyCode),
                    "Tokens: " + tokens(project.totalTokens)]
                if !hidePersonalInfo, let path = project.path { rows.append("Path: " + safe(path)) }
                rows.append("Models (selected project and period)")
                if project.modelHistoryCompleteness == .incomplete {
                    rows.append("Incomplete model coverage: available rows may not explain the project total.")
                }
                if project.models.isEmpty { rows.append("No publishable model breakdown is available for this project.") }
                for model in project.models {
                    let rank = project.modelHistoryCompleteness == .complete ? "#\(model.rank) " : "Partial · "
                    rows.append(rank + safe(model.modelName) + " · " + cost(model.totalCost, currency: group.currencyCode)
                        + " · " + tokens(model.totalTokens) + " tokens")
                    rows.append(tokenMixDetails(model.tokenMix))
                }
                rows.append("Daily history (captured days within source coverage)")
                rows.append("Missing days are not inferred as zero. Unknown amounts preserve incomplete coverage.")
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                formatter.timeZone = group.timeZone
                for daily in project.daily {
                    rows.append(formatter.string(from: daily.day) + " · "
                        + cost(daily.totalCost, currency: group.currencyCode) + " · "
                        + tokens(daily.totalTokens) + " tokens")
                }

                if snapshot.stale { rows.append("Stale data: a new collection has not completed.") }
                sections.append(WindowsSnapshotSection(title: title, text: rows.joined(separator: "\r\n")))
            }
            for (index, session) in group.sessions.enumerated() {
                let title = "Session \(index + 1) · " + safe(session.displayName) + " · " + safe(group.currencyCode)
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                formatter.timeZone = group.timeZone
                var rows = context + [title,
                    "Last activity: " + formatter.string(from: session.lastActivity),
                    "Cost: " + cost(session.totalCost, currency: group.currencyCode),
                    "Tokens: " + tokens(session.totalTokens),
                    "Requests: " + (session.requestCount.map { $0.formatted() } ?? "Unknown"),
                    tokenMixDetails(session.tokenMix),
                    "Session totals may include activity before the selected period."]
                if snapshot.stale { rows.append("Stale data: a new collection has not completed.") }
                if session.models.isEmpty { rows.append("No per-model session breakdown is available.") }
                for model in session.models {
                    rows.append(safe(model.modelName) + " · " + cost(model.totalCost, currency: group.currencyCode)
                        + " · " + tokens(model.totalTokens) + " tokens")
                    rows.append(tokenMixDetails(model.tokenMix))
                }
                sections.append(WindowsSnapshotSection(title: title, text: rows.joined(separator: "\r\n")))
            }
        }
        return sections
    }

    /// Use the same captured accounting metadata in the summary and chart detail views.
    static func accountingDetails(_ group: WindowsSpendDashboardModel.CurrencyGroup) -> [String] {
        let provenance: String
        switch group.provenance {
        case .listPriceEstimate: provenance = "List-price equivalent"
        case .vendorMetered: provenance = "Plan metered"
        case .mixed: provenance = "Metered and list-price"
        case .unknown: provenance = "Spend unavailable"
        }
        let coverage = group.coverage
        var rows = ["Cost basis: " + provenance,
                    "Subscriptions: \(group.providers.count)",
                    tokenMixDetails(group.tokenMix),
                    "Coverage: Priced \(coverage.priced.formatted()) · Unpriced \(coverage.unpriced.formatted())"
                        + " · Unmetered \(coverage.unmetered.formatted()) · Estimated \(coverage.estimated.formatted())"]
        if group.hasPartialCost {
            rows.append("Partial cost estimate: \(group.pricedProviderCount) of \(group.providers.count) subscriptions have spend. ~ marks a subtotal with missing subscriptions.")
        }
        if group.hasPartialTokens {
            let known = group.providers.count { $0.totalTokens != nil }
            rows.append("Partial token total: \(known) of \(group.providers.count) subscriptions report tokens. Missing values are not zero.")
        }
        if let metered = group.meteredCost {
            rows.append("Plan metered: " + cost(metered, currency: group.currencyCode))
        }
        rows.append("Coverage counts describe source requests or rows, not covered days. Cost figures are not billing receipts.")
        rows.append("Token classes may overlap or have partial coverage; they must not be added to infer the total.")
        return rows
    }

    private static func tokenMixDetails(_ mix: CostUsageTokenMix) -> String {
        func exact(_ value: Int?) -> String { value.map { $0.formatted() } ?? "Unknown" }
        return "Input: " + exact(mix.inputTokens) + " · Output: " + exact(mix.outputTokens)
            + " · Cache read: " + exact(mix.cacheReadTokens) + " · Cache write: " + exact(mix.cacheCreationTokens)
            + " · Reasoning: " + exact(mix.reasoningTokens)
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
