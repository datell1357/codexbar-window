#if os(Windows)
import CodexBarCore
import Foundation

public struct WindowsWidgetSupplement: Sendable {
    public let codeReviewRemainingPercent: Double?
    public let codeReviewDisplayedPercent: Double?
    public let compactTokenFallback: Bool
    public let creditsBalance: WindowsWidgetMetric?
    public let todayCost: WindowsWidgetMetric?
    public let last30DaysCost: WindowsWidgetMetric?

    static func make(content: WindowsWidgetContentResolver.Content, configuration: WindowsWidgetConfiguration,
                     snapshot: WidgetSnapshot?, now: Date, maximumAge: TimeInterval) throws -> Self {
        let review = content.entry?.codeReviewRemainingPercent.flatMap { $0.isFinite ? $0 : nil }
        // Inspect all rows, not only those fitting the current size: a clipped quota row is still quota data.
        let allRows = try WindowsWidgetUsage.rows(from: content, now: now)
        func cost(_ metric: WindowsWidgetConfiguration.Metric) throws -> WindowsWidgetMetric? {
            if metric == .credits {
                guard content.entry?.creditsRemaining != nil ||
                      (content.provider == .devin && content.entry?.providerCost?.period == "Extra usage balance") else { return nil }
            } else { guard content.entry?.tokenUsage != nil else { return nil } }
            var instance = content.instance; instance.metric = metric
            let projected = try configuration.applying(.upsert(instance))
            let metricContent = try WindowsWidgetContentResolver.resolve(instanceID: instance.id,
                configuration: projected, snapshot: snapshot, now: now, maximumAge: maximumAge)
            return WindowsWidgetMetric.make(from: metricContent)
        }
        return Self(codeReviewRemainingPercent: review,
            codeReviewDisplayedPercent: review.map { content.showUsed ? 100 - $0 : $0 },
            compactTokenFallback: allRows.isEmpty && content.entry?.codeReviewRemainingPercent == nil && content.entry?.tokenUsage != nil,
            creditsBalance: try cost(.credits), todayCost: try cost(.todayCost), last30DaysCost: try cost(.last30DaysCost))
    }
}
#endif
