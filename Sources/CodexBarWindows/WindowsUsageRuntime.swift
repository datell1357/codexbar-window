#if os(Windows)
import CodexBarCore
import AdaptiveRefreshCore
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public struct WindowsUsagePresentationSettings: Sendable {
    public let hidePersonalInfo: Bool
    public let showOptionalCreditsAndExtraUsage: Bool
    public let usageBarsShowUsed: Bool
    public let resetTimesShowAbsolute: Bool

    public static func load(from defaults: UserDefaults? = nil) -> Self {
        let defaults = defaults ?? UserDefaults(suiteName: WindowsRefreshSettings.suiteName) ?? .standard
        return Self(
            hidePersonalInfo: defaults.object(forKey: "hidePersonalInfo") as? Bool ?? false,
            showOptionalCreditsAndExtraUsage: defaults.object(forKey: "showOptionalCreditsAndExtraUsage") as? Bool ?? true,
            usageBarsShowUsed: defaults.object(forKey: "usageBarsShowUsed") as? Bool ?? false,
            resetTimesShowAbsolute: defaults.object(forKey: "resetTimesShowAbsolute") as? Bool ?? false)
    }
}

/// Owns the Windows tray's provider refresh lifecycle.  Win32 callbacks only
/// enqueue work; all provider I/O stays on this actor and is serialized.
public actor WindowsUsageRuntime {
    public typealias RowPublisher = @Sendable ([String]) -> Void
    public typealias CombinedPublisher = @Sendable ([String], [WindowsTrayMenuEntry]) -> Void
    public typealias NotificationPublisher = @Sendable (WindowsSessionQuotaNotification) -> Void
    public typealias QuotaWarningPublisher = @Sendable (WindowsQuotaWarningNotification) -> Void
    public typealias PredictivePaceWarningPublisher = @Sendable (WindowsPredictivePaceWarningNotification) -> Void
    public struct RefreshSignals: Sendable {
        public var lowPowerModeEnabled: Bool
        /// Nil means the native power snapshot succeeded. A non-nil value is
        /// the GetLastError code from an unavailable snapshot.
        public var powerStateError: UInt32?
        /// Windows adapters may report thermal pressure once available. Until
        /// then this remains a public boolean to avoid exposing core package
        /// implementation types across the executable boundary.
        public var thermalConstrained: Bool

        public init(
            lowPowerModeEnabled: Bool = false,
            thermalConstrained: Bool = false,
            powerStateError: UInt32? = nil)
        {
            self.lowPowerModeEnabled = lowPowerModeEnabled
            self.thermalConstrained = thermalConstrained
            self.powerStateError = powerStateError
        }
    }
    public typealias RefreshSignalProvider = @Sendable () -> RefreshSignals

    private let configStore: CodexBarConfigStore
    private let browserDetection: BrowserDetection
    private let fetcher: UsageFetcher
    private let claudeFetcher: ClaudeUsageFetcher
    private let pluginApprovalStore: ProviderPluginApprovalStore
    private var publisher: RowPublisher
    private var combinedPublisher: CombinedPublisher
    private var notificationPublisher: NotificationPublisher
    private var quotaWarningPublisher: QuotaWarningPublisher
    private var predictivePaceWarningPublisher: PredictivePaceWarningPublisher
    private var refreshTask: Task<Void, Never>?
    private var refreshCompletionWaiters: [CheckedContinuation<Void, Never>] = []
    private var startupConnectivityRetryTask: Task<Void, Never>?
    private var startupConnectivityRetryActive = false
    private var startupConnectivityRetryNeeded = false
    private var queuedOptionalRefresh = false
    private var queuedPredictiveSettingsRefresh = false
    private var queuedCodexWebSettingsRefresh = false
    private var scheduleTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var resetBoundaryRefreshTask: Task<Void, Never>?
    private var scheduledResetBoundaryRefreshAt: Date?
    private var attemptedResetBoundaryRefreshes: Set<Date> = []
    private var scheduleGeneration: UInt64 = 0
    private var scheduledDeadline: ContinuousClock.Instant?
    private let signalProvider: RefreshSignalProvider
    private var lastMenuOpenedAt: Date?
    private var refreshSettings: WindowsRefreshSettings
    private var started = false
    private var pluginDiscoveryInitialized = false
    private var shuttingDown = false
    private var presentations: [ProviderInstanceID: WindowsUsagePresentation] = [:]
    private enum RenderEntry { case presentation(WindowsUsagePresentation); case row(String) }
    private var renderEntries: [RenderEntry] = []
    private var statusMenuEntries: [WindowsTrayMenuEntry] = []
    private struct DashboardContextKey: Equatable {
        let accountID: UUID?
        let accountScope: String?
        let accountOrganization: String?
        let accountWorkspace: String?
        let accountTokenDigest: String?
        let region: String?
        let workspaceID: String?
        let cookieSource: ProviderCookieSource?
        let cookieDigest: String?
        let apiKeyDigest: String?
        let secretKeyDigest: String?
        let source: ProviderSourceMode?
    }
    private struct DashboardContext {
        let key: DashboardContextKey
        let sourceLabel: String?
        let claudeLoginMethod: String?
        let zaiUsageScope: ZaiUsageScope?
    }
    private var dashboardContextCache: [ProviderInstanceID: DashboardContext] = [:]
    private var sessionQuotaStates: [ProviderInstanceID: SessionQuotaTransitionCore.State] = [:]
    private var codexSessionQuotaBaselineWatermark: Date?
    private var quotaWarningStates: [QuotaWarningTransitionCore.Key: QuotaWarningTransitionCore.State] = [:]
    private var latestProviderConfigs: [ProviderInstanceID: ProviderConfig] = [:]
    private var latestEnabledProviderIDs: Set<ProviderInstanceID>?
    private var quotaWarningGeneration: UInt64 = 0
    private var predictivePaceWarningGeneration: UInt64 = 0
    private var predictivePaceWarningKeys: Set<PredictivePaceWarningTransitionCore.Key> = []
    // Windows keeps one in-memory dataset for the currently visible Codex owner.
    // Persistence is delegated to the shared history actor; no account dictionary
    // is kept here, so a stale owner cannot score another account.
    private let historicalUsageHistoryStore: HistoricalUsageHistoryStore
    private var codexHistoricalDataset: CodexHistoricalDataset?
    private var codexHistoricalDatasetAccountKey: String?
    private var historicalTrackingGeneration: UInt64 = 0
    private var lastHistoricalTrackingEnabled: Bool

    public init(
        configStore: CodexBarConfigStore = CodexBarConfigStore(),
        publisher: @escaping RowPublisher = { _ in },
        combinedPublisher: @escaping CombinedPublisher = { _, _ in },
        notificationPublisher: @escaping NotificationPublisher = { _ in },
        quotaWarningPublisher: @escaping QuotaWarningPublisher = { _ in },
        predictivePaceWarningPublisher: @escaping PredictivePaceWarningPublisher = { _ in },
        signalProvider: @escaping RefreshSignalProvider = {
            let settings = WindowsRefreshSettings.load()
            let power = WindowsPowerState.read()
            let errorCode: UInt32? = if case let .unavailable(code) = power.availability { code } else { nil }
            return RefreshSignals(
                lowPowerModeEnabled: settings.resolvedLowPowerModeEnabled(state: power),
                powerStateError: errorCode)
        })
    {
        let browserDetection = BrowserDetection()
        self.configStore = configStore
        self.browserDetection = browserDetection
        self.fetcher = UsageFetcher()
        self.claudeFetcher = ClaudeUsageFetcher(browserDetection: browserDetection)
        self.pluginApprovalStore = ProviderPluginApprovalStore()
        self.publisher = publisher
        self.combinedPublisher = combinedPublisher
        self.notificationPublisher = notificationPublisher
        self.quotaWarningPublisher = quotaWarningPublisher
        self.predictivePaceWarningPublisher = predictivePaceWarningPublisher
        self.signalProvider = signalProvider
        self.refreshSettings = WindowsRefreshSettings.load()
        self.historicalUsageHistoryStore = HistoricalUsageHistoryStore()
        self.lastHistoricalTrackingEnabled = WindowsPredictivePaceWarningSettings.load().historicalTrackingEnabled
    }

    public func setPublisher(_ publisher: @escaping RowPublisher) {
        self.publisher = publisher
    }

    public func setCombinedPublisher(_ publisher: @escaping CombinedPublisher) {
        self.combinedPublisher = publisher
        guard !self.shuttingDown else { return }
        self.publishRenderEntries(settings: WindowsUsagePresentationSettings.load())
    }

    public func setQuotaWarningPublisher(_ publisher: @escaping QuotaWarningPublisher) {
        self.quotaWarningPublisher = publisher
    }

    public func setPredictivePaceWarningPublisher(_ publisher: @escaping PredictivePaceWarningPublisher) {
        self.predictivePaceWarningPublisher = publisher
    }

    public func predictivePaceWarningSettingsDidChange(_ settings: WindowsPredictivePaceWarningSettings) async {
        guard !self.shuttingDown else { return }
        self.predictivePaceWarningGeneration &+= 1
        if !settings.notificationsEnabled { self.predictivePaceWarningKeys.removeAll(keepingCapacity: true) }
        if settings.historicalTrackingEnabled != self.lastHistoricalTrackingEnabled {
            self.historicalTrackingGeneration &+= 1
            self.lastHistoricalTrackingEnabled = settings.historicalTrackingEnabled
            if !settings.historicalTrackingEnabled {
                self.codexHistoricalDataset = nil
                self.codexHistoricalDatasetAccountKey = nil
            }
        }
        if self.refreshTask != nil {
            self.queuedPredictiveSettingsRefresh = true
            return
        }
        await self.refresh()
    }

    public func setNotificationPublisher(_ publisher: @escaping NotificationPublisher) {
        self.notificationPublisher = publisher
    }

    public func loadProviderQuotaWarningEditor(
        providerID: ProviderInstanceID) -> WindowsProviderQuotaWarningLoadResult
    {
        guard !self.shuttingDown else { return .shuttingDown }
        do {
            guard let config = try self.configStore.load(),
                  config.enabledProviders().contains(providerID),
                  let providerConfig = config.providerConfig(for: providerID)
            else { return .providerMissing }
            let global = WindowsQuotaWarningSettings.load()
            let warningConfig = providerConfig.quotaWarnings
            return .loaded(.init(
                providerID: providerID,
                session: .init(config: warningConfig?.session, globalThresholds: global.sessionThresholds),
                weekly: .init(config: warningConfig?.weekly, globalThresholds: global.weeklyThresholds)))
        } catch {
            return .failed("load: \(error.localizedDescription)")
        }
    }

    public func loadCodexWebSettings() -> WindowsCodexWebSettingsLoadResult {
        guard !self.shuttingDown else { return .shuttingDown }
        do {
            guard let config = try self.configStore.load(),
                  config.enabledProviders().contains(ProviderInstanceID.codex),
                  let providerConfig = config.providerConfig(for: ProviderInstanceID.codex)
            else { return .providerMissing }
            return .loaded(Self.codexWebSettingsSnapshot(from: providerConfig))
        } catch {
            return .failed("load: \(error.localizedDescription)")
        }
    }

    public func saveCodexWebSettings(
        patch: WindowsCodexWebSettingsPatch) -> WindowsCodexWebSettingsSaveResult
    {
        guard !self.shuttingDown else { return .shuttingDown }
        do {
            guard var config = try self.configStore.load(),
                  config.enabledProviders().contains(ProviderInstanceID.codex),
                  var providerConfig = config.providerConfig(for: ProviderInstanceID.codex)
            else { return .providerMissing }

            let current = Self.codexWebSettingsSnapshot(from: providerConfig)
            let sourceMode = patch.sourceMode ?? current.sourceMode
            let cookieSource = patch.cookieSource ?? current.cookieSource
            let resultingHeader: String?
            switch patch.manualHeader {
            case .unchanged:
                // Preserve the stored value exactly. Older configs may contain a
                // malformed header; unrelated source/cookie edits must not erase it.
                resultingHeader = providerConfig.cookieHeader
            case let .replace(raw):
                guard let normalized = Self.usableCookieHeader(raw) else {
                    return .failed("save: manual cookie header is invalid")
                }
                resultingHeader = normalized
            }

            guard !(sourceMode == .web && cookieSource == .off) else {
                return .failed("save: web source requires cookies")
            }
            guard cookieSource != .manual || Self.usableCookieHeader(resultingHeader) != nil else {
                return .failed("save: manual cookie source requires a stored header or replacement")
            }

            let resulting = WindowsCodexWebSettingsSnapshot(
                sourceMode: sourceMode,
                cookieSource: cookieSource,
                hasStoredManualHeader: Self.usableCookieHeader(resultingHeader) != nil)
            let storedSource: ProviderSourceMode? = sourceMode == .auto ? nil : sourceMode
            let storedCookieSource: ProviderCookieSource? = cookieSource == .auto ? nil : cookieSource
            let headerChanged = providerConfig.cookieHeader != resultingHeader
            let settingsChanged = providerConfig.source != storedSource ||
                providerConfig.cookieSource != storedCookieSource || headerChanged
            guard settingsChanged else {
                return .unchanged(current)
            }
            providerConfig.source = storedSource
            providerConfig.cookieSource = storedCookieSource
            providerConfig.cookieHeader = resultingHeader
            config.setProviderConfig(providerConfig)
            try self.configStore.save(config)
            self.latestProviderConfigs[ProviderInstanceID.codex] = providerConfig
            if self.refreshTask != nil {
                self.queuedCodexWebSettingsRefresh = true
            }
            return .saved(resulting)
        } catch {
            return .failed("save: \(error.localizedDescription)")
        }
    }

    private static func codexWebSettingsSnapshot(from config: ProviderConfig) -> WindowsCodexWebSettingsSnapshot {
        WindowsCodexWebSettingsSnapshot(
            sourceMode: config.source ?? .auto,
            cookieSource: config.cookieSource ?? .auto,
            hasStoredManualHeader: Self.usableCookieHeader(config.cookieHeader) != nil)
    }

    private static func usableCookieHeader(_ raw: String?) -> String? {
        guard let normalized = CookieHeaderNormalizer.normalize(raw),
              !CookieHeaderNormalizer.pairs(from: normalized).isEmpty else {
            return nil
        }
        return normalized
    }

    public func saveProviderQuotaWarnings(
        providerID: ProviderInstanceID,
        patch: WindowsProviderQuotaWarningPatch) -> WindowsProviderQuotaWarningSaveResult
    {
        guard !self.shuttingDown else { return .shuttingDown }
        let loadedConfig: CodexBarConfig?
        do {
            loadedConfig = try self.configStore.load()
        } catch {
            return .failed("load: \(error.localizedDescription)")
        }
        do {
            guard var config = loadedConfig,
                  config.enabledProviders().contains(providerID),
                  var providerConfig = config.providerConfig(for: providerID)
            else { return .providerMissing }

            let global = WindowsQuotaWarningSettings.load()
            let current = providerConfig.quotaWarnings
            let updatedSession = Self.applyQuotaWarningPatch(patch.session, to: current?.session)
            let updatedWeekly = Self.applyQuotaWarningPatch(patch.weekly, to: current?.weekly)
            let updatedWarningConfig = QuotaWarningConfig(session: updatedSession, weekly: updatedWeekly)
            let normalizedWarningConfig: QuotaWarningConfig? = updatedWarningConfig.isEmpty ? nil : updatedWarningConfig
            guard normalizedWarningConfig != current else {
                return .unchanged(.init(
                    providerID: providerID,
                    session: .init(config: current?.session, globalThresholds: global.sessionThresholds),
                    weekly: .init(config: current?.weekly, globalThresholds: global.weeklyThresholds)))
            }
            providerConfig.quotaWarnings = normalizedWarningConfig
            config.setProviderConfig(providerConfig)
            try self.configStore.save(config)
            let enabledIDs = Set(config.enabledProviders())
            self.latestEnabledProviderIDs = enabledIDs
            self.predictivePaceWarningKeys = self.predictivePaceWarningKeys.filter {
                enabledIDs.contains($0.provider.instanceID)
            }
            self.latestProviderConfigs = enabledIDs.reduce(into: [:]) { result, id in
                if result[id] == nil, let config = config.providerConfig(for: id) {
                    result[id] = config
                }
            }
            self.quotaWarningGeneration &+= 1
            let latestGlobal = WindowsQuotaWarningSettings.load()
            self.quotaWarningStates = self.quotaWarningStates.filter { key, _ in
                guard enabledIDs.contains(key.provider.instanceID) else { return false }
                let settings = self.latestProviderConfigs[key.provider.instanceID].map {
                    latestGlobal.resolved(providerConfig: $0)
                } ?? latestGlobal
                return settings.isEnabled(for: key.lane)
            }
            return .saved(.init(
                providerID: providerID,
                session: .init(config: normalizedWarningConfig?.session, globalThresholds: global.sessionThresholds),
                weekly: .init(config: normalizedWarningConfig?.weekly, globalThresholds: global.weeklyThresholds)))
        } catch {
            return .failed("save: \(error.localizedDescription)")
        }
    }

    private static func applyQuotaWarningPatch(
        _ patch: WindowsProviderQuotaWarningLanePatch,
        to original: QuotaWarningWindowConfig?) -> QuotaWarningWindowConfig?
    {
        switch patch {
        case .unchanged: return original
        case .clear: return nil
        case let .replace(config): return config.hasOverride ? config : nil
        }
    }

    /// Applies a global threshold edit without refreshing providers. Existing
    /// episodes remain intact; only lanes that are now effectively disabled are
    /// removed from the transition state cache.
    public func quotaWarningSettingsDidChange(_ settings: WindowsQuotaWarningSettings) async {
        guard !self.shuttingDown else { return }
        guard let enabledProviders = self.latestEnabledProviderIDs else { return }
        self.quotaWarningStates = self.quotaWarningStates.filter { key, _ in
            guard enabledProviders.contains(key.provider.instanceID) else { return false }
            let providerSettings = self.latestProviderConfigs[key.provider.instanceID].map {
                settings.resolved(providerConfig: $0)
            } ?? settings
            return providerSettings.isEnabled(for: key.lane)
        }
    }

    public func sessionQuotaNotificationSettingsDidChange() async {
        guard !self.shuttingDown else { return }
        if !self.sessionQuotaNotificationsEnabled() {
            self.codexSessionQuotaBaselineWatermark = max(self.codexSessionQuotaBaselineWatermark ?? .distantPast, self.sessionQuotaStates[UsageProvider.codex.instanceID]?.observedAt ?? .distantPast)
        }
    }

    /// Re-renders retained snapshots after display-only preferences change.
    /// No provider network request is performed.
    public func presentationSettingsDidChange() async {
        guard !self.shuttingDown, !self.renderEntries.isEmpty else { return }
        self.publishRenderEntries(settings: WindowsUsagePresentationSettings.load())
    }

    /// Applies the optional-usage setting change. Disabling only re-renders
    /// retained snapshots; enabling requests one refresh, coalesced behind an
    /// in-flight refresh when necessary.
    public func optionalUsageSettingsDidChange() async {
        guard !self.shuttingDown else { return }
        let showOptionalUsage = WindowsUsagePresentationSettings.load().showOptionalCreditsAndExtraUsage
        guard showOptionalUsage else {
            self.queuedOptionalRefresh = false
            guard !self.renderEntries.isEmpty else { return }
            self.publishRenderEntries(settings: WindowsUsagePresentationSettings.load())
            return
        }
        if self.refreshTask != nil {
            self.queuedOptionalRefresh = true
            return
        }
        await self.refresh()
    }

    /// Re-reads the persisted cadence and replaces the automatic scheduler.
    /// The active provider refresh is left untouched; changing frequency does
    /// not trigger an additional network request.
    public func refreshSettingsDidChange() async {
        guard !self.shuttingDown else { return }
        let settings = WindowsRefreshSettings.load()
        self.refreshSettings = settings
        guard self.started else { return }
        self.scheduleGeneration &+= 1
        let generation = self.scheduleGeneration
        // A cadence restart invalidates any boundary task created from the
        // previous interval. Clear both the task and marker so a later pass
        // can schedule an identical boundary again.
        self.cancelResetBoundaryRefresh()
        let oldSchedule = self.scheduleTask
        self.scheduleTask = nil
        self.sleepTask?.cancel()
        self.sleepTask = nil
        self.scheduledDeadline = nil
        oldSchedule?.cancel()
        if let oldSchedule { await oldSchedule.value }

        guard !self.shuttingDown, generation == self.scheduleGeneration,
              settings.frequency != .manual,
              settings.frequency != .adaptiveAgentAware
        else { return }
        self.scheduleTask = Task { [weak self] in
            guard let self else { return }
            await self.runRefreshSchedule(generation: generation)
        }
    }

    /// Performs the initial refresh and starts the selected cadence exactly once.
    public func start() async {
        guard !self.shuttingDown, !self.started else { return }
        self.started = true
        self.refreshSettings = WindowsRefreshSettings.load()
        self.scheduleGeneration &+= 1
        let generation = self.scheduleGeneration
        self.scheduleTask = Task { [weak self] in
            guard let self else { return }
            await self.runStartupConnectivityRefresh(attempt: 0)
            await self.runRefreshSchedule(generation: generation)
        }
    }

    public func noteMenuOpened(at date: Date = Date()) {
        self.lastMenuOpenedAt = date
        guard self.refreshSettings.frequency.usesAdaptivePolicy,
              self.refreshSettings.frequency != .adaptiveAgentAware
        else { return }
        let signals = self.signalProvider()
        let decision = AdaptiveRefreshPolicyCore().nextDelay(for: .init(
            now: date,
            lastMenuOpenAt: date,
            lastCodingActivityAt: nil,
            lowPowerModeEnabled: signals.lowPowerModeEnabled,
            thermalPressure: signals.thermalConstrained ? .constrained : .nominal))
        let candidate = ContinuousClock.now + decision.delay
        if self.scheduledDeadline.map({ candidate < $0 }) ?? true {
            self.scheduledDeadline = candidate
            self.sleepTask?.cancel()
        }
    }

    public func notePowerChanged() {
        guard !self.shuttingDown else { return }
        // Battery Saver changes the effective automatic floor. Re-evaluate a
        // pending reset-boundary refresh even when the normal scheduler is
        // currently asleep or absent.
        self.scheduleResetBoundaryRefreshIfNeeded(
            snapshots: self.currentSnapshots(from: self.renderEntries),
            now: Date())
        guard self.refreshSettings.frequency != .manual,
              self.refreshSettings.frequency != .adaptiveAgentAware,
              self.sleepTask != nil
        else { return }
        let signals = self.signalProvider()
        let delay: Duration
        if let baseSeconds = self.refreshSettings.frequency.seconds {
            delay = .seconds(signals.lowPowerModeEnabled ? max(baseSeconds, 1800) : baseSeconds)
        } else {
            delay = AdaptiveRefreshPolicyCore().nextDelay(for: .init(
                now: Date(),
                lastMenuOpenAt: self.lastMenuOpenedAt,
                lowPowerModeEnabled: signals.lowPowerModeEnabled,
                thermalPressure: signals.thermalConstrained ? .constrained : .nominal)).delay
        }
        self.scheduledDeadline = ContinuousClock.now + delay
        self.sleepTask?.cancel()
    }

    /// Refreshes enabled providers once. A second request while a
    /// refresh is in flight is intentionally coalesced instead of overlapping
    /// credential and warm-session work.
    public func refresh() async {
        guard !self.shuttingDown, self.refreshTask == nil else { return }
        repeat {
            let task: Task<Void, Never> = Task { [weak self] in
                guard let self else { return }
                await self.performRefresh()
            }
            self.refreshTask = task
            await task.value
            self.refreshTask = nil
            let optionalRefreshNeeded = self.queuedOptionalRefresh &&
                WindowsUsagePresentationSettings.load().showOptionalCreditsAndExtraUsage
            let predictiveSettingsRefreshNeeded = self.queuedPredictiveSettingsRefresh
            let codexWebSettingsRefreshNeeded = self.queuedCodexWebSettingsRefresh
            guard !self.shuttingDown,
                  optionalRefreshNeeded || predictiveSettingsRefreshNeeded || codexWebSettingsRefreshNeeded
            else {
                self.queuedOptionalRefresh = false
                self.queuedPredictiveSettingsRefresh = false
                self.queuedCodexWebSettingsRefresh = false
                break
            }
            self.queuedOptionalRefresh = false
            self.queuedPredictiveSettingsRefresh = false
            self.queuedCodexWebSettingsRefresh = false
        }
        while !self.shuttingDown
        self.resumeRefreshCompletionWaiters()
    }

    private func performRefresh() async {
        let refreshQuotaWarningGeneration = self.quotaWarningGeneration
        let refreshPredictivePaceWarningGeneration = self.predictivePaceWarningGeneration
        let refreshHistoricalTrackingGeneration = self.historicalTrackingGeneration
        let presentationSettings = WindowsUsagePresentationSettings.load()
        let fetchOptionalUsage = presentationSettings.showOptionalCreditsAndExtraUsage
        do {
            if !self.pluginDiscoveryInitialized {
                _ = UserProviderPluginRegistry.refresh()
                self.pluginDiscoveryInitialized = true
            }
            let config = try self.configStore.loadOrCreateDefault()
            let enabledIDs = Set(config.enabledProviders())
            self.latestEnabledProviderIDs = enabledIDs
            self.predictivePaceWarningKeys = self.predictivePaceWarningKeys.filter {
                enabledIDs.contains($0.provider.instanceID)
            }
            self.latestProviderConfigs = enabledIDs.reduce(into: [:]) { result, id in
                if result[id] == nil, let providerConfig = config.providerConfig(for: id) {
                    result[id] = providerConfig
                }
            }
            self.sessionQuotaStates = self.sessionQuotaStates.filter { enabledIDs.contains($0.key) }
            self.quotaWarningStates = self.quotaWarningStates.filter { enabledIDs.contains($0.key.provider.instanceID) }
            for instanceID in config.enabledProviders() {
                guard let provider = instanceID.firstPartyProvider else { continue }
                let accounts = config.providerConfig(for: instanceID)?.tokenAccounts?.accounts ?? []
                if accounts.isEmpty { self.dashboardContextCache.removeValue(forKey: instanceID) }
            }
            // Publish the current config's status rows before account resolution can fail.
            self.statusMenuEntries = config.enabledProviders().compactMap { instanceID in
                guard let provider = instanceID.firstPartyProvider else { return nil }
                let metadata = ProviderDescriptorRegistry.descriptor(for: provider).metadata
                return WindowsTrayMenuEntry(
                    providerID: provider.rawValue,
                    title: metadata.displayName,
                    statusURL: metadata.statusPageURL ?? metadata.statusLinkURL,
                    dashboardVisible: metadata.dashboardURL != nil,
                    changelogURL: metadata.changelogURL,
                    changelogVisible: metadata.changelogURL != nil,
                    disabledText: metadata.statusPageURL == nil && metadata.statusLinkURL == nil ? "unavailable" : nil)
            }
            let accountContext = try TokenAccountCLIContext(
                selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: false),
                config: config,
                verbose: false)
            // Capture Codex reconciliation once for this refresh. Every fetch,
            // settings/environment projection, and history decision must share
            // this same snapshot so an account switch cannot mix owners.
            let codexAccountContext: CodexAccountContextSnapshot? = enabledIDs.contains(UsageProvider.codex.instanceID)
                ? accountContext.codexAccountContextSnapshot() : nil
            var entries: [RenderEntry] = []
            self.presentations.removeAll(keepingCapacity: true)
            if let errorCode = self.signalProvider().powerStateError {
                entries.append(.row("Windows power status unavailable (error \(errorCode))"))
            }
            for instanceID in config.enabledProviders() {
                try Task.checkCancellation()
                guard let provider = instanceID.firstPartyProvider else {
                    let fetched = await self.fetchPluginRows(
                        instanceID: instanceID,
                        config: config,
                        presentationSettings: presentationSettings)
                    if let presentation = self.presentations[instanceID] { entries.append(.presentation(presentation)) }
                    else { entries.append(contentsOf: fetched.map(RenderEntry.row)) }
                    continue
                }
                if provider == .codex {
                    guard let codexAccountContext else { continue }
                    let configuredAccounts = try? accountContext.resolvedAccounts(for: provider)
                    if let configuredAccounts, !configuredAccounts.isEmpty {
                        let fetched = await self.fetchRows(
                            provider: provider,
                            context: accountContext,
                            config: config,
                            codexAccountContext: codexAccountContext,
                            presentationSettings: presentationSettings,
                            quotaWarningGeneration: refreshQuotaWarningGeneration,
                            predictivePaceWarningGeneration: refreshPredictivePaceWarningGeneration,
                            historicalTrackingGeneration: refreshHistoricalTrackingGeneration)
                        if let presentation = self.presentations[provider.instanceID] { entries.append(.presentation(presentation)) }
                        else { entries.append(contentsOf: fetched.map(RenderEntry.row)) }
                    } else {
                        let projection = codexAccountContext.visibleAccounts
                        let active = projection.visibleAccounts.first {
                            $0.id == projection.activeVisibleAccountID
                        }
                        let fetched = await self.fetchRows(
                            provider: provider,
                            context: accountContext,
                            config: config,
                            codexVisibleAccount: active,
                            codexAccountContext: active.flatMap { codexAccountContext.selecting(activeSource: $0.selectionSource) },
                            presentationSettings: presentationSettings,
                            quotaWarningGeneration: refreshQuotaWarningGeneration,
                            predictivePaceWarningGeneration: refreshPredictivePaceWarningGeneration,
                            historicalTrackingGeneration: refreshHistoricalTrackingGeneration)
                        if let presentation = self.presentations[provider.instanceID] { entries.append(.presentation(presentation)) }
                        else { entries.append(contentsOf: fetched.map(RenderEntry.row)) }
                    }
                } else {
                    let fetched = await self.fetchRows(
                        provider: provider,
                        context: accountContext,
                        config: config,
                        codexAccountContext: nil,
                        presentationSettings: presentationSettings,
                        quotaWarningGeneration: refreshQuotaWarningGeneration,
                        predictivePaceWarningGeneration: refreshPredictivePaceWarningGeneration,
                        historicalTrackingGeneration: refreshHistoricalTrackingGeneration)
                    if let presentation = self.presentations[provider.instanceID] { entries.append(.presentation(presentation)) }
                    else { entries.append(contentsOf: fetched.map(RenderEntry.row)) }
                }
            }
            let zaiUsageScope: ZaiUsageScope? = (try? accountContext.resolvedAccounts(for: .zai).first)
                .flatMap { $0.sanitizedUsageScope.flatMap(ZaiUsageScope.init(rawValue:)) }
            self.statusMenuEntries = config.enabledProviders().compactMap { instanceID in
                guard let provider = instanceID.firstPartyProvider else { return nil }
                let metadata = ProviderDescriptorRegistry.descriptor(for: provider).metadata
                let account = (try? accountContext.resolvedAccounts(for: provider).first) ?? nil
                if account == nil { self.dashboardContextCache.removeValue(forKey: instanceID) }
                let environment = accountContext.environment(
                    base: ProcessInfo.processInfo.environment,
                    provider: provider,
                    account: account,
                    codexAccountContext: provider == .codex ? codexAccountContext : nil)
                let presentation = self.presentations[instanceID]
                let providerConfig = config.providerConfig(for: instanceID)
                let digest: (String?) -> String? = { value in
                    guard let value else { return nil }
                    return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
                }
                let key = DashboardContextKey(
                    accountID: account?.id,
                    accountScope: account?.sanitizedUsageScope,
                    accountOrganization: account?.sanitizedOrganizationID,
                    accountWorkspace: account?.sanitizedWorkspaceID,
                    accountTokenDigest: digest(account?.token),
                    region: providerConfig?.region,
                    workspaceID: providerConfig?.workspaceID,
                    cookieSource: providerConfig?.cookieSource,
                    cookieDigest: digest(providerConfig?.cookieHeader),
                    apiKeyDigest: digest(providerConfig?.apiKey),
                    secretKeyDigest: digest(providerConfig?.secretKey),
                    source: providerConfig?.source)
                let cached = key.accountID == nil ? nil : self.dashboardContextCache[instanceID]
                let cachedMatches = cached?.key == key
                let sourceLabel = presentation?.result?.sourceLabel ?? (cachedMatches ? cached?.sourceLabel : nil)
                let claudeLoginMethod = presentation?.snapshot.identity?.loginMethod ?? (cachedMatches ? cached?.claudeLoginMethod : nil)
                let cachedScope = cachedMatches ? cached?.zaiUsageScope : nil
                let dashboardURL = WindowsDashboardResolver.resolve(
                    provider: provider,
                    config: config,
                    sourceLabel: sourceLabel,
                    claudeLoginMethod: claudeLoginMethod,
                    zaiUsageScope: provider == .zai ? (zaiUsageScope ?? cachedScope) : nil,
                    environment: environment)
                if presentation != nil {
                    if key.accountID != nil {
                        self.dashboardContextCache[instanceID] = DashboardContext(
                            key: key,
                            sourceLabel: presentation?.result?.sourceLabel,
                            claudeLoginMethod: presentation?.snapshot.identity?.loginMethod,
                            zaiUsageScope: provider == .zai ? zaiUsageScope : nil)
                    } else {
                        self.dashboardContextCache.removeValue(forKey: instanceID)
                    }
                }
                return WindowsTrayMenuEntry(
                    providerID: provider.rawValue,
                    title: metadata.displayName,
                    statusURL: metadata.statusPageURL ?? metadata.statusLinkURL,
                    dashboardURL: dashboardURL?.absoluteString,
                    dashboardVisible: metadata.dashboardURL != nil,
                    changelogURL: metadata.changelogURL,
                    changelogVisible: metadata.changelogURL != nil,
                    disabledText: metadata.statusPageURL == nil && metadata.statusLinkURL == nil ? "unavailable" : nil)
            }
            if self.refreshSettings.frequency == .adaptiveAgentAware
            {
                entries.append(.row("Windows activity scanner unavailable; automatic refresh disabled"))
            }
            guard !self.shuttingDown else { return }
            let latestOptionalUsage = WindowsUsagePresentationSettings.load().showOptionalCreditsAndExtraUsage
            if !fetchOptionalUsage && latestOptionalUsage {
                self.queuedOptionalRefresh = true
                return
            }
            self.renderEntries = entries
            self.scheduleResetBoundaryRefreshIfNeeded(
                snapshots: self.currentSnapshots(from: entries),
                now: Date())
            self.publishRenderEntries(settings: WindowsUsagePresentationSettings.load())
        } catch is CancellationError {
            return
        } catch {
            self.recordStartupConnectivityRetryableFailure(error)
            let message = "CodexBar: \(error.localizedDescription)"
            guard !self.shuttingDown else { return }
            let latestOptionalUsage = WindowsUsagePresentationSettings.load().showOptionalCreditsAndExtraUsage
            if !fetchOptionalUsage && latestOptionalUsage {
                self.queuedOptionalRefresh = true
                return
            }
            self.renderEntries = [.row(message)]
            self.scheduleResetBoundaryRefreshIfNeeded(snapshots: [:], now: Date())
            self.publishRenderEntries(settings: WindowsUsagePresentationSettings.load())
        }
    }

    private func publishRenderEntries(settings: WindowsUsagePresentationSettings) {
        guard !self.shuttingDown else { return }
        let rendered = self.renderEntries.flatMap { entry -> [String] in
            switch entry {
            case let .presentation(presentation):
                let updated = WindowsUsagePresentation(
                    instanceID: presentation.instanceID, provider: presentation.provider,
                    title: presentation.title, privacyTitle: presentation.privacyTitle,
                    result: presentation.result, snapshot: presentation.snapshot,
                    hidePersonalInfo: settings.hidePersonalInfo,
                    showOptionalUsage: settings.showOptionalCreditsAndExtraUsage,
                    usageBarsShowUsed: settings.usageBarsShowUsed,
                    resetTimesShowAbsolute: settings.resetTimesShowAbsolute)
                return updated.rows()
            case let .row(row): return [row]
            }
        }
        let displayRows = rendered.isEmpty ? ["No providers are enabled"] : rendered
        let publishedRows = settings.hidePersonalInfo ? displayRows.map { LogRedactor.redact($0) } : displayRows
        self.publisher(publishedRows)
        self.combinedPublisher(publishedRows, self.statusMenuEntries)
    }

    public func shutdown() async {
        guard !self.shuttingDown else { return }
        self.shuttingDown = true
        self.scheduleGeneration &+= 1
        self.queuedOptionalRefresh = false
        self.queuedPredictiveSettingsRefresh = false
        self.queuedCodexWebSettingsRefresh = false
        let task = self.refreshTask
        task?.cancel()
        self.startupConnectivityRetryTask?.cancel()
        self.sleepTask?.cancel()
        self.resetBoundaryRefreshTask?.cancel()
        let schedule = self.scheduleTask
        schedule?.cancel()
        if let schedule { await schedule.value }
        self.scheduleTask = nil
        self.sleepTask = nil
        self.resetBoundaryRefreshTask = nil
        self.scheduledResetBoundaryRefreshAt = nil
        if let task { await task.value }
        self.refreshTask = nil
        self.resumeRefreshCompletionWaiters()
        self.startupConnectivityRetryTask = nil
        self.startupConnectivityRetryActive = false
        self.startupConnectivityRetryNeeded = false
        self.sessionQuotaStates.removeAll(keepingCapacity: false)
        self.codexSessionQuotaBaselineWatermark = nil
        self.quotaWarningStates.removeAll(keepingCapacity: false)
        self.predictivePaceWarningKeys.removeAll(keepingCapacity: false)
        self.historicalTrackingGeneration &+= 1
        self.codexHistoricalDataset = nil
        self.codexHistoricalDatasetAccountKey = nil
        self.latestProviderConfigs.removeAll(keepingCapacity: false)
        self.latestEnabledProviderIDs = nil
        await CLIProbeSessionResetter.resetAll()
    }

    private func sessionQuotaNotificationsEnabled() -> Bool {
        UserDefaults(suiteName: WindowsRefreshSettings.suiteName)?.object(forKey: "sessionQuotaNotificationsEnabled") as? Bool ?? true
    }

    private func evaluateSessionQuota(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        codexVisibleAccount: CodexVisibleAccount?,
        tokenAccount: ProviderTokenAccount?)
    {
        guard !self.shuttingDown else { return }
        let enabled = self.sessionQuotaNotificationsEnabled()
        let ownerKey = provider == .codex
            ? self.codexSessionOwnerKey(snapshot: snapshot, visibleAccount: codexVisibleAccount, tokenAccount: tokenAccount)
            : nil
        if provider == .codex, !enabled {
            self.codexSessionQuotaBaselineWatermark = max(
                max(
                    self.codexSessionQuotaBaselineWatermark ?? .distantPast,
                    self.sessionQuotaStates[UsageProvider.codex.instanceID]?.observedAt ?? .distantPast),
                snapshot.updatedAt)
            self.sessionQuotaStates.removeValue(forKey: provider.instanceID)
            return
        }
        guard provider != .codex || ownerKey != nil else {
            self.codexSessionQuotaBaselineWatermark = max(
                max(self.codexSessionQuotaBaselineWatermark ?? .distantPast,
                    self.sessionQuotaStates[provider.instanceID]?.observedAt ?? .distantPast),
                snapshot.updatedAt)
            self.sessionQuotaStates.removeValue(forKey: provider.instanceID)
            return
        }
        if provider == .codex,
           let watermark = self.codexSessionQuotaBaselineWatermark,
           snapshot.updatedAt <= watermark
        {
            return
        }
        guard let selected = SessionQuotaTransitionCore.sessionWindow(provider: provider, snapshot: snapshot) else {
            if provider == .codex {
                if let previous = self.sessionQuotaStates[provider.instanceID], previous.codexOwnerKey != ownerKey {
                    self.codexSessionQuotaBaselineWatermark = max(
                        max(self.codexSessionQuotaBaselineWatermark ?? .distantPast, previous.observedAt),
                        snapshot.updatedAt)
                    self.sessionQuotaStates.removeValue(forKey: provider.instanceID)
                } else if let previous = self.sessionQuotaStates[provider.instanceID] {
                    self.sessionQuotaStates[provider.instanceID] = previous.advancingObservationWatermark(
                        to: snapshot.updatedAt)
                } else if let watermark = self.codexSessionQuotaBaselineWatermark {
                    self.codexSessionQuotaBaselineWatermark = max(watermark, snapshot.updatedAt)
                }
            } else {
                self.sessionQuotaStates.removeValue(forKey: provider.instanceID)
            }
            return
        }
        guard !selected.window.isSyntheticPlaceholder else { return }
        let forceBaseline = provider == .codex && self.codexSessionQuotaBaselineWatermark != nil
        if forceBaseline { self.codexSessionQuotaBaselineWatermark = nil }
        let evaluation = SessionQuotaTransitionCore.evaluate(
            previous: self.sessionQuotaStates[provider.instanceID],
            observation: .init(provider: provider, remaining: selected.window.remainingPercent, source: selected.source, resetBoundary: selected.window.resetsAt, observedAt: snapshot.updatedAt, evaluationTime: Date(), codexOwnerKey: ownerKey),
            notificationsEnabled: enabled,
            forceBaseline: forceBaseline)
        self.sessionQuotaStates[provider.instanceID] = evaluation.state
        guard enabled, !forceBaseline, evaluation.outcome.transition != .none else { return }
        let restored = evaluation.outcome.transition == .restored
        let providerName = ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
        self.notificationPublisher(.init(
            title: "\(providerName) session \(restored ? "restored" : "depleted")",
            body: restored ? "Session quota is available again." : "0% left. Will notify when it's available again."))
    }

    private func evaluateQuotaWarnings(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        codexVisibleAccount: CodexVisibleAccount?,
        tokenAccount: ProviderTokenAccount?,
        environment: [String: String],
        config: CodexBarConfig,
        claudeAccountUUIDBefore: String?,
        claudeAccountUUIDAfter: String?,
        strategyKind: ProviderFetchKind? = nil,
        oauthHistoryOwnerIdentifier: String? = nil,
        quotaWarningGeneration: UInt64)
    {
        guard !self.shuttingDown, quotaWarningGeneration == self.quotaWarningGeneration else { return }
        let globalSettings = WindowsQuotaWarningSettings.load()
        let settings = config.providerConfig(for: provider.instanceID).map {
            globalSettings.resolved(providerConfig: $0)
        } ?? globalSettings
        guard settings.notificationsEnabled else { return }
        let accountDiscriminator = self.quotaAccountDiscriminator(provider: provider, snapshot: snapshot,
            codexVisibleAccount: codexVisibleAccount, tokenAccount: tokenAccount, environment: environment,
            strategyKind: strategyKind, oauthHistoryOwnerIdentifier: oauthHistoryOwnerIdentifier,
            claudeAccountUUIDBefore: claudeAccountUUIDBefore, claudeAccountUUIDAfter: claudeAccountUUIDAfter)
        let selection = QuotaWarningTransitionCore.candidates(provider: provider, snapshot: snapshot,
            accountDiscriminator: accountDiscriminator)
        for window in QuotaWarningWindow.allCases {
            guard settings.isEnabled(for: window) else {
                self.quotaWarningStates = self.quotaWarningStates.filter { $0.key.provider != provider || $0.key.lane != window }
                continue
            }
            let candidate = selection.candidates.first { $0.key.lane == window && $0.key.windowID == nil }
            if let candidate {
                self.evaluateCandidate(candidate, settings: settings, accountDisplayName: WindowsUsagePresentationSettings.load().hidePersonalInfo ? nil : snapshot.accountEmail(for: provider))
            } else {
                self.quotaWarningStates.removeValue(forKey: .init(provider: provider, lane: window, accountDiscriminator: accountDiscriminator))
            }
        }
        for candidate in selection.candidates where candidate.key.windowID != nil && settings.isEnabled(for: candidate.key.lane) {
            self.evaluateCandidate(candidate, settings: settings, accountDisplayName: WindowsUsagePresentationSettings.load().hidePersonalInfo ? nil : snapshot.accountEmail(for: provider))
        }
        if selection.reconciliation.authoritative {
            self.quotaWarningStates = self.quotaWarningStates.filter { key, _ in
                key.provider != provider || key.accountDiscriminator != accountDiscriminator || key.windowID == nil || selection.reconciliation.recognizedExtraWindowIDs.contains(key.windowID!)
            }
        }
    }

    private func evaluateCandidate(_ candidate: QuotaWarningTransitionCore.Candidate?, settings: WindowsQuotaWarningSettings, accountDisplayName: String?) {
        guard let candidate else { return }
        let key = candidate.key
        let evaluation = QuotaWarningTransitionCore.evaluate(previous: self.quotaWarningStates[key], current: candidate.window,
            source: candidate.source, thresholds: settings.thresholds(for: key.lane), enabled: true)
        if let state = evaluation.state { self.quotaWarningStates[key] = state }
        if case let .warning(threshold) = evaluation.outcome {
            let providerName = ProviderDescriptorRegistry.descriptor(for: key.provider).metadata.displayName
            self.quotaWarningPublisher(.init(providerName: providerName, window: key.lane, threshold: threshold,
                currentRemaining: candidate.window.remainingPercent, accountDisplayName: accountDisplayName, windowDisplayLabel: candidate.displayLabel))
        }
    }

    private func codexHistoricalOwnership(
        snapshot: UsageSnapshot,
        codexVisibleAccount: CodexVisibleAccount?,
        codexAccountContext: CodexAccountContextSnapshot,
        preferredEmail: String? = nil) -> CodexHistoricalOwnershipContext
    {
        let source = codexVisibleAccount?.selectionSource
            ?? codexAccountContext.resolvedActiveSource.resolvedSource
        let selectedContext = codexAccountContext.selecting(activeSource: source)
        let identity = selectedContext.identity(for: source)
        let normalizedEmail = CodexIdentityResolver.normalizeEmail(
            preferredEmail ?? codexVisibleAccount?.email ?? snapshot.accountEmail(for: .codex))
            ?? (if case let .emailOnly(email) = identity {
                CodexIdentityResolver.normalizeEmail(email)
            } else {
                nil
            })
        let resolvedIdentity: CodexIdentity = switch identity {
        case .unresolved:
            if case .liveSystem = source, let normalizedEmail {
                .emailOnly(normalizedEmail: normalizedEmail)
            } else {
                .unresolved
            }
        default:
            identity
        }
        return CodexHistoricalOwnershipContext.resolve(
            identity: resolvedIdentity,
            normalizedEmail: normalizedEmail,
            currentWeeklyResetAt: CodexProviderDescriptor.predictivePaceSourceWindows(snapshot: snapshot).weekly?.resetsAt,
            snapshot: selectedContext.reconciliationSnapshot,
            projection: selectedContext.visibleAccounts,
            includeVisibleAccounts: codexVisibleAccount != nil)
    }

    private func recordCodexHistoricalSampleIfNeeded(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        authorizedDashboard: CodexAuthorizedDashboard?,
        codexVisibleAccount: CodexVisibleAccount?,
        codexAccountContext: CodexAccountContextSnapshot?,
        generation: UInt64) async
    {
        guard provider == .codex else { return }
        let settings = WindowsPredictivePaceWarningSettings.load()
        guard !self.shuttingDown, settings.historicalTrackingEnabled,
              generation == self.historicalTrackingGeneration,
              self.latestEnabledProviderIDs?.contains(UsageProvider.codex.instanceID) == true
        else { return }
        guard let codexAccountContext else { return }
        let ownership = self.codexHistoricalOwnership(
            snapshot: snapshot,
            codexVisibleAccount: codexVisibleAccount,
            codexAccountContext: codexAccountContext)
        guard let owner = ownership.canonicalKey else {
            // Missing identity is not evidence that the current owner disappeared.
            return
        }
        let liveWeekly = CodexProviderDescriptor.predictivePaceSourceWindows(snapshot: snapshot).weekly
        var datasetOwnership = ownership
        if let liveWeekly, liveWeekly.resetsAt != nil, liveWeekly.windowMinutes != nil {
            // Persist only canonical live records; legacy continuity is admitted only when
            // the captured ownership context proves it belongs to this account.
            _ = await self.historicalUsageHistoryStore.recordCodexWeekly(
                window: liveWeekly, sampledAt: snapshot.updatedAt, accountKey: owner)
            guard !self.shuttingDown,
                  generation == self.historicalTrackingGeneration,
                  self.latestEnabledProviderIDs?.contains(UsageProvider.codex.instanceID) == true,
                  WindowsPredictivePaceWarningSettings.load().historicalTrackingEnabled
            else { return }
        }

        // Windows currently has no native web-dashboard producer. This consumer only
        // accepts an already authorized bundle returned by the shared provider fetch path.
        if let authorizedDashboard,
           let dashboardOwner = Self.dashboardBackfillOwner(authorizedDashboard),
           dashboardOwner == owner,
           let candidate = CodexHistoricalDashboardBackfillCore.candidate(
               authorizedDashboard: authorizedDashboard,
               fallbackWeekly: liveWeekly,
               fallbackUpdatedAt: snapshot.updatedAt)
        {
            let backfillOwnership = self.codexHistoricalOwnership(
                snapshot: snapshot,
                codexVisibleAccount: codexVisibleAccount,
                codexAccountContext: codexAccountContext,
                preferredEmail: candidate.attachedAccountEmail)
            guard backfillOwnership.canonicalKey == owner,
                  backfillOwnership.canonicalKey == dashboardOwner
            else { return }
            datasetOwnership = backfillOwnership
            // A dashboard may provide its own weekly window, so live weekly usage is optional.
            _ = await self.historicalUsageHistoryStore.backfillCodexWeeklyFromUsageBreakdown(
                candidate.usageBreakdown,
                referenceWindow: candidate.referenceWindow,
                now: candidate.calibrationAt,
                accountKey: backfillOwnership.canonicalKey)
            guard !self.shuttingDown,
                  generation == self.historicalTrackingGeneration,
                  self.latestEnabledProviderIDs?.contains(UsageProvider.codex.instanceID) == true,
                  WindowsPredictivePaceWarningSettings.load().historicalTrackingEnabled
            else { return }
        }

        guard !self.shuttingDown,
              generation == self.historicalTrackingGeneration,
              self.latestEnabledProviderIDs?.contains(UsageProvider.codex.instanceID) == true,
              WindowsPredictivePaceWarningSettings.load().historicalTrackingEnabled
        else { return }
        let dataset = await self.historicalUsageHistoryStore.loadCodexDataset(
            canonicalAccountKey: owner,
            canonicalEmailHashKey: datasetOwnership.hasAdjacentEmailScopeAmbiguity ? nil : datasetOwnership.canonicalEmailHashKey,
            legacyEmailHash: datasetOwnership.hasAdjacentEmailScopeAmbiguity ? nil : datasetOwnership.historicalLegacyEmailHash,
            hasAdjacentMultiAccountVeto: datasetOwnership.hasAdjacentMultiAccountVeto)
        guard !self.shuttingDown,
              generation == self.historicalTrackingGeneration,
              self.latestEnabledProviderIDs?.contains(UsageProvider.codex.instanceID) == true,
              WindowsPredictivePaceWarningSettings.load().historicalTrackingEnabled
        else { return }
        self.codexHistoricalDatasetAccountKey = owner
        self.codexHistoricalDataset = dataset
    }

    /// Returns the canonical owner proven by the authorized dashboard bundle.
    /// Unresolved identities use the bundle's scoped expected or trusted usage email;
    /// routing hints and raw dashboard fields are intentionally excluded.
    private static func dashboardBackfillOwner(_ authorized: CodexAuthorizedDashboard) -> String? {
        let proof = authorized.input.proof
        let identity: CodexIdentity
        switch proof.currentIdentity {
        case .unresolved:
            // Authority evaluation permits unresolved continuity only when the
            // trusted usage email matches the exact dashboard snapshot. A scoped
            // expected email is equally proven when present; never derive owner
            // identity from the dashboard payload or routing hints.
            guard let email = CodexIdentityResolver.normalizeEmail(
                proof.expectedScopedEmail ?? proof.trustedCurrentUsageEmail)
            else {
                return nil
            }
            identity = .emailOnly(normalizedEmail: email)
        default:
            identity = proof.currentIdentity
        }
        return CodexHistoryOwnership.canonicalKey(for: identity)
    }

    private func evaluatePredictivePaceWarnings(
        provider: UsageProvider, snapshot: UsageSnapshot,
        predictivePaceWarningGeneration: UInt64,
        codexVisibleAccount: CodexVisibleAccount?, tokenAccount: ProviderTokenAccount?,
        codexAccountContext: CodexAccountContextSnapshot?,
        environment: [String: String],
        claudeAccountUUIDBefore: String?, claudeAccountUUIDAfter: String?,
        strategyKind: ProviderFetchKind?, oauthHistoryOwnerIdentifier: String?)
    {
        let settings = WindowsPredictivePaceWarningSettings.load()
        guard !self.shuttingDown,
              predictivePaceWarningGeneration == self.predictivePaceWarningGeneration,
              self.latestEnabledProviderIDs?.contains(provider.instanceID) == true
        else { return }
        guard settings.notificationsEnabled, provider == .codex || provider == .claude else {
            if provider == .codex || provider == .claude {
                self.predictivePaceWarningKeys = self.predictivePaceWarningKeys.filter { $0.provider != provider }
            }
            return
        }
        let resolved = provider == .codex ? codexAccountContext.flatMap {
            self.codexHistoricalOwnership(
                snapshot: snapshot,
                codexVisibleAccount: codexVisibleAccount,
                codexAccountContext: $0).canonicalKey
        } : self.quotaAccountDiscriminator(
            provider: provider, snapshot: snapshot, codexVisibleAccount: codexVisibleAccount,
            tokenAccount: tokenAccount, environment: environment,
            strategyKind: strategyKind, oauthHistoryOwnerIdentifier: oauthHistoryOwnerIdentifier,
            claudeAccountUUIDBefore: claudeAccountUUIDBefore, claudeAccountUUIDAfter: claudeAccountUUIDAfter)
        let owner: String? = if provider == .codex {
            resolved
        } else {
            PredictivePaceWarningOwnerIdentityCore.discriminator(.init(
                provider: provider, snapshotAccountID: snapshot.identity?.accountID,
                snapshotEmail: snapshot.accountEmail(for: provider),
                codexSelectedWorkspaceAccountID: nil,
                codexSelectedEmail: nil, tokenAccountID: tokenAccount?.id,
                claudeResolvedDiscriminator: resolved))
        }
        guard let owner else {
            // An incomplete identity is not evidence that a prior account disappeared.
            // Preserve the episode until a later successful snapshot supplies stable ownership.
            return
        }
        let source: PredictivePaceWarningCandidateCore.SourceWindows = if provider == .codex {
            CodexProviderDescriptor.predictivePaceSourceWindows(snapshot: snapshot)
        } else {
            .init(session: SessionQuotaTransitionCore.sessionWindow(provider: provider, snapshot: snapshot)?.window,
                weekly: snapshot.secondary)
        }
        let weekly = source.weekly.flatMap { window -> UsagePace? in
            if provider == .codex, settings.historicalTrackingEnabled {
                guard ProviderDescriptorRegistry.descriptor(for: .codex).pace.allowsPace(
                    dataConfidence: snapshot.dataConfidence),
                    window.remainingPercent > 0
                else { return nil }

                if settings.weeklyProgressWorkDays == nil,
                   self.codexHistoricalDatasetAccountKey == owner,
                   let historical = CodexHistoricalPaceEvaluator.evaluate(
                       window: window,
                       now: snapshot.updatedAt,
                       dataset: self.codexHistoricalDataset)
                {
                    // Once a learned result exists, apply the same floor as the
                    // original resolver; do not silently replace it with linear pace.
                    return historical.expectedUsedPercent >= 3 ? historical : nil
                }
                guard let fallback = UsagePace.weekly(
                    window: window,
                    now: snapshot.updatedAt,
                    defaultWindowMinutes: 10080,
                    workDays: settings.weeklyProgressWorkDays),
                    fallback.expectedUsedPercent >= 3
                else { return nil }
                return fallback
            }
            return PredictivePaceWarningCandidateCore.linearWeeklyPace(
                provider: provider,
                window: window,
                dataConfidence: snapshot.dataConfidence,
                now: snapshot.updatedAt,
                workDays: settings.weeklyProgressWorkDays)
        }
        let candidates = PredictivePaceWarningCandidateCore.candidates(
            provider: provider,
            sourceWindows: source,
            weeklyPace: weekly,
            now: snapshot.updatedAt)
        for candidate in candidates {
            guard let resetsAt = candidate.rateWindow.resetsAt else { continue }
            let key = PredictivePaceWarningTransitionCore.Key(
                provider: provider,
                accountDiscriminator: owner,
                window: candidate.window,
                resetWindow: .init(
                    windowMinutes: candidate.rateWindow.windowMinutes,
                    resetsAt: resetsAt))
            PredictivePaceWarningTransitionCore.reconcileSiblingWindowKeys(
                activeKey: key,
                notifiedKeys: &self.predictivePaceWarningKeys)
            guard PredictivePaceWarningTransitionCore.recordObservation(
                key: key,
                pace: candidate.pace,
                notifiedKeys: &self.predictivePaceWarningKeys),
                  let eta = candidate.pace.etaSeconds, eta > 0 else { continue }
            self.predictivePaceWarningPublisher(.init(
                providerName: ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName,
                window: candidate.window,
                etaSeconds: eta,
                accountDisplayName: WindowsUsagePresentationSettings.load().hidePersonalInfo
                    ? nil : snapshot.accountEmail(for: provider)))
        }
    }

    private func quotaAccountDiscriminator(provider: UsageProvider, snapshot: UsageSnapshot,
        codexVisibleAccount: CodexVisibleAccount?, tokenAccount: ProviderTokenAccount?, environment: [String: String],
        strategyKind: ProviderFetchKind?, oauthHistoryOwnerIdentifier: String?,
        claudeAccountUUIDBefore: String?, claudeAccountUUIDAfter: String?) -> String? {
        if let tokenAccount { return "token-account:\(tokenAccount.id.uuidString.lowercased())" }
        if provider == .codex { return self.codexSessionOwnerKey(snapshot: snapshot, visibleAccount: codexVisibleAccount, tokenAccount: nil) }
        if provider == .claude, (strategyKind == .cli || strategyKind == .oauth),
           let uuid = claudeAccountUUIDBefore?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !uuid.isEmpty,
           uuid == claudeAccountUUIDAfter?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        {
            let profile = ClaudeOAuthCredentialsStore.credentialsProfileIdentifier(environment: environment)
            let raw = "claude:active-account:v3:\(profile):\(uuid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
            let digest = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
            return "claude-account:\(digest)"
        }
        if provider == .claude, strategyKind == .oauth,
           let owner = oauthHistoryOwnerIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !owner.isEmpty {
            return "claude-oauth-owner:\(owner)"
        }
        return nil
    }

    private func codexSessionOwnerKey(
        snapshot: UsageSnapshot,
        visibleAccount: CodexVisibleAccount?,
        tokenAccount: ProviderTokenAccount?) -> String?
    {
        let email = CodexIdentityResolver.normalizeEmail(visibleAccount?.email ?? snapshot.accountEmail(for: .codex))
        let accountID = CodexOpenAIWorkspaceResolver.normalizeWorkspaceAccountID(visibleAccount?.workspaceAccountID ?? snapshot.identity?.accountID)
        let identity = CodexIdentityResolver.resolve(accountId: accountID, email: email)
        let sourceKey: String?
        let fingerprint: String?
        if let visibleAccount {
            fingerprint = CodexAuthFingerprint.normalize(visibleAccount.authFingerprint)
            switch visibleAccount.selectionSource {
            case .liveSystem: sourceKey = "live-system"
            case let .managedAccount(id): sourceKey = "managed:\(id.uuidString.lowercased())"
            case let .profileHome(path):
                sourceKey = CodexHomeScope.normalizedHomePath(path).map { "profile:\($0)" }
            }
        } else if let tokenAccount {
            sourceKey = "token:\(tokenAccount.id.uuidString.lowercased())"
            fingerprint = CodexAuthFingerprint.fingerprint(data: Data(tokenAccount.token.utf8))
        } else {
            sourceKey = nil
            fingerprint = nil
        }
        let raw: String
        switch identity {
        case let .providerAccount(id):
            guard let email else { return nil }
            raw = "codex-session-quota-owner:v1\0provider\0\(id)\0\(email)"
        case let .emailOnly(email):
            guard let sourceKey, let fingerprint else { return nil }
            raw = "codex-session-quota-owner:v1\0email\0\(sourceKey)\0\(email)\0\(fingerprint)"
        case .unresolved: return nil
        }
        return CodexAuthFingerprint.fingerprint(data: Data(raw.utf8))
    }

    private func runRefreshSchedule(generation: UInt64) async {
        guard generation == self.scheduleGeneration else { return }
        let frequency = self.refreshSettings.frequency
        guard frequency != .manual else { return }
        // No Windows activity scanner exists yet. Agent-aware mode remains
        // unavailable even if a stale consent value says allowed.
        if frequency == .adaptiveAgentAware { return }

        let clock = ContinuousClock()
        let initialSignals = self.signalProvider()
        var fixedInterval = Duration.seconds(frequency.seconds ?? 0)
        if initialSignals.lowPowerModeEnabled { fixedInterval = max(fixedInterval, .seconds(1800)) }
        var scheduledAt = clock.now + fixedInterval
        self.scheduledDeadline = frequency.usesAdaptivePolicy ? nil : scheduledAt
        while !Task.isCancelled, generation == self.scheduleGeneration {
            if frequency.usesAdaptivePolicy {
                let signals = self.signalProvider()
                let decision = AdaptiveRefreshPolicyCore().nextDelay(for: .init(
                    now: Date(),
                    lastMenuOpenAt: self.lastMenuOpenedAt,
                    lastCodingActivityAt: nil,
                    lowPowerModeEnabled: signals.lowPowerModeEnabled,
                    thermalPressure: signals.thermalConstrained ? .constrained : .nominal))
                scheduledAt = self.scheduledDeadline ?? (clock.now + decision.delay)
            } else {
                let signals = self.signalProvider()
                let base = Duration.seconds(frequency.seconds ?? 0)
                fixedInterval = signals.lowPowerModeEnabled ? max(base, .seconds(1800)) : base
                if self.scheduledDeadline == nil { self.scheduledDeadline = scheduledAt }
                scheduledAt = self.scheduledDeadline ?? scheduledAt
            }
            let deadline = scheduledAt
            // Publish the active deadline before sleeping so a wake callback can
            // compare against and replace it; nil would make every tick abort.
            self.scheduledDeadline = deadline
            let sleeper = Task {
                do { try await clock.sleep(until: deadline) } catch { }
            }
            self.sleepTask = sleeper
            await sleeper.value
            guard generation == self.scheduleGeneration else { return }
            self.sleepTask = nil
            if Task.isCancelled { return }
            if self.scheduledDeadline != deadline { continue }
            guard !Task.isCancelled else { return }
            await self.refresh()
            guard generation == self.scheduleGeneration else { return }
            if !frequency.usesAdaptivePolicy {
                let latestSignals = self.signalProvider()
                let base = Duration.seconds(frequency.seconds ?? 0)
                fixedInterval = latestSignals.lowPowerModeEnabled ? max(base, .seconds(1800)) : base
                let completedAt = clock.now
                repeat { scheduledAt += fixedInterval }
                while scheduledAt <= completedAt
                self.scheduledDeadline = scheduledAt
            } else {
                self.scheduledDeadline = nil
            }
        }
    }

    private static let resetBoundaryRefreshGraceSeconds: TimeInterval = 30
    private static let resetBoundaryRefreshMinimumDelaySeconds: TimeInterval = 5

    private struct ResetBoundaryRefreshCandidate {
        let refreshAt: Date
        let boundaryRefreshAt: Date
    }

    /// Mirrors UsageStore's reset-boundary heuristic for the Windows runtime.
    /// Only snapshots from the just-completed pass are considered, so disabled
    /// providers and stale presentations cannot create background work.
    private func scheduleResetBoundaryRefreshIfNeeded(
        snapshots: [ProviderInstanceID: UsageSnapshot],
        now: Date)
    {
        let signals = self.signalProvider()
        guard !self.shuttingDown,
              let normalRefreshInterval = self.normalRefreshIntervalForHeuristics(now: now, signals: signals)
        else {
            self.cancelResetBoundaryRefresh()
            return
        }
        let normalRefreshDate = now.addingTimeInterval(normalRefreshInterval)
        let minimumAutomaticRefreshInterval: TimeInterval? = signals.lowPowerModeEnabled
            ? 1800
            : nil
        let earliestAutomaticRefreshDate = minimumAutomaticRefreshInterval.map(now.addingTimeInterval)
        let minimumDelayRefreshDate = now.addingTimeInterval(Self.resetBoundaryRefreshMinimumDelaySeconds)
        let candidate = snapshots.values
            .flatMap { snapshot in
                ([snapshot.primary, snapshot.secondary, snapshot.tertiary]
                    .compactMap { $0 }
                    + (snapshot.extraRateWindows?.map(\.window) ?? []))
                    .map { (snapshot, $0) }
            }
            .compactMap { snapshot, window -> ResetBoundaryRefreshCandidate? in
                guard let resetsAt = window.resetsAt else { return nil }
                let boundaryRefreshAt = resetsAt.addingTimeInterval(Self.resetBoundaryRefreshGraceSeconds)
                guard !self.attemptedResetBoundaryRefreshes.contains(boundaryRefreshAt),
                      boundaryRefreshAt <= normalRefreshDate,
                      snapshot.updatedAt < boundaryRefreshAt
                else { return nil }
                let earliestAllowed = max(
                    minimumDelayRefreshDate,
                    earliestAutomaticRefreshDate ?? minimumDelayRefreshDate)
                let refreshAt = max(boundaryRefreshAt, earliestAllowed)
                guard refreshAt <= normalRefreshDate else { return nil }
                return ResetBoundaryRefreshCandidate(
                    refreshAt: refreshAt,
                    boundaryRefreshAt: boundaryRefreshAt)
            }
            .min { $0.refreshAt < $1.refreshAt }
        guard let candidate else {
            self.cancelResetBoundaryRefresh()
            return
        }
        if let scheduled = self.scheduledResetBoundaryRefreshAt,
           abs(scheduled.timeIntervalSince(candidate.refreshAt)) < 1
        {
            return
        }
        self.cancelResetBoundaryRefresh()
        self.scheduledResetBoundaryRefreshAt = candidate.refreshAt
        let generation = self.scheduleGeneration
        self.resetBoundaryRefreshTask = Task { [weak self] in
            let delay = max(0, candidate.refreshAt.timeIntervalSince(Date()))
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            guard generation == self.scheduleGeneration,
                  self.scheduledResetBoundaryRefreshAt == candidate.refreshAt
            else { return }
            self.scheduledResetBoundaryRefreshAt = nil
            self.resetBoundaryRefreshTask = nil
            guard self.refreshTask == nil, !self.shuttingDown else { return }
            self.recordAttemptedResetBoundaryRefresh(candidate.boundaryRefreshAt)
            await self.refresh()
        }
    }

    private func cancelResetBoundaryRefresh() {
        self.resetBoundaryRefreshTask?.cancel()
        self.resetBoundaryRefreshTask = nil
        self.scheduledResetBoundaryRefreshAt = nil
    }

    private func recordAttemptedResetBoundaryRefresh(_ boundaryRefreshAt: Date) {
        self.attemptedResetBoundaryRefreshes.insert(boundaryRefreshAt)
        if self.attemptedResetBoundaryRefreshes.count > 64,
           let oldest = self.attemptedResetBoundaryRefreshes.min()
        {
            self.attemptedResetBoundaryRefreshes.remove(oldest)
        }
    }

    private func normalRefreshIntervalForHeuristics(now: Date, signals: RefreshSignals) -> TimeInterval? {
        let frequency = self.refreshSettings.frequency
        let interval: TimeInterval
        if let seconds = frequency.seconds {
            interval = seconds
        } else {
            guard frequency == .adaptive else { return nil }
            let delay = AdaptiveRefreshPolicyCore().nextDelay(for: .init(
                now: now,
                lastMenuOpenAt: self.lastMenuOpenedAt,
                lastCodingActivityAt: nil,
                lowPowerModeEnabled: signals.lowPowerModeEnabled,
                thermalPressure: signals.thermalConstrained ? .constrained : .nominal)).delay
            interval = TimeInterval(delay.components.seconds)
        }
        return signals.lowPowerModeEnabled ? max(interval, 1800) : interval
    }

    /// Keeps persistent CLI sessions alive for one normal refresh interval,
    /// with the same floor used by ProviderRegistry on other platforms.
    /// Manual and unavailable agent-aware cadences retain the 180-second floor,
    /// while adaptive/low-power policies follow their current effective cadence.
    private func persistentCLISessionIdleWindow(now: Date, signals: RefreshSignals) -> TimeInterval {
        let normalInterval = self.normalRefreshIntervalForHeuristics(now: now, signals: signals)
        return max(180, (normalInterval ?? 120) + 60)
    }

    private func currentSnapshots(
        from entries: [RenderEntry]) -> [ProviderInstanceID: UsageSnapshot]
    {
        Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
            guard case let .presentation(presentation) = entry else { return nil }
            return (presentation.instanceID, presentation.snapshot)
        })
    }

    private func fetchRows(
        provider: UsageProvider,
        context: TokenAccountCLIContext,
        config: CodexBarConfig,
        codexVisibleAccount: CodexVisibleAccount? = nil,
        codexAccountContext: CodexAccountContextSnapshot? = nil,
        presentationSettings: WindowsUsagePresentationSettings,
        quotaWarningGeneration: UInt64,
        predictivePaceWarningGeneration: UInt64,
        historicalTrackingGeneration: UInt64) async -> [String]
    {
        do {
            let account: ProviderTokenAccount? = if codexVisibleAccount == nil {
                try context.resolvedAccounts(for: provider).first
            } else {
                nil
            }
            let sourceOverride = codexVisibleAccount?.selectionSource
            let retainedCodexContext = codexAccountContext.map {
                if let sourceOverride { return $0.selecting(activeSource: sourceOverride) }
                return $0
            }
            let env = context.environment(
                base: ProcessInfo.processInfo.environment,
                provider: provider,
                account: account,
                codexActiveSourceOverride: sourceOverride,
                codexAccountContext: retainedCodexContext)
            let settings = context.settingsSnapshot(
                for: provider,
                account: account,
                codexActiveSourceOverride: sourceOverride,
                codexAccountContext: retainedCodexContext)
            let source = context.effectiveSourceMode(
                base: context.preferredSourceMode(for: provider),
                provider: provider,
                account: account)
            let fetchContext = ProviderFetchContext(
                runtime: .app,
                sourceMode: source,
                includeCredits: presentationSettings.showOptionalCreditsAndExtraUsage,
                includeOptionalUsage: presentationSettings.showOptionalCreditsAndExtraUsage,
                requiresOptionalUsageCompleteness: presentationSettings.showOptionalCreditsAndExtraUsage,
                webTimeout: 60,
                webDebugDumpHTML: false,
                verbose: false,
                env: env,
                settings: settings,
                fetcher: context.fetcher(base: self.fetcher, provider: provider, env: env),
                claudeFetcher: self.claudeFetcher,
                browserDetection: self.browserDetection,
                selectedTokenAccountID: account?.id,
                tokenAccountTokenUpdater: context.tokenUpdater(for: account),
                providerManualTokenUpdater: context.manualTokenUpdater(),
                persistsCLISessions: true,
                persistentCLISessionIdleWindow: self.persistentCLISessionIdleWindow(
                    now: Date(),
                    signals: self.signalProvider()))
            let claudeAccountUUIDBefore = provider == .claude
                ? ClaudeAccountProfile.accountUuid(environment: env) : nil
            let outcome = await ProviderDescriptorRegistry.descriptor(for: provider).fetchOutcome(context: fetchContext)
            switch outcome.result {
            case let .success(result):
                let metadata = ProviderDescriptorRegistry.descriptor(for: provider).metadata
                let labeledUsage: UsageSnapshot = if let codexVisibleAccount {
                    context.applyCodexVisibleAccountLabel(result.usage, account: codexVisibleAccount)
                } else if let account {
                    context.applyAccountLabel(result.usage, provider: provider, account: account)
                } else {
                    result.usage
                }
                let accountLabel = labeledUsage.accountEmail(for: provider)
                let title = accountLabel.map { "\(metadata.displayName) [\($0)]" } ?? metadata.displayName
                let presentation = WindowsUsagePresentation(instanceID: provider.instanceID, provider: provider, title: title, privacyTitle: metadata.displayName, result: result, snapshot: labeledUsage, hidePersonalInfo: presentationSettings.hidePersonalInfo, showOptionalUsage: presentationSettings.showOptionalCreditsAndExtraUsage, usageBarsShowUsed: presentationSettings.usageBarsShowUsed, resetTimesShowAbsolute: presentationSettings.resetTimesShowAbsolute)
                self.presentations[provider.instanceID] = presentation
                self.evaluateSessionQuota(provider: provider, snapshot: result.usage, codexVisibleAccount: codexVisibleAccount, tokenAccount: account)
                self.evaluateQuotaWarnings(provider: provider, snapshot: result.usage,
                    codexVisibleAccount: codexVisibleAccount, tokenAccount: account, environment: env, config: config,
                    claudeAccountUUIDBefore: claudeAccountUUIDBefore,
                    claudeAccountUUIDAfter: provider == .claude
                        ? ClaudeAccountProfile.accountUuid(environment: env) : nil,
                    strategyKind: result.strategyKind,
                    oauthHistoryOwnerIdentifier: result.claudeOAuthHistoryOwnerIdentifier,
                    quotaWarningGeneration: quotaWarningGeneration)
                await self.recordCodexHistoricalSampleIfNeeded(
                    provider: provider,
                    snapshot: result.usage,
                    authorizedDashboard: result.authorizedDashboard,
                    codexVisibleAccount: codexVisibleAccount,
                    codexAccountContext: retainedCodexContext,
                    generation: historicalTrackingGeneration)
                self.evaluatePredictivePaceWarnings(provider: provider, snapshot: result.usage,
                    predictivePaceWarningGeneration: predictivePaceWarningGeneration,
                    codexVisibleAccount: codexVisibleAccount, tokenAccount: account,
                    codexAccountContext: retainedCodexContext,
                    environment: env,
                    claudeAccountUUIDBefore: claudeAccountUUIDBefore,
                    claudeAccountUUIDAfter: provider == .claude ? ClaudeAccountProfile.accountUuid(environment: env) : nil,
                    strategyKind: result.strategyKind,
                    oauthHistoryOwnerIdentifier: result.claudeOAuthHistoryOwnerIdentifier)
                return presentation.rows()
            case let .failure(error):
                self.recordStartupConnectivityRetryableFailure(error)
                return ["\(provider.rawValue): \(error.localizedDescription)"]
            }
        } catch is CancellationError {
            return []
        } catch {
            self.recordStartupConnectivityRetryableFailure(error)
            return ["\(provider.rawValue): \(error.localizedDescription)"]
        }
    }

    private func fetchPluginRows(instanceID: ProviderInstanceID, config: CodexBarConfig, presentationSettings: WindowsUsagePresentationSettings) async -> [String] {
        guard let plugin = UserProviderPluginRegistry.plugin(for: instanceID) else {
            return ["\(instanceID.rawValue): plugin not found"]
        }
        let providerConfig = config.providerConfig(for: instanceID)
        let settings = providerConfig?.pluginSettings ?? [:]
        let secrets = providerConfig?.pluginSecrets ?? [:]
        do {
            try Task.checkCancellation()
            let snapshot = try await plugin.fetchUsage(
                settings: settings,
                secrets: secrets,
                environment: ProcessInfo.processInfo.environment,
                approvalStore: self.pluginApprovalStore,
                instanceCookieResolver: UserProviderPluginCookieBroker.resolver(
                    browserDetection: self.browserDetection))
            try Task.checkCancellation()
            let accountLabel = snapshot.identity(for: instanceID)?.accountEmail
            let title = accountLabel.map { "\(plugin.manifest.name) [\($0)]" } ?? plugin.manifest.name
            let presentation = WindowsUsagePresentation(instanceID: instanceID, provider: nil, title: title, privacyTitle: plugin.manifest.name, result: nil, snapshot: snapshot, hidePersonalInfo: presentationSettings.hidePersonalInfo, showOptionalUsage: presentationSettings.showOptionalCreditsAndExtraUsage, usageBarsShowUsed: presentationSettings.usageBarsShowUsed, resetTimesShowAbsolute: presentationSettings.resetTimesShowAbsolute)
            self.presentations[instanceID] = presentation
            return presentation.rows()
        } catch is CancellationError {
            return []
        } catch {
            return ["\(plugin.manifest.name): \(error.localizedDescription)"]
        }
    }

    private func runStartupConnectivityRefresh(attempt: Int) async {
        guard !self.shuttingDown else { return }
        while self.refreshTask != nil, !Task.isCancelled, !self.shuttingDown {
            await self.waitForRefreshCompletion()
        }
        guard !Task.isCancelled, !self.shuttingDown else { return }
        self.startupConnectivityRetryActive = true
        self.startupConnectivityRetryNeeded = false
        await self.refresh()
        self.startupConnectivityRetryActive = false
        guard !Task.isCancelled, !self.shuttingDown else { return }
        self.completeStartupConnectivityRetryPass(currentAttempt: attempt)
    }

    private func waitForRefreshCompletion() async {
        guard self.refreshTask != nil, !self.shuttingDown else { return }
        await withCheckedContinuation { continuation in
            self.refreshCompletionWaiters.append(continuation)
        }
    }

    private func resumeRefreshCompletionWaiters() {
        let waiters = self.refreshCompletionWaiters
        self.refreshCompletionWaiters.removeAll(keepingCapacity: true)
        for waiter in waiters { waiter.resume() }
    }

    private func completeStartupConnectivityRetryPass(currentAttempt: Int) {
        guard !self.shuttingDown, !Task.isCancelled, self.startupConnectivityRetryNeeded else {
            self.startupConnectivityRetryTask = nil
            return
        }
        let delays: [TimeInterval] = [15, 45, 120, 300]
        let nextAttempt = currentAttempt + 1
        guard nextAttempt <= delays.count else {
            self.startupConnectivityRetryTask = nil
            return
        }
        self.startupConnectivityRetryTask?.cancel()
        let delay = delays[nextAttempt - 1]
        self.startupConnectivityRetryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            await self.runStartupConnectivityRefresh(attempt: nextAttempt)
        }
    }

    private func recordStartupConnectivityRetryableFailure(_ error: Error) {
        guard self.startupConnectivityRetryActive,
              Self.isStartupConnectivityRetryableError(error)
        else { return }
        self.startupConnectivityRetryNeeded = true
    }

    private static func isStartupConnectivityRetryableError(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed:
                return true
            default:
                return false
            }
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("timed out") ||
            message.contains("timeout") ||
            message.contains("network connection was lost") ||
            message.contains("not connected to the internet") ||
            message.contains("cannot find host") ||
            message.contains("cannot connect to host") ||
            message.contains("dns lookup")
    }
}
#endif
