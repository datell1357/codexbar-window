#if os(Windows)
import CodexBarCore
import Foundation

/// Prepared cards retain the exact render revision and action token used to generate their payloads.
/// The host retains these objects only after publication succeeds and discards them on context invalidation.
public struct WindowsWidgetCardBatch: Sendable {
    public struct Card: Sendable {
        public let rendered: WindowsWidgetService.Rendered
        public let payload: WindowsWidgetAdaptiveCard.Payload
        public let actionToken: UUID
        public var instanceID: String { self.rendered.presentation.instanceID }
        fileprivate init(rendered: WindowsWidgetService.Rendered, payload: WindowsWidgetAdaptiveCard.Payload,
                         actionToken: UUID) {
            self.rendered = rendered; self.payload = payload; self.actionToken = actionToken
        }
    }
    public enum Failure: Sendable { case missingInstance, invalidContent, unsupportedKind }
    public enum Outcome: Sendable {
        case ready(Card)
        /// Keep the host's customization UI; this is neither a blank card nor a publication failure.
        case customizing(instanceID: String)
        case failed(instanceID: String, reason: Failure)
    }
    public let delivery: WindowsWidgetRefreshCoordinator.Delivery
    /// Preserves all request positions, including render failures and unsupported templates.
    public let outcomes: [Outcome]
    /// Replace old values for failed cards. Missing instances must instead be removed by the host.
    /// Posting one of these does not make that instance a successfully rendered/actionable card.
    public let failurePayloads: [String: WindowsWidgetAdaptiveCard.Payload]

    public static func make(from delivery: WindowsWidgetRefreshCoordinator.Delivery, locale: Locale,
                            labels: WindowsWidgetAdaptiveCard.Labels = .init(),
                            theme: WindowsWidgetHistoryImage.Theme = .light, rightToLeft: Bool = false,
                            customizing: Set<String> = [], resetTimesShowAbsolute: Bool = true) throws -> Self {
        try Task.checkCancellation()
        // Preserve a single palette (or lookup failure) for all chart images in this delivery.
        let chartAppearance = Result { try WindowsWidgetChartAccessibility.capture() }
        var outcomes: [Outcome] = []
        outcomes.reserveCapacity(delivery.batch.outcomes.count)
        for outcome in delivery.batch.outcomes {
            try Task.checkCancellation()
            let instanceID: String
            switch outcome {
            case .rendered(let presentation): instanceID = presentation.instanceID
            case .failed(let id, _): instanceID = id
            }
            if customizing.contains(instanceID) {
                outcomes.append(.customizing(instanceID: instanceID))
                continue
            }
            switch outcome {
            case let .failed(instanceID, reason):
                let failure: Failure
                switch reason {
                case .missingInstance: failure = .missingInstance
                case .invalidContent: failure = .invalidContent
                }
                outcomes.append(.failed(instanceID: instanceID, reason: failure))
            case .rendered(let presentation):
                let token = UUID()
                let rendered = WindowsWidgetService.Rendered(settings: delivery.batch.settings, presentation: presentation)
                do {
                    let payload = try WindowsWidgetAdaptiveCard.make(presentation, locale: locale,
                        labels: labels, actionToken: token, theme: theme, rightToLeft: rightToLeft,
                        resetTimesShowAbsolute: resetTimesShowAbsolute, chartAppearance: chartAppearance)
                    try WindowsWidgetCardTransfer.requireTransferable(payload, widgetID: presentation.instanceID)
                    outcomes.append(.ready(Card(rendered: rendered, payload: payload, actionToken: token)))
                } catch WindowsWidgetAdaptiveCard.Failure.unsupportedKind {
                    outcomes.append(.failed(instanceID: presentation.instanceID, reason: .unsupportedKind))
                } catch {
                    outcomes.append(.failed(instanceID: presentation.instanceID, reason: .invalidContent))
                }
            }
        }
        var failurePayloads: [String: WindowsWidgetAdaptiveCard.Payload] = [:]
        let now = Date()
        for outcome in outcomes {
            try Task.checkCancellation()
            guard case let .failed(id, reason) = outcome else { continue }
            let retryable: Bool
            switch reason {
            case .missingInstance: continue
            case .invalidContent: retryable = true
            case .unsupportedKind: retryable = false
            }
            let payload = try WindowsWidgetAdaptiveCard.failurePayload(retryable: retryable,
                labels: labels, rightToLeft: rightToLeft, now: now)
            try WindowsWidgetCardTransfer.requireTransferable(payload, widgetID: id)
            failurePayloads[id] = payload
        }
        try Task.checkCancellation()
        return Self(delivery: delivery, outcomes: outcomes, failurePayloads: failurePayloads)
    }
}
#endif
