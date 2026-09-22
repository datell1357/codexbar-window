#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarWindows

/// Implementation-only fixtures: synthetic config directories, no providers, UI, or real accounts.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsSpendOwnershipTests {
    private typealias Source = WindowsSpendSnapshotLoader.Source

    private static func makeDirectory(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-spend-owner-" + label + "-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func writeClaudeConfig(root: URL, accountUuid: String) throws {
        let config = "{\"oauthAccount\":{\"accountUuid\":\"" + accountUuid + "\"}}"
        try config.write(to: root.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
    }

    private static func source(provider: UsageProvider, environment: [String: String]) -> Source {
        Source(id: provider.rawValue + ":fixture", provider: provider, displayName: provider.rawValue,
            modelProviderName: provider.rawValue, environment: environment, cacheRoot: nil,
            codexHomePath: nil, cursorCookieHeader: nil, subscriptionName: nil,
            allowVertexClaudeFallback: false, includePiSessions: false)
    }

    @Test
    func `claude retention eligibility requires a captured session scope`() throws {
        let root = try Self.makeDirectory("claude")
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = [ClaudeConfigPaths.configDirectoryEnvironmentKey: root.path]
        // A missing or signed-out profile cannot prove ownership, so retention stays off.
        #expect(ClaudeAccountProfile.identifiedSessionScope(environment: environment) == nil)
        var source = Self.source(provider: .claude, environment: environment)
        #expect(!source.supportsRetainedCollection)
        try Self.writeClaudeConfig(root: root, accountUuid: "11111111-2222-3333-4444-555555555555")
        let scope = try #require(ClaudeAccountProfile.identifiedSessionScope(environment: environment))
        source.expectedClaudeSessionScope = scope
        #expect(source.supportsRetainedCollection)
        // A different account UUID yields a different scope; captured values cannot cross accounts.
        try Self.writeClaudeConfig(root: root, accountUuid: "99999999-8888-7777-6666-555555555555")
        #expect(ClaudeAccountProfile.identifiedSessionScope(environment: environment) != scope)
    }

    @Test
    func `a rotated claude profile fails the source instead of retaining a prior value`() async throws {
        let root = try Self.makeDirectory("claude-rotate")
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = [ClaudeConfigPaths.configDirectoryEnvironmentKey: root.path]
        try Self.writeClaudeConfig(root: root, accountUuid: "11111111-2222-3333-4444-555555555555")
        var source = Self.source(provider: .claude, environment: environment)
        source.expectedClaudeSessionScope = try #require(
            ClaudeAccountProfile.identifiedSessionScope(environment: environment))
        try Self.writeClaudeConfig(root: root, accountUuid: "99999999-8888-7777-6666-555555555555")
        let loader = WindowsSpendSnapshotLoader.make(sources: [source], forceRefresh: true,
            allowPricingRefresh: false, calendar: Calendar(identifier: .gregorian), capturedAt: Date())
        let scan = try await loader(30)
        #expect(scan.inputs.isEmpty)
        let failure = try #require(scan.sourceFailures.first)
        #expect(failure.sourceID == source.id)
        #expect(failure.accountIdentityUnconfirmed)
        #expect(!failure.localInventoryPending)
        #expect(!scan.retentionEligibleSourceIDs.isEmpty)
    }

    @Test
    func `a signed-out claude profile fails a scoped source instead of scanning ambient logs`() async throws {
        let root = try Self.makeDirectory("claude-signout")
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = [ClaudeConfigPaths.configDirectoryEnvironmentKey: root.path]
        try Self.writeClaudeConfig(root: root, accountUuid: "11111111-2222-3333-4444-555555555555")
        var source = Self.source(provider: .claude, environment: environment)
        source.expectedClaudeSessionScope = try #require(
            ClaudeAccountProfile.identifiedSessionScope(environment: environment))
        try FileManager.default.removeItem(at: root.appendingPathComponent(".claude.json"))
        let loader = WindowsSpendSnapshotLoader.make(sources: [source], forceRefresh: true,
            allowPricingRefresh: false, calendar: Calendar(identifier: .gregorian), capturedAt: Date())
        let scan = try await loader(30)
        let failure = try #require(scan.sourceFailures.first)
        #expect(failure.accountIdentityUnconfirmed)
        #expect(!failure.localInventoryPending)
    }

    @Test
    func `vertex credential fingerprint binds path and content and fails closed`() throws {
        let root = try Self.makeDirectory("vertex")
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = root.appendingPathComponent("adc.json")
        let cloudConfig = root.appendingPathComponent("gcloud", isDirectory: true)
        try FileManager.default.createDirectory(at: cloudConfig, withIntermediateDirectories: true)
        var environment = [
            "GOOGLE_APPLICATION_CREDENTIALS": credentials.path,
            "CLOUDSDK_CONFIG": cloudConfig.path,
        ]
        #expect(VertexAIOAuthCredentialsStore.credentialFileFingerprint(environment: environment) == nil)
        try "{\"type\":\"authorized_user\",\"client_id\":\"a\"}".write(
            to: credentials, atomically: true, encoding: .utf8)
        let fingerprint = try #require(
            VertexAIOAuthCredentialsStore.credentialFileFingerprint(environment: environment))
        #expect(fingerprint == VertexAIOAuthCredentialsStore.credentialFileFingerprint(environment: environment))
        try "{\"type\":\"authorized_user\",\"client_id\":\"b\"}".write(
            to: credentials, atomically: true, encoding: .utf8)
        #expect(VertexAIOAuthCredentialsStore.credentialFileFingerprint(environment: environment) != fingerprint)
        let other = root.appendingPathComponent("other.json")
        try "{\"type\":\"authorized_user\",\"client_id\":\"b\"}".write(
            to: other, atomically: true, encoding: .utf8)
        environment["GOOGLE_APPLICATION_CREDENTIALS"] = other.path
        #expect(VertexAIOAuthCredentialsStore.credentialFileFingerprint(environment: environment) != fingerprint)
        environment["GOOGLE_APPLICATION_CREDENTIALS"] = credentials.path
        let oversized = root.appendingPathComponent("oversized.json")
        try Data(repeating: 0x41, count: 256 * 1024 + 1).write(to: oversized)
        environment["GOOGLE_APPLICATION_CREDENTIALS"] = oversized.path
        #expect(VertexAIOAuthCredentialsStore.credentialFileFingerprint(environment: environment) == nil)
    }

    @Test
    func `a replaced vertex credential fails the source instead of retaining a prior value`() async throws {
        let root = try Self.makeDirectory("vertex-rotate")
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = root.appendingPathComponent("adc.json")
        let cloudConfig = root.appendingPathComponent("gcloud", isDirectory: true)
        try FileManager.default.createDirectory(at: cloudConfig, withIntermediateDirectories: true)
        let environment = [
            "GOOGLE_APPLICATION_CREDENTIALS": credentials.path,
            "CLOUDSDK_CONFIG": cloudConfig.path,
        ]
        try "{\"type\":\"authorized_user\",\"client_id\":\"a\"}".write(
            to: credentials, atomically: true, encoding: .utf8)
        var source = Self.source(provider: .vertexai, environment: environment)
        source.expectedVertexCredentialFingerprint = try #require(
            VertexAIOAuthCredentialsStore.credentialFileFingerprint(environment: environment))
        #expect(source.supportsRetainedCollection)
        try "{\"type\":\"authorized_user\",\"client_id\":\"rotated\"}".write(
            to: credentials, atomically: true, encoding: .utf8)
        let loader = WindowsSpendSnapshotLoader.make(sources: [source], forceRefresh: true,
            allowPricingRefresh: false, calendar: Calendar(identifier: .gregorian), capturedAt: Date())
        let scan = try await loader(30)
        #expect(scan.inputs.isEmpty)
        let failure = try #require(scan.sourceFailures.first)
        #expect(failure.sourceID == source.id)
        #expect(failure.accountIdentityUnconfirmed)
        #expect(!failure.localInventoryPending)
    }

    @Test
    func `a missing vertex credential keeps the source retention ineligible`() {
        var source = Self.source(provider: .vertexai, environment: [:])
        source.expectedVertexCredentialFingerprint = nil
        #expect(!source.supportsRetainedCollection)
    }

    @Test
    func `antigravity credential fingerprint binds env injection and the store file`() throws {
        let root = try Self.makeDirectory("antigravity")
        defer { try? FileManager.default.removeItem(at: root) }
        var environment = ["HOME": root.path]
        // No env injection and no store file: fail closed.
        #expect(AntigravityOAuthCredentialsStore.credentialFileFingerprint(environment: environment) == nil)
        var source = Self.source(provider: .antigravity, environment: environment)
        #expect(!source.supportsRetainedCollection)
        let store = root.appendingPathComponent(".codexbar/antigravity", isDirectory: true)
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        let file = store.appendingPathComponent("oauth_creds.json")
        try "{\"email\":\"a@example.com\"}".write(to: file, atomically: true, encoding: .utf8)
        let first = try #require(
            AntigravityOAuthCredentialsStore.credentialFileFingerprint(environment: environment))
        source.expectedAntigravityCredentialFingerprint = first
        #expect(source.supportsRetainedCollection)
        // Rotated bytes produce a different owner; captured values cannot cross accounts.
        try "{\"email\":\"b@example.com\"}".write(to: file, atomically: true, encoding: .utf8)
        #expect(AntigravityOAuthCredentialsStore.credentialFileFingerprint(environment: environment) != first)
        // Injected credentials are their own captured proof and take precedence over the file.
        environment[AntigravityOAuthCredentialsStore.environmentCredentialsKey] = "{\"email\":\"c@example.com\"}"
        let injected = try #require(
            AntigravityOAuthCredentialsStore.credentialFileFingerprint(environment: environment))
        #expect(injected != first)
        #expect(AntigravityOAuthCredentialsStore.credentialFileFingerprint(environment: environment) == injected)
    }

    @Test
    func `a replaced antigravity credential fails the source instead of retaining a prior value`() async throws {
        let root = try Self.makeDirectory("antigravity-rotate")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent(".codexbar/antigravity", isDirectory: true)
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        let file = store.appendingPathComponent("oauth_creds.json")
        try "{\"email\":\"a@example.com\"}".write(to: file, atomically: true, encoding: .utf8)
        let environment = ["HOME": root.path]
        var source = Self.source(provider: .antigravity, environment: environment)
        source.expectedAntigravityCredentialFingerprint = try #require(
            AntigravityOAuthCredentialsStore.credentialFileFingerprint(environment: environment))
        #expect(source.supportsRetainedCollection)
        try "{\"email\":\"rotated@example.com\"}".write(to: file, atomically: true, encoding: .utf8)
        let loader = WindowsSpendSnapshotLoader.make(sources: [source], forceRefresh: true,
            allowPricingRefresh: false, calendar: Calendar(identifier: .gregorian), capturedAt: Date())
        let scan = try await loader(30)
        #expect(scan.inputs.isEmpty)
        let failure = try #require(scan.sourceFailures.first)
        #expect(failure.sourceID == source.id)
        #expect(failure.accountIdentityUnconfirmed)
        #expect(!failure.localInventoryPending)
    }
}
#endif
