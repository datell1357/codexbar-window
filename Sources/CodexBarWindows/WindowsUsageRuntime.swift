#if os(Windows)
import CodexBarCore
import AdaptiveRefreshCore
import Foundation

/// Owns the Windows tray's provider refresh lifecycle.  Win32 callbacks only
/// enqueue work; all provider I/O stays on this actor and is serialized.
public actor WindowsUsageRuntime {
    public typealias RowPublisher = @Sendable ([String]) -> Void
    public struct RefreshSignals: Sendable {
        public var lowPowerModeEnabled: Bool
        /// Windows adapters may report thermal pressure once available. Until
        /// then this remains a public boolean to avoid exposing core package
        /// implementation types across the executable boundary.
        public var thermalConstrained: Bool

        public init(
            lowPowerModeEnabled: Bool = false,
            thermalConstrained: Bool = false)
        {
            self.lowPowerModeEnabled = lowPowerModeEnabled
            self.thermalConstrained = thermalConstrained
        }
    }
    public typealias RefreshSignalProvider = @Sendable () -> RefreshSignals

    private let configStore: CodexBarConfigStore
    private let browserDetection: BrowserDetection
    private let fetcher: UsageFetcher
    private let claudeFetcher: ClaudeUsageFetcher
    private let pluginApprovalStore: ProviderPluginApprovalStore
    private var publisher: RowPublisher
    private var refreshTask: Task<Void, Never>?
    private var scheduleTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var scheduledDeadline: ContinuousClock.Instant?
    private let signalProvider: RefreshSignalProvider
    private var lastMenuOpenedAt: Date?
    private var refreshSettings: WindowsRefreshSettings
    private var pluginDiscoveryInitialized = false
    private var shuttingDown = false

    public init(
        configStore: CodexBarConfigStore = CodexBarConfigStore(),
        publisher: @escaping RowPublisher = { _ in },
        signalProvider: @escaping RefreshSignalProvider = { RefreshSignals() })
    {
        let browserDetection = BrowserDetection()
        self.configStore = configStore
        self.browserDetection = browserDetection
        self.fetcher = UsageFetcher()
        self.claudeFetcher = ClaudeUsageFetcher(browserDetection: browserDetection)
        self.pluginApprovalStore = ProviderPluginApprovalStore()
        self.publisher = publisher
        self.signalProvider = signalProvider
        self.refreshSettings = WindowsRefreshSettings.load()
    }

    public func setPublisher(_ publisher: @escaping RowPublisher) {
        self.publisher = publisher
    }

    /// Performs the initial refresh and starts the selected cadence exactly once.
    public func start() async {
        guard !self.shuttingDown, self.scheduleTask == nil else { return }
        self.refreshSettings = WindowsRefreshSettings.load()
        self.scheduleTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            await self.runRefreshSchedule()
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

    /// Refreshes enabled providers once. A second request while a
    /// refresh is in flight is intentionally coalesced instead of overlapping
    /// credential and warm-session work.
    public func refresh() async {
        guard !self.shuttingDown, self.refreshTask == nil else { return }
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh()
        }
        self.refreshTask = task
        await task.value
        self.refreshTask = nil
    }

    private func performRefresh() async {
        do {
            if !self.pluginDiscoveryInitialized {
                _ = UserProviderPluginRegistry.refresh()
                self.pluginDiscoveryInitialized = true
            }
            let config = try self.configStore.loadOrCreateDefault()
            let accountContext = try TokenAccountCLIContext(
                selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: false),
                config: config,
                verbose: false)
            var rows: [String] = []
            for instanceID in config.enabledProviders() {
                try Task.checkCancellation()
                guard let provider = instanceID.firstPartyProvider else {
                    rows.append(contentsOf: await self.fetchPluginRows(
                        instanceID: instanceID,
                        config: config))
                    continue
                }
                if provider == .codex {
                    let configuredAccounts = try? accountContext.resolvedAccounts(for: provider)
                    if let configuredAccounts, !configuredAccounts.isEmpty {
                        rows.append(contentsOf: await self.fetchRows(provider: provider, context: accountContext))
                    } else {
                        let projection = accountContext.visibleCodexAccounts()
                        let active = projection.visibleAccounts.first {
                            $0.id == projection.activeVisibleAccountID
                        }
                        rows.append(contentsOf: await self.fetchRows(
                            provider: provider,
                            context: accountContext,
                            codexVisibleAccount: active))
                    }
                } else {
                    rows.append(contentsOf: await self.fetchRows(provider: provider, context: accountContext))
                }
            }
            if self.refreshSettings.frequency == .adaptiveAgentAware
            {
                rows.append("Windows activity scanner unavailable; automatic refresh disabled")
            }
            guard !self.shuttingDown else { return }
            self.publisher(rows.isEmpty ? ["No providers are enabled"] : rows)
        } catch is CancellationError {
            return
        } catch {
            self.publisher(["CodexBar: \(error.localizedDescription)"])
        }
    }

    public func shutdown() async {
        guard !self.shuttingDown else { return }
        self.shuttingDown = true
        let task = self.refreshTask
        task?.cancel()
        self.sleepTask?.cancel()
        let schedule = self.scheduleTask
        schedule?.cancel()
        if let schedule { await schedule.value }
        self.scheduleTask = nil
        self.sleepTask = nil
        if let task { await task.value }
        self.refreshTask = nil
        await CLIProbeSessionResetter.resetAll()
    }

    private func runRefreshSchedule() async {
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
        while !Task.isCancelled {
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
            self.sleepTask = nil
            if Task.isCancelled { return }
            if self.scheduledDeadline != deadline { continue }
            guard !Task.isCancelled else { return }
            await self.refresh()
            if !frequency.usesAdaptivePolicy {
                let completedAt = clock.now
                repeat { scheduledAt += fixedInterval }
                while scheduledAt <= completedAt
                self.scheduledDeadline = scheduledAt
            } else {
                self.scheduledDeadline = nil
            }
        }
    }

    private func fetchRows(
        provider: UsageProvider,
        context: TokenAccountCLIContext,
        codexVisibleAccount: CodexVisibleAccount? = nil) async -> [String]
    {
        do {
            let account: ProviderTokenAccount? = if codexVisibleAccount == nil {
                try context.resolvedAccounts(for: provider).first
            } else {
                nil
            }
            let sourceOverride = codexVisibleAccount?.selectionSource
            let env = context.environment(
                base: ProcessInfo.processInfo.environment,
                provider: provider,
                account: account,
                codexActiveSourceOverride: sourceOverride)
            let settings = context.settingsSnapshot(
                for: provider,
                account: account,
                codexActiveSourceOverride: sourceOverride)
            let source = context.effectiveSourceMode(
                base: context.preferredSourceMode(for: provider),
                provider: provider,
                account: account)
            let fetchContext = ProviderFetchContext(
                runtime: .app,
                sourceMode: source,
                includeCredits: true,
                requiresOptionalUsageCompleteness: true,
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
                persistentCLISessionIdleWindow: 900)
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
                let window = labeledUsage.primary ?? labeledUsage.secondary
                guard let window else { return [metadata.displayName] }
                let value = UsageFormatter.usageLine(remaining: window.remainingPercent, used: window.usedPercent, showUsed: false)
                let resetText = UsageFormatter.resetLine(for: window, style: .countdown)
                let reset = resetText.map { " · \($0)" } ?? ""
                let accountLabel = labeledUsage.accountEmail(for: provider)
                let title = accountLabel.map { "\(metadata.displayName) [\($0)]" } ?? metadata.displayName
                return ["\(title): \(value)\(reset)".trimmingCharacters(in: .whitespaces)]
            case let .failure(error):
                return ["\(provider.rawValue): \(error.localizedDescription)"]
            }
        } catch is CancellationError {
            return []
        } catch {
            return ["\(provider.rawValue): \(error.localizedDescription)"]
        }
    }

    private func fetchPluginRows(instanceID: ProviderInstanceID, config: CodexBarConfig) async -> [String] {
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
            guard let window = snapshot.primary ?? snapshot.secondary else {
                return [plugin.manifest.name]
            }
            let value = UsageFormatter.usageLine(
                remaining: window.remainingPercent,
                used: window.usedPercent,
                showUsed: false)
            let accountLabel = snapshot.identity(for: instanceID)?.accountEmail
            let title = accountLabel.map { "\(plugin.manifest.name) [\($0)]" } ?? plugin.manifest.name
            return ["\(title): \(value)"]
        } catch is CancellationError {
            return []
        } catch {
            return ["\(plugin.manifest.name): \(error.localizedDescription)"]
        }
    }
}
#endif
