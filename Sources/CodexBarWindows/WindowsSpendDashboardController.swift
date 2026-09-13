#if os(Windows)
import Foundation
import CodexBarCore

/// Owns one coherent spend scan. Native UI can change its projection without rescanning logs.
actor WindowsSpendDashboardController {
    struct SourceFailure: Sendable {
        let sourceID: String
        let provider: UsageProvider
        // Display a generic explanation; never retain raw provider/credential error text.
    }
    struct Scan: Sendable {
        let inputs: [WindowsSpendDashboardModel.ProviderInput]
        let subscriptionNames: [String: WindowsShareStatsSubscriptionName]
        var sourceFailures: [SourceFailure] = []
        var openCodexObservation: WindowsOpenCodexSpendSource.Observation = .disabled
        var capturedAt: Date = Date()
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
    }
    typealias Loader = @Sendable (_ historyDays: Int) async throws -> Scan
    typealias Publisher = @Sendable (Snapshot) -> Void

    private var loader: Loader
    private let publisher: Publisher
    private var options = Options()
    private var scan: Scan?
    private var loadedAt: Date?
    private var phase: Phase = .idle
    private var failure: Failure?
    private var generation: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    private var stopped = false

    /// The loader must use the same bucket calendar as these options.
    init(loader: @escaping Loader, options: Options = Options(), publisher: @escaping Publisher) {
        self.loader = loader
        self.options = Self.normalized(options)
        self.publisher = publisher
    }

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
    func replaceCollection(loader: @escaping Loader, options: Options) -> Bool {
        guard !self.stopped else { return false }
        self.clearCollection()
        self.loader = loader
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
        let model = WindowsSpendDashboardModel.build(inputs: self.scan?.inputs ?? [],
            requestedDays: options.days, now: now,
            calendar: CostUsageBucketTimeZone.calendar(identifier: options.bucketTimeZoneIdentifier),
            preferredCurrencyCode: options.preferredCurrencyCode,
            hiddenSourceIDs: options.hiddenSourceIDs,
            hideNativeCodexWhenOpenCodexPresent: options.hideNativeCodexWhenOpenCodexPresent,
            selectedDay: options.selectedDay)
        // Failed/refreshing data remains visible with stale status but is not offered for sharing.
        let share = self.phase == .ready
            ? WindowsShareStatsBuilder.make(model: model, subscriptionNames: self.scan?.subscriptionNames ?? [:]) : nil
        return Snapshot(generation: self.generation, phase: self.phase, model: model, sharePayload: share,
            loadedAt: self.loadedAt, stale: self.scan != nil && (self.phase == .refreshing || self.phase == .failed),
            failure: self.failure, openCodexObservation: self.scan?.openCodexObservation ?? .disabled, sourceFailures: self.scan?.sourceFailures ?? [])
    }

    func refresh() async {
        guard !self.stopped else { return }
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
            let sourceIDs = scan.inputs.map(\.id) + scan.sourceFailures.map(\.sourceID)
            guard Set(sourceIDs).count == sourceIDs.count else {
                self.failure = .duplicateSourceIDs
                self.phase = .failed
                self.publish()
                return
            }
            self.scan = scan
            self.loadedAt = scan.capturedAt
            self.phase = scan.sourceFailures.isEmpty && scan.openCodexObservation != .unavailable ? .ready : .partial
            self.failure = nil
        } catch {
            guard !self.stopped, self.generation == generation else { return }
            self.failure = .scanFailed
            self.phase = .failed
        }
        self.publish()
    }

    private func publish() { self.publisher(self.snapshot()) }
}
#endif
