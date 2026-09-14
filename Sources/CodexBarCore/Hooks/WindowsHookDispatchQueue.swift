#if os(Windows)
import Foundation

/// Serial, bounded ownership of Windows hook processes. The runtime supplies transition events.
public actor WindowsHookDispatchQueue {
    public struct Submission: Sendable {
        public let accepted: Int
        public let omitted: Int
    }
    private struct Pending: Sendable {
        let event: HookEvent
        let config: HooksConfig
        let authorization: (@Sendable () async -> Bool)?
    }
    public enum ObservationFailure: Error { case oversized, duplicateProvider, inconsistentLane }
    private var detector = HookTransitionDetector()
    private var statusDetector = HookTransitionDetector()
    private var statusContext: Data?
    private var observationContext: Data?
    private var authorization: (@Sendable () async -> Bool)?
    private var config = HooksConfig()
    private var privacy = true
    private var pending: [Pending] = []
    private var active: Task<Void, Never>?
    private var activeID: UUID?
    private var limiter = HookRateLimiter()
    private var stopped = false
    private static let maximumPending = 256

    public init() {}

    /// A config/privacy change discards queued old events and cancels the current command.
    /// Its process must drain before any newly configured command can start.
    public func configure(_ config: HooksConfig, hidePersonalInfo: Bool) {
        guard !self.stopped else { return }
        guard config != self.config || hidePersonalInfo != self.privacy else { return }
        self.detector = HookTransitionDetector()
        self.statusDetector = HookTransitionDetector()
        self.statusContext = nil
        self.config = config
        self.privacy = hidePersonalInfo
        self.pending.removeAll()
        self.active?.cancel()
        self.limiter = HookRateLimiter()
    }

    /// Submit a complete refresh batch, with all account lanes grouped once per provider instance.
    /// contextRevision is an opaque digest of provider/account ownership, never credential bytes.
    public func observe(
        _ observations: [HookProviderObservation], config: HooksConfig,
        hidePersonalInfo: Bool, contextRevision: Data, now: Date = Date(),
        failures: [HookEvent] = [], authorization: (@Sendable () async -> Bool)? = nil) throws -> Submission
    {
        try Task.checkCancellation()
        guard failures.count <= 256, failures.allSatisfy({ $0.event == .refreshFailed }) else {
            throw ObservationFailure.inconsistentLane
        }
        guard observations.count <= 256, contextRevision.count <= 64 else { throw ObservationFailure.oversized }
        var providers = Set<String>()
        var laneCount = 0
        for observation in observations {
            guard providers.insert(observation.provider).inserted else { throw ObservationFailure.duplicateProvider }
            laneCount += observation.lanes.count + observation.unavailableLaneKeys.count
            guard laneCount <= 4096 else { throw ObservationFailure.oversized }
            var keys = Set<HookQuotaLaneKey>()
            guard observation.unavailableLaneKeys.allSatisfy({ $0.provider == observation.provider }) else {
                throw ObservationFailure.inconsistentLane
            }
            for lane in observation.lanes {
                guard lane.key.provider == observation.provider, !observation.unavailableLaneKeys.contains(lane.key),
                      keys.insert(lane.key).inserted else {
                    throw ObservationFailure.inconsistentLane
                }
            }
        }
        self.configure(config, hidePersonalInfo: hidePersonalInfo)
        self.authorization = authorization
        if self.observationContext != contextRevision {
            self.observationContext = contextRevision
            self.detector = HookTransitionDetector()
            self.pending.removeAll()
            self.active?.cancel()
            self.limiter = HookRateLimiter()
        }
        guard !self.stopped, config.enabled, config.events.count <= HooksConfig.maximumRuleCount else {
            return Submission(accepted: 0, omitted: 0)
        }
        var events: [HookDispatch] = []
        for observation in observations {
            events.append(contentsOf: self.detector.evaluate(observation: observation, config: config, now: now))
        }
        events.append(contentsOf: failures.map { HookDispatch(event: $0) })
        return self.submit(events)
    }

    /// Public provider status has no account lanes and must not prune quota baselines.
    /// It shares the process queue and rate limiter with quota/failure hooks.
    public func observeStatuses(
        _ statuses: [String: HookProviderStatus], config: HooksConfig,
        hidePersonalInfo: Bool, contextRevision: Data, now: Date = Date(),
        authorization: (@Sendable () async -> Bool)? = nil) throws -> Submission
    {
        try Task.checkCancellation()
        guard statuses.count <= 256, contextRevision.count <= 64,
              statuses.keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }) else {
            throw ObservationFailure.oversized
        }
        self.configure(config, hidePersonalInfo: hidePersonalInfo)
        self.authorization = authorization
        if self.statusContext != contextRevision {
            self.statusContext = contextRevision
            self.statusDetector = HookTransitionDetector()
        }
        guard !self.stopped, config.enabled, config.events.count <= HooksConfig.maximumRuleCount else {
            return Submission(accepted: 0, omitted: 0)
        }
        var events: [HookDispatch] = []
        for provider in statuses.keys.sorted() {
            let observation = HookProviderObservation(provider: provider, lanes: [], status: statuses[provider] ?? .unknown)
            events.append(contentsOf: self.statusDetector.evaluate(observation: observation, config: config, now: now))
        }
        return self.submit(events)
    }

    /// Coarse failure events produced separately from successful sibling account observations.
    public func submitFailures(_ events: [HookEvent]) -> Submission {
        guard events.count <= 256, events.allSatisfy({ $0.event == .refreshFailed }) else {
            return Submission(accepted: 0, omitted: events.count)
        }
        return self.submit(events.map { HookDispatch(event: $0) })
    }

    public func submit(_ dispatches: [HookDispatch]) -> Submission {
        guard !self.stopped, self.config.enabled,
              self.config.events.count <= HooksConfig.maximumRuleCount else {
            return Submission(accepted: 0, omitted: dispatches.count)
        }
        var accepted = 0
        var omitted = 0
        for dispatch in dispatches {
            // Detector-selected rules must still exist unchanged in the current configuration.
            let rules = dispatch.rules.map { selected in
                selected.filter { self.config.events.contains($0) }
            } ?? self.config.events
            let config = HooksConfig(enabled: true, events: rules)
            let original = dispatch.event
            let event = HookEvent(event: original.event, provider: original.provider,
                account: self.privacy ? nil : original.account, window: original.window,
                usagePercent: original.usagePercent, used: original.used, limit: original.limit,
                resetAt: original.resetAt, status: original.status, timestamp: original.timestamp)
            guard !config.matchingRules(for: event).isEmpty else { continue }
            guard self.pending.count < Self.maximumPending else { omitted += 1; continue }
            self.pending.append(Pending(event: event, config: config, authorization: self.authorization))
            accepted += 1
        }
        self.startNext()
        return Submission(accepted: accepted, omitted: omitted)
    }

    public func shutdown() async {
        self.stopped = true
        self.statusDetector = HookTransitionDetector()
        self.statusContext = nil
        self.detector = HookTransitionDetector()
        self.observationContext = nil
        self.pending.removeAll()
        let task = self.active
        task?.cancel()
        await task?.value
    }

    private func startNext() {
        guard !self.stopped, self.active == nil, !self.pending.isEmpty else { return }
        let next = self.pending.removeFirst()
        let id = UUID()
        self.activeID = id
        let limiter = self.limiter
        self.active = Task.detached(priority: .utility) { [weak self] in
            if !Task.isCancelled {
                await HookRunner.dispatch(event: next.event, config: next.config, rateLimiter: limiter, authorization: next.authorization)
            }
            await self?.finished(id)
        }
    }

    private func finished(_ id: UUID) {
        guard self.activeID == id else { return }
        self.active = nil
        self.activeID = nil
        self.startNext()
    }
}
#endif
