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
    enum Failure: Error { case duplicateProviders, duplicateAccounts, codexContextMissing, codexHomeUnavailable }

    static func resolve(config: CodexBarConfig, costEnabledProviders: Set<UsageProvider>,
                        environment: [String: String], cacheRoot: URL,
                        codexContext: CodexAccountContextSnapshot?,
                        allowVertexClaudeFallback: Bool = false,
                        includePiSessions: Bool = true) throws -> [WindowsSpendSnapshotLoader.Source] {
        guard Set(config.providers.map(\.id)).count == config.providers.count else { throw Failure.duplicateProviders }
        let context = try ProviderAccountContext(selection: .init(), config: config, verbose: false,
                                                  baseEnvironment: environment)
        var sources: [WindowsSpendSnapshotLoader.Source] = []
        for id in config.enabledProviders() {
            guard let provider = id.firstPartyProvider, costEnabledProviders.contains(provider) else { continue }
            let entry = config.providerConfig(for: id)
            let accounts = entry?.tokenAccounts?.accounts ?? []
            guard Set(accounts.map(\.id)).count == accounts.count else { throw Failure.duplicateAccounts }
            let account = try context.resolvedAccounts(for: provider).first
            let home: String?
            if provider == .codex {
                guard let codexContext else { throw Failure.codexContextMissing }
                switch codexContext.resolvedActiveSource.resolvedSource {
                case .liveSystem:
                    home = CodexHomeScope.normalizedHomePath(CodexHomeScope.ambientHomeURL(env: environment).path)
                case let .managedAccount(accountID):
                    guard !codexContext.reconciliationSnapshot.hasUnreadableAddedAccountStore else { throw Failure.codexHomeUnavailable }
                    home = codexContext.reconciliationSnapshot.storedAccounts.first { $0.id == accountID }
                        .flatMap { CodexHomeScope.normalizedHomePath($0.managedHomePath) }
                case let .profileHome(path):
                    home = CodexHomeScope.normalizedHomePath(path)
                }
                guard home != nil else { throw Failure.codexHomeUnavailable }
            } else {
                home = nil
            }
            let scoped = context.environment(base: environment, provider: provider, account: account,
                                             codexAccountContext: provider == .codex ? codexContext : nil)
            let identity = [provider.rawValue, account?.id.uuidString ?? "ambient", home ?? ""]
                .map { "\($0.utf8.count):\($0)" }.joined()
            let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
            let metadata = ProviderDescriptorRegistry.descriptor(for: provider).metadata
            let cookie = ProviderCredentialSettingsContext(config: entry, account: account).cookieSettings(for: provider)
            sources.append(.init(id: provider.rawValue + ":" + key, provider: provider,
                displayName: metadata.displayName, modelProviderName: metadata.displayName,
                environment: scoped, cacheRoot: cacheRoot.appendingPathComponent(key, isDirectory: true),
                codexHomePath: home, cursorCookieHeader: provider == .cursor ? cookie.manualCookieHeader : nil,
                subscriptionName: nil, allowVertexClaudeFallback: allowVertexClaudeFallback,
                includePiSessions: includePiSessions))
        }
        return sources
    }
}
#endif
