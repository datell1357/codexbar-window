#if os(Windows)
import Foundation
import CodexBarCore

/// Windows-owned spend preferences. Merely loading settings never starts collection.
struct WindowsSpendSettings: Sendable, Equatable {
    var collectionEnabled = false
    var codexLocalLedgerEnabled = false
    var historyDays = 30
    var bucketTimeZoneIdentifier = ""
    var preferredCurrencyCode = "USD"
    var hiddenSourceIDs: Set<String> = []
    var hideNativeCodexWhenOpenCodexPresent = false

    static func load(userDefaults: UserDefaults? = nil) -> Self {
        guard let defaults = userDefaults ?? UserDefaults(suiteName: WindowsRefreshSettings.suiteName) else { return Self() }
        var value = Self()
        value.collectionEnabled = defaults.object(forKey: "tokenCostUsageEnabled") as? Bool ?? false
        value.codexLocalLedgerEnabled = defaults.object(forKey: "codexLocalSessionCostLedgerEnabled") as? Bool ?? false
        value.historyDays = max(1, min(WindowsSpendHistoryPolicy.scanDays,
            defaults.object(forKey: "costUsageHistoryDays") as? Int ?? 30))
        let storedZone = defaults.string(forKey: "tokenCostUsageBucketTimeZone") ?? ""
        value.bucketTimeZoneIdentifier = CostUsageBucketTimeZone.isValidIdentifier(storedZone)
            ? storedZone : CostUsageBucketTimeZone.pinIdentifier()
        value.preferredCurrencyCode = Self.currency(defaults.string(forKey: "preferredCurrencyCode") ?? "USD")
        value.hiddenSourceIDs = Set((defaults.stringArray(forKey: "spendHiddenSourceIDs") ?? []).filter(Self.validSourceID))
        value.hideNativeCodexWhenOpenCodexPresent = defaults.object(forKey: "spendHideNativeCodexWithOpenCodex") as? Bool ?? false
        return value
    }

    func save(userDefaults: UserDefaults? = nil) throws {
        guard let defaults = userDefaults ?? UserDefaults(suiteName: WindowsRefreshSettings.suiteName) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let zone = CostUsageBucketTimeZone.isValidIdentifier(self.bucketTimeZoneIdentifier)
            ? self.bucketTimeZoneIdentifier : CostUsageBucketTimeZone.pinIdentifier()
        // Persist the bucket boundary before enabling future collection.
        defaults.set(zone, forKey: "tokenCostUsageBucketTimeZone")
        defaults.set(self.collectionEnabled, forKey: "tokenCostUsageEnabled")
        defaults.set(self.codexLocalLedgerEnabled, forKey: "codexLocalSessionCostLedgerEnabled")
        defaults.set(max(1, min(WindowsSpendHistoryPolicy.scanDays, self.historyDays)), forKey: "costUsageHistoryDays")
        defaults.set(Self.currency(self.preferredCurrencyCode), forKey: "preferredCurrencyCode")
        defaults.set(self.hiddenSourceIDs.filter(Self.validSourceID).sorted(), forKey: "spendHiddenSourceIDs")
        defaults.set(self.hideNativeCodexWhenOpenCodexPresent, forKey: "spendHideNativeCodexWithOpenCodex")
    }

    func enabledProviders(config: CodexBarConfig) -> Set<UsageProvider> {
        Set(config.enabledProviders().compactMap { id in
            guard let provider = id.firstPartyProvider,
                  self.collectionEnabled || (provider == .codex && self.codexLocalLedgerEnabled),
                  ProviderDescriptorRegistry.descriptor(for: provider).tokenCost.supportsTokenCost else { return nil }
            return provider
        })
    }

    /// Projection preferences do not change which logs were scanned or their day boundaries.
    func usesSameCollection(as other: Self) -> Bool {
        self.collectionEnabled == other.collectionEnabled &&
            self.codexLocalLedgerEnabled == other.codexLocalLedgerEnabled &&
            self.bucketCalendar.timeZone.identifier == other.bucketCalendar.timeZone.identifier
    }

    var dashboardOptions: WindowsSpendDashboardController.Options {
        var options = WindowsSpendDashboardController.Options()
        options.days = max(1, min(WindowsSpendHistoryPolicy.scanDays, self.historyDays))
        options.bucketTimeZoneIdentifier = self.bucketTimeZoneIdentifier
        options.preferredCurrencyCode = Self.currency(self.preferredCurrencyCode)
        options.hiddenSourceIDs = self.hiddenSourceIDs
        options.hideNativeCodexWhenOpenCodexPresent = self.hideNativeCodexWhenOpenCodexPresent
        return options
    }

    var bucketCalendar: Calendar {
        CostUsageBucketTimeZone.calendar(identifier: self.bucketTimeZoneIdentifier)
    }

    private static func currency(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased() == "auto" { return "auto" }
        let code = value.uppercased()
        return code.utf8.count == 3 && code.utf8.allSatisfy { (65...90).contains($0) } ? code : "USD"
    }

    private static func validSourceID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512 &&
            !value.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }
}
#endif
