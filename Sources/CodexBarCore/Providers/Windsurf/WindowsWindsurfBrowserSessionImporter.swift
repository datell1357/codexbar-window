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
    public enum Failure: Error { case timedOut, browserUnavailable }

    public init() {}

    public func discover(deadline: Date = Date().addingTimeInterval(15)) throws -> Discovery {
        try Self.check(deadline)
        guard BrowserCookieAccessGate.shouldAttempt(.chrome) else { throw Failure.browserUnavailable }
        let profiles = try WindowsChromiumLocalStorageProfiles.discover(browsers: [.chrome], deadline: deadline)
        var candidates: [Candidate] = []
        var failed = 0
        var busy = 0
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
            catch { failed += 1 }
            // A per-profile timeout must not become a successful partial discovery.
            try Self.check(deadline)
        }
        return Discovery(candidates: candidates, failedProfileCount: failed, busyProfileCount: busy,
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

    private static func check(_ deadline: Date) throws {
        try Task.checkCancellation()
        guard Date() < deadline else { throw Failure.timedOut }
    }
}
#endif
