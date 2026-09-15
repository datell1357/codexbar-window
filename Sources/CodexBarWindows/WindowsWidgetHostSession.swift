#if os(Windows)
import Foundation

/// One authenticated native connection. The transport serializes calls and destroys this session on disconnect.
public actor WindowsWidgetHostSession {
    public enum Failure: Error, Sendable { case busy, closed, unknownInstance, definitionChanged, stalePublication }
    public enum Effect: Sendable {
        case refreshRequired
        case removed(String)
        case customization(WindowsWidgetCustomization)
        case idle
    }
    public struct Reply: Sendable {
        public let requestID: UUID
        public let effect: Effect
    }
    public enum ErrorCode: String, Codable, Sendable {
        case busy, closed, invalidMessage, staleContext, settingsChanged, unavailable, cancelled
    }
    public enum Response: Sendable {
        case accepted(reply: Reply, nextSequence: UInt64)
        case rejected(requestID: UUID?, code: ErrorCode, consumed: Bool, nextSequence: UInt64)
    }

    /// A fixed error vocabulary prevents provider errors, paths, or credential details entering the wire response.
    public func receive(_ payload: Data) async -> Response {
        guard !self.closed, self.sequence < UInt64.max else {
            return .rejected(requestID: nil, code: .closed, consumed: false, nextSequence: self.sequence)
        }
        guard !self.busy, self.pendingInvalidations.isEmpty else {
            return .rejected(requestID: nil, code: .busy, consumed: false, nextSequence: self.sequence)
        }
        let event: WindowsWidgetHostEvent
        do {
            event = try WindowsWidgetHostEvent.decode(payload, expectedSessionID: self.sessionID,
                expectedSequence: self.sequence)
        } catch {
            return .rejected(requestID: nil, code: .invalidMessage, consumed: false, nextSequence: self.sequence)
        }
        do {
            let reply = try await self.handle(payload)
            return .accepted(reply: reply, nextSequence: self.sequence)
        } catch {
            let code: ErrorCode
            switch error {
            case is CancellationError: code = .cancelled
            case let failure as Failure:
                switch failure {
                case .busy: code = .busy
                case .closed: code = .closed
                default: code = .staleContext
                }
            case let failure as WindowsWidgetConfigurationStore.Failure:
                switch failure {
                case .busy: code = .busy
                case .changed: code = .settingsChanged
                default: code = .unavailable
                }
            case is WindowsWidgetRefreshCoordinator.Failure, is WindowsWidgetRuntimeBridge.Failure:
                code = .staleContext
            default: code = .unavailable
            }
            return .rejected(requestID: event.requestID, code: code,
                consumed: self.sequence > event.sequence, nextSequence: self.sequence)
        }
    }

    /// Transport entry point after peer authentication and frame-size enforcement.
    public func receiveEncoded(_ payload: Data) async throws -> Data {
        guard !self.closed else { throw Failure.closed }
        if !self.handshakeComplete {
            guard !self.busy, self.pendingInvalidations.isEmpty, self.sequence == 0 else { throw Failure.busy }
            let response = try WindowsWidgetHandshake.accept(payload, sessionID: self.sessionID)
            self.busy = true
            defer { self.busy = false }
            try await self.startRuntimeObservation()
            guard !self.closed else { throw Failure.closed }
            self.handshakeComplete = true
            return response
        }
        struct Route: Decodable { let method: String? }
        if let route = try? JSONDecoder().decode(Route.self, from: payload), route.method != nil {
            return try await self.receiveControl(payload)
        }
        var response = await self.receive(payload)
        if case let .accepted(reply, nextSequence) = response,
           case let .customization(form) = reply.effect {
            let current = await self.coordinator.isCurrentCustomization(form)
            if self.closed || !current {
                response = .rejected(requestID: reply.requestID, code: .staleContext,
                    consumed: true, nextSequence: nextSequence)
            }
        }
        return try WindowsWidgetHostResponseCodec.encode(response, sessionID: self.sessionID)
    }

    private func receiveControl(_ payload: Data) async throws -> Data {
        func rejection(_ id: UUID?, _ code: ErrorCode, consumed: Bool) throws -> Data {
            try WindowsWidgetHostResponseCodec.encode(.rejected(requestID: id, code: code,
                consumed: consumed, nextSequence: self.sequence), sessionID: self.sessionID)
        }
        guard !self.closed, self.sequence < UInt64.max else { return try rejection(nil, .closed, consumed: false) }
        guard !self.busy, self.pendingInvalidations.isEmpty else { return try rejection(nil, .busy, consumed: false) }
        let request: WindowsWidgetControlRequest
        do { request = try .decode(payload, sessionID: self.sessionID, sequence: self.sequence) }
        catch { return try rejection(nil, .invalidMessage, consumed: false) }
        self.sequence += 1
        do {
            let result: Data
            switch request.method {
            case .prepare:
                result = try await self.prepareTransfer(now: Date(), maximumAge: 30 * 60,
                    theme: request.theme == "dark" ? .dark : .light)
            case .card:
                guard let ticket = request.ticket, let id = request.widgetID else { throw Failure.unknownInstance }
                result = try await self.transferCard(ticket: ticket, widgetID: id)
            case .acknowledge:
                guard let ticket = request.ticket, let ids = request.publishedIDs else { throw Failure.unknownInstance }
                try await self.acknowledgeTransfer(ticket: ticket, publishedIDs: ids)
                result = try WindowsWidgetCardTransfer.encode(["state": "acknowledged"])
            }
            guard !self.closed else { return try rejection(request.requestID, .closed, consumed: true) }
            return try WindowsWidgetCardTransfer.encode([
                "protocolVersion": 1, "sessionID": self.sessionID.uuidString.lowercased(),
                "requestID": request.requestID.uuidString.lowercased(), "accepted": true,
                "consumed": true, "nextSequence": String(self.sequence),
                "payload": try JSONSerialization.jsonObject(with: result),
            ])
        } catch {
            let code: ErrorCode = error is CancellationError ? .cancelled :
                (error is Failure || error is WindowsWidgetRuntimeBridge.Failure ||
                 error is WindowsWidgetRefreshCoordinator.Failure ? .staleContext : .unavailable)
            return try rejection(request.requestID, code, consumed: true)
        }
    }

    /// Acceptance means the authenticated hello was parsed, not that Windows registered or rendered a card.
    func hasAcceptedTransportHandshake() -> Bool { self.handshakeComplete && !self.closed }

    private var handshakeComplete = false
    private let runtime: WindowsUsageRuntime
    private var runtimeStamp: WindowsUsageRuntime.WidgetContextStamp?
    private var runtimeSubscriptionID: UUID?
    private var runtimeObservation: Task<Void, Never>?
    private var invalidationRevision = UUID()
    private var pendingInvalidations = Set<UUID>()
    private let onContextInvalidated: (@Sendable (UUID) -> Void)?
    private let sessionID: UUID
    private let coordinator: WindowsWidgetRefreshCoordinator
    private let bridge: WindowsWidgetRuntimeBridge
    private var sequence: UInt64 = 0
    private var busy = false
    private var closed = false
    private var shutdownTask: Task<Void, Never>?
    private var instances: [String: WindowsWidgetHostDefinition.HostInstance] = [:]
    private var published: WindowsWidgetRuntimeBridge.Prepared?
    private var transfer: (ticket: UUID, prepared: WindowsWidgetRuntimeBridge.Prepared, deadline: ContinuousClock.Instant)?

    public init(sessionID: UUID, runtime: WindowsUsageRuntime, service: WindowsWidgetService,
                onRefreshDue: (@Sendable (UUID) -> Void)? = nil,
                onContextInvalidated: (@Sendable (UUID) -> Void)? = nil) {
        self.sessionID = sessionID
        self.runtime = runtime
        self.onContextInvalidated = onContextInvalidated
        let coordinator = WindowsWidgetRefreshCoordinator(service: service, onRefreshDue: onRefreshDue)
        self.coordinator = coordinator
        self.bridge = WindowsWidgetRuntimeBridge(runtime: runtime, coordinator: coordinator)
    }

    /// Transport owner supplies a nonblocking invalidation callback to its native withdrawal channel.
    /// Observation starts only after authenticated hello (or a trusted in-process operation).
    private func startRuntimeObservation() async throws {
        guard self.runtimeSubscriptionID == nil else { return }
        let subscription = try await self.runtime.subscribeWidgetInvalidations()
        guard !self.closed else {
            await self.runtime.unsubscribeWidgetInvalidations(subscription.id)
            throw Failure.closed
        }
        self.runtimeSubscriptionID = subscription.id
        // Apply the initial reconciliation before hello completes, not during the first native request.
        // The native worker always withdraws its OS inventory before its first card request.
        // Do not signal that same initial reconciliation as a concurrent account change after hello.
        await self.runtimeDidInvalidate(subscription.initialRevision, subscriptionID: subscription.id,
            notifyNative: false)
        guard !self.closed else { throw Failure.closed }
        self.runtimeObservation = Task { [weak self] in
            for await revision in subscription.events {
                guard !Task.isCancelled else { return }
                if revision == subscription.initialRevision { continue }
                await self?.runtimeDidInvalidate(revision, subscriptionID: subscription.id)
            }
            guard !Task.isCancelled else { return }
            await self?.runtimeObservationEnded(subscriptionID: subscription.id)
        }
    }

    private func runtimeDidInvalidate(_ revision: UUID, subscriptionID: UUID, notifyNative: Bool = true) async {
        guard !self.closed, self.runtimeSubscriptionID == subscriptionID else { return }
        let operation = UUID()
        self.pendingInvalidations.insert(operation)
        defer { self.pendingInvalidations.remove(operation) }
        self.invalidationRevision = revision
        self.runtimeStamp = nil
        self.published = nil
        self.transfer = nil
        if notifyNative { self.onContextInvalidated?(revision) }
        await self.coordinator.invalidateContext()
    }

    private func runtimeObservationEnded(subscriptionID: UUID) async {
        guard !self.closed, self.runtimeSubscriptionID == subscriptionID else { return }
        // A terminal runtime cannot serve another snapshot; closing cancels outstanding coordinator work.
        await self.close()
    }

    private func beginOperation() async throws {
        try Task.checkCancellation()
        guard !self.closed else { throw Failure.closed }
        guard !self.busy, self.pendingInvalidations.isEmpty else { throw Failure.busy }
        // Reserve the operation before crossing actors so another request cannot enter during invalidation.
        self.busy = true
        do {
            try await self.startRuntimeObservation()
            let revision = self.invalidationRevision
            let stamp = try await self.runtime.widgetContextStamp()
            try Task.checkCancellation()
            guard !self.closed else { throw Failure.closed }
            guard self.invalidationRevision == revision else { throw Failure.stalePublication }
            if self.runtimeStamp != stamp {
                self.published = nil
                self.transfer = nil
                await self.coordinator.invalidateContext()
                guard !self.closed else { throw Failure.closed }
                guard self.invalidationRevision == revision else { throw Failure.stalePublication }
                self.runtimeStamp = stamp
            }
        } catch {
            self.published = nil
            self.transfer = nil
            self.runtimeStamp = nil
            await self.coordinator.invalidateContext()
            self.busy = false
            throw error
        }
    }

    public func restore(_ inventory: [WindowsWidgetHostDefinition.HostInstance]) async throws {
        try await self.beginOperation(); defer { self.busy = false }
        _ = try await self.coordinator.reconcileHostInstances(inventory)
        guard !self.closed else { return }
        self.instances = Dictionary(uniqueKeysWithValues: inventory.map { ($0.id, $0) })
        self.published = nil
    }

    /// A decoded request consumes its sequence even on handler failure: a committed save must never replay.
    public func handle(_ payload: Data) async throws -> Reply {
        try await self.beginOperation(); defer { self.busy = false }
        guard self.sequence < UInt64.max else { throw Failure.closed }
        let event = try WindowsWidgetHostEvent.decode(payload, expectedSessionID: self.sessionID,
            expectedSequence: self.sequence)
        self.sequence += 1
        let effect: Effect
        switch event.kind {
        case .created:
            guard let instance = event.instance else { throw Failure.unknownInstance }
            if let existing = self.instances[instance.id], existing.definition != instance.definition {
                throw Failure.definitionChanged
            }
            guard self.instances[instance.id] != nil || self.instances.count < WindowsWidgetConfiguration.maximumInstances
            else { throw WindowsWidgetConfiguration.Failure.tooManyInstances }
            _ = try await self.coordinator.registerHostInstance(id: instance.id,
                definitionID: instance.definition.rawValue, size: instance.size)
            guard !self.closed else { return Reply(requestID: event.requestID, effect: .idle) }
            self.instances[instance.id] = instance; self.published = nil
            effect = .refreshRequired
        case .deleted:
            _ = try await self.coordinator.unregisterInstance(id: event.widgetID)
            self.instances.removeValue(forKey: event.widgetID); self.published = nil
            effect = .removed(event.widgetID)
        case .contextChanged, .activated:
            guard let instance = event.instance, let previous = self.instances[event.widgetID] else {
                throw Failure.unknownInstance
            }
            guard instance.definition == previous.definition else { throw Failure.definitionChanged }
            self.instances[instance.id] = instance
            await self.coordinator.invalidateContext(); self.published = nil
            effect = .refreshRequired
        case .deactivated:
            guard self.instances[event.widgetID] != nil else { throw Failure.unknownInstance }
            effect = .idle
        case .customizationRequested:
            try self.requireMatchingInstance(event)
            effect = .customization(try await self.coordinator.openCustomization(widgetID: event.widgetID))
        case .action:
            try self.requireMatchingInstance(event)
            guard let verb = event.verb, let arguments = event.arguments else { throw Failure.unknownInstance }
            if verb == WindowsWidgetAction.switchProviderVerb {
                guard let published = self.published else { throw Failure.stalePublication }
                _ = try await self.bridge.handlePublishedAction(published, verb: verb,
                    arguments: arguments, widgetID: event.widgetID)
            } else {
                _ = try await self.coordinator.handleAction(verb: verb, arguments: arguments, widgetID: event.widgetID)
            }
            self.published = nil
            effect = .refreshRequired
        }
        return Reply(requestID: event.requestID, effect: self.closed ? .idle : effect)
    }

    private func requireMatchingInstance(_ event: WindowsWidgetHostEvent) throws {
        guard let incoming = event.instance, let existing = self.instances[event.widgetID] else {
            throw Failure.unknownInstance
        }
        guard incoming.definition == existing.definition, incoming.size == existing.size else {
            throw Failure.definitionChanged
        }
    }

    public func prepare(now: Date, maximumAge: TimeInterval, theme: WindowsWidgetHistoryImage.Theme) async throws
        -> WindowsWidgetRuntimeBridge.Result {
        try await self.beginOperation(); defer { self.busy = false }
        let revision = self.invalidationRevision
        let result = try await self.bridge.prepareHostInstances(self.instances.values.sorted { $0.id < $1.id },
            now: now, maximumAge: maximumAge, theme: theme)
        guard !self.closed else { throw Failure.closed }
        guard self.pendingInvalidations.isEmpty, self.invalidationRevision == revision else {
            throw Failure.stalePublication
        }
        return result
    }

    public func prepareTransfer(now: Date, maximumAge: TimeInterval, theme: WindowsWidgetHistoryImage.Theme) async throws -> Data {
        try await self.beginOperation(); defer { self.busy = false }
        self.transfer = nil
        let revision = self.invalidationRevision
        let result = try await self.bridge.prepareHostInstances(self.instances.values.sorted { $0.id < $1.id },
            now: now, maximumAge: maximumAge, theme: theme)
        guard !self.closed else { throw Failure.closed }
        guard self.pendingInvalidations.isEmpty, self.invalidationRevision == revision else {
            throw Failure.stalePublication
        }
        switch result {
        case .pending: return try WindowsWidgetCardTransfer.encode(["state": "pending"])
        case .withdrawn: return try WindowsWidgetCardTransfer.encode(["state": "withdrawn"])
        case let .ready(prepared):
            let ticket = UUID()
            let manifest = try WindowsWidgetCardTransfer.manifest(ticket: ticket, cards: prepared.cards)
            self.transfer = (ticket, prepared, ContinuousClock.now.advanced(by: .seconds(120)))
            return manifest
        }
    }

    public func transferCard(ticket: UUID, widgetID: String) async throws -> Data {
        try await self.beginOperation(); defer { self.busy = false }
        guard let transfer = self.transfer, transfer.ticket == ticket, ContinuousClock.now < transfer.deadline,
              await self.bridge.isCurrent(transfer.prepared), !self.closed,
              self.pendingInvalidations.isEmpty, self.transfer?.ticket == ticket,
              ContinuousClock.now < transfer.deadline else {
            throw Failure.stalePublication
        }
        return try WindowsWidgetCardTransfer.card(ticket: ticket, widgetID: widgetID, cards: transfer.prepared.cards)
    }

    public func acknowledgeTransfer(ticket: UUID, publishedIDs: [String]) async throws {
        try await self.beginOperation(); defer { self.busy = false }
        guard let transfer = self.transfer, transfer.ticket == ticket, ContinuousClock.now < transfer.deadline else {
            throw Failure.stalePublication
        }
        let revision = self.invalidationRevision
        try await self.bridge.recordPublished(transfer.prepared, instanceIDs: publishedIDs)
        guard !self.closed else { throw Failure.closed }
        guard self.pendingInvalidations.isEmpty, self.invalidationRevision == revision,
              self.transfer?.ticket == ticket, ContinuousClock.now < transfer.deadline else {
            self.published = nil
            self.transfer = nil
            await self.coordinator.invalidateContext()
            throw Failure.stalePublication
        }
        self.published = transfer.prepared
        self.transfer = nil
    }

    public func recordPublished(_ prepared: WindowsWidgetRuntimeBridge.Prepared, instanceIDs: [String]) async throws {
        try await self.beginOperation(); defer { self.busy = false }
        let revision = self.invalidationRevision
        try await self.bridge.recordPublished(prepared, instanceIDs: instanceIDs)
        guard !self.closed else { throw Failure.closed }
        guard self.pendingInvalidations.isEmpty, self.invalidationRevision == revision else {
            throw Failure.stalePublication
        }
        self.published = prepared
    }

    /// Native content must be withdrawn separately. shutdown cancels/drains coordinator work.
    public func close() async {
        if let shutdownTask {
            await shutdownTask.value
            return
        }
        self.closed = true
        let subscriptionID = self.runtimeSubscriptionID
        self.runtimeSubscriptionID = nil
        let observation = self.runtimeObservation
        self.runtimeObservation = nil
        observation?.cancel()
        self.invalidationRevision = UUID()
        self.onContextInvalidated?(self.invalidationRevision)
        self.runtimeStamp = nil
        self.transfer = nil
        self.instances = [:]
        self.published = nil
        let runtime = self.runtime
        let coordinator = self.coordinator
        // Install a shared drain task before suspending. A second close must not report completion early.
        // Capture collaborators rather than self so cleanup also survives the last external owner disappearing.
        let task = Task {
            if let subscriptionID { await runtime.unsubscribeWidgetInvalidations(subscriptionID) }
            await coordinator.shutdown()
        }
        self.shutdownTask = task
        // Do not await observation.value: terminal stream delivery can itself be waiting on this close.
        // Pending observation callbacks check closed/subscriptionID and cannot restart work.
        await task.value
    }

    deinit { self.runtimeObservation?.cancel() }
}
#endif
