#if os(Windows)
import CodexBarCore
import Foundation

/// Owns one full visible-widget refresh set. A platform host must not use separate sets as partial updates.
public actor WindowsWidgetRefreshCoordinator {
    public enum Failure: Error, Sendable { case stopped, superseded, contextChanged, invalidPublication, staleCard, actionInProgress }
    public enum ActionResult: Sendable { case saved(WindowsWidgetConfigurationStore.Snapshot), cancelled }
    public struct Delivery: Sendable {
        public let generation: UUID
        public let contextID: UUID
        public let batch: WindowsWidgetService.Batch
    }
    private let service: WindowsWidgetService
    /// Enqueue a host refresh without blocking this actor; the context must be carried into that refresh.
    private let onRefreshDue: (@Sendable (UUID) -> Void)?
    private var refreshTimer: Task<Void, Never>?
    private var refreshTimerID: UUID?
    private var retryDeadlines: [String: Date] = [:]
    private var generation = UUID()
    private var contextID = UUID()
    private var active: Task<WindowsWidgetService.Batch, Error>?
    private var stopped = false
    private var published: [String: WindowsWidgetCardBatch.Card] = [:]
    private var publishedGeneration: UUID?
    private var forms: [String: WindowsWidgetCustomization] = [:]
    private var openingForms: [String: UUID] = [:]
    private var activeAction: Task<WindowsWidgetConfigurationStore.Snapshot, Error>?
    private var actionID: UUID?


    public init(service: WindowsWidgetService, onRefreshDue: (@Sendable (UUID) -> Void)? = nil) {
        self.service = service; self.onRefreshDue = onRefreshDue
    }

    deinit { self.refreshTimer?.cancel() }

    /// Capture before obtaining the usage snapshot; a later invalidation makes that snapshot ineligible.
    public func currentContextID() -> UUID { self.contextID }

    /// Entry point for an authenticated transport. The envelope must carry the context captured before fetching.
    /// Invalid payloads fail before replacing an in-flight valid refresh.
    public func refreshEncoded(_ requests: [WindowsWidgetService.RenderRequest], payload: Data,
                               now: Date, maximumAge: TimeInterval) async throws -> Delivery {
        try Task.checkCancellation()
        guard !self.stopped else { throw Failure.stopped }
        let expectedContext = self.contextID
        let snapshot = try WindowsWidgetSnapshotCodec.decode(payload, expectedContextID: expectedContext, now: now)
        try Task.checkCancellation()
        return try await self.refresh(requests, usage: snapshot, contextID: expectedContext,
            now: now, maximumAge: maximumAge)
    }

    public func refresh(_ requests: [WindowsWidgetService.RenderRequest], usage: WidgetSnapshot?,
                        contextID: UUID, now: Date, maximumAge: TimeInterval) async throws -> Delivery {
        try Task.checkCancellation()
        guard !self.stopped else { throw Failure.stopped }
        guard self.contextID == contextID else { throw Failure.contextChanged }
        let generation = UUID()
        self.generation = generation
        self.refreshTimer?.cancel(); self.refreshTimer = nil; self.refreshTimerID = nil
        let previous = self.active
        previous?.cancel()
        // Drain the cancelled work before starting its replacement; do not accumulate detached refreshes.
        if let previous { _ = await previous.result }
        guard !self.stopped else { throw Failure.stopped }
        guard self.generation == generation else { throw Failure.superseded }
        self.active = nil
        try Task.checkCancellation()
        let service = self.service
        let task = Task {
            try await service.renderBatch(requests, usage: usage, now: now, maximumAge: maximumAge)
        }
        self.active = task
        do {
            let batch = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            guard !self.stopped else { throw Failure.stopped }
            guard self.generation == generation else { throw Failure.superseded }
            self.active = nil
            return Delivery(generation: generation, contextID: contextID, batch: batch)
        } catch {
            if self.generation == generation {
                self.active = nil
                // renderBatch validates request bounds/IDs before reading settings. Invalid requests are not retryable.
                if !self.stopped, self.contextID == contextID, !Task.isCancelled,
                   !(error is CancellationError), !(error is WindowsWidgetService.RequestFailure) {
                    let retryDate = Date().addingTimeInterval(60)
                    self.retryDeadlines = Dictionary(uniqueKeysWithValues: requests.map { ($0.instanceID, retryDate) })
                    self.schedulePublishedRefresh()
                }
            }
            throw error
        }
    }

    /// Startup/reconnect recovery. Explicit deletion events, rather than inventory omissions, remove settings.
    public func reconcileHostInstances(_ instances: [WindowsWidgetHostDefinition.HostInstance]) async throws
        -> WindowsWidgetConfigurationStore.Snapshot {
        try Task.checkCancellation()
        guard !self.stopped else { throw Failure.stopped }
        await self.invalidateContext()
        try Task.checkCancellation()
        guard !self.stopped else { throw Failure.stopped }
        do {
            let saved = try await self.service.reconcileHostInstances(instances)
            await self.invalidateContext()
            return saved
        } catch {
            await self.invalidateContext()
            throw error
        }
    }

    /// Map the OS definition and size before accepting its creation event.
    public func registerHostInstance(id: String, definitionID: String, size: WindowsWidgetHostDefinition.Size) async throws
        -> WindowsWidgetConfigurationStore.Snapshot {
        let instance = try WindowsWidgetHostDefinition.HostInstance(id: id, definitionID: definitionID, size: size)
        return try await self.registerInstance(id: instance.id, kind: instance.definition.kind)
    }

    /// Host creation callback. The host separately maps its registered definition ID to a supported kind.
    public func registerInstance(id: String, kind: WindowsWidgetConfiguration.Kind) async throws
        -> WindowsWidgetConfigurationStore.Snapshot {
        try Task.checkCancellation()
        guard !self.stopped else { throw Failure.stopped }
        await self.invalidateContext()
        try Task.checkCancellation()
        guard !self.stopped else { throw Failure.stopped }
        let saved = try await self.service.registerInstance(id: id, kind: kind)
        // A refresh may have started while the store was saving; invalidate that old-settings result too.
        await self.invalidateContext()
        return saved
    }

    /// Host deletion callback. Invalidates retained actions before changing persisted instances.
    public func unregisterInstance(id: String) async throws -> WindowsWidgetConfigurationStore.Snapshot {
        try Task.checkCancellation()
        guard !self.stopped else { throw Failure.stopped }
        await self.invalidateContext()
        try Task.checkCancellation()
        guard !self.stopped else { throw Failure.stopped }
        let saved = try await self.service.unregisterInstance(id: id)
        await self.invalidateContext()
        return saved
    }

    /// Apply a host customization form against the revision captured when that form was opened.
    public func customizeInstance(id: String, expected: WindowsWidgetConfigurationStore.Snapshot,
                                  provider: UsageProvider, metric: WindowsWidgetConfiguration.Metric? = nil,
                                  window: WindowsWidgetConfiguration.Window? = nil) async throws
        -> WindowsWidgetConfigurationStore.Snapshot {
        try Task.checkCancellation()
        guard !self.stopped else { throw Failure.stopped }
        await self.invalidateContext()
        try Task.checkCancellation()
        guard !self.stopped else { throw Failure.stopped }
        let saved = try await self.service.customizeInstance(id: id, expected: expected,
            provider: provider, metric: metric, window: window)
        await self.invalidateContext()
        return saved
    }

    /// Prepare only a current delivery. The host must still check isCurrent on its serialized publication path.
    public func prepareCards(_ delivery: Delivery, locale: Locale,
                             labels: WindowsWidgetAdaptiveCard.Labels = .init(),
                            theme: WindowsWidgetHistoryImage.Theme = .light, rightToLeft: Bool = false,
                            resetTimesShowAbsolute: Bool = true) throws -> WindowsWidgetCardBatch {
        try Task.checkCancellation()
        guard !self.stopped else { throw Failure.stopped }
        guard self.contextID == delivery.contextID else { throw Failure.contextChanged }
        guard self.generation == delivery.generation else { throw Failure.superseded }
        return try WindowsWidgetCardBatch.make(from: delivery, locale: locale, labels: labels, theme: theme,
            rightToLeft: rightToLeft, customizing: Set(self.forms.keys).union(self.openingForms.keys),
            resetTimesShowAbsolute: resetTimesShowAbsolute)
    }

    /// Application-facing card preparation using the currently selected Windows UI language.
    public func prepareLocalizedCards(_ delivery: Delivery, theme: WindowsWidgetHistoryImage.Theme) throws
        -> WindowsWidgetCardBatch {
        let localization = WindowsStatusLocalization.Snapshot()
        return try self.prepareCards(delivery, locale: Locale(identifier: localization.language),
            labels: WindowsWidgetLocalization.labels(localization), theme: theme,
            rightToLeft: localization.isRightToLeft,
            resetTimesShowAbsolute: WindowsUsagePresentationSettings.load().resetTimesShowAbsolute)
    }

    /// Acknowledge the successful subset after the host finishes publishing this complete refresh set.
    /// The host must clear failed/removed OS cards separately; they are no longer actionable here.
    public func recordPublished(_ cards: WindowsWidgetCardBatch, instanceIDs: [String]) throws {
        try Task.checkCancellation()
        guard !self.stopped else { throw Failure.stopped }
        guard self.isCurrent(cards.delivery) else { throw Failure.superseded }
        guard instanceIDs.count <= WindowsWidgetConfiguration.maximumInstances,
              Set(instanceIDs).count == instanceIDs.count else { throw Failure.invalidPublication }
        var available: [String: WindowsWidgetCardBatch.Card] = [:]
        var retryIDs = Set<String>()
        for outcome in cards.outcomes {
            switch outcome {
            case .ready(let card): available[card.instanceID] = card
            case .failed(let id, .invalidContent): retryIDs.insert(id)
            case .failed, .customizing: break
            }
        }
        var accepted: [String: WindowsWidgetCardBatch.Card] = [:]
        for id in instanceIDs {
            guard let card = available[id] else { throw Failure.invalidPublication }
            accepted[id] = card
        }
        retryIDs.formUnion(Set(available.keys).subtracting(accepted.keys))
        let retryDate = Date().addingTimeInterval(60)
        self.retryDeadlines = Dictionary(uniqueKeysWithValues: retryIDs.map { ($0, retryDate) })
        self.published = accepted
        self.publishedGeneration = cards.delivery.generation
        self.schedulePublishedRefresh()
    }

    private func schedulePublishedRefresh() {
        self.refreshTimer?.cancel(); self.refreshTimer = nil; self.refreshTimerID = nil
        guard !self.stopped, self.onRefreshDue != nil else { return }
        let normal = self.published.values
            .filter {
                self.forms[$0.instanceID] == nil && self.openingForms[$0.instanceID] == nil &&
                    self.retryDeadlines[$0.instanceID] == nil
            }
            .map { $0.payload.nextRefresh }
        let retries = self.retryDeadlines.filter { self.forms[$0.key] == nil && self.openingForms[$0.key] == nil }.map(\.value)
        guard let deadline = (normal + retries).min() else { return }
        let interval = deadline.timeIntervalSinceNow
        guard interval.isFinite else { return }
        // A delayed publication may already be due; avoid a tight loop while retaining a bounded retry horizon.
        let delay = UInt64(max(1, min(30 * 60, interval)) * 1_000_000_000)
        let ticket = UUID(), context = self.contextID
        self.refreshTimerID = ticket
        self.refreshTimer = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) }
            catch { return }
            guard !Task.isCancelled else { return }
            await self?.refreshTimerFired(ticket: ticket, context: context)
        }
    }

    private func refreshTimerFired(ticket: UUID, context: UUID) {
        guard !self.stopped, self.contextID == context, self.refreshTimerID == ticket else { return }
        self.refreshTimer = nil; self.refreshTimerID = nil
        self.onRefreshDue?(context)
    }

    /// Returns a localized form for an authenticated customization event. Latest open wins per widget.
    public func openCustomization(widgetID: String) async throws -> WindowsWidgetCustomization {
        try Task.checkCancellation()
        guard !self.stopped else { throw Failure.stopped }
        try WindowsWidgetConfiguration(instances: [.init(id: widgetID, kind: .usage)]).validate()
        let occupied = Set(self.forms.keys).union(self.openingForms.keys)
        guard occupied.contains(widgetID) || occupied.count < WindowsWidgetConfiguration.maximumInstances
        else { throw WindowsWidgetConfiguration.Failure.tooManyInstances }
        let context = self.contextID, ticket = UUID()
        self.openingForms[widgetID] = ticket
        self.forms.removeValue(forKey: widgetID)
        self.schedulePublishedRefresh()
        // Invalidate already prepared normal cards before the host starts showing a form.
        self.generation = UUID()
        self.active?.cancel()
        do {
            let settings = try await self.service.settings()
            try Task.checkCancellation()
            guard !self.stopped else { throw Failure.stopped }
            guard self.contextID == context else { throw Failure.contextChanged }
            guard self.openingForms[widgetID] == ticket else { throw Failure.superseded }
            let localization = WindowsStatusLocalization.Snapshot()
            let form = try WindowsWidgetCustomization.make(instanceID: widgetID, settings: settings,
                labels: WindowsWidgetLocalization.labels(localization), rightToLeft: localization.isRightToLeft)
            self.forms[widgetID] = form
            self.openingForms.removeValue(forKey: widgetID)
            return form
        } catch {
            if self.openingForms[widgetID] == ticket {
                self.openingForms.removeValue(forKey: widgetID)
                self.schedulePublishedRefresh()
            }
            throw error
        }
    }

    /// Token matching prevents a delayed close event from closing a newer form for the same widget.
    public func closeCustomization(widgetID: String, actionToken: UUID) {
        if self.forms[widgetID]?.actionToken == actionToken {
            self.forms.removeValue(forKey: widgetID)
            self.schedulePublishedRefresh()
            self.generation = UUID()
            self.active?.cancel()
        }
    }

    /// Recheck immediately before posting a form on the host's serialized UI publication path.
    public func isCurrentCustomization(_ form: WindowsWidgetCustomization) -> Bool {
        !self.stopped && self.forms[form.instance.id]?.actionToken == form.actionToken
    }

    /// A card action must still target the exact batch checked by the runtime bridge.
    /// Customization events use their independent form token and do not enter this path.
    public func handlePublishedAction(delivery: Delivery, verb: String, arguments: Data,
                                      widgetID: String) async throws -> ActionResult {
        guard self.isCurrent(delivery) else { throw Failure.staleCard }
        guard verb == WindowsWidgetAction.switchProviderVerb else { throw WindowsWidgetAction.Failure.unsupportedAction }
        return try await self.handleAction(verb: verb, arguments: arguments, widgetID: widgetID)
    }

    /// Call only for an authenticated OS callback. Payload widget IDs are not used for routing.
    public func handleAction(verb: String, arguments: Data, widgetID: String) async throws -> ActionResult {
        try Task.checkCancellation()
        guard !self.stopped else { throw Failure.stopped }
        guard self.activeAction == nil else { throw Failure.actionInProgress }
        if verb == WindowsWidgetCustomization.cancelVerb {
            guard let form = self.forms[widgetID] else { throw Failure.staleCard }
            try form.validateCancellation(arguments: arguments, widgetID: widgetID)
            self.closeCustomization(widgetID: widgetID, actionToken: form.actionToken)
            self.onRefreshDue?(self.contextID)
            return .cancelled
        }
        let context = self.contextID
        let id = UUID()
        let service = self.service
        let task: Task<WindowsWidgetConfigurationStore.Snapshot, Error>
        if verb == WindowsWidgetCustomization.saveVerb {
            guard let form = self.forms[widgetID] else { throw Failure.staleCard }
            let selection = try form.selection(arguments: arguments, widgetID: widgetID)
            task = Task {
                try await service.customizeInstance(id: widgetID, expected: form.settings,
                    provider: selection.provider, metric: selection.metric, window: selection.window)
            }
        } else {
            guard self.publishedGeneration == self.generation, let card = self.published[widgetID]
            else { throw Failure.staleCard }
            task = Task {
                try await WindowsWidgetAction.handle(verb: verb, arguments: arguments, widgetID: widgetID,
                    card: card, service: service)
            }
        }
        self.activeAction = task; self.actionID = id
        do {
            let saved = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: { task.cancel() }
            if self.actionID == id { self.activeAction = nil; self.actionID = nil }
            // Saving changes the selected provider; every card based on the old settings must refresh.
            if self.contextID == context { await self.invalidateContext() }
            // Never turn a committed settings write into a cancellation/failure report.
            return .saved(saved)
        } catch {
            if self.actionID == id { self.activeAction = nil; self.actionID = nil }
            if let failure = error as? WindowsWidgetConfigurationStore.Failure,
               case .changed = failure, self.contextID == context {
                // The rejected save changed nothing. Discard stale forms/cards before a fresh snapshot.
                await self.invalidateContext()
            }
            throw error
        }
    }

    /// Check again on the host's serialized delivery path before handing a result to the OS.
    public func isCurrent(_ delivery: Delivery) -> Bool {
        !self.stopped && self.generation == delivery.generation && self.contextID == delivery.contextID
    }

    /// Invoke on account/privacy/configuration changes, including changes that do not start a new refresh.
    /// The platform host must also clear any already published cards; this invalidates pending deliveries and retained action targets.
    public func invalidateContext() async {
        self.contextID = UUID()
        let invalidation = UUID()
        self.generation = invalidation
        self.published = [:]; self.publishedGeneration = nil
        self.forms = [:]; self.openingForms = [:]
        self.retryDeadlines = [:]
        self.refreshTimer?.cancel(); self.refreshTimer = nil; self.refreshTimerID = nil
        let action = self.activeAction
        let invalidatedActionID = self.actionID
        action?.cancel()
        let task = self.active
        task?.cancel()
        if let task { _ = await task.result }
        if let action { _ = await action.result }
        if self.actionID == invalidatedActionID { self.activeAction = nil; self.actionID = nil }
        // A newer refresh may have started while the old task was draining.
        if self.generation == invalidation { self.active = nil }
    }

    public func shutdown() async {
        self.stopped = true
        self.contextID = UUID()
        self.generation = UUID()
        self.published = [:]; self.publishedGeneration = nil
        self.forms = [:]; self.openingForms = [:]
        self.retryDeadlines = [:]
        self.refreshTimer?.cancel(); self.refreshTimer = nil; self.refreshTimerID = nil
        let action = self.activeAction
        action?.cancel()
        let task = self.active
        task?.cancel()
        if let task { _ = await task.result }
        if let action { _ = await action.result }
        self.activeAction = nil; self.actionID = nil
        self.active = nil
    }
}
#endif
