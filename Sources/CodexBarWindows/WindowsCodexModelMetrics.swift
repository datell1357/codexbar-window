#if os(Windows)
import Foundation
import CodexBarCore

/// Ratios describe the captured native Codex scope, independently of model selection and UI pages.
enum WindowsCodexModelMetrics {
    struct Ratio: Sendable {
        let value: Double?
        let complete: Bool
    }
    struct Pricing: Sendable {
        let priced: WindowsCodexModelAnalysis.Count
        let unpriced: WindowsCodexModelAnalysis.Count
        let countsComplete: Bool
        let coverage: Ratio
        let status: String
        let statusComplete: Bool
    }
    struct Shares: Sendable {
        let tokens: Ratio
        let knownCost: Ratio
        let sessionReferences: Ratio
    }
    struct Aliases: Sendable {
        let values: [String]
        let complete: Bool
    }

    static func pricing(_ key: String, period: WindowsCodexModelAnalysis.Period, collected: Bool) -> Pricing {
        let totals = period.models[key]
        let scopeComplete = collected && period.tokensComplete && period.activity.complete
        let expected = totals?.tokens.value ?? (totals == nil && period.tokensComplete ? 0 : nil)
        if expected == 0, scopeComplete {
            var zero = WindowsCodexModelAnalysis.Count(); zero.add(0)
            return .init(priced: zero, unpriced: zero, countsComplete: true,
                coverage: .init(value: 1, complete: true), status: "no_usage", statusComplete: true)
        }
        var price = WindowsCodexEffortPricing.Value()
        if let activity = period.activity.models[key] {
            for amount in activity.effortPricing.values { price.merge(amount) }
        }
        var partitionMatches = false
        if let priced = price.pricedTokens.value, let unpriced = price.unpricedTokens.value,
           price.pricedTokens.complete, price.unpricedTokens.complete, let expected {
            let total = priced.addingReportingOverflow(unpriced)
            partitionMatches = !total.overflow && total.partialValue == expected
        }
        let countsComplete = scopeComplete && partitionMatches
        let coverage = partitionMatches
            ? Self.ratio(price.pricedTokens.value.map(Double.init), expected.map(Double.init), complete: countsComplete)
            : Ratio(value: nil, complete: false)
        let status: String
        if price.cost.value != nil, (price.pricedTokens.value ?? 0) > 0 {
            status = countsComplete && totals?.cost.complete == true && price.costComplete ? "known" : "partial"
        } else { status = "unavailable" }
        return .init(priced: price.pricedTokens, unpriced: price.unpricedTokens, countsComplete: countsComplete,
            coverage: coverage, status: status, statusComplete: countsComplete)
    }

    static func referenceTotal(period: WindowsCodexModelAnalysis.Period, collected: Bool) -> WindowsCodexModelAnalysis.Count {
        let activityComplete = collected && period.tokensComplete && period.activity.complete
        var references = WindowsCodexModelAnalysis.Count()
        if period.activity.models.isEmpty, activityComplete { references.add(0) }
        for value in period.activity.models.values {
            references.add(value.sessions.isEmpty && !value.sessionsComplete ? nil : value.sessions.count)
            if !value.sessionsComplete { references.add(nil) }
        }
        return references
    }

    static func shares(_ key: String, period: WindowsCodexModelAnalysis.Period, collected: Bool,
                       referenceTotal: WindowsCodexModelAnalysis.Count? = nil) -> Shares {
        let model = period.models[key]
        let tokensComplete = collected && period.tokensComplete
        let costComplete = collected && period.costComplete
        let tokens = model?.tokens.value ?? (model == nil && tokensComplete ? 0 : nil)
        let cost = model?.cost.value ?? (model == nil && costComplete ? 0 : nil)
        let activityComplete = collected && period.tokensComplete && period.activity.complete
        let references = referenceTotal ?? Self.referenceTotal(period: period, collected: collected)
        let activity = period.activity.models[key]
        let count: Int?
        if let activity { count = activity.sessions.isEmpty && !activity.sessionsComplete ? nil : activity.sessions.count }
        else { count = activityComplete ? 0 : nil }
        return .init(
            tokens: Self.ratio(tokens.map(Double.init), period.tokens.value.map(Double.init),
                complete: tokensComplete && (model?.tokens.complete ?? true)),
            knownCost: Self.ratio(cost, period.cost.value, complete: costComplete && (model?.cost.complete ?? true)),
            sessionReferences: Self.ratio(count.map(Double.init), references.value.map(Double.init),
                complete: activityComplete && references.complete && (activity?.sessionsComplete ?? true)))
    }

    static func aliases(_ key: String, period: WindowsCodexModelAnalysis.Period, collected: Bool) -> Aliases {
        let model = period.activity.models[key]
        let absent = period.models[key] == nil && period.tokensComplete
        return .init(values: model?.rawAliases.sorted() ?? [],
            complete: collected && period.tokensComplete && period.activity.complete
                && (model?.aliasesComplete ?? absent))
    }

    static func ratio(_ numerator: Double?, _ denominator: Double?, complete: Bool) -> Ratio {
        guard let numerator, let denominator, numerator.isFinite, denominator.isFinite,
              numerator >= 0, denominator >= 0,
              numerator <= denominator || WindowsSpendDashboardModel.costsMatch(numerator, denominator)
        else { return .init(value: nil, complete: false) }
        if denominator == 0 {
            return .init(value: numerator == 0 && complete ? 0 : nil, complete: numerator == 0 && complete)
        }
        let result = min(1, numerator / denominator)
        guard result.isFinite else { return .init(value: nil, complete: false) }
        return .init(value: result, complete: complete)
    }
}
#endif
