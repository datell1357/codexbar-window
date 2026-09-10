#if os(Windows)
import CodexBarCore
import Foundation

/// Immutable, platform-neutral data retained by the Windows tray between refreshes.
/// It deliberately keeps the complete provider result so future menu surfaces can
/// consume charts and provider-specific payloads without another network request.
public struct WindowsUsagePresentation: Sendable {
    public let instanceID: ProviderInstanceID
    public let provider: UsageProvider?
    public let title: String
    public let privacyTitle: String?
    public let result: ProviderFetchResult?
    public let snapshot: UsageSnapshot
    public let hidePersonalInfo: Bool
    public let showOptionalUsage: Bool
    public let usageBarsShowUsed: Bool
    public let resetTimesShowAbsolute: Bool

    public init(
        instanceID: ProviderInstanceID,
        provider: UsageProvider?,
        title: String,
        privacyTitle: String? = nil,
        result: ProviderFetchResult?,
        snapshot: UsageSnapshot,
        hidePersonalInfo: Bool = false,
        showOptionalUsage: Bool = true,
        usageBarsShowUsed: Bool = false,
        resetTimesShowAbsolute: Bool = false)
    {
        self.instanceID = instanceID
        self.provider = provider
        self.title = title
        self.privacyTitle = privacyTitle
        self.result = result
        self.snapshot = snapshot
        self.hidePersonalInfo = hidePersonalInfo
        self.showOptionalUsage = showOptionalUsage
        self.usageBarsShowUsed = usageBarsShowUsed
        self.resetTimesShowAbsolute = resetTimesShowAbsolute
    }

