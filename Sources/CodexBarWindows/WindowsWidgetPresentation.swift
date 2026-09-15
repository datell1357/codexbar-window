#if os(Windows)
import CodexBarCore
import Foundation

/// Single, side-effect-free entry point for the Windows widget host's render requests.
public struct WindowsWidgetPresentation: Sendable {
    public enum Body: Sendable {
        case unavailable
        case switcher(providers: [UsageProvider], rows: [WindowsWidgetUsage.Row])
        case usage([WindowsWidgetUsage.Row])
        case history(rows: [WindowsWidgetUsage.Row], chart: WindowsWidgetHistory)
        case metric(WindowsWidgetMetric)
        case burnDown(WindowsWidgetBurnDown)
        case combinedBurnDown(WindowsWidgetBurnDown)
    }
    public enum Failure: Error, Sendable { case invalidBurnDownSelection }
    public let instanceID: String
    public let kind: WindowsWidgetConfiguration.Kind
    public let provider: UsageProvider
    public let state: WindowsWidgetContentResolver.State
    public let updatedAt: Date?
    public let showUsed: Bool
    public let body: Body
    public let supplement: WindowsWidgetSupplement?
    /// A requested refresh date; the Windows host/OS determines actual delivery.
    public let nextRefresh: Date
    public let renderedAt: Date
    public let family: ProviderWidgetFamily
    public let hostSize: WindowsWidgetHostDefinition.Size?
    public let historyChart: WindowsWidgetHistory?

    public static func make(
        instanceID: String, configuration: WindowsWidgetConfiguration, snapshot: WidgetSnapshot?,
        family: ProviderWidgetFamily, now: Date, maximumAge: TimeInterval,
        hostSize: WindowsWidgetHostDefinition.Size? = nil) throws -> Self
    {
        let content = try WindowsWidgetContentResolver.resolve(instanceID: instanceID,
            configuration: configuration, snapshot: snapshot, now: now, maximumAge: maximumAge)
        let rowFamily: ProviderWidgetFamily
        if let hostSize {
            guard let definition = WindowsWidgetHostDefinition.allCases.first(where: { $0.kind == content.instance.kind }),
                  definition.sizes.contains(hostSize) else { throw WindowsWidgetHostDefinition.Failure.unsupportedSize }
            rowFamily = hostSize == .small ? .small : .medium
        } else { rowFamily = family }
        let fallbackRefresh = now.addingTimeInterval(30 * 60)
        let burnDown = WindowsWidgetBurnDown.make(from: content, now: now)
        let refresh = burnDown?.nextRefresh ?? fallbackRefresh
        func usageRows() throws -> [WindowsWidgetUsage.Row] {
            if hostSize == .large { return try WindowsWidgetUsage.rows(from: content, now: now) }
            return try WindowsWidgetUsage.rows(from: content, family: rowFamily, now: now)
        }
        let body: Body
        switch content.instance.kind {
        case .switcher:
            // Keep switching available even when the selected provider has no current entry.
            body = .switcher(providers: content.availableProviders,
                rows: try usageRows())
        case .usage:
            body = content.entry == nil ? .unavailable : .usage(
                try usageRows())
        case .history:
            if content.entry == nil { body = .unavailable }
            else {
                body = .history(rows: [],
                    chart: try WindowsWidgetHistory.make(from: content))
            }
        case .metric:
            body = content.entry == nil ? .unavailable : .metric(WindowsWidgetMetric.make(from: content))
        case .burnDown, .combinedBurnDown:
            if content.entry == nil { body = .unavailable }
            else {
                guard let burnDown else { throw Failure.invalidBurnDownSelection }
                body = content.instance.kind == .burnDown ? .burnDown(burnDown) : .combinedBurnDown(burnDown)
            }
        }
        let supplement: WindowsWidgetSupplement?
        switch content.instance.kind {
        case .switcher, .usage, .history:
            supplement = try WindowsWidgetSupplement.make(content: content, configuration: configuration,
                snapshot: snapshot, now: now, maximumAge: maximumAge)
        default: supplement = nil
        }
        let historyChart: WindowsWidgetHistory?
        if case .history(_, let chart) = body { historyChart = chart }
        else if hostSize == .large, content.entry != nil,
                content.instance.kind == .usage || content.instance.kind == .switcher {
            historyChart = try WindowsWidgetHistory.make(from: content)
        } else { historyChart = nil }
        return Self(instanceID: instanceID, kind: content.instance.kind, provider: content.provider,
            state: content.state, updatedAt: content.entry?.updatedAt, showUsed: content.showUsed,
            body: body, supplement: supplement, nextRefresh: refresh, renderedAt: now, family: rowFamily, hostSize: hostSize, historyChart: historyChart)
    }
}
#endif
