#if os(Windows)
import Foundation
import CodexBarCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Builds native cost sources from one config/account capture. Does not read accounts or scan files.
enum WindowsSpendSourceResolver {
    enum Failure: Error { case duplicateProviders, duplicateAccounts, duplicateCodexHomes, codexContextMissing, codexHomeUnavailable }

    static func resolve(config: CodexBarConfig, settings: WindowsSpendSettings,
                        environment: [String: String], cacheRoot: URL,
                        codexContext: CodexAccountContextSnapshot?) throws -> [WindowsSpendSnapshotLoader.Source] {
        try self.resolve(config: config, costEnabledProviders: settings.enabledProviders(config: config),
                         environment: environment, cacheRoot: cacheRoot, codexContext: codexContext,
                         bucketTimeZoneIdentifier: settings.bucketCalendar.timeZone.identifier)
    }

    static func resolve(config: CodexBarConfig, costEnabledProviders: Set<UsageProvider>,
                        environment: [String: String], cacheRoot: URL,
                        codexContext: CodexAccountContextSnapshot?,
                        allowVertexClaudeFallback: Bool = false,
                        includePiSessions: Bool = true,
                        bucketTimeZoneIdentifier: String = CostUsageBucketTimeZone.pinIdentifier()) throws -> [WindowsSpendSnapshotLoader.Source] {
        guard Set(config.providers.map(\.id)).count == config.providers.count else { throw Failure.duplicateProviders }
        let context = try ProviderAccountContext(selection: .init(), config: config, verbose: false,
                                                  baseEnvironment: environment)
        var sources: [WindowsSpendSnapshotLoader.Source] = []
        for id in config.enabledProviders() {
            guard let provider = id.firstPartyProvider, costEnabledProviders.contains(provider) else { continue }
            let entry = config.providerConfig(for: id)
            let accounts = entry?.tokenAccounts?.accounts ?? []
            guard Set(accounts.map(\.id)).count == accounts.count else { throw Failure.duplicateAccounts }
            if provider == .codex {
                guard let codexContext else { throw Failure.codexContextMissing }
                sources.append(contentsOf: try self.codexSources(context: codexContext, environment: environment,
                    cacheRoot: cacheRoot, bucketTimeZoneIdentifier: bucketTimeZoneIdentifier))
                continue
            }
            let account = try context.resolvedAccounts(for: provider).first
            let home: String? = nil
            let scoped = context.environment(base: environment, provider: provider, account: account,
                                             codexAccountContext: provider == .codex ? codexContext : nil)
            let identity = [provider.rawValue, account?.id.uuidString ?? "ambient", home ?? ""]
                .map { "\($0.utf8.count):\($0)" }.joined()
            let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
            let metadata = ProviderDescriptorRegistry.descriptor(for: provider).metadata
            let cookie = ProviderCredentialSettingsContext(config: entry, account: account).cookieSettings(for: provider)
            // Retain the stable filter ID while separating cached data after credential or scope changes.
            var scopeConfig = entry
            scopeConfig?.enabled = nil
            scopeConfig?.quotaWarnings = nil
            scopeConfig?.tokenAccounts = nil
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let configData = try encoder.encode(scopeConfig)
            let environmentData = try encoder.encode(scoped)
            let accountData = try encoder.encode(account)
            let cookieData = try encoder.encode(provider == .cursor ? cookie.manualCookieHeader : nil)
            let zoneData = Data(bucketTimeZoneIdentifier.utf8)
            var scopeDigest = SHA256()
            for component in [configData, environmentData, accountData, cookieData, zoneData] {
                scopeDigest.update(data: Data("\(component.count):".utf8))
                scopeDigest.update(data: component)
            }
            let scopeKey = scopeDigest.finalize().map { String(format: "%02x", $0) }.joined()

            sources.append(.init(id: provider.rawValue + ":" + key, provider: provider,
                displayName: metadata.displayName, modelProviderName: metadata.displayName,
                environment: scoped, cacheRoot: cacheRoot.appendingPathComponent(key, isDirectory: true)
                    .appendingPathComponent(scopeKey, isDirectory: true),
                codexHomePath: home, cursorCookieHeader: provider == .cursor ? cookie.manualCookieHeader : nil,
                subscriptionName: nil, allowVertexClaudeFallback: allowVertexClaudeFallback,
                includePiSessions: includePiSessions,
                expectedCursorAccountID: provider == .cursor ? account?.externalIdentifier : nil))
        }
        return sources
    }

    private static func codexSources(context: CodexAccountContextSnapshot, environment: [String: String],
                                     cacheRoot: URL, bucketTimeZoneIdentifier: String) throws -> [WindowsSpendSnapshotLoader.Source] {
        let accounts = context.visibleAccounts.visibleAccounts
        guard Set(accounts.map(\.id)).count == accounts.count else { throw Failure.duplicateAccounts }
        var seenHomes: Set<String> = []
        let providerName = ProviderDescriptorRegistry.descriptor(for: .codex).metadata.displayName
        return try accounts.enumerated().map { index, account in
            let home: String?
            let token: String
            switch account.selectionSource {
            case .liveSystem:
                token = "live"
                home = CodexHomeScope.normalizedHomePath(CodexHomeScope.ambientHomeURL(env: environment).path)
            case let .managedAccount(id):
                token = "managed:" + id.uuidString.lowercased()
                home = context.reconciliationSnapshot.hasUnreadableAddedAccountStore ? nil :
                    context.reconciliationSnapshot.storedAccounts.first { $0.id == id }
                        .flatMap { CodexHomeScope.normalizedHomePath($0.managedHomePath) }
            case let .profileHome(path):
                token = "profile:" + path
                home = CodexHomeScope.normalizedHomePath(path)
            }
            if let home {
                let canonical = URL(fileURLWithPath: home).standardizedFileURL.path.lowercased()
                guard seenHomes.insert(canonical).inserted else { throw Failure.duplicateCodexHomes }
            }
            let id = self.digest([account.id, token])
            let owner = CodexAuthFingerprint.normalize(account.authFingerprint)
            let cache = self.digest([account.id, token, home ?? "unavailable-home", owner ?? "missing-auth", bucketTimeZoneIdentifier])
            let scoped = home.map { CodexHomeScope.scopedEnvironment(base: environment, codexHome: $0) } ?? environment
            return WindowsSpendSnapshotLoader.Source(id: "codex:" + id, provider: .codex,
                displayName: accounts.count == 1 ? providerName : providerName + " · #\(index + 1)",
                modelProviderName: providerName, environment: scoped,
                cacheRoot: cacheRoot.appendingPathComponent(cache, isDirectory: true), codexHomePath: home,
                cursorCookieHeader: nil, subscriptionName: nil, allowVertexClaudeFallback: false, includePiSessions: true,
                verifyCodexOwner: true, expectedCodexAuthFingerprint: owner)
        }
    }

    private static func digest(_ fields: [String]) -> String {
        let value = fields.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

}
#endif
