#if os(Windows)
import Foundation
import CodexBarCore

/// Windows-owned spend preferences. Merely loading settings never starts collection.
struct WindowsSpendSettings: Sendable, Equatable {
    enum PersistenceFailure: Error { case settingsChanged }
    // Tray and app requests share the backend process. Keep their preference read/compare/write
    // operations serialized; this is not a cross-process transaction against external editors.
    private static let persistenceLock = NSRecursiveLock()
    var openCodexUsageLogsEnabled = false
    var collectionEnabled = false
    var codexLocalLedgerEnabled = false
    var historyDays = 30
    var bucketTimeZoneIdentifier = ""
    var preferredCurrencyCode = "USD"
    var hiddenSourceIDs: Set<String> = []
    var hideNativeCodexWhenOpenCodexPresent = false

    static func load(userDefaults: UserDefaults? = nil) -> Self {
        Self.persistenceLock.lock()
        defer { Self.persistenceLock.unlock() }
        guard let defaults = userDefaults ?? UserDefaults(suiteName: WindowsRefreshSettings.suiteName) else { return Self() }
        var value = Self()
        value.openCodexUsageLogsEnabled = defaults.object(forKey: "openCodexUsageLogsEnabled") as? Bool ?? false
        value.collectionEnabled = defaults.object(forKey: "tokenCostUsageEnabled") as? Bool ?? false
        value.codexLocalLedgerEnabled = defaults.object(forKey: "codexLocalSessionCostLedgerEnabled") as? Bool ?? false
        value.historyDays = max(1, min(WindowsSpendHistoryPolicy.scanDays,
            Self.storedValue(defaults, key: "tokenCostUsageHistoryDays", legacyKey: "costUsageHistoryDays") as? Int ?? 30))
        let storedZone = defaults.string(forKey: "tokenCostUsageBucketTimeZone") ?? ""
        value.bucketTimeZoneIdentifier = CostUsageBucketTimeZone.isValidIdentifier(storedZone)
            ? storedZone : CostUsageBucketTimeZone.pinIdentifier()
        value.preferredCurrencyCode = Self.currency(defaults.string(forKey: "preferredCurrencyCode") ?? "USD")
        value.hiddenSourceIDs = Set((Self.storedValue(defaults, key: "spendDashboardHiddenSourceIDs", legacyKey: "spendHiddenSourceIDs") as? [String] ?? []).filter(Self.validSourceID))
        value.hideNativeCodexWhenOpenCodexPresent = Self.storedValue(defaults, key: "hideNativeCodexCostWhenOpenCodexPresent", legacyKey: "spendHideNativeCodexWithOpenCodex") as? Bool ?? false
        return value
    }

    func save(userDefaults: UserDefaults? = nil) throws {
        Self.persistenceLock.lock()
        defer { Self.persistenceLock.unlock() }
        guard let defaults = userDefaults ?? UserDefaults(suiteName: WindowsRefreshSettings.suiteName) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let zone = CostUsageBucketTimeZone.isValidIdentifier(self.bucketTimeZoneIdentifier)
            ? self.bucketTimeZoneIdentifier : CostUsageBucketTimeZone.pinIdentifier()
        // Persist the bucket boundary before enabling future collection.
        defaults.set(zone, forKey: "tokenCostUsageBucketTimeZone")
        defaults.set(self.openCodexUsageLogsEnabled, forKey: "openCodexUsageLogsEnabled")
        defaults.set(self.collectionEnabled, forKey: "tokenCostUsageEnabled")
        defaults.set(self.codexLocalLedgerEnabled, forKey: "codexLocalSessionCostLedgerEnabled")
        Self.store(max(1, min(WindowsSpendHistoryPolicy.scanDays, self.historyDays)), in: defaults,
                   key: "tokenCostUsageHistoryDays", legacyKey: "costUsageHistoryDays")
        defaults.set(Self.currency(self.preferredCurrencyCode), forKey: "preferredCurrencyCode")
        Self.store(self.hiddenSourceIDs.filter(Self.validSourceID).sorted(), in: defaults,
                   key: "spendDashboardHiddenSourceIDs", legacyKey: "spendHiddenSourceIDs")
        Self.store(self.hideNativeCodexWhenOpenCodexPresent, in: defaults,
                   key: "hideNativeCodexCostWhenOpenCodexPresent", legacyKey: "spendHideNativeCodexWithOpenCodex")
    }

