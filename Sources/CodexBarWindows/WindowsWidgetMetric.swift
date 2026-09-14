#if os(Windows)
import CodexBarCore
import Foundation

/// Numeric metric projection. The native renderer formats money using its display locale.
public struct WindowsWidgetMetric: Sendable {
    public enum Unit: Sendable { case credits, currency(String), unknownCurrency }
    public let value: Double?
    public let unit: Unit
    public let label: String
    public let tokenCount: Int?
    public let updatedAt: Date?
    public let isStale: Bool
    public let isAPIEstimate: Bool

    public static func make(from content: WindowsWidgetContentResolver.Content) -> Self {
        let entry = content.entry
        switch content.instance.metric {
        case .credits:
            if content.provider == .devin, let cost = entry?.providerCost, cost.period == "Extra usage balance" {
                return Self(value: currency(cost.currencyCode) == nil ? nil : finite(cost.used),
                    unit: currency(cost.currencyCode).map(Unit.currency) ?? .unknownCurrency, label: "Extra usage balance",
                    tokenCount: nil, updatedAt: cost.updatedAt, isStale: content.metricIsStale, isAPIEstimate: false)
            }
            return Self(value: finite(entry?.creditsRemaining), unit: .credits, label: "Credits left",
                tokenCount: nil, updatedAt: entry?.updatedAt, isStale: content.state == .stale, isAPIEstimate: false)
        case .todayCost, .last30DaysCost:
            let token = entry?.tokenUsage
            let today = content.instance.metric == .todayCost
            let code = token.flatMap { currency($0.currencyCode) }
            let amount = today ? token?.sessionCostUSD : token?.last30DaysCostUSD
            let count = today ? token?.sessionTokens : token?.last30DaysTokens
            let period = cleanLabel(today ? token?.sessionLabel : token?.last30DaysLabel) ?? (today ? "Today" : "30d")
            let estimate = content.provider == .codex
            let label = estimate ? (period.contains("API est.") ? period : period + " API est. · not billed") : period + " cost"
            return Self(value: code == nil ? nil : finite(amount), unit: code.map(Unit.currency) ?? .unknownCurrency, label: label,
                tokenCount: count.flatMap { $0 >= 0 ? $0 : nil }, updatedAt: token?.updatedAt,
                isStale: content.metricIsStale, isAPIEstimate: estimate)
        }
    }

    private static func finite(_ value: Double?) -> Double? { value.flatMap { $0.isFinite ? $0 : nil } }
    private static func currency(_ value: String) -> String? {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.utf8.count == 3, code.utf8.allSatisfy({ (65...90).contains($0) }) else { return nil }
        return code
    }
    private static func cleanLabel(_ value: String?) -> String? {
        guard let value, value.utf8.count <= 256,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        let label = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }
}
#endif
