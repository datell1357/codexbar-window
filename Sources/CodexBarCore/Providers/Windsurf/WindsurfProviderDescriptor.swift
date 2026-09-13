import Foundation

public enum WindsurfProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    private static var credentials: ProviderCredentialAdapter? {
        #if os(Windows)
        ProviderCredentialAdapter(tokenAccountSupport: TokenAccountSupport(
            title: "Devin session bundle",
            subtitle: "Paste a Windsurf session JSON bundle or the four devin_* localStorage values exported together from one signed-in browser origin.",
            placeholder: "JSON session bundle",
            injection: .cookieHeader,
            requiresManualCookieSource: true,
            cookieName: nil,
            selectedAccountRequiresManualCookieSource: true,
            cookieHeaderNormalizer: { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
        #else
        nil
        #endif
    }

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .windsurf,
            settingsSection: .init(WindsurfProviderSettingsKey.self, cookieSettings: { settings in
                CookieProviderSettings(
                    cookieSource: settings.cookieSource,
                    manualCookieHeader: settings.manualCookieHeader)
            }, credentialSettings: { context in
                #if os(Windows)
                let cookie = context.cookieSettings(for: .windsurf)
                let source: WindsurfUsageDataSource
                switch context.config?.source {
                case .web: source = .web
                case .cli: source = .cli
                default: source = .auto
                }
                return WindsurfProviderSettings(usageDataSource: source, cookieSource: cookie.cookieSource,
                                                manualCookieHeader: cookie.manualCookieHeader)
                #else
                return nil
                #endif
            }),
            credentials: Self.credentials,
            metadata: ProviderMetadata(
                id: .windsurf,
                displayName: "Windsurf",
                sessionLabel: "Daily",
                weeklyLabel: "Weekly",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Windsurf usage",
                cliName: "windsurf",
                defaultEnabled: false,
                widgetSelectable: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                sharePlanLabels: [
                    "free": "Free", "pro": "Pro", "team": "Teams", "teams": "Teams",
                    "enterprise": "Enterprise", "ultimate": "Ultimate",
                ],
                dashboardURL: "https://windsurf.com/subscription/usage",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .windsurf),
                iconResourceName: "ProviderIcon-windsurf",
                color: ProviderColor(red: 52 / 255, green: 232 / 255, blue: 187 / 255),
                confettiPalette: [
                    ProviderColor(hex: 0x000000),
                    ProviderColor(hex: 0x09B6A2),
                    ProviderColor(hex: 0x34E8BB),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Windsurf cost summary is not supported." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .web, .cli],
                pipeline: ProviderFetchPipeline(resolveStrategies: { context in
                    #if os(Windows)
                    // Manual session selection is handled by the web strategy. Automatic local
                    // reads need not attempt an unimplemented browser importer first.
                    if context.sourceMode == .auto, context.settings?.windsurf?.cookieSource != .manual {
                        return [WindsurfLocalFetchStrategy()]
                    }
                    #endif
                    return [WindsurfWebFetchStrategy(), WindsurfLocalFetchStrategy()]
                })),
            cli: ProviderCLIConfig(
                name: "windsurf",
                versionDetector: nil,
                browserSupportExemption: { source, _, settings in
                    #if os(Windows)
                    // Auto can use the local editor cache; manual web uses no browser importer.
                    if source != .web { return true }
                    return settings?.windsurf?.cookieSource == .manual &&
                        !(settings?.windsurf?.manualCookieHeader?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    #else
                    return false
                    #endif
                }))
    }
}

struct WindsurfWebFetchStrategy: ProviderFetchStrategy {
    let id: String = "windsurf.web"
    let kind: ProviderFetchKind = .web

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        guard context.sourceMode.usesWeb else { return false }
        guard context.settings?.windsurf?.cookieSource != .off else { return false }
        return true
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        #if os(macOS) || os(Windows)
        let cookieSource = context.settings?.windsurf?.cookieSource ?? .auto
        #if os(Windows)
        if context.selectedTokenAccountID != nil, cookieSource != .manual {
            throw WindsurfWebFetcherError.invalidManualSession("The selected account has no manual session. Restore its credentials before refreshing.")
        }
        #endif
        let manualToken = Self.manualToken(from: context)
        let usage = try await WindsurfWebFetcher.fetchUsage(
            browserDetection: context.browserDetection,
            cookieSource: cookieSource,
            manualSessionInput: manualToken,
            timeout: context.webTimeout,
            logger: context.verbose ? { print($0) } : nil)
        return self.makeResult(usage: usage, sourceLabel: "windsurf-web")
        #else
        throw WindsurfStatusProbeError.notSupported
        #endif
    }

    func shouldFallback(on _: Error, context: ProviderFetchContext) -> Bool {
        #if os(Windows)
        if context.selectedTokenAccountID != nil || context.settings?.windsurf?.cookieSource == .manual { return false }
        #endif
        return context.sourceMode == .auto
    }

    private static func manualToken(from context: ProviderFetchContext) -> String? {
        guard context.settings?.windsurf?.cookieSource == .manual else { return nil }
        let header = context.settings?.windsurf?.manualCookieHeader ?? ""
        return header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : header
    }
}

struct WindsurfLocalFetchStrategy: ProviderFetchStrategy {
    let id: String = "windsurf.local"
    let kind: ProviderFetchKind = .localProbe

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        #if os(Windows)
        // The editor cache cannot establish ownership of a selected manual web account.
        if context.selectedTokenAccountID != nil || context.settings?.windsurf?.cookieSource == .manual { return false }
        #endif
        return context.sourceMode != .web
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let probe = WindsurfStatusProbe()
        #if os(Windows)
        let task = Task.detached(priority: .utility) { try probe.fetch() }
        let planInfo = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        #else
        let planInfo = try probe.fetch()
        #endif
        #if os(Windows)
        let now = Date()
        if let end = planInfo.endTimestamp,
           Date(timeIntervalSince1970: TimeInterval(end) / 1000) <= now {
            throw WindsurfStatusProbeError.expiredCache
        }
        let usage = planInfo.toUsageSnapshot(now: now)
        guard usage.primary != nil || usage.secondary != nil else { throw WindsurfStatusProbeError.noData }
        return self.makeResult(usage: usage, sourceLabel: "local cache (age unknown)",
            diagnostic: "The editor cache has no usage update timestamp. The read time is not a live server refresh; expired reset windows are excluded.")
        #else
        let usage = planInfo.toUsageSnapshot()
        return self.makeResult(usage: usage, sourceLabel: "local")
        #endif
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
