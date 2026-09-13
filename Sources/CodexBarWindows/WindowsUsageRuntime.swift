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

    enum SpendCollectionState: Sendable { case idle, disabled, collecting, available, failed, stopped }
    private var collectedSpendSources: [WindowsSpendSnapshotLoader.Source]?
    private var spendController: WindowsSpendDashboardController?
    private var collectedSpendSettings: WindowsSpendSettings?
    private var spendSnapshot: WindowsSpendDashboardController.Snapshot?
    private var spendState: SpendCollectionState = .idle
    private var spendGeneration: UInt64 = 0

    /// The native dashboard reads this actor-owned value, never a previous controller's data.
    func currentSpendSnapshot() -> (SpendCollectionState, WindowsSpendDashboardController.Snapshot?) {
        (self.spendState, self.spendSnapshot)
    }

    public func loadSpendSourceSelection() -> WindowsSpendSourceResult {
        guard !self.shuttingDown, self.refreshTask == nil, self.spendState == .available,
              let snapshot = self.spendSnapshot, let settings = self.collectedSpendSettings,
              WindowsSpendSettings.load() == settings else {
            return .unavailable("Complete a cost collection before choosing sources.")
        }
        var sources = snapshot.model.availableSources
        if settings.openCodexUsageLogsEnabled || settings.hiddenSourceIDs.contains(WindowsSpendDashboardModel.openCodexSourceID) {
            if !sources.contains(where: { $0.id == WindowsSpendDashboardModel.openCodexSourceID }) {
                sources.append(.init(id: WindowsSpendDashboardModel.openCodexSourceID, displayName: "OpenCodeX logs (all subscriptions)"))
            }
        }
        guard !sources.isEmpty, sources.count <= 4096, Set(sources.map(\.id)).count == sources.count else {
            return .unavailable("No selectable cost sources are available.")
        }
        let entries = sources.enumerated().map { index, source in
            let title = String(LogRedactor.redact(source.id == WindowsSpendDashboardModel.openCodexSourceID ? "OpenCodeX logs (all subscriptions)" : source.displayName).unicodeScalars
                .filter { $0.value >= 0x20 && $0.value != 0x7F }.map(String.init).joined().prefix(160))
            return WindowsSpendSourceSelection.Entry(id: source.id,
                title: "\(index + 1). " + (title.isEmpty ? "Source" : title),
                included: !settings.hiddenSourceIDs.contains(source.id))
        }
        return .selection(.init(generation: self.spendGeneration, entries: entries))
    }

    public func saveSpendSourceSelection(generation: UInt64,
                                         mutation: WindowsSpendSourceMutation) async -> WindowsSpendSourceResult {
        guard !self.shuttingDown, generation == self.spendGeneration,
              case let .selection(selection) = self.loadSpendSourceSelection(),
              var settings = self.collectedSpendSettings else {
            return .unavailable("Cost sources or settings changed. Reopen the source menu.")
        }
        let ids = Set(selection.entries.map(\.id))
        switch mutation {
        case let .setIncluded(id, included):
            guard ids.contains(id) else { return .unavailable("This cost source is no longer available.") }
            if included { settings.hiddenSourceIDs.remove(id) } else { settings.hiddenSourceIDs.insert(id) }
        case .showAll: settings.hiddenSourceIDs.subtract(ids)
        case .hideAll: settings.hiddenSourceIDs.formUnion(ids)
        }
        do { try settings.save() }
        catch { return .unavailable("Cost source preferences could not be saved.") }
        await self.spendSettingsDidChange()
        return .saved
    }

    private var canPresentSpendSnapshot: Bool {
        switch self.spendState {
        case .available, .collecting, .failed: return self.spendSnapshot != nil
        case .idle, .disabled, .stopped: return false
        }
    }

    public func tokenActivityResult() -> ShareStatsCopyResult {
        guard !self.shuttingDown, self.canPresentSpendSnapshot,
              let snapshot = self.spendSnapshot, !snapshot.model.tokenActivity.isEmpty,
              let settings = self.collectedSpendSettings, WindowsSpendSettings.load() == settings else {
            return .unavailable("Token activity is not ready. Complete a cost collection and try again.")
        }
        return .costHistory(WindowsSpendHistorySnapshot.tokenActivity(snapshot, calendar: settings.bucketCalendar))
    }

    public func spendHourlyResult(day: Date, currency: String, generation: UInt64) async -> ShareStatsCopyResult {
        guard !self.shuttingDown, generation == self.spendGeneration, self.canPresentSpendSnapshot,
              let snapshot = self.spendSnapshot, let controller = self.spendController,
              let settings = self.collectedSpendSettings, WindowsSpendSettings.load() == settings,
              let group = snapshot.model.groups.first(where: { $0.currencyCode == currency }),
              day >= group.chartDomain.lowerBound, day < group.chartDomain.upperBound else {
            return .unavailable("The cost history changed. Reopen the daily chart before requesting hourly details.")
        }
        let selected = await controller.snapshot(forDay: day, now: snapshot.loadedAt ?? Date())
        guard !self.shuttingDown, generation == self.spendGeneration, WindowsSpendSettings.load() == settings,
              self.spendSnapshot?.loadedAt == snapshot.loadedAt, selected.loadedAt == snapshot.loadedAt else {
            return .unavailable("The cost history changed while preparing hourly details.")
        }
        var history = WindowsSpendHistorySnapshot.hourly(snapshot.stale ? selected.refreshing() : selected, day: day)
        history.generation = generation
        history.preferredSeriesCode = currency
        return .costHistory(history)
    }

    public func spendHistoryResult() -> ShareStatsCopyResult {
        guard !self.shuttingDown, self.canPresentSpendSnapshot,
              let snapshot = self.spendSnapshot, !snapshot.model.groups.isEmpty,
              let settings = self.collectedSpendSettings, WindowsSpendSettings.load() == settings else {
            return .unavailable("Cost history is not ready. Complete a cost collection and try again.")
        }
        var history = WindowsSpendHistorySnapshot.make(snapshot)
        history.generation = self.spendGeneration
        return .costHistory(history)
    }

    public enum ShareStatsCopyResult: Sendable {
        case costHistory(WindowsSpendHistorySnapshot)
        case json(Data, filename: String, copy: Bool, notice: String?)
        case image(Data, filename: String)
        case clipboardImage(png: Data, dib: Data)
        case preview(png: Data, dib: Data, filename: String, text: String)
        case ready(String)
        case unavailable(String)
    }

    public func spendJSONResult(copy: Bool) -> ShareStatsCopyResult {
        guard !self.shuttingDown, self.canPresentSpendSnapshot,
              let snapshot = self.spendSnapshot,
              !snapshot.model.groups.isEmpty, let settings = self.collectedSpendSettings,
              WindowsSpendSettings.load() == settings else {
            return .unavailable("No exportable cost snapshot is available for the current settings. Refresh all and retry.")
        }
        do {
            let data = try WindowsSpendDashboardJSONExporter.encodedData(
                model: snapshot.model, hiddenSourceIDs: settings.hiddenSourceIDs.sorted())
            guard data.count <= 16 * 1024 * 1024 else { return .unavailable("The cost JSON exceeds the 16 MiB export limit.") }
            var notices: [String] = []
            if !snapshot.sourceFailures.isEmpty {
                notices.append("Partial collection: \(snapshot.sourceFailures.count) failed source(s) are excluded.")
            }
            if snapshot.sourceFailures.contains(where: { $0.accountIdentityUnconfirmed }) {
                notices.append("An account identity could not be confirmed. Re-import the intended account; its failed source is excluded.")
            }
            if snapshot.openCodexObservation == .unavailable {
                notices.append("OpenCodeX logs are unavailable and are excluded.")
            }
            if snapshot.stale { notices.append("This export uses the last captured data; collection has not completed successfully.") }
            if !notices.isEmpty {
                notices.append("The original JSON schema does not include collection failure or stale-status fields.")
            }
            if copy {
                guard let text = String(data: data, encoding: .utf8), text.utf16.count <= 65_536 else {
                    return .unavailable("The cost JSON is too large for clipboard copying. Use Export cost JSON instead.")
                }
            }
            return .json(data, filename: WindowsSpendDashboardJSONExporter.defaultFilename(days: snapshot.model.requestedDays),
                         copy: copy, notice: notices.isEmpty ? nil : notices.joined(separator: "\r\n"))
        } catch {
            return .unavailable("Cost JSON could not be encoded. No export was produced.")
        }
    }

    public func shareStatsImageResult(copyToClipboard: Bool = false, preview: Bool = false) -> ShareStatsCopyResult {
        guard !self.shuttingDown, self.spendState == .available,
              let snapshot = self.spendSnapshot, snapshot.phase == .ready, !snapshot.stale,
              let payload = snapshot.sharePayload, let settings = self.collectedSpendSettings,
              WindowsSpendSettings.load() == settings else {
            return .unavailable("Sharing an image needs a completed collection with unchanged settings and no failed sources.")
        }
        guard let image = WindowsShareStatsRenderer.render(payload: payload, calendar: settings.bucketCalendar) else {
            return .unavailable("The Share Stats image could not be generated.")
        }
        let filename = "codexbar-subscriptions-last-\(payload.days)-days.png"
        if preview {
            let text = WindowsShareStatsFormatting.text(payload, calendar: settings.bucketCalendar)
            guard let redacted = WindowsClipboard.summary(rows: text.components(separatedBy: "\n")) else {
                return .unavailable("The Share Stats preview text is unavailable.")
            }
            return .preview(png: image.png, dib: image.dib, filename: filename, text: redacted)
        }
        if copyToClipboard { return .clipboardImage(png: image.png, dib: image.dib) }
        return .image(image.png, filename: filename)
    }

    public func shareStatsCopyResult() -> ShareStatsCopyResult {
        guard !self.shuttingDown, self.spendState == .available,
              let snapshot = self.spendSnapshot, snapshot.phase == .ready, !snapshot.stale,
              let payload = snapshot.sharePayload, let settings = self.collectedSpendSettings,
              WindowsSpendSettings.load() == settings else {
            return .unavailable("Share Stats needs a completed collection with unchanged settings and no failed sources. Refresh all and try again.")
        }
        let text = WindowsShareStatsFormatting.text(payload, calendar: settings.bucketCalendar)
        guard let redacted = WindowsClipboard.summary(rows: text.components(separatedBy: "\n")) else {
            return .unavailable("The Share Stats text is empty or too large to copy.")
        }
        return .ready(redacted)
    }

    public struct SpendSummaryResult: Sendable {
        public let expandedText: String?
        public let text: String
        public let hidePersonalInfo: Bool
    }

    public func spendSummaryResult() -> SpendSummaryResult {
        let privacy = WindowsUsagePresentationSettings.load().hidePersonalInfo
        let expanded: String?
        if case .available = self.spendState, let snapshot = self.spendSnapshot,
           snapshot.model.groups.contains(where: { $0.models.count > 8 || $0.projects.count > 8 }) {
            expanded = WindowsSpendSummary.text(snapshot: snapshot, hidePersonalInfo: privacy, expanded: true)
        } else { expanded = nil }
        return SpendSummaryResult(expandedText: expanded, text: self.spendSummaryText(hidePersonalInfo: privacy), hidePersonalInfo: privacy)
    }

    private func spendSummaryText(hidePersonalInfo: Bool) -> String {
        switch self.spendState {
        case .idle: return "Cost data is not ready. Refresh all to collect enabled sources."
        case .disabled: return "Cost collection is disabled or no enabled provider supports costs. Use Cost collection to change preferences."
        case .collecting:
            if self.spendSnapshot == nil { return "Cost collection is in progress. Reopen this summary after collection finishes." }
        case .stopped: return "Cost collection has stopped."
        case .failed:
            if self.spendSnapshot == nil { return "Cost collection failed. Refresh all to retry." }
        case .available: break
        }
        guard let snapshot = self.spendSnapshot,
              self.collectedSpendSettings == WindowsSpendSettings.load() else {
            return "Cost data is unavailable for the current settings. Refresh all and reopen the summary."
        }
        return WindowsSpendSummary.text(snapshot: snapshot, hidePersonalInfo: hidePersonalInfo)
    }

    private let configStore: CodexBarConfigStore
    private let browserDetection: BrowserDetection
    private let fetcher: UsageFetcher
    private let claudeFetcher: ClaudeUsageFetcher
    private let pluginApprovalStore: ProviderPluginApprovalStore
    private var publisher: RowPublisher
    private var combinedPublisher: CombinedPublisher
    private var notificationPublisher: NotificationPublisher
    private var accountInvalidationPublisher: @Sendable (ProviderInstanceID) -> Void = { _ in }
    private var quotaWarningPublisher: QuotaWarningPublisher
    private var predictivePaceWarningPublisher: PredictivePaceWarningPublisher
    private var refreshTask: Task<Void, Never>?
    private var refreshCompletionWaiters: [CheckedContinuation<Void, Never>] = []
    private var startupConnectivityRetryTask: Task<Void, Never>?
    private var startupConnectivityRetryActive = false
    private var startupConnectivityRetryNeeded = false
    private var queuedSpendRefresh = false
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
    private var providerCopyErrors: [String: String] = [:]
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
    private var observedAccountSignatures: [ProviderInstanceID: String]?
    private struct CodexObservedOwner: Equatable {
        let requestedSource: CodexActiveSource
        let resolvedSource: CodexActiveSource
        let identity: CodexIdentity
        let managedHomePath: String?
        let storeUnreadable: Bool
    }
    private var observedCodexOwner: CodexObservedOwner?
    private struct CredentialEditTicket {
        let id: UUID
        let providerID: ProviderInstanceID
        let accountID: UUID
        let revision: Data
        let expiresAt: Date
    }
    private var credentialEditTicket: CredentialEditTicket?
    private struct AccountRemovalTicket {
        let edit: CredentialEditTicket
        let selectedID: UUID
        let accountIDs: [UUID]
    }
    private var accountRemovalTicket: AccountRemovalTicket?
    // Private retry state restored from a DPAPI-protected removal journal. Never publish credentials.
    private var pendingAntigravityRemovals: [UUID: ProviderTokenAccount] = [:]
    private var removalJournalLoaded = false
    private var removalJournalFailed = false
    private var removalJournal: WindowsAccountRemovalJournal {
        .init(fileURL: self.configStore.fileURL.appendingPathExtension("removal-recovery"))
    }
    private func loadRemovalJournalIfNeeded() throws {
        guard !self.removalJournalLoaded else { return }
        self.pendingAntigravityRemovals = try self.removalJournal.load()
        self.removalJournalLoaded = true
        self.removalJournalFailed = false
    }


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

    public func setAccountInvalidationPublisher(_ publisher: @escaping @Sendable (ProviderInstanceID) -> Void) {
        self.accountInvalidationPublisher = publisher
    }

    public func setNotificationPublisher(_ publisher: @escaping NotificationPublisher) {
        self.notificationPublisher = publisher
    }

    public func loadTokenAccountSelection(
        providerID: ProviderInstanceID) -> WindowsTokenAccountSelectionLoadResult
    {
        guard !self.shuttingDown else { return .shuttingDown }
        do {
            guard let provider = providerID.firstPartyProvider,
                  let support = TokenAccountSupportCatalog.support(for: provider),
                  let config = try self.configStore.load(), config.enabledProviders().contains(providerID),
                  let data = config.providerConfig(for: providerID)?.tokenAccounts,
                  !data.accounts.isEmpty,
                  Set(data.accounts.map(\.id)).count == data.accounts.count else { return .unavailable }
            let hide = WindowsUsagePresentationSettings.load().hidePersonalInfo
            let accounts = data.accounts.enumerated().map { index, account in
                let label = hide ? "Account \(index + 1)" :
                    String(LogRedactor.redact(account.label).replacingOccurrences(of: "\0", with: "").prefix(160))
                return WindowsTokenAccountSelectionSnapshot.Account(
                    id: account.id, title: label.isEmpty ? "Account \(index + 1)" : label,
                    labelRevision: Self.accountLabelRevision(account.label))
            }
            return .loaded(.init(providerID: providerID, accounts: accounts,
                                 selectedID: data.accounts[data.clampedActiveIndex()].id,
                                 requiresManualSource: support.requiresManualCookieSource))
        } catch { return .failed }
    }

    /// Rejects stale menus and in-flight fetches rather than publishing mixed-account results.
    /// The caller requests refresh only after a successful save.
    public func selectTokenAccount(providerID: ProviderInstanceID, accountID: UUID,
                                   expectedSelectedID: UUID?) -> WindowsTokenAccountSelectionSaveResult {
        guard !self.shuttingDown else { return .shuttingDown }
        guard self.refreshTask == nil else { return .refreshInProgress }
        do {
            guard let provider = providerID.firstPartyProvider,
                  let support = TokenAccountSupportCatalog.support(for: provider),
                  var config = try self.configStore.load(), config.enabledProviders().contains(providerID),
                  var entry = config.providerConfig(for: providerID), let data = entry.tokenAccounts,
                  !data.accounts.isEmpty,
                  Set(data.accounts.map(\.id)).count == data.accounts.count else { return .unavailable }
            guard data.accounts[data.clampedActiveIndex()].id == expectedSelectedID,
                  let index = data.accounts.firstIndex(where: { $0.id == accountID }) else { return .staleSelection }
            let sourceChanged = support.requiresManualCookieSource && entry.cookieSource != .manual
            guard index != data.clampedActiveIndex() || sourceChanged else { return .unchanged }
            entry.tokenAccounts = ProviderTokenAccountData(version: data.version, accounts: data.accounts,
                                                           activeIndex: index)
            if support.requiresManualCookieSource { entry.cookieSource = .manual }
            config.setProviderConfig(entry)
            try self.configStore.save(config)
            self.latestProviderConfigs[providerID] = entry
            self.invalidateSelectedAccountState(providerID)
            // Withdraw the previous owner's presentation until the next refresh publishes.
            self.presentations.removeValue(forKey: providerID)
            self.providerCopyErrors.removeValue(forKey: providerID.rawValue)
            self.renderEntries = [.row("Account selection changed. Refreshing usage…")]
            self.statusMenuEntries.removeAll()
            self.publishRenderEntries(settings: WindowsUsagePresentationSettings.load())
            return .saved
        } catch { return .failed }
    }

    /// Add to the existing config account schema. Persistence uses the configured store;
    /// no claim of Credential Manager migration is made by this API.
    public struct CursorBrowserChoice: Sendable {
        public let id: UUID
        public let title: String
    }
    public enum CursorBrowserImportResult: Sendable {
        case choices(requestID: UUID, rows: [CursorBrowserChoice], failedCount: Int, omittedCount: Int, privacy: Bool)
        case unavailable(String)
    }
    private struct PendingCursorBrowserImport {
        let id: UUID
        let expires: Date
        let revision: Data
        let selectedID: UUID?
        let privacy: Bool
        let candidates: [UUID: WindowsCursorBrowserSessionImporter.ValidatedCandidate]
    }
    private var cursorBrowserValidationTask: Task<WindowsCursorBrowserSessionImporter.ValidatedCandidate, Error>?
    private var cursorBrowserImportRequest: UUID?
    private var cursorBrowserDiscoveryTask: Task<WindowsCursorBrowserSessionImporter.Discovery, Error>?
    private var pendingCursorBrowserImport: PendingCursorBrowserImport?

    private func cursorImportRevision() throws -> (Data, UUID?)? {
        guard let config = try self.configStore.load(), config.enabledProviders().contains(UsageProvider.cursor.instanceID),
              let entry = config.providerConfig(for: UsageProvider.cursor.instanceID) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let revision = Data(SHA256.hash(data: try encoder.encode(entry)))
        let accounts = entry.tokenAccounts
        let selected = accounts.flatMap { $0.accounts.isEmpty ? nil : $0.accounts[$0.clampedActiveIndex()].id }
        return (revision, selected)
    }

    public func discoverCursorBrowserAccounts(requestID: UUID = UUID()) async -> CursorBrowserImportResult {
        guard !Task.isCancelled else { return .unavailable("The browser import was cancelled.") }
        guard !self.shuttingDown, self.refreshTask == nil else { return .unavailable("Wait for the current refresh to finish.") }
        self.cancelCursorBrowserImport()
        self.cursorBrowserImportRequest = requestID
        self.pendingCursorBrowserImport = nil
        let privacy = WindowsUsagePresentationSettings.load().hidePersonalInfo
        do {
            guard let (revision, selected) = try self.cursorImportRevision() else { return .unavailable("Enable Cursor before importing an account.") }
            let deadline = Date().addingTimeInterval(60)
            let importer = WindowsCursorBrowserSessionImporter()
            // Profile enumeration and SQLite reads must not occupy the usage runtime actor.
            let discoveryTask = Task.detached(priority: .utility) {
                try importer.discover(deadline: deadline)
            }
            self.cursorBrowserDiscoveryTask = discoveryTask
            defer {
                if self.cursorBrowserImportRequest == requestID { self.cursorBrowserDiscoveryTask = nil }
            }
            let discovery = try await withTaskCancellationHandler {
                try await discoveryTask.value
            } onCancel: {
                discoveryTask.cancel()
            }
            try Task.checkCancellation()
            guard !self.shuttingDown, self.cursorBrowserImportRequest == requestID else {
                return .unavailable("The browser import was cancelled or replaced.")
            }
            var validated: [UUID: WindowsCursorBrowserSessionImporter.ValidatedCandidate] = [:]
            var rows: [CursorBrowserChoice] = []
            var failures = discovery.failedProfileCount
            var attempted = 0
            var seenSessions = Set<Data>()
            for candidate in discovery.candidates.prefix(16) {
                try Task.checkCancellation()
                guard Date() < deadline else { break }
                guard !self.shuttingDown, self.cursorBrowserImportRequest == requestID,
                      try self.cursorImportRevision()?.0 == revision,
                      WindowsUsagePresentationSettings.load().hidePersonalInfo == privacy else {
                    return .unavailable("Cursor accounts or privacy settings changed. Start the import again.")
                }
                attempted += 1
                // Only collapse identical session headers. A user ID alone does not identify
                // a team context, so different sessions for the same user remain selectable.
                let fingerprint = Data(SHA256.hash(data: Data(candidate.cookieHeader.utf8)))
                guard seenSessions.insert(fingerprint).inserted else { continue }
                do {
                    let validationTask = Task.detached(priority: .utility) {
                        try await importer.validate(candidate, deadline: deadline)
                    }
                    self.cursorBrowserValidationTask = validationTask
                    defer {
                        if self.cursorBrowserImportRequest == requestID { self.cursorBrowserValidationTask = nil }
                    }
                    let result = try await withTaskCancellationHandler {
                        try await validationTask.value
                    } onCancel: {
                        validationTask.cancel()
                    }
                    try Task.checkCancellation()
                    guard !self.shuttingDown, self.cursorBrowserImportRequest == requestID else {
                        return .unavailable("The browser import was cancelled or replaced.")
                    }
                    let id = UUID()
                    validated[id] = result
                    let label = privacy ? "Cursor account \(rows.count + 1)" :
                        (result.snapshot.accountEmail ?? result.snapshot.accountName ?? "Cursor account \(rows.count + 1)")
                    let safe = String(LogRedactor.redact(label).unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }.map(String.init).joined().prefix(160))
                    rows.append(.init(id: id, title: safe))
                } catch is CancellationError { throw CancellationError() }
                catch let error as URLError where error.code == .timedOut {
                    failures += 1
                    break
                }
                catch { failures += 1 }
            }
            try Task.checkCancellation()
            guard !self.shuttingDown, self.cursorBrowserImportRequest == requestID,
                  try self.cursorImportRevision()?.0 == revision,
                  WindowsUsagePresentationSettings.load().hidePersonalInfo == privacy else {
                return .unavailable("Cursor accounts or privacy settings changed. Start the import again.")
            }
            guard !rows.isEmpty else {
                if Date() >= deadline {
                    return .unavailable("Cursor browser import reached its time limit. Check connectivity and retry.")
                }
                return .unavailable("No Firefox Cursor session could be verified. Sign in to cursor.com in Firefox and retry.")
            }
            self.pendingCursorBrowserImport = .init(id: requestID, expires: Date().addingTimeInterval(300),
                revision: revision, selectedID: selected, privacy: privacy, candidates: validated)
            return .choices(requestID: requestID, rows: rows, failedCount: failures,
                            omittedCount: discovery.candidates.count - attempted, privacy: privacy)
        } catch {
            return .unavailable("Cursor browser import did not complete. Retry after checking Firefox access.")
        }
    }

    public func cancelCursorBrowserImport(requestID: UUID? = nil) {
        if let requestID, self.cursorBrowserImportRequest != requestID { return }
        self.cursorBrowserValidationTask?.cancel()
        self.cursorBrowserValidationTask = nil
        self.cursorBrowserDiscoveryTask?.cancel()
        self.cursorBrowserDiscoveryTask = nil
        self.cursorBrowserImportRequest = nil
        self.pendingCursorBrowserImport = nil
    }

    public func importCursorBrowserAccount(requestID: UUID, candidateID: UUID, label: String) -> WindowsTokenAccountAddResult {
        guard !self.shuttingDown else { return .shuttingDown }
        guard self.refreshTask == nil else { return .refreshInProgress }
        guard let pending = self.pendingCursorBrowserImport, pending.id == requestID,
              pending.expires > Date(), pending.privacy == WindowsUsagePresentationSettings.load().hidePersonalInfo,
              let candidate = pending.candidates[candidateID] else { return .staleSelection }
        do {
            guard try self.cursorImportRevision()?.0 == pending.revision else { return .staleSelection }
            let result = self.addTokenAccount(.init(providerID: UsageProvider.cursor.instanceID, accountID: candidateID,
                label: label, token: candidate.candidate.cookieHeader, usageScope: nil, organizationID: nil,
                workspaceID: nil, expectedSelectedID: pending.selectedID),
                verifiedExternalIdentifier: candidate.accountID)
            switch result {
            case .saved, .alreadyAdded: self.cancelCursorBrowserImport()
            default: break
            }
            return result
        } catch { return .failed }
    }

    public func addTokenAccount(_ request: WindowsTokenAccountAddRequest) -> WindowsTokenAccountAddResult {
        self.addTokenAccount(request, verifiedExternalIdentifier: nil)
    }

    /// Only a validated browser candidate supplies this identity; free-form account inputs cannot assert it.
    private func addTokenAccount(_ request: WindowsTokenAccountAddRequest,
                                 verifiedExternalIdentifier: String?) -> WindowsTokenAccountAddResult {
        if let identity = verifiedExternalIdentifier {
            guard request.providerID == UsageProvider.cursor.instanceID, !identity.isEmpty,
                  identity.utf8.count <= 512,
                  !identity.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
                return .invalidInput
            }
        }
        guard !self.shuttingDown else { return .shuttingDown }
        guard self.refreshTask == nil else { return .refreshInProgress }
        let token = request.token.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = request.label.trimmingCharacters(in: .whitespacesAndNewlines)
        func field(_ raw: String?) -> String? {
            guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        }
        let scope = field(request.usageScope)?.lowercased(), organization = field(request.organizationID), workspace = field(request.workspaceID)
        guard WindowsAccountInputRules.invalidField(label: label, token: token, scope: scope,
                                                    organization: organization, workspace: workspace) == nil
        else { return .invalidInput }
        do {
            guard let provider = request.providerID.firstPartyProvider,
                  let support = TokenAccountSupportCatalog.support(for: provider),
                  var config = try self.configStore.load(), config.enabledProviders().contains(request.providerID),
                  var entry = config.providerConfig(for: request.providerID) else { return .unavailable }
            guard WindowsAccountInputRules.providerIssue(provider: provider, support: support, scope: scope,
                                                         organization: organization, workspace: workspace) == nil
            else { return .invalidInput }
            let data = entry.tokenAccounts
            let accounts = data?.accounts ?? []
            guard Set(accounts.map(\.id)).count == accounts.count else { return .unavailable }
            let resolvedLabel = label.isEmpty ? "Account \(accounts.count + 1)" : label
            if let existing = accounts.first(where: { $0.id == request.accountID }) {
                guard existing.token == token, (label.isEmpty || existing.label == label),
                      existing.usageScope == scope, existing.organizationID == organization,
                      existing.workspaceID == workspace,
                      existing.externalIdentifier == verifiedExternalIdentifier else { return .staleSelection }
                return .alreadyAdded(existing.id)
            }
            let selectedID = accounts.isEmpty ? nil : accounts[data!.clampedActiveIndex()].id
            guard selectedID == request.expectedSelectedID else { return .staleSelection }
            let account = ProviderTokenAccount(id: request.accountID, label: resolvedLabel, token: token,
                addedAt: Date().timeIntervalSince1970, lastUsed: nil,
                externalIdentifier: verifiedExternalIdentifier, usageScope: scope,
                organizationID: organization, workspaceID: workspace)
            entry.tokenAccounts = ProviderTokenAccountData(version: data?.version ?? 1,
                                                           accounts: accounts + [account], activeIndex: accounts.count)
            if support.clearsAPIKeyOnMutation { entry.apiKey = nil }
            if support.requiresManualCookieSource { entry.cookieSource = .manual }
            config.setProviderConfig(entry)
            try self.configStore.save(config)
            self.latestProviderConfigs[request.providerID] = entry
            self.invalidateSelectedAccountState(request.providerID)
            self.presentations.removeValue(forKey: request.providerID)
            self.providerCopyErrors.removeValue(forKey: request.providerID.rawValue)
            self.renderEntries = [.row("Account added. Refresh usage to load the selected account.")]
            self.statusMenuEntries.removeAll()
            self.publishRenderEntries(settings: WindowsUsagePresentationSettings.load())
            return .saved(account.id)
        } catch { return .failed }
    }

    private func reconcileCodexOwner(_ context: CodexAccountContextSnapshot?) {
        guard let context else {
            if self.observedCodexOwner != nil {
                self.invalidateSelectedAccountState(UsageProvider.codex.instanceID)
            }
            self.observedCodexOwner = nil
            return
        }
        let projection = context.visibleAccounts
        let active = projection.visibleAccounts.first { $0.id == projection.activeVisibleAccountID }
        let source = active?.selectionSource ?? context.resolvedActiveSource.resolvedSource
        let selected = context.selecting(activeSource: source)
        let managedHomePath: String?
        if case let .managedAccount(id) = source {
            managedHomePath = selected.reconciliationSnapshot.storedAccounts.first { $0.id == id }
                .flatMap { CodexHomeScope.normalizedHomePath($0.managedHomePath) }
        } else {
            managedHomePath = nil
        }
        // Compare ownership, not OAuth token rotation or display labels. Retain
        // only the selected owner in memory; never publish or persist this value.
        let current = CodexObservedOwner(
            requestedSource: context.reconciliationSnapshot.activeSource,
            resolvedSource: source,
            identity: selected.identity(for: source),
            managedHomePath: managedHomePath,
            storeUnreadable: selected.reconciliationSnapshot.hasUnreadableAddedAccountStore)
        if let previous = self.observedCodexOwner, previous != current {
            self.invalidateSelectedAccountState(UsageProvider.codex.instanceID)
        }
        self.observedCodexOwner = current
    }

    private func reconcileConfiguredAccounts(_ config: CodexBarConfig) {
        var current: [ProviderInstanceID: String] = [:]
        for id in config.enabledProviders() {
            guard id.firstPartyProvider != nil, let entry = config.providerConfig(for: id) else { continue }
            let data = entry.tokenAccounts
            let account = data.flatMap { $0.accounts.isEmpty ? nil : $0.accounts[$0.clampedActiveIndex()] }
            // Length-prefix every optional field to avoid ambiguous concatenations. Keep only
            // the digest between refreshes; labels and account ordering do not define ownership.
            let fields: [String?] = [account?.id.uuidString, account?.token, account?.externalIdentifier,
                account?.sanitizedUsageScope, account?.sanitizedOrganizationID, account?.sanitizedWorkspaceID,
                entry.apiKey, entry.secretKey, entry.cookieHeader, entry.source?.rawValue,
                entry.cookieSource?.rawValue, entry.region, entry.workspaceID, entry.enterpriseHost]
            let value = fields.map { field in field.map { "s:\($0.utf8.count):\($0)" } ?? "n:" }.joined()
            current[id] = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        if let previous = self.observedAccountSignatures {
            for id in Set(previous.keys).union(current.keys) where previous[id] != current[id] {
                self.invalidateSelectedAccountState(id)
            }
        }
        self.observedAccountSignatures = current
    }

    private func invalidateSelectedAccountState(_ providerID: ProviderInstanceID) {
        self.spendGeneration &+= 1
        self.collectedSpendSources = nil
        self.spendSnapshot = nil
        self.spendState = .idle
        // Delivery adapters run synchronously, preserving order with earlier runtime notifications.
        self.accountInvalidationPublisher(providerID)
        self.dashboardContextCache.removeValue(forKey: providerID)
        // Session transitions are keyed only by provider. The first observation for
        // a newly selected account must establish a baseline, not compare with its predecessor.
        self.sessionQuotaStates.removeValue(forKey: providerID)
        if providerID == UsageProvider.codex.instanceID {
            self.codexSessionQuotaBaselineWatermark = Date()
            self.historicalTrackingGeneration &+= 1
            self.codexHistoricalDataset = nil
            self.codexHistoricalDatasetAccountKey = nil
        }
        // Threshold and pace deduplication already include account discriminators.
        // Retain those histories so returning to an account does not repeat its warning.
    }

    private static func accountLabelRevision(_ label: String) -> String {
        SHA256.hash(data: Data(label.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func credentialEditRevision(_ account: ProviderTokenAccount) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return Data(SHA256.hash(data: try encoder.encode(account)))
    }

    public func beginTokenAccountCredentialEdit(providerID: ProviderInstanceID,
                                                accountID: UUID) -> WindowsTokenAccountCredentialLoadResult {
        guard !self.shuttingDown else { return .shuttingDown }
        guard self.refreshTask == nil else { return .refreshInProgress }
        self.credentialEditTicket = nil
        do {
            guard let provider = providerID.firstPartyProvider,
                  TokenAccountSupportCatalog.support(for: provider) != nil,
                  let config = try self.configStore.load(), config.enabledProviders().contains(providerID),
                  let data = config.providerConfig(for: providerID)?.tokenAccounts,
                  Set(data.accounts.map(\.id)).count == data.accounts.count,
                  let account = data.accounts.first(where: { $0.id == accountID }) else { return .unavailable }
            let ticket = CredentialEditTicket(id: UUID(), providerID: providerID, accountID: accountID,
                revision: try Self.credentialEditRevision(account), expiresAt: Date().addingTimeInterval(600))
            self.credentialEditTicket = ticket
            return .loaded(ticketID: ticket.id, provider: provider)
        } catch { return .failed }
    }

    public func beginTokenAccountMetadataEdit(providerID: ProviderInstanceID,
                                              accountID: UUID) -> WindowsTokenAccountMetadataLoadResult {
        guard !self.shuttingDown else { return .shuttingDown }
        guard self.refreshTask == nil else { return .refreshInProgress }
        self.credentialEditTicket = nil
        do {
            guard let provider = providerID.firstPartyProvider,
                  let support = TokenAccountSupportCatalog.support(for: provider),
                  support.showsOrganizationField || support.showsTeamModeControls,
                  let config = try self.configStore.load(), config.enabledProviders().contains(providerID),
                  let data = config.providerConfig(for: providerID)?.tokenAccounts,
                  Set(data.accounts.map(\.id)).count == data.accounts.count,
                  let account = data.accounts.first(where: { $0.id == accountID }) else { return .unavailable }
            // One disk read supplies both the editor values and its save revision.
            let ticket = CredentialEditTicket(id: UUID(), providerID: providerID, accountID: accountID,
                revision: try Self.credentialEditRevision(account), expiresAt: Date().addingTimeInterval(600))
            self.credentialEditTicket = ticket
            return .loaded(.init(ticketID: ticket.id, provider: provider, usageScope: account.usageScope,
                organizationID: account.organizationID, workspaceID: account.workspaceID))
        } catch { return .failed }
    }

    public func beginTokenAccountRemoval(providerID: ProviderInstanceID,
                                          accountID: UUID) -> WindowsTokenAccountRemovalLoadResult {
        guard !self.shuttingDown else { return .shuttingDown }
        guard self.refreshTask == nil else { return .refreshInProgress }
        self.accountRemovalTicket = nil
        do {
            guard let provider = providerID.firstPartyProvider,
                  TokenAccountSupportCatalog.support(for: provider) != nil,
                  let config = try self.configStore.load(), config.enabledProviders().contains(providerID),
                  let data = config.providerConfig(for: providerID)?.tokenAccounts,
                  Set(data.accounts.map(\.id)).count == data.accounts.count,
                  let account = data.accounts.first(where: { $0.id == accountID }) else { return .unavailable }
            let edit = CredentialEditTicket(id: UUID(), providerID: providerID, accountID: accountID,
                revision: try Self.credentialEditRevision(account), expiresAt: Date().addingTimeInterval(600))
            let selectedID = data.accounts[data.clampedActiveIndex()].id
            self.accountRemovalTicket = .init(edit: edit, selectedID: selectedID, accountIDs: data.accounts.map(\.id))
            let position = (data.accounts.firstIndex { $0.id == accountID } ?? 0) + 1
            let hide = WindowsUsagePresentationSettings.load().hidePersonalInfo
            let filtered = String(LogRedactor.redact(account.label).unicodeScalars.map { scalar in
                scalar.value < 0x20 || scalar.value == 0x7F || (0x202A...0x202E).contains(scalar.value) ||
                    (0x2066...0x2069).contains(scalar.value) ? " " : String(scalar)
            }.joined().prefix(160)).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = hide || filtered.isEmpty ? "Account \(position)" : filtered
            return .loaded(.init(ticketID: edit.id, provider: provider,
                removesSelectedAccount: selectedID == accountID, remainingAccountCount: data.accounts.count - 1,
                accountPosition: position, accountTitle: title, hidePersonalInfo: hide))
        } catch { return .failed }
    }

    public func cancelTokenAccountRemoval(ticketID: UUID) {
        if self.accountRemovalTicket?.edit.id == ticketID { self.accountRemovalTicket = nil }
    }

    /// Call only after the user confirms removal of the account represented by the ticket.
    public func removeTokenAccount(ticketID: UUID) -> WindowsTokenAccountRemovalSaveResult {
        guard !self.shuttingDown else { return .shuttingDown }
        guard self.refreshTask == nil else { return .refreshInProgress }
        guard let removal = self.accountRemovalTicket, removal.edit.id == ticketID else { return .staleAccount }
        self.accountRemovalTicket = nil
        let ticket = removal.edit
        guard ticket.expiresAt > Date() else { return .staleAccount }
        do {
            guard let provider = ticket.providerID.firstPartyProvider,
                  let support = TokenAccountSupportCatalog.support(for: provider),
                  var config = try self.configStore.load(), config.enabledProviders().contains(ticket.providerID),
                  var entry = config.providerConfig(for: ticket.providerID), let data = entry.tokenAccounts,
                  data.accounts.map(\.id) == removal.accountIDs,
                  !data.accounts.isEmpty,
                  data.accounts[data.clampedActiveIndex()].id == removal.selectedID,
                  let index = data.accounts.firstIndex(where: { $0.id == ticket.accountID }),
                  try Self.credentialEditRevision(data.accounts[index]) == ticket.revision else { return .staleAccount }
            let removed = data.accounts[index]
            var remaining = data.accounts
            remaining.remove(at: index)
            if remaining.isEmpty {
                entry.tokenAccounts = nil
            } else {
                let selected = remaining.firstIndex { $0.id == removal.selectedID } ?? min(index, remaining.count - 1)
                entry.tokenAccounts = .init(version: data.version, accounts: remaining, activeIndex: selected)
            }
            let sourceChanged = support.clearsAPIKeyOnMutation && entry.apiKey != nil
            if support.clearsAPIKeyOnMutation { entry.apiKey = nil }
            config.setProviderConfig(entry)
            if provider == .antigravity {
                try self.loadRemovalJournalIfNeeded()
                var pending = self.pendingAntigravityRemovals
                pending[removed.id] = removed
                // Persist intent before removing config. If config save fails, retry sees
                // the still-saved account and preserves its shared credential.
                try self.removalJournal.save(pending)
                self.pendingAntigravityRemovals = pending
            }
            try self.configStore.save(config)
            var cleanupFailed = false
            do {
                try WindowsAccountRemovalCleanup.removeSharedCredentialIfNeeded(
                    provider: provider, removed: removed, remaining: remaining)
                if provider == .antigravity {
                    var pending = self.pendingAntigravityRemovals
                    pending.removeValue(forKey: removed.id)
                    try self.removalJournal.save(pending)
                    self.pendingAntigravityRemovals = pending
                }
            } catch {
                // Config removal already succeeded. Report the partial outcome without secrets.
                cleanupFailed = true
                if provider == .antigravity { self.pendingAntigravityRemovals[removed.id] = removed }
            }
            self.latestProviderConfigs[ticket.providerID] = entry
            if self.credentialEditTicket?.providerID == ticket.providerID,
               self.credentialEditTicket?.accountID == ticket.accountID { self.credentialEditTicket = nil }
            if removal.selectedID == ticket.accountID || sourceChanged || cleanupFailed {
                self.invalidateSelectedAccountState(ticket.providerID)
                self.presentations.removeValue(forKey: ticket.providerID)
                self.providerCopyErrors.removeValue(forKey: ticket.providerID.rawValue)
                self.renderEntries = [.row("Saved account removed. Refresh usage to load the current source.")]
                self.statusMenuEntries.removeAll()
            }
            self.publishRenderEntries(settings: WindowsUsagePresentationSettings.load())
            return cleanupFailed ? .removedWithCacheCleanupFailure : .removed
        } catch { return .failed }
    }

    private func retryPendingAntigravityRemovals(config: CodexBarConfig) {
        do { try self.loadRemovalJournalIfNeeded() }
        catch { self.removalJournalFailed = true; return }
        guard !self.pendingAntigravityRemovals.isEmpty else { return }
        let remaining = config.providerConfig(for: UsageProvider.antigravity.instanceID)?.tokenAccounts?.accounts ?? []
        // A fresh list matters: a user may have re-added the same identity since the failure.
        for (id, removed) in Array(self.pendingAntigravityRemovals) {
            do {
                try WindowsAccountRemovalCleanup.removeSharedCredentialIfNeeded(
                    provider: .antigravity, removed: removed, remaining: remaining)
                var pending = self.pendingAntigravityRemovals
                pending.removeValue(forKey: id)
                try self.removalJournal.save(pending)
                self.pendingAntigravityRemovals = pending
            } catch {
                // Keep the account blocked for this refresh; no credential or filesystem error is logged.
            }
        }
    }

    public func cancelTokenAccountCredentialEdit(ticketID: UUID) {
        if self.credentialEditTicket?.id == ticketID { self.credentialEditTicket = nil }
    }

    /// The replacement contains a secret and must never be logged or returned to the UI.
    public func replaceTokenAccountCredential(ticketID: UUID,
                                              replacement: String) -> WindowsTokenAccountCredentialSaveResult {
        self.updateTokenAccount(ticketID: ticketID, replacement: replacement, metadata: nil)
    }

    /// Reuses the opaque account revision ticket; no credential leaves the runtime.
    public func updateTokenAccountMetadata(ticketID: UUID,
                                           patch: WindowsTokenAccountMetadataPatch) -> WindowsTokenAccountCredentialSaveResult {
        self.updateTokenAccount(ticketID: ticketID, replacement: nil, metadata: patch)
    }

    private func updateTokenAccount(ticketID: UUID, replacement: String?,
                                    metadata: WindowsTokenAccountMetadataPatch?) -> WindowsTokenAccountCredentialSaveResult {
        guard !self.shuttingDown else { return .shuttingDown }
        guard self.refreshTask == nil else { return .refreshInProgress }
        guard let ticket = self.credentialEditTicket, ticket.id == ticketID else { return .staleAccount }
        guard ticket.expiresAt > Date() else {
            self.credentialEditTicket = nil
            return .staleAccount
        }
        let replacementToken = replacement?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let token = replacementToken {
            guard !token.isEmpty, token.utf8.count <= 65_536, !token.contains("\0") else { return .invalidInput }
        }
        do {
            guard let provider = ticket.providerID.firstPartyProvider,
                  let support = TokenAccountSupportCatalog.support(for: provider),
                  var config = try self.configStore.load(), config.enabledProviders().contains(ticket.providerID),
                  var entry = config.providerConfig(for: ticket.providerID), let data = entry.tokenAccounts,
                  Set(data.accounts.map(\.id)).count == data.accounts.count,
                  let index = data.accounts.firstIndex(where: { $0.id == ticket.accountID }),
                  try Self.credentialEditRevision(data.accounts[index]) == ticket.revision else {
                self.credentialEditTicket = nil
                return .staleAccount
            }
            let existing = data.accounts[index]
            let token = replacementToken ?? existing.token
            func applying(_ patch: WindowsTokenAccountFieldPatch?, to current: String?) -> String? {
                guard let patch, case let .replace(value) = patch else { return current }
                guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
                return value
            }
            let scope: String?
            if let patch = metadata?.usageScope, case .replace = patch {
                scope = applying(patch, to: existing.usageScope)?.lowercased()
            } else {
                scope = existing.usageScope
            }
            let organization = applying(metadata?.organizationID, to: existing.organizationID)
            let workspace = applying(metadata?.workspaceID, to: existing.workspaceID)
            if metadata != nil {
                // Use a synthetic token only for the metadata bounds helper; do not
                // reject legacy credential formats during an unrelated metadata edit.
                guard WindowsAccountInputRules.invalidField(label: "", token: "metadata", scope: scope,
                    organization: organization, workspace: workspace) == nil,
                      WindowsAccountInputRules.providerIssue(provider: provider, support: support,
                    scope: scope, organization: organization, workspace: workspace) == nil else { return .invalidInput }
            }
            guard existing.token != token || existing.usageScope != scope ||
                  existing.organizationID != organization || existing.workspaceID != workspace else {
                self.credentialEditTicket = nil
                return .unchanged
            }
            var accounts = data.accounts
            accounts[index] = ProviderTokenAccount(id: existing.id, label: existing.label, token: token,
                addedAt: existing.addedAt, lastUsed: existing.lastUsed,
                externalIdentifier: provider == .cursor && token != existing.token ? nil : existing.externalIdentifier, usageScope: scope,
                organizationID: organization, workspaceID: workspace)
            entry.tokenAccounts = ProviderTokenAccountData(version: data.version, accounts: accounts,
                                                           activeIndex: data.activeIndex)
            let isSelected = index == data.clampedActiveIndex()
            if isSelected {
                if support.clearsAPIKeyOnMutation { entry.apiKey = nil }
                if support.requiresManualCookieSource { entry.cookieSource = .manual }
            }
            config.setProviderConfig(entry)
            try self.configStore.save(config)
            self.credentialEditTicket = nil
            self.latestProviderConfigs[ticket.providerID] = entry
            if isSelected {
                self.invalidateSelectedAccountState(ticket.providerID)
                self.presentations.removeValue(forKey: ticket.providerID)
                self.providerCopyErrors.removeValue(forKey: ticket.providerID.rawValue)
                self.renderEntries = [.row("Account settings updated. Refresh usage to load the account.")]
                self.statusMenuEntries.removeAll()
            }
            self.publishRenderEntries(settings: WindowsUsagePresentationSettings.load())
            return .saved
        } catch { return .failed }
    }

    /// Rename only: no credential normalization, account activation or auth-source mutation.
    public func renameTokenAccount(_ request: WindowsTokenAccountRenameRequest) -> WindowsTokenAccountRenameResult {
        guard !self.shuttingDown else { return .shuttingDown }
        guard self.refreshTask == nil else { return .refreshInProgress }
        let label = request.replacementLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.utf16.count <= 160,
              !label.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            return .invalidLabel
        }
        do {
            guard let provider = request.providerID.firstPartyProvider,
                  TokenAccountSupportCatalog.support(for: provider) != nil,
                  var config = try self.configStore.load(), config.enabledProviders().contains(request.providerID),
                  var entry = config.providerConfig(for: request.providerID), let data = entry.tokenAccounts,
                  Set(data.accounts.map(\.id)).count == data.accounts.count else { return .unavailable }
            guard let index = data.accounts.firstIndex(where: { $0.id == request.accountID }),
                  Self.accountLabelRevision(data.accounts[index].label) == request.expectedLabelRevision else { return .staleAccount }
            let existing = data.accounts[index]
            guard existing.label != label else { return .unchanged }
            var accounts = data.accounts
            accounts[index] = ProviderTokenAccount(
                id: existing.id, label: label, token: existing.token, addedAt: existing.addedAt,
                lastUsed: existing.lastUsed, externalIdentifier: existing.externalIdentifier,
                usageScope: existing.usageScope, organizationID: existing.organizationID,
                workspaceID: existing.workspaceID)
            entry.tokenAccounts = ProviderTokenAccountData(version: data.version, accounts: accounts,
                                                           activeIndex: data.activeIndex)
            config.setProviderConfig(entry)
            try self.configStore.save(config)
            self.latestProviderConfigs[request.providerID] = entry
            // Re-project menu labels without fetching credentials or changing usage ownership.
            self.publishRenderEntries(settings: WindowsUsagePresentationSettings.load())
            return .saved
        } catch { return .failed }
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

    public func spendSettingsDidChange() async {
        guard !self.shuttingDown else { return }
        let settings = WindowsSpendSettings.load()
        let previousSnapshot = self.spendSnapshot
        let previousSettings = self.collectedSpendSettings
        let controller = self.spendController
        let canReproject = self.refreshTask == nil && self.spendState == .available &&
            previousSettings?.usesSameCollection(as: settings) == true && previousSnapshot != nil
        self.spendGeneration &+= 1
        let generation = self.spendGeneration
        self.spendSnapshot = nil
        self.spendState = .idle
        if canReproject, let controller, let previousSnapshot {
            self.spendState = .collecting
            if previousSettings?.preferredCurrencyCode != settings.preferredCurrencyCode {
                await CurrencyExchange.shared.fetchLatestRatesIfNeeded(preferredCurrencyCode: settings.preferredCurrencyCode)
            }
            guard !self.shuttingDown, generation == self.spendGeneration else { return }
            let result = await controller.setOptions(settings.dashboardOptions)
            guard !self.shuttingDown, generation == self.spendGeneration else { return }
            if case .applied = result {
                // Reprojection keeps the captured data boundary, including across local midnight.
                let snapshot = await controller.snapshot(now: previousSnapshot.loadedAt ?? Date())
                guard !self.shuttingDown, generation == self.spendGeneration else { return }
                if WindowsSpendSettings.load() == settings {
                    self.collectedSpendSettings = settings
                    self.spendSnapshot = snapshot
                    self.spendState = .available
                    return
                }
            }
        }
        // Source/calendar changes, missing data, or a stopped controller need a fresh scan.
        let refreshing = self.refreshTask != nil
        if refreshing { self.queuedSpendRefresh = true }
        self.spendController = nil
        if let controller { await controller.stop() }
        guard !self.shuttingDown, generation == self.spendGeneration else { return }
        if !refreshing { await self.refresh() }
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
            let spendRefreshNeeded = self.queuedSpendRefresh
            let codexWebSettingsRefreshNeeded = self.queuedCodexWebSettingsRefresh
            guard !self.shuttingDown,
                  optionalRefreshNeeded || predictiveSettingsRefreshNeeded || codexWebSettingsRefreshNeeded || spendRefreshNeeded
            else {
                self.queuedSpendRefresh = false
                self.queuedOptionalRefresh = false
                self.queuedPredictiveSettingsRefresh = false
                self.queuedCodexWebSettingsRefresh = false
                break
            }
            self.queuedSpendRefresh = false
            self.queuedOptionalRefresh = false
            self.queuedPredictiveSettingsRefresh = false
            self.queuedCodexWebSettingsRefresh = false
        }
        while !self.shuttingDown
        self.resumeRefreshCompletionWaiters()
    }

    private func performRefresh() async {
        self.spendGeneration &+= 1
        self.spendSnapshot = nil
        self.spendState = .idle
        let refreshQuotaWarningGeneration = self.quotaWarningGeneration
        let refreshPredictivePaceWarningGeneration = self.predictivePaceWarningGeneration
        let presentationSettings = WindowsUsagePresentationSettings.load()
        let fetchOptionalUsage = presentationSettings.showOptionalCreditsAndExtraUsage
        do {
            if !self.pluginDiscoveryInitialized {
                _ = UserProviderPluginRegistry.refresh()
                self.pluginDiscoveryInitialized = true
            }
            let config = try self.configStore.loadOrCreateDefault()
            self.reconcileConfiguredAccounts(config)
            self.retryPendingAntigravityRemovals(config: config)
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
            self.reconcileCodexOwner(codexAccountContext)
            let refreshHistoricalTrackingGeneration = self.historicalTrackingGeneration
            var entries: [RenderEntry] = []
            self.presentations.removeAll(keepingCapacity: true)
            self.providerCopyErrors.removeAll(keepingCapacity: true)
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
                if provider == .antigravity, self.removalJournalFailed || !self.pendingAntigravityRemovals.isEmpty {
                    let message = "Antigravity: shared authentication cache cleanup is pending. Usage collection is paused; refresh retries cleanup."
                    self.providerCopyErrors[provider.rawValue] = message
                    entries.append(.row(message))
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
                guard let provider = instanceID.firstPartyProvider else {
                    let errorText = self.providerCopyErrors[instanceID.rawValue]
                    guard errorText != nil || self.presentations[instanceID] != nil else { return nil }
                    let name = UserProviderPluginRegistry.plugin(for: instanceID)?.manifest.name ?? "Missing plugin"
                    let title = LogRedactor.redact("\(name) [\(instanceID.rawValue)]")
                        .replacingOccurrences(of: "\0", with: "")
                    return WindowsTrayMenuEntry(
                        providerID: instanceID.rawValue,
                        title: String(title.prefix(160)),
                        statusURL: nil,
                        statusVisible: false,
                        dashboardVisible: false,
                        errorCopyText: errorText)
                }
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
                    disabledText: metadata.statusPageURL == nil && metadata.statusLinkURL == nil ? "unavailable" : nil,
                    errorCopyText: self.providerCopyErrors[provider.rawValue])
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
            await self.collectSpend(config: config, codexContext: codexAccountContext)
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

    private func collectSpend(config: CodexBarConfig, codexContext: CodexAccountContextSnapshot?) async {
        guard !self.shuttingDown, !Task.isCancelled else { return }
        let generation = self.spendGeneration
        let settings = WindowsSpendSettings.load()
        guard !self.shuttingDown, generation == self.spendGeneration, !Task.isCancelled else { return }
        guard !settings.enabledProviders(config: config).isEmpty || settings.openCodexUsageLogsEnabled else {
            if let previous = self.spendController { await previous.stop() }
            self.spendController = nil
            self.collectedSpendSources = nil
            self.spendState = .disabled
            return
        }
        do {
            // Pin the calendar before a first enabled scan. Loading preferences alone never writes.
            try settings.save()
            let sources = try WindowsSpendSourceResolver.resolve(config: config, settings: settings,
                environment: ProcessInfo.processInfo.environment,
                cacheRoot: self.configStore.fileURL.deletingLastPathComponent()
                    .appendingPathComponent("spend-cache", isDirectory: true),
                codexContext: codexContext)
            let canReuse = self.collectedSpendSettings == settings && self.collectedSpendSources == sources &&
                !settings.openCodexUsageLogsEnabled && !sources.isEmpty &&
                sources.allSatisfy(\.supportsRetainedCollection)
            let controller: WindowsSpendDashboardController
            if canReuse, let previous = self.spendController {
                controller = previous
                let previousSnapshot = await previous.snapshot()
                guard !self.shuttingDown, generation == self.spendGeneration, !Task.isCancelled else { return }
                self.spendSnapshot = previousSnapshot.refreshing()
            } else {
                if let previous = self.spendController { await previous.stop() }
                controller = WindowsSpendDashboardController(
                loader: WindowsSpendSnapshotLoader.make(sources: sources, settings: settings,
                    openCodexCacheRoot: self.configStore.fileURL.deletingLastPathComponent()
                        .appendingPathComponent("opencodex-cache", isDirectory: true)),
                options: settings.dashboardOptions, publisher: { _ in })
            }
            guard !self.shuttingDown, generation == self.spendGeneration, !Task.isCancelled else {
                await controller.stop()
                return
            }
            self.spendController = controller
            self.spendState = .collecting
            // The original converter refreshes non-USD rates at most daily and retains fallback rates on failure.
            await CurrencyExchange.shared.fetchLatestRatesIfNeeded(preferredCurrencyCode: settings.preferredCurrencyCode)
            guard !self.shuttingDown, generation == self.spendGeneration, !Task.isCancelled else { return }
            await controller.refresh()
            guard !self.shuttingDown, generation == self.spendGeneration, !Task.isCancelled else { return }
            // External preference changes while scanning must not publish the old configuration.
            guard WindowsSpendSettings.load() == settings else {
                await controller.stop()
                self.spendController = nil
                self.spendSnapshot = nil
                self.collectedSpendSources = nil
                self.collectedSpendSettings = nil
                self.spendState = .idle
                return
            }
            let snapshot = await controller.snapshot()
            guard !self.shuttingDown, generation == self.spendGeneration, !Task.isCancelled else { return }
            self.collectedSpendSources = sources
            self.collectedSpendSettings = settings
            self.spendSnapshot = snapshot
            self.spendState = snapshot.phase == .failed ? .failed : .available
        } catch {
            guard !self.shuttingDown, generation == self.spendGeneration else { return }
            // Do not expose credential, path, or configuration decoder diagnostics to the dashboard.
            self.spendSnapshot = nil
            self.spendState = .failed
        }
    }

    private func publishRenderEntries(settings: WindowsUsagePresentationSettings) {
        guard !self.shuttingDown else { return }
        var copyRows: [String: String] = [:]
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
                let rows = updated.rows()
                copyRows[presentation.instanceID.rawValue] = WindowsClipboard.summary(rows: rows)
                return rows
            case let .row(row): return [row]
            }
        }
        let displayRows = rendered.isEmpty ? ["No providers are enabled"] : rendered
        let publishedRows = settings.hidePersonalInfo ? displayRows.map { LogRedactor.redact($0) } : displayRows
        self.publisher(publishedRows)
        let copyEntries = self.statusMenuEntries.map { entry in
            var updated = entry
            updated.usageCopyText = copyRows[entry.providerID]
            if let provider = UsageProvider(rawValue: entry.providerID),
               let support = TokenAccountSupportCatalog.support(for: provider),
               let data = self.latestProviderConfigs[provider.instanceID]?.tokenAccounts,
               !data.accounts.isEmpty, Set(data.accounts.map(\.id)).count == data.accounts.count {
                let accounts = data.accounts.enumerated().map { index, account in
                    let fallback = "Account \(index + 1)"
                    let title = settings.hidePersonalInfo ? fallback :
                        String(LogRedactor.redact(account.label).replacingOccurrences(of: "\0", with: "").prefix(160))
                    return WindowsTokenAccountSelectionSnapshot.Account(id: account.id,
                                                                          title: title.isEmpty ? fallback : title,
                                                                          labelRevision: Self.accountLabelRevision(account.label))
                }
                updated.tokenAccountSelection = .init(providerID: provider.instanceID, accounts: accounts,
                    selectedID: data.accounts[data.clampedActiveIndex()].id,
                    requiresManualSource: support.requiresManualCookieSource)
            }
            return updated
        }
        self.combinedPublisher(publishedRows, copyEntries)
    }

    public func shutdown() async {
        guard !self.shuttingDown else { return }
        self.shuttingDown = true
        self.cancelCursorBrowserImport()
        self.queuedSpendRefresh = false
        self.spendGeneration &+= 1
        self.spendSnapshot = nil
        self.spendState = .stopped
        if let controller = self.spendController { await controller.stop() }
        self.spendController = nil
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
        self.observedAccountSignatures = nil
        self.observedCodexOwner = nil
        self.credentialEditTicket = nil
        self.accountRemovalTicket = nil
        self.pendingAntigravityRemovals.removeAll()
        self.removalJournalLoaded = false
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
            body: restored ? "Session quota is available again." : "0% left. Will notify when it's available again.",
            providerID: provider.instanceID))
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
                currentRemaining: candidate.window.remainingPercent, accountDisplayName: accountDisplayName, windowDisplayLabel: candidate.displayLabel, providerID: key.provider.instanceID))
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
                    ? nil : snapshot.accountEmail(for: provider), providerID: provider.instanceID))
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
                selectedTokenAccountExternalIdentifier: account?.externalIdentifier,
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
                self.providerCopyErrors[provider.rawValue] = WindowsClipboard.summary(rows: [provider.rawValue, error.localizedDescription])
                return ["\(provider.rawValue): \(error.localizedDescription)"]
            }
        } catch is CancellationError {
            return []
        } catch {
            self.recordStartupConnectivityRetryableFailure(error)
            self.providerCopyErrors[provider.rawValue] = WindowsClipboard.summary(rows: [provider.rawValue, error.localizedDescription])
                return ["\(provider.rawValue): \(error.localizedDescription)"]
        }
    }

    private func fetchPluginRows(instanceID: ProviderInstanceID, config: CodexBarConfig, presentationSettings: WindowsUsagePresentationSettings) async -> [String] {
        guard let plugin = UserProviderPluginRegistry.plugin(for: instanceID) else {
            let message = "\(instanceID.rawValue): plugin not found"
            self.providerCopyErrors[instanceID.rawValue] = WindowsClipboard.summary(rows: [message])
            return [message]
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
            self.providerCopyErrors[instanceID.rawValue] = WindowsClipboard.summary(
                rows: [plugin.manifest.name, instanceID.rawValue, error.localizedDescription])
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
