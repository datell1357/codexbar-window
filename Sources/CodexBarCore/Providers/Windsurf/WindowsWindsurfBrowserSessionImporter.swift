#if os(Windows)
import Foundation

/// Explicit import operations; discovery and probes never change saved or selected accounts.
public struct WindowsWindsurfBrowserSessionImporter: Sendable {
    public struct Candidate: Sendable {
        public let id: UUID
        public let sourceLabel: String
        public let origin: String
        public let sessionBundle: String
    }
    public struct Discovery: Sendable {
        public let candidates: [Candidate]
        public let failedProfileCount: Int
        public let unsupportedProfileCount: Int
        public let busyProfileCount: Int
        public let omittedProfileCount: Int
        public let incompleteOriginCount: Int
        public let invalidOriginCount: Int
    }
    public struct ProbedCandidate: Sendable {
        public let candidate: Candidate
        public let snapshot: UsageSnapshot
        // Intentionally no verified account ID: GetPlanStatus does not provide one.
    }
    public enum Failure: Error { case timedOut, browserUnavailable, invalidProfileDirectory }

    public static let profileDirectoryEnvironmentKey = "CODEXBAR_WINDSURF_BROWSER_PROFILE_DIRECTORY"

    public static let supportedBrowsers: [Browser] = [
        .chrome, .edge, .brave, .chromium,
        .chromeBeta, .chromeCanary, .edgeBeta, .edgeCanary, .braveBeta, .braveNightly,
    ]

    public init() {}

    public func discover(browser: Browser = .chrome, profileDirectory: String? = nil, environment: [String: String] = ProcessInfo.processInfo.environment, deadline: Date = Date().addingTimeInterval(15)) throws -> Discovery {
        try Self.check(deadline)
        guard Self.supportedBrowsers.contains(browser), BrowserCookieAccessGate.shouldAttempt(browser) else { throw Failure.browserUnavailable }
        let matches = environment.filter { $0.key.caseInsensitiveCompare(Self.profileDirectoryEnvironmentKey) == .orderedSame }
        guard profileDirectory != nil || matches.count <= 1 else { throw Failure.invalidProfileDirectory }
        let profiles: WindowsChromiumLocalStorageProfiles.Discovery
        if let path = profileDirectory ?? matches.first?.value {
            profiles = .init(profiles: [try Self.customProfile(path, browser: browser)], omittedCount: 0)
        } else {
            profiles = try WindowsChromiumLocalStorageProfiles.discover(browsers: [browser], environment: environment, deadline: deadline)
        }
        var candidates: [Candidate] = []
        var failed = 0
        var busy = 0
        var unsupported = 0
        var incomplete = 0
        var invalid = 0
        for profile in profiles.profiles {
            try Self.check(deadline)
            do {
                let result = try WindowsWindsurfBrowserSessions.load(profile: profile, deadline: deadline)
                incomplete += result.incompleteOrigins
                invalid += result.invalidOrigins
                candidates.append(contentsOf: result.candidates.map {
                    Candidate(id: $0.id, sourceLabel: $0.sourceLabel, origin: $0.origin, sessionBundle: $0.sessionBundle)
                })
            } catch is CancellationError { throw CancellationError() }
            catch WindowsLevelDBReadLock.Failure.busy { busy += 1 }
            catch WindowsChromiumLocalStorageDecoder.Failure.unsupportedSchema { unsupported += 1 }
            catch WindowsLevelDBTableContainer.Failure.unsupportedCompression { unsupported += 1 }
            catch { failed += 1 }
            // A per-profile timeout must not become a successful partial discovery.
            try Self.check(deadline)
        }
        return Discovery(candidates: candidates, failedProfileCount: failed, unsupportedProfileCount: unsupported, busyProfileCount: busy,
            omittedProfileCount: profiles.omittedCount, incompleteOriginCount: incomplete, invalidOriginCount: invalid)
    }

    /// This confirms a usable plan response, not the identity claimed in the browser bundle.
    public func probe(_ candidate: Candidate, deadline: Date,
                      transport: (any ProviderHTTPTransport)? = nil) async throws -> ProbedCandidate {
        try Self.check(deadline)
        let remaining = min(60, max(0, deadline.timeIntervalSinceNow))
        let transport = transport ?? WindowsManualAccountHTTPTransport.shared
        let result = try await withThrowingTaskGroup(of: UsageSnapshot.self) { group in
            group.addTask {
                try await WindsurfWebFetcher.probeBrowserSession(candidate.sessionBundle,
                    timeout: remaining, transport: transport)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                throw Failure.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
        try Self.check(deadline)
        return ProbedCandidate(candidate: candidate, snapshot: result)
    }

    private static func customProfile(_ path: String, browser: Browser) throws -> WindowsChromiumLocalStorageProfiles.Profile {
        // Require an explicit local drive path, not drive-relative, UNC or device namespace input.
        let bytes = Array(path.utf8)
        guard path.utf16.count <= 32700, bytes.count >= 3,
              (65...90).contains(bytes[0]) || (97...122).contains(bytes[0]),
              bytes[1] == 58, bytes[2] == 92 || bytes[2] == 47,
              !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              !path.contains("\""), !path.dropFirst(2).contains(":") else { throw Failure.invalidProfileDirectory }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let storage = directory.appendingPathComponent("Local Storage", isDirectory: true)
            .appendingPathComponent("leveldb", isDirectory: true)
        for url in [directory, storage] {
            guard let attributes = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  attributes.isDirectory == true, attributes.isSymbolicLink != true else {
                throw Failure.invalidProfileDirectory
            }
        }
        return .init(id: browser.rawValue + ":custom", browser: browser,
            label: browser.rawValue + " custom profile", directory: storage)
    }

    private static func check(_ deadline: Date) throws {
        try Task.checkCancellation()
        guard Date() < deadline else { throw Failure.timedOut }
    }
}
#endif
