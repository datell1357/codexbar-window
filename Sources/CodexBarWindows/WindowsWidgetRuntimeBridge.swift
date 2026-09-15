#if os(Windows)
import CodexBarCore
import Foundation

/// Connects the retained runtime observations to one complete host refresh set.
/// The native host still owns authenticated callbacks and serialized OS publication.
public struct WindowsWidgetRuntimeBridge: Sendable {
    public enum Failure: Error, Sendable { case staleSnapshot }
    public enum Result: Sendable {
        /// The host must withdraw account content and schedule a later refresh.
        case pending
        /// No account-scoped snapshot is eligible for publication.
        case withdrawn
        case ready(Prepared)
    }
    public struct Prepared: Sendable {
        public let cards: WindowsWidgetCardBatch
        public let unavailableProviders: [UsageProvider]
        fileprivate let runtimeContext: UUID
        fileprivate let spendGeneration: UInt64
        fileprivate let bridgeID: UUID
        fileprivate let presentationSettings: WindowsUsagePresentationSettings
        fileprivate let spendSettings: WindowsSpendSettings
        fileprivate let language: String
    }
    private let runtime: WindowsUsageRuntime
    private let coordinator: WindowsWidgetRefreshCoordinator
    private let id = UUID()

    public init(runtime: WindowsUsageRuntime, coordinator: WindowsWidgetRefreshCoordinator) {
        self.runtime = runtime; self.coordinator = coordinator
    }

    /// Accept the complete OS inventory after authenticating the host connection.
    /// Creation/deletion callbacks must reconcile persistent instances before calling this method.
    public func prepareHostInstances(_ instances: [WindowsWidgetHostDefinition.HostInstance], now: Date,
                                     maximumAge: TimeInterval, theme: WindowsWidgetHistoryImage.Theme) async throws -> Result {
        guard instances.count <= WindowsWidgetConfiguration.maximumInstances else {
            throw WindowsWidgetService.RequestFailure.tooManyRequests
        }
        guard Set(instances.map(\.id)).count == instances.count else {
            throw WindowsWidgetService.RequestFailure.duplicateID
        }
        return try await self.prepare(instances.map(\.renderRequest), now: now, maximumAge: maximumAge, theme: theme)
    }

    public func prepare(_ requests: [WindowsWidgetService.RenderRequest], now: Date,
                        maximumAge: TimeInterval, theme: WindowsWidgetHistoryImage.Theme) async throws -> Result {
        try Task.checkCancellation()
        let hostContext = await self.coordinator.currentContextID()
        let presentationSettings = WindowsUsagePresentationSettings.load()
        let spendSettings = WindowsSpendSettings.load()
        let localization = WindowsStatusLocalization.Snapshot()
        let result = try await self.runtime.widgetQuotaSnapshot(now: now)
        try Task.checkCancellation()
        switch result {
        case .pending: return .pending
        case .withdrawn: return .withdrawn
        case let .available(snapshot, context, spendGeneration, unavailable):
            let delivery = try await self.coordinator.refresh(requests, usage: snapshot,
                contextID: hostContext, now: now, maximumAge: maximumAge)
            let cards = try await self.coordinator.prepareCards(delivery,
                locale: Locale(identifier: localization.language),
                labels: WindowsWidgetLocalization.labels(localization), theme: theme,
                rightToLeft: localization.isRightToLeft,
                resetTimesShowAbsolute: presentationSettings.resetTimesShowAbsolute)
            let prepared = Prepared(cards: cards, unavailableProviders: unavailable,
                runtimeContext: context, spendGeneration: spendGeneration, bridgeID: self.id,
                presentationSettings: presentationSettings, spendSettings: spendSettings, language: localization.language)
            guard await self.isCurrent(prepared) else { throw Failure.staleSnapshot }
            try Task.checkCancellation()
            return .ready(prepared)
        }
    }

    /// Call immediately before OS publication and again when acknowledging its result.
    /// This check cannot replace serialization of account invalidations with OS writes in the host.
    public func isCurrent(_ prepared: Prepared) async -> Bool {
        guard prepared.bridgeID == self.id, !Task.isCancelled,
              await self.runtime.isWidgetQuotaSnapshotCurrent(context: prepared.runtimeContext,
                  spendGeneration: prepared.spendGeneration) else { return false }
        guard await self.coordinator.isCurrent(prepared.cards.delivery) else { return false }
        // Read after actor suspension so preference changes during preparation cannot silently publish old choices.
        return WindowsUsagePresentationSettings.load() == prepared.presentationSettings &&
            WindowsSpendSettings.load() == prepared.spendSettings &&
            WindowsStatusLocalization.Snapshot().language == prepared.language
    }

    /// The native host supplies its retained successful publication and authenticated OS widget ID.
    /// Serialize account invalidation with this call, just as with OS publication.
    public func handlePublishedAction(_ prepared: Prepared, verb: String, arguments: Data,
                                      widgetID: String) async throws -> WindowsWidgetRefreshCoordinator.ActionResult {
        guard arguments.count <= 4096 else { throw WindowsWidgetAction.Failure.oversized }
        guard verb == WindowsWidgetAction.switchProviderVerb else { throw WindowsWidgetAction.Failure.unsupportedAction }
        guard prepared.cards.outcomes.contains(where: { outcome in
            if case let .ready(card) = outcome { return card.instanceID == widgetID }
            return false
        }), await self.isCurrent(prepared) else { throw Failure.staleSnapshot }
        // The coordinator also requires a successful publication and verifies that card's action token.
        // A successful save invalidates the delivery, so do not turn that committed result into a stale error.
        return try await self.coordinator.handlePublishedAction(delivery: prepared.cards.delivery,
            verb: verb, arguments: arguments, widgetID: widgetID)
    }

    public func recordPublished(_ prepared: Prepared, instanceIDs: [String]) async throws {
        guard await self.isCurrent(prepared) else { throw Failure.staleSnapshot }
        try await self.coordinator.recordPublished(prepared.cards, instanceIDs: instanceIDs)
        // An account change while acknowledging must trigger host withdrawal, not a successful publication report.
        guard await self.isCurrent(prepared) else { throw Failure.staleSnapshot }
    }
}
#endif