    /// Native app writes only changed fields, avoiding unrelated settings being overwritten by a stale copy.
    func saveChanges(from previous: Self, userDefaults: UserDefaults? = nil) throws {
        Self.persistenceLock.lock()
        defer { Self.persistenceLock.unlock() }
        guard let defaults = userDefaults ?? UserDefaults(suiteName: WindowsRefreshSettings.suiteName) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard Self.load(userDefaults: defaults) == previous else { throw PersistenceFailure.settingsChanged }
        if self.bucketTimeZoneIdentifier != previous.bucketTimeZoneIdentifier ||
            !CostUsageBucketTimeZone.isValidIdentifier(defaults.string(forKey: "tokenCostUsageBucketTimeZone") ?? "") {
            let zone = CostUsageBucketTimeZone.isValidIdentifier(self.bucketTimeZoneIdentifier)
                ? self.bucketTimeZoneIdentifier : CostUsageBucketTimeZone.pinIdentifier()
            defaults.set(zone, forKey: "tokenCostUsageBucketTimeZone")
        }
        if self.collectionEnabled != previous.collectionEnabled {
            defaults.set(self.collectionEnabled, forKey: "tokenCostUsageEnabled")
        }
        if self.codexLocalLedgerEnabled != previous.codexLocalLedgerEnabled {
            defaults.set(self.codexLocalLedgerEnabled, forKey: "codexLocalSessionCostLedgerEnabled")
        }
        if self.openCodexUsageLogsEnabled != previous.openCodexUsageLogsEnabled {
            defaults.set(self.openCodexUsageLogsEnabled, forKey: "openCodexUsageLogsEnabled")
        }
        if self.hideNativeCodexWhenOpenCodexPresent != previous.hideNativeCodexWhenOpenCodexPresent {
            Self.store(self.hideNativeCodexWhenOpenCodexPresent, in: defaults,
                key: "hideNativeCodexCostWhenOpenCodexPresent", legacyKey: "spendHideNativeCodexWithOpenCodex")
        }
        if self.preferredCurrencyCode != previous.preferredCurrencyCode {
            defaults.set(Self.currency(self.preferredCurrencyCode), forKey: "preferredCurrencyCode")
        }
        if self.hiddenSourceIDs != previous.hiddenSourceIDs {
            Self.store(self.hiddenSourceIDs.filter(Self.validSourceID).sorted(), in: defaults,
                key: "spendDashboardHiddenSourceIDs", legacyKey: "spendHiddenSourceIDs")
        }
        if self.historyDays != previous.historyDays {
            Self.store(max(1, min(WindowsSpendHistoryPolicy.scanDays, self.historyDays)), in: defaults,
                key: "tokenCostUsageHistoryDays", legacyKey: "costUsageHistoryDays")
        }
        guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Prefer the original key, including explicit false/empty values. Loading never writes defaults.
    private static func storedValue(_ defaults: UserDefaults, key: String, legacyKey: String) -> Any? {
        defaults.object(forKey: key) ?? defaults.object(forKey: legacyKey)
    }

    /// Mirror earlier Windows keys so an older build can still read settings saved by this build.
    private static func store(_ value: Any, in defaults: UserDefaults, key: String, legacyKey: String) {
        defaults.set(value, forKey: key)
        defaults.set(value, forKey: legacyKey)
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
        self.openCodexUsageLogsEnabled == other.openCodexUsageLogsEnabled &&
            self.hideNativeCodexWhenOpenCodexPresent == other.hideNativeCodexWhenOpenCodexPresent &&
            self.hiddenSourceIDs.contains(WindowsSpendDashboardModel.openCodexSourceID) == other.hiddenSourceIDs.contains(WindowsSpendDashboardModel.openCodexSourceID) &&
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
