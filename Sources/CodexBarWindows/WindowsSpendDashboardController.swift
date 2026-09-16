#if os(Windows)
import Foundation
import CodexBarCore

/// Owns one coherent spend scan. Native UI can change its projection without rescanning logs.
actor WindowsSpendDashboardController {
    struct SourceFailure: Sendable {
        let sourceID: String
        let provider: UsageProvider
        var accountIdentityUnconfirmed = false
        var localInventoryPending = false
        var discoveredFiles: Int? = nil
        var completedFiles: Int? = nil
        var verifyingContent = false
        // Display a generic explanation; never retain raw provider/credential error text.
    }
    struct Scan: Sendable {
        var inputs: [WindowsSpendDashboardModel.ProviderInput]
        let subscriptionNames: [String: WindowsShareStatsSubscriptionName]
        var sourceFailures: [SourceFailure] = []
        var openCodexObservation: WindowsOpenCodexSpendSource.Observation = .disabled
        var capturedAt: Date = Date()
        var widgetCosts: [WindowsWidgetSnapshotBuilder.CostOnlyObservation] = []
        var widgetCostFailures: [SourceFailure] = []
        var retentionEligibleSourceIDs: Set<String> = []
    }
    struct Options: Sendable {
        var days = 30
        var bucketTimeZoneIdentifier = CostUsageBucketTimeZone.pinIdentifier()
        var preferredCurrencyCode = "auto"
        var hiddenSourceIDs: Set<String> = []
        var hideNativeCodexWhenOpenCodexPresent = false
        var selectedDay: Date?
    }
    enum Phase: Sendable { case idle, refreshing, ready, partial, failed, stopped }
    enum OptionsResult: Sendable { case applied, requiresCollectionReconfiguration, stopped }
    enum Failure: Sendable { case scanFailed, duplicateSourceIDs }
    enum WidgetCostPublication: Sendable {
        /// Source context was removed, replaced, or stopped; withdraw prior widget costs.
        case withdrawn
        /// No new costs are being published while collection is pending.
        case pending
        case failed
        /// Successful sources remain usable independently of source-specific failures.
        case available(costs: [WindowsWidgetSnapshotBuilder.CostOnlyObservation], failures: [SourceFailure])
    }
    struct Snapshot: Sendable {
        let generation: UInt64
        let phase: Phase
        let model: WindowsSpendDashboardModel
        let sharePayload: WindowsShareStatsPayload?
        let loadedAt: Date?
        let stale: Bool
        let failure: Failure?
        let openCodexObservation: WindowsOpenCodexSpendSource.Observation
        let sourceFailures: [SourceFailure]
        var widgetPublication: WidgetCostPublication = .withdrawn
        var continuingLocalDiscovery = false
        var retainedSourceDates: [String: Date] = [:]
        var publicationSequence: UInt64 = 0

        func refreshing() -> Self {
            Self(generation: self.generation, phase: .refreshing, model: self.model, sharePayload: nil,
                 loadedAt: self.loadedAt, stale: true, failure: nil,
                 openCodexObservation: self.openCodexObservation, sourceFailures: self.sourceFailures, widgetPublication: .pending,
                 continuingLocalDiscovery: self.continuingLocalDiscovery, retainedSourceDates: self.retainedSourceDates,
                 publicationSequence: self.publicationSequence)
        }
    }
    typealias Loader = @Sendable (_ historyDays: Int) async throws -> Scan
    typealias ContinuationLoader = @Sendable (_ historyDays: Int, _ sourceIDs: Set<String>) async throws -> Scan
    typealias ContinuationPause = @Sendable () async throws -> Void
    typealias Publisher = @Sendable (Snapshot) -> Void

    private var loader: Loader
    private var publisher: Publisher
    private var continuationLoader: ContinuationLoader?
    private let continuationPause: ContinuationPause
    private var continuationTask: Task<Void, Never>?
    private var publicationSequence: UInt64 = 0
    private var retainedInputs: [String: WindowsSpendDashboardModel.ProviderInput] = [:]
    private var options = Options()
    private var scan: Scan?
    private var loadedAt: Date?
    private var phase: Phase = .idle
    private var failure: Failure?
    private var generation: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    private var stopped = false

    /// The loader must use the same bucket calendar as these options.
    init(loader: @escaping Loader, continuationLoader: ContinuationLoader? = nil,
         continuationPause: @escaping ContinuationPause = { try await Task.sleep(for: .milliseconds(250)) },
         options: Options = Options(), publisher: @escaping Publisher) {
        self.loader = loader
        self.continuationLoader = continuationLoader
        self.continuationPause = continuationPause
        self.options = Self.normalized(options)
        self.publisher = publisher
    }

    func setPublisher(_ publisher: @escaping Publisher) { self.publisher = publisher }

    @discardableResult
    func setOptions(_ options: Options) -> OptionsResult {
        guard !self.stopped else { return .stopped }
        let normalized = Self.normalized(options)
        guard normalized.bucketTimeZoneIdentifier == self.options.bucketTimeZoneIdentifier else {
            return .requiresCollectionReconfiguration
        }
        self.options = normalized
        self.publish()
        return .applied
    }

    /// Replace source credentials/account ownership or the bucket calendar as one operation.
    /// Construct the replacement loader with the same calendar as options before calling this.
    @discardableResult
    func replaceCollection(loader: @escaping Loader, continuationLoader: ContinuationLoader? = nil,
                           options: Options) -> Bool {
        guard !self.stopped else { return false }
        self.clearCollection()
        self.loader = loader
        self.continuationLoader = continuationLoader
        self.options = Self.normalized(options)
        self.publish()
        return true
    }

    private static func normalized(_ options: Options) -> Options {
        var result = options
        result.days = max(1, min(WindowsSpendHistoryPolicy.scanDays, options.days))
        result.bucketTimeZoneIdentifier = CostUsageBucketTimeZone
            .timeZone(identifier: options.bucketTimeZoneIdentifier).identifier
        return result
    }

    func snapshot(now: Date = Date()) -> Snapshot {
        self.makeSnapshot(options: self.options, now: now)
    }

    /// Project a day without changing the dashboard or sharing preferences.
    func snapshot(forDay day: Date, now: Date) -> Snapshot {
        var options = self.options
        options.selectedDay = day
        return self.makeSnapshot(options: options, now: now)
    }

    private func makeSnapshot(options: Options, now: Date) -> Snapshot {
        let displayedInputs = (self.scan?.inputs ?? []) + self.retainedInputs.values.sorted { $0.id < $1.id }
        let model = WindowsSpendDashboardModel.build(inputs: displayedInputs,
            requestedDays: options.days, now: now,
            calendar: CostUsageBucketTimeZone.calendar(identifier: options.bucketTimeZoneIdentifier),
            preferredCurrencyCode: options.preferredCurrencyCode,
            hiddenSourceIDs: options.hiddenSourceIDs,
            hideNativeCodexWhenOpenCodexPresent: options.hideNativeCodexWhenOpenCodexPresent,
            selectedDay: options.selectedDay)
        // Failed/refreshing data remains visible with stale status but is not offered for sharing.
        let share = self.phase == .ready && self.retainedInputs.isEmpty
            ? WindowsShareStatsBuilder.make(model: model, subscriptionNames: self.scan?.subscriptionNames ?? [:]) : nil
        let widgetPublication: WidgetCostPublication
        switch self.phase {
        case .idle, .stopped: widgetPublication = .withdrawn
        case .refreshing: widgetPublication = .pending
        case .failed: widgetPublication = .failed
        case .ready, .partial:
            if let scan = self.scan {
                widgetPublication = .available(costs: scan.widgetCosts,
                    failures: scan.sourceFailures + scan.widgetCostFailures)
            } else { widgetPublication = .withdrawn }
        }
        return Snapshot(generation: self.generation, phase: self.phase, model: model, sharePayload: share,
            loadedAt: self.loadedAt, stale: !self.retainedInputs.isEmpty
                || (self.scan != nil && (self.phase == .refreshing || self.phase == .failed)),
            failure: self.failure, openCodexObservation: self.scan?.openCodexObservation ?? .disabled,
            sourceFailures: self.scan?.sourceFailures ?? [], widgetPublication: widgetPublication,
            continuingLocalDiscovery: self.continuationTask != nil,
            retainedSourceDates: self.retainedInputs.mapValues { $0.snapshot.updatedAt },
            publicationSequence: self.publicationSequence)
    }

    func refresh() async {
        guard !self.stopped else { return }
        // The active collection already has a continuation; do not rescan completed sources.
        if self.continuationTask != nil { return }
        if let task = self.refreshTask { await task.value; return }
        self.generation &+= 1
        let generation = self.generation
        self.phase = .refreshing
        self.failure = nil
        self.publish()
        let loader = self.loader
        let task = Task { await self.performRefresh(generation: generation, loader: loader) }
        self.refreshTask = task
        await task.value
        if self.generation == generation { self.refreshTask = nil }
    }

    /// Withdraw current data without changing the configured loader.
    /// Old owner data is withdrawn immediately, including if cancellation is ignored by a loader.
    func invalidateSourceContext() {
        guard !self.stopped else { return }
        self.clearCollection()
        self.publish()
    }

    private func clearCollection() {
        self.generation &+= 1
        self.refreshTask?.cancel()
        self.refreshTask = nil
        self.continuationTask?.cancel()
        self.continuationTask = nil
        self.retainedInputs = [:]
        self.scan = nil
        self.loadedAt = nil
        self.failure = nil
        self.phase = .idle
    }

    func stop() {
        self.stopped = true
        self.generation &+= 1
        self.refreshTask?.cancel()
        self.refreshTask = nil
        self.continuationTask?.cancel()
        self.continuationTask = nil
        self.retainedInputs = [:]
        self.scan = nil
        self.loadedAt = nil
        self.failure = nil
        self.phase = .stopped
        self.publish()
    }

    private func performRefresh(generation: UInt64, loader: Loader) async {
        guard !self.stopped, self.generation == generation else { return }
        do {
            try Task.checkCancellation()
            let scan = try await loader(WindowsSpendHistoryPolicy.scanDays)
            try Task.checkCancellation()
            guard !self.stopped, self.generation == generation else { return }
            guard self.install(scan) else { self.publish(); return }
            self.scheduleContinuation(generation: generation)
        } catch {
            guard !self.stopped, self.generation == generation else { return }
            self.failure = .scanFailed
            self.phase = .failed
        }
        self.publish()
    }

    private func install(_ next: Scan) -> Bool {
        let ids = next.inputs.map(\.id) + next.sourceFailures.map(\.sourceID)
        guard Set(ids).count == ids.count else {
            self.failure = .duplicateSourceIDs
            self.phase = .failed
            return false
        }
        var prior = self.retainedInputs
        for input in self.scan?.inputs ?? [] where input.sourceKind == .native { prior[input.id] = input }
        self.retainedInputs = [:]
        for failure in next.sourceFailures where failure.localInventoryPending && !failure.accountIdentityUnconfirmed {
            guard next.openCodexObservation == .disabled,
                  next.retentionEligibleSourceIDs.contains(failure.sourceID),
                  let input = prior[failure.sourceID], input.provider == failure.provider else { continue }
            self.retainedInputs[failure.sourceID] = input
        }
        self.scan = next
        self.loadedAt = next.capturedAt
        self.phase = next.sourceFailures.isEmpty && next.openCodexObservation != .unavailable ? .ready : .partial
        self.failure = nil
        return true
    }

    private var pendingSourceIDs: Set<String> {
        Set((self.scan?.sourceFailures ?? []).filter(\.localInventoryPending).map(\.sourceID))
    }

    private func scheduleContinuation(generation: UInt64) {
        guard self.continuationLoader != nil, !self.pendingSourceIDs.isEmpty,
              self.continuationTask == nil else { return }
        self.continuationTask = Task { await self.continueCollection(generation: generation) }
    }

    private func continueCollection(generation: UInt64) async {
        guard let resume = self.continuationLoader else { return }
        do {
            while !self.stopped, self.generation == generation, !self.pendingSourceIDs.isEmpty {
                try await self.continuationPause()
                try Task.checkCancellation()
                guard !self.stopped, self.generation == generation else { return }
                let pending = self.pendingSourceIDs
                let next = try await resume(WindowsSpendHistoryPolicy.scanDays, pending)
                try Task.checkCancellation()
                guard !self.stopped, self.generation == generation else { return }
                guard self.install(next) else {
                    self.continuationTask = nil
                    self.publish()
                    return
                }
                if self.pendingSourceIDs.isEmpty { self.continuationTask = nil }
                self.publish()
            }
        } catch {
            guard !self.stopped, self.generation == generation else { return }
            self.continuationTask = nil
            self.failure = .scanFailed
            self.phase = .failed
            self.publish()
        }
    }

    private func publish() {
        self.publicationSequence &+= 1
        self.publisher(self.snapshot())
    }
}
#endif
