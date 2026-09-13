import Foundation

public enum ZedProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()

    private static var credentials: ProviderCredentialAdapter? {
        #if os(Windows)
        ProviderCredentialAdapter(tokenAccountSupport: TokenAccountSupport(
            title: "Zed credentials",
            subtitle: "Enter the user ID and access token separated by one space. For a custom server, append its HTTPS origin after another space.",
            placeholder: "userID accessToken [https://server]",
            injection: .environment(key: WindowsZedCredentialsReader.environmentKey),
            requiresManualCookieSource: false, cookieName: nil))
        #else
        nil
        #endif
    }

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .zed,
            credentials: Self.credentials,
            metadata: ProviderMetadata(
                id: .zed,
                displayName: "Zed",
                sessionLabel: "Edit predictions",
                weeklyLabel: "Billing cycle",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Zed usage",
                cliName: "zed",
                defaultEnabled: false,
                widgetSelectable: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                sharePlanLabels: [
                    "zed free": "Zed Free", "zed pro": "Zed Pro", "zed pro trial": "Zed Pro Trial",
                    "zed student": "Zed Student", "zed business": "Zed Business",
                ],
                dashboardURL: nil,
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .zed),
                iconResourceName: "ProviderIcon-zed",
                color: ProviderColor(red: 8 / 255, green: 78 / 255, blue: 255 / 255),
                confettiPalette: [
                    ProviderColor(hex: 0x084CCF),
                    ProviderColor(hex: 0x000000),
                    ProviderColor(hex: 0xFFFFFF),
                ],
                widgetColor: ProviderColor(red: 64 / 255, green: 156 / 255, blue: 255 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Zed cost summary is not supported." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in
                    [ZedLocalFetchStrategy()]
                })),
            cli: ProviderCLIConfig(
                name: "zed",
                versionDetector: nil,
                browserSupportExemption: { _, _, _ in
                    #if os(Windows)
                    true
                    #else
                    false
                    #endif
                }))
    }
}

struct ZedLocalFetchStrategy: ProviderFetchStrategy {
    let id: String = "zed.local"
    let kind: ProviderFetchKind = .localProbe

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        true
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        _ = context
        #if os(Windows)
        let reader = WindowsZedCredentialsReader(environment: context.env)
        let settings = try reader.settings()
        let snapshot = try await ZedStatusProbe(
            credentialsReader: reader,
            settingsLoader: { settings }).fetch()
        return self.makeResult(usage: snapshot.toUsageSnapshot(), sourceLabel: "manual API")
        #else
        let snapshot = try await ZedStatusProbe().fetch()
        return self.makeResult(usage: snapshot.toUsageSnapshot(), sourceLabel: "local")
        #endif
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
