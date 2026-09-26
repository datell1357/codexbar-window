#if os(Windows)
import Foundation
import CodexBarCore

/// Artifact bytes stay in the backend process. Only the action and its display revision cross the UI pipe.
enum WindowsAppSpendExport {
    struct Action: Codable, Sendable {
        let kind: String
        let expectedRevision: String
        var isValid: Bool {
            ["preview", "copyText", "copyImage", "saveImage", "copyJSON", "saveJSON"].contains(self.kind)
                && self.expectedRevision.utf8.count == 64
                && self.expectedRevision.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
    }
    struct Delivery: Sendable {
        let requestID: UUID
        let hidePersonalInfo: Bool
        let result: WindowsUsageRuntime.ShareStatsCopyResult
        let isCurrent: @Sendable () -> Bool
    }

    static func make(snapshot: WindowsSpendDashboardController.Snapshot, currency: String,
                     action: String, hidePersonalInfo: Bool, hiddenSourceIDs: [String], calendar: Calendar,
                     renderer: (WindowsShareStatsPayload, Calendar) -> WindowsShareStatsRenderer.RenderedImage? = {
                         WindowsShareStatsRenderer.render(payload: $0, calendar: $1)
                     }) -> WindowsUsageRuntime.ShareStatsCopyResult {
        guard let group = snapshot.model.groups.first(where: { $0.currencyCode == currency }),
              snapshot.model.selectedDay == nil else {
            return .unavailable("The selected period or currency is unavailable. Reload the cost view.")
        }
        if action == "copyJSON" || action == "saveJSON" {
            let model = WindowsSpendDashboardModel(requestedDays: snapshot.model.requestedDays, groups: [group])
            do {
                let data = try WindowsSpendDashboardJSONExporter.encodedData(model: model,
                    hiddenSourceIDs: hiddenSourceIDs, hidePersonalInfo: hidePersonalInfo)
                guard !data.isEmpty, data.count <= 16 * 1024 * 1024 else {
                    return .unavailable("The cost JSON exceeds the 16 MiB export limit.")
                }
                let copy = action == "copyJSON"
                if copy {
                    guard let text = String(data: data, encoding: .utf8), text.utf16.count <= 65536 else {
                        return .unavailable("The cost JSON is too large for the clipboard. Use Save cost JSON.")
                    }
                }
                let notice = Self.collectionNotice(snapshot)
                return .json(data, filename: "codexbar-spend-last-\(model.requestedDays)-days-\(currency).json",
                             copy: copy, notice: notice)
            } catch { return .unavailable("Cost JSON could not be encoded. No export was produced.") }
        }
        guard ["preview", "copyText", "copyImage", "saveImage"].contains(action),
              snapshot.phase == .ready, !snapshot.stale, snapshot.sourceFailures.isEmpty,
              snapshot.openCodexObservation != .unavailable,
              let original = snapshot.sharePayload, original.days == snapshot.model.requestedDays else {
            return .unavailable("Share Stats needs a completed collection without failed sources. Refresh costs and retry.")
        }
        // Keep subscription-plan labels from the captured share payload; do not resolve current accounts again.
        let payload = WindowsShareStatsPayload(days: original.days, periodEnd: group.chartDomain.upperBound,
            providers: original.providers.filter { $0.currencyCode == currency }.map {
                .init(provider: $0.provider,
                    providerName: ProviderDescriptorRegistry.descriptor(for: $0.provider).metadata.displayName,
                    subscriptionName: $0.subscriptionName, currencyCode: currency, totalTokens: $0.totalTokens,
                    estimatedCost: $0.estimatedCost, coveredDayCount: $0.coveredDayCount)
            },
            topModels: original.topModels.filter { $0.currencyCode == currency }.map {
                .init(provider: $0.provider,
                    providerName: ProviderDescriptorRegistry.descriptor(for: $0.provider).metadata.displayName,
                    modelName: $0.modelName, currencyCode: currency, totalTokens: $0.totalTokens, estimatedCost: $0.estimatedCost)
            },
            currencies: original.currencies.filter { $0.currencyCode == currency },
            totalTokens: group.totalTokens, hasPartialTokens: group.hasPartialTokens)
        guard payload.hasShareableData, payload.currencies.count == 1 else {
            return .unavailable("No shareable values are available in the selected currency.")
        }
        let text = WindowsShareStatsFormatting.text(payload, calendar: calendar)
        guard let redacted = WindowsClipboard.summary(rows: text.components(separatedBy: "\n")) else {
            return .unavailable("Share Stats text is unavailable or exceeds the clipboard limit.")
        }
        if action == "copyText" { return .ready(redacted) }
        guard let image = renderer(payload, calendar), !image.png.isEmpty, !image.dib.isEmpty,
              image.png.count <= 16 * 1024 * 1024, image.dib.count <= 16 * 1024 * 1024 else {
            return .unavailable("The Share Stats image could not be generated.")
        }
        let filename = "codexbar-subscriptions-last-\(payload.days)-days-\(currency).png"
        if action == "preview" { return .preview(png: image.png, dib: image.dib, filename: filename, text: redacted) }
        if action == "copyImage" { return .clipboardImage(png: image.png, dib: image.dib) }
        return .image(image.png, filename: filename)
    }

    static func collectionNotice(_ snapshot: WindowsSpendDashboardController.Snapshot) -> String? {
        var notes: [String] = []
        if !snapshot.sourceFailures.isEmpty {
            notes.append("Partial collection: \(snapshot.sourceFailures.count) pending or failed source(s). Sources without retained values are excluded.")
        }
        if !snapshot.retainedSourceDates.isEmpty {
            notes.append("Previously captured values from \(snapshot.retainedSourceDates.count) source(s) are retained as stale data.")
        }
        if snapshot.sourceFailures.contains(where: \.accountIdentityUnconfirmed) {
            notes.append("An account identity could not be confirmed; its failed source is excluded.")
        }
        if snapshot.openCodexObservation == .unavailable { notes.append("OpenCodeX logs are unavailable and excluded.") }
        if snapshot.stale { notes.append("This export includes the last captured values while collection is incomplete.") }
        if !notes.isEmpty { notes.append("The original JSON schema has no fields for these collection failure or stale states.") }
        return notes.isEmpty ? nil : notes.joined(separator: "\r\n")
    }
}
#endif
