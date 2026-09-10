#if os(Windows)
import CodexBarCore
import Foundation

/// Resolves dashboard links using the same provider-specific inputs as the
/// macOS controller, without depending on the AppKit SettingsStore.
public enum WindowsDashboardResolver {
    public static func resolve(
        provider: UsageProvider,
        config: CodexBarConfig,
        sourceLabel: String? = nil,
        claudeLoginMethod: String? = nil,
        zaiUsageScope: ZaiUsageScope? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL?
    {
        let entry = config.providerConfig(for: provider.instanceID)
        switch provider {
        case .alibaba:
            let region = AlibabaCodingPlanAPIRegion(rawValue: entry?.region ?? "") ?? .international
            return region.dashboardURL
        case .alibabatokenplan:
            let region = AlibabaTokenPlanAPIRegion(rawValue: entry?.region ?? "") ?? .chinaMainland
            return AlibabaTokenPlanUsageFetcher.dashboardURL(region: region, environment: environment)
        case .minimax:
            let region = MiniMaxAPIRegion(rawValue: entry?.region ?? "") ?? .global
            return region.dashboardURL
        case .opencodego:
            return OpenCodeGoUsageFetcher.dashboardURL(workspaceID: entry?.workspaceID)
        case .wayfinder:
            let effectiveEnvironment = ProviderConfigEnvironment.applyProviderConfigOverrides(
                base: environment, provider: .wayfinder, config: entry)
            return WayfinderSettingsReader.dashboardURL(environment: effectiveEnvironment)
        case .zai:
            let region = ZaiAPIRegion(rawValue: entry?.region ?? "") ?? .global
            let scope = zaiUsageScope ?? .personal
            return ZaiEndpointRouter.resolveDashboardURL(
                region: region, environment: environment, usageScope: scope)
        case .qoder:
            let settings = QoderProviderSettings(
                cookieSource: entry?.cookieSource ?? .auto,
                manualCookieHeader: entry?.cookieHeader)
            return QoderProviderDescriptor.dashboardURL(settings: settings, sourceLabel: sourceLabel)
        default:
            let metadata = ProviderDescriptorRegistry.metadata[provider]
            let rawURL: String? = if provider == .claude,
                                     ClaudePlan.isSubscriptionLoginMethod(claudeLoginMethod)
            {
                metadata?.subscriptionDashboardURL ?? metadata?.dashboardURL
            } else {
                metadata?.dashboardURL
            }
            guard let rawURL else { return nil }
            return URL(string: rawURL)
        }
    }
}
#endif