    /// Renders the same semantic lanes and optional details used by the native
    /// menu descriptor. Charts remain retained in `snapshot.details`; the text
    /// tray intentionally does not pretend to provide a chart surface.
    public func rows(now: Date = Date()) -> [String] {
        let descriptor = self.provider.map { ProviderDescriptorRegistry.descriptor(for: $0) }
        let metadata = descriptor?.metadata
        let presentation = descriptor?.presentation
        var rows = [self.hidePersonalInfo ? (self.privacyTitle ?? self.title) : self.title]
        let labels = if let metadata {
            presentation?.rateWindowLabels(metadata: metadata, snapshot: self.snapshot, now: now)
                ?? ProviderRateWindowLabels(primary: metadata.sessionLabel, secondary: metadata.weeklyLabel, tertiary: metadata.opusLabel ?? "Sonnet", showsTertiary: metadata.supportsOpus)
        } else {
            ProviderRateWindowLabels(primary: "Primary", secondary: "Secondary", tertiary: "Tertiary", showsTertiary: true)
        }
        if let primary = self.snapshot.primary {
            rows.append(self.rateRow(label: labels.primary, window: primary, now: now, detailAsReset: presentation?.menu.usesPrimaryDescriptionAsDetail(snapshot: self.snapshot) == true))
        }
        if let secondary = self.snapshot.secondary {
            rows.append(self.rateRow(label: labels.secondary, window: secondary, now: now))
        }
        if labels.showsTertiary, let tertiary = self.snapshot.tertiary {
            rows.append(self.rateRow(label: labels.tertiary, window: tertiary, now: now))
        }
        let selectedExtras = presentation?.extraRateWindows(snapshot: self.snapshot) ?? []
        let extras = selectedExtras + (self.snapshot.extraRateWindows ?? []).filter { candidate in
            !selectedExtras.contains(where: { $0.id == candidate.id })
        }
        for extra in extras {
            rows.append(self.rateRow(label: extra.title, window: extra.window, now: now, usageKnown: extra.usageKnown))
        }
        if let credits = self.result?.credits, presentation?.menuCard.showsCreditsSection != false, self.showOptionalUsage {
            if credits.balanceReadSucceeded {
                rows.append("Credits: \(UsageFormatter.creditsString(from: credits.remaining))")
            }
            if let limit = credits.codexCreditLimit {
                rows.append("\(limit.title): \(UsageFormatter.usageLine(remaining: limit.remainingPercent, used: limit.usedPercent, showUsed: self.usageBarsShowUsed))")
                if let reset = limit.resetsAt {
                    let resetWindow = RateWindow(usedPercent: limit.usedPercent, windowMinutes: nil, resetsAt: reset, resetDescription: nil)
                    if let text = UsageFormatter.resetLine(for: resetWindow, style: self.resetTimeDisplayStyle, now: now) { rows.append(text) }
                }
            }
        }
        if let presentation {
            let costPresentation = presentation.cost(snapshot: self.snapshot)
            let costVisible = presentation.menuCard.showsProviderCost(context: ProviderCostVisibilityContext(snapshot: self.snapshot, showOptionalUsage: self.showOptionalUsage))
            if costVisible, costPresentation.menuCardStyle != .hidden {
                for balance in costPresentation.balances {
                    rows.append("\(balance.label): \(UsageFormatter.currencyString(balance.amount, currencyCode: balance.currencyCode))")
                }
            }
            if costVisible, costPresentation.showsGenericFallback, costPresentation.menuCardStyle != .hidden, let cost = self.snapshot.providerCost {
                rows.append("Cost: \(UsageFormatter.currencyString(cost.used, currencyCode: cost.currencyCode))")
                if let balance = cost.balance,
                   !costPresentation.balances.contains(where: { $0.amount == balance && $0.currencyCode == cost.currencyCode }) {
                    rows.append("Balance: \(UsageFormatter.currencyString(balance, currencyCode: cost.currencyCode))")
                }
            }
        } else if self.showOptionalUsage, let cost = self.snapshot.providerCost {
            rows.append("Cost: \(UsageFormatter.currencyString(cost.used, currencyCode: cost.currencyCode))")
            if let balance = cost.balance { rows.append("Balance: \(UsageFormatter.currencyString(balance, currencyCode: cost.currencyCode))") }
        }
        if let presentation {
            let identityPresentation = self.provider.map { presentation.identity(provider: $0, snapshot: self.snapshot) }
            if let badge = identityPresentation?.badge { rows.append("Plan: \(badge)") }
            if let plan = identityPresentation?.plan, plan != identityPresentation?.badge { rows.append("Plan detail: \(plan)") }
            for detail in identityPresentation?.details ?? [] {
                rows.append("\(detail.label): \(detail.value)")
            }
        }
        // Windows refreshes request optional usage completeness, so detail sections
        // are shown by default. Their chart payload remains retained for a future UI.
        let optionalDetails = presentation?.optionalDetails
        for section in self.snapshot.details where self.showOptionalUsage || !(optionalDetails?.hidesAllWithoutOptionalUsage ?? false) {
            if !self.showOptionalUsage, let title = section.title, optionalDetails?.hiddenTitlesWithoutOptionalUsage.contains(title) == true { continue }
            if let title = section.title { rows.append(title) }
            rows.append(contentsOf: section.rows.map { row in
                if let secondary = row.secondaryValue { return "\(row.label): \(row.value) · \(secondary)" }
                return "\(row.label): \(row.value)"
            })
        }
        if let diagnostic = self.result?.diagnostic, !diagnostic.isEmpty { rows.append("Diagnostic: \(diagnostic)") }
        return self.hidePersonalInfo ? rows.map { LogRedactor.redact($0) } : rows
    }

    private func rateRow(label: String, window: RateWindow, now: Date, detailAsReset: Bool = false, usageKnown: Bool = true) -> String {
        guard usageKnown, !window.isSyntheticPlaceholder else { return "\(label): usage unavailable" }
        let value = UsageFormatter.usageLine(remaining: window.remainingPercent, used: window.usedPercent, showUsed: self.usageBarsShowUsed)
        let reset = detailAsReset ? window.resetDescription : UsageFormatter.resetLine(for: window, style: self.resetTimeDisplayStyle, now: now)
        return reset.map { "\(label): \(value) · \($0)" } ?? "\(label): \(value)"
    }

    private var resetTimeDisplayStyle: ResetTimeDisplayStyle {
        self.resetTimesShowAbsolute ? .absolute : .countdown
    }
}
#endif
