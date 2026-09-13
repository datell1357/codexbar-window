import Foundation

#if os(macOS)
import SweetCookieKit
#endif

public enum AugmentProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    private static let credentials = ProviderCredentialAdapter(tokenAccountSupport: TokenAccountSupport(
        title: "Session tokens",
        subtitle: "Store multiple Augment Cookie headers.",
        placeholder: "Cookie: …",
        injection: .cookieHeader,
        requiresManualCookieSource: true,
        cookieName: nil,
        selectedAccountRequiresManualCookieSource: Self.requiresSelectedManualSource))

    private static var requiresSelectedManualSource: Bool {
        #if os(Windows)
        true
        #else
        false
        #endif
    }

    private static var sourceModes: Set<ProviderSourceMode> {
        #if os(Windows)
        [.auto, .cli, .web]
        #else
        [.auto, .cli]
        #endif
    }

    static func makeDescriptor() -> ProviderDescriptor {
        #if os(macOS)
        // Custom browser order that includes Chrome Beta and other variants
        // to support users running beta/canary versions
        let browserOrder: BrowserCookieImportOrder = [
            .safari,
            .chrome,
            .chromeBeta, // Added for Chrome Beta support
            .chromeCanary, // Added for Chrome Canary support
            .edge,
            .edgeBeta,
            .brave,
            .arc,
            .dia,
            .arcBeta,
            .firefox,
        ]
        #else
        let browserOrder: BrowserCookieImportOrder? = nil
        #endif

        return ProviderDescriptor(
            id: .augment,
            settingsSection: .init(AugmentProviderSettingsKey.self, cookieSettings: AugmentProviderSettings.self),
            credentials: self.credentials,
            metadata: ProviderMetadata(
                id: .augment,
                displayName: "Augment",
                sessionLabel: "Credits",
                weeklyLabel: "Usage",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: true,
                creditsHint: "Augment Code credits for AI-powered coding assistance.",
                toggleTitle: "Show Augment usage",
                cliName: "augment",
                defaultEnabled: false,
                widgetSelectable: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                sharePlanLabels: [
                    "free": "Free", "community": "Community", "indie": "Indie", "pro": "Pro",
                    "team": "Team", "enterprise": "Enterprise",
                ],
                debugPane: ProviderDebugPaneCapabilities(probeLogOrder: 3, errorSimulationOrder: 4),
                browserCookieOrder: browserOrder,
                dashboardURL: "https://app.augmentcode.com/account/subscription",
                statusPageURL: "https://status.augmentcode.com"),
            branding: ProviderBranding(
                iconStyle: .init(provider: .augment),
                iconResourceName: "ProviderIcon-augment",
                color: ProviderColor(red: 99 / 255, green: 102 / 255, blue: 241 / 255),
                confettiPalette: [
                    ProviderColor(hex: 0xF97316),
                    ProviderColor(hex: 0x111111),
                    ProviderColor(hex: 0xFFF7ED),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Augment cost summary is not supported." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: Self.sourceModes,
                pipeline: ProviderFetchPipeline(resolveStrategies: { context in
                    #if os(Windows)
                    if context.settings?.augment?.cookieSource == .manual {
                        return [AugmentStatusFetchStrategy()]
                    }
                    #endif
                    var strategies: [any ProviderFetchStrategy] = []
                    // Try CLI first (no browser prompts!)
                    strategies.append(AugmentCLIFetchStrategy())
                    // Fallback to web (browser cookies)
                    strategies.append(AugmentStatusFetchStrategy())
                    return strategies
                })),
            cli: ProviderCLIConfig(
                name: "augment",
                versionDetector: nil,
                browserSupportExemption: { source, _, settings in
                    #if os(Windows)
                    return source != .web || (settings?.augment?.cookieSource == .manual &&
                        CookieHeaderNormalizer.normalize(settings?.augment?.manualCookieHeader) != nil)
                    #else
                    return false
                    #endif
                }))
    }
}

struct AugmentCLIFetchStrategy: ProviderFetchStrategy {
    let id: String = "augment.cli"
    let kind: ProviderFetchKind = .cli

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        #if os(Windows)
        guard context.sourceMode != .web, context.settings?.augment?.cookieSource != .manual else { return false }
        #endif
        // Check if auggie CLI is installed
        let env = ProcessInfo.processInfo.environment
        let loginPATH = LoginShellPathCache.shared.current
        #if os(Windows)
        // Let fetch report an invalid explicit installation rather than silently skipping it.
        if CodexBarPlatformPaths.environmentValue("AUGGIE_CLI_PATH", environment: env) != nil { return true }
        var pathEnvironment = env
        pathEnvironment["PATH"] = PathBuilder.effectivePATH(
            purposes: [.tty, .nodeTooling], env: env, loginPATH: loginPATH)
        return AuggieCLIProbe.windowsCommand(environment: pathEnvironment) != nil
        #else
        return BinaryLocator.resolveAuggieBinary(env: env, loginPATH: loginPATH) != nil
        #endif
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let probe = AuggieCLIProbe()
        let snap = try await probe.fetch()
        return self.makeResult(
            usage: snap.toUsageSnapshot(),
            sourceLabel: "cli")
    }

    func shouldFallback(on error: Error, context _: ProviderFetchContext) -> Bool {
        #if os(Windows)
        // Automatic web import is not implemented. Preserve the CLI error rather than
        // replacing it with an unrelated missing-cookie error or swallowing cancellation.
        return false
        #else
        // Fallback to web if CLI fails (not authenticated, etc.)
        if let cliError = error as? AuggieCLIError {
            switch cliError {
            case .notAuthenticated, .noOutput, .parseError:
                return true
            }
        }
        return true
        #endif
    }
}

struct AugmentStatusFetchStrategy: ProviderFetchStrategy {
    let id: String = "augment.web"
    let kind: ProviderFetchKind = .web

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        #if os(Windows)
        guard context.sourceMode != .cli else { return false }
        #endif
        guard context.settings?.augment?.cookieSource != .off else { return false }
        return true
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let probe = AugmentStatusProbe()
        let manual = Self.manualCookieHeader(from: context)
        let logger: ((String) -> Void)? = context.verbose
            ? { msg in CodexBarLog.logger(LogCategories.provider(.augment)).verbose(msg) }
            : nil
        let snap = try await probe.fetch(cookieHeaderOverride: manual, logger: logger)
        #if os(Windows)
        let usage = snap.toUsageSnapshot()
        var notes: [String] = []
        if snap.subscriptionAvailable == false {
            notes.append("Credits loaded, but subscription identity and billing details are unavailable.")
        }
        if usage.primary == nil {
            notes.append("Credit amounts are available, but the usage percentage cannot be determined without a valid limit.")
        }
        return self.makeResult(usage: usage, sourceLabel: "web",
            diagnostic: notes.isEmpty ? nil : notes.joined(separator: " "))
        #else
        return self.makeResult(
            usage: snap.toUsageSnapshot(),
            sourceLabel: "web")
        #endif
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func manualCookieHeader(from context: ProviderFetchContext) -> String? {
        guard context.settings?.augment?.cookieSource == .manual else { return nil }
        return CookieHeaderNormalizer.normalize(context.settings?.augment?.manualCookieHeader)
    }
}
