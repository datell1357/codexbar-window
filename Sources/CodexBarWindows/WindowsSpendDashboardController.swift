#if os(Windows)
import Foundation
import CodexBarCore

/// Owns one coherent spend scan. Native UI can change its projection without rescanning logs.
actor WindowsSpendDashboardController {
    struct Scan: Sendable {
        let inputs: [WindowsSpendDashboardModel.ProviderInput]
        let subscriptionNames: [String: WindowsShareStatsSubscriptionName]
    }
    struct Options: Sendable {
        var days = 30
        var preferredCurrencyCode = "auto"
        var hiddenSourceIDs: Set<String> = []
        var hideNativeCodexWhenOpenCodexPresent = false
        var selectedDay: Date?
    }
    enum Phase: Sendable { case idle, refreshing, ready, failed, stopped }
    enum Failure: Sendable { case scanFailed, duplicateSourceIDs }
    struct Snapshot: Sendable {
        let generation: UInt64
        let phase: Phase
        let model: WindowsSpendDashboardModel
        let sharePayload: WindowsShareStatsPayload?
        let loadedAt: Date?
        let stale: Bool
        let failure: Failure?
    }
    typealias Loader = @Sendable (_ historyDays: Int) async throws -> Scan
    typealias Publisher = @Sendable (Snapshot) -> Void

    private let loader: Loader
    private let publisher: Publisher
    private var options = Options()
    private var scan: Scan?
    private var loadedAt: Date?
    private var phase: Phase = .idle
    private var failure: Failure?
    private var generation: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    private var stopped = false

    init(loader: @escaping Loader, publisher: @escaping Publisher) {
        self.loader = loader
        self.publisher = publisher
    }

    func setOptions(_ options: Options) {
        guard !self.stopped else { return }
        self.options = options
        self.options.days = max(1, min(WindowsSpendHistoryPolicy.scanDays, options.days))
        self.publish()
    }

    func snapshot(now: Date = Date()) -> Snapshot {
        let model = WindowsSpendDashboardModel.build(inputs: self.scan?.inputs ?? [],
            requestedDays: self.options.days, now: now,
            preferredCurrencyCode: self.options.preferredCurrencyCode,
            hiddenSourceIDs: self.options.hiddenSourceIDs,
            hideNativeCodexWhenOpenCodexPresent: self.options.hideNativeCodexWhenOpenCodexPresent,
            selectedDay: self.options.selectedDay)
        // Failed/refreshing data remains visible with stale status but is not offered for sharing.
        let share = self.phase == .ready
            ? WindowsShareStatsBuilder.make(model: model, subscriptionNames: self.scan?.subscriptionNames ?? [:]) : nil
        return Snapshot(generation: self.generation, phase: self.phase, model: model, sharePayload: share,
            loadedAt: self.loadedAt, stale: self.scan != nil && self.phase != .ready, failure: self.failure)
    }

    func refresh() async {
        guard !self.stopped else { return }
        if let task = self.refreshTask { await task.value; return }
        self.generation &+= 1
        let generation = self.generation
        self.phase = .refreshing
        self.failure = nil
        self.publish()
        let task = Task { await self.performRefresh(generation: generation) }
        self.refreshTask = task
        await task.value
        if self.generation == generation { self.refreshTask = nil }
    }

    /// Call before changing the account/source context used by the loader.
    /// Old owner data is withdrawn immediately, including if cancellation is ignored by a loader.
    func invalidateSourceContext() {
        guard !self.stopped else { return }
        self.generation &+= 1
        self.refreshTask?.cancel()
        self.refreshTask = nil
        self.scan = nil
        self.loadedAt = nil
        self.failure = nil
        self.phase = .idle
        self.publish()
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

    private func performRefresh(generation: UInt64) async {
        do {
            let scan = try await self.loader(WindowsSpendHistoryPolicy.scanDays)
            try Task.checkCancellation()
            guard !self.stopped, self.generation == generation else { return }
            guard Set(scan.inputs.map(\.id)).count == scan.inputs.count else {
                self.failure = .duplicateSourceIDs
                self.phase = .failed
                self.publish()
                return
            }
            self.scan = scan
            self.loadedAt = Date()
            self.phase = .ready
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
