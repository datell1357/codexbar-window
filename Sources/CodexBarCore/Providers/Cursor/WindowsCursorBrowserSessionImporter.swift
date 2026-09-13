#if os(Windows)
import Foundation

/// Explicit browser-import backend. Discovery never commits a candidate or changes the selected account.
public struct WindowsCursorBrowserSessionImporter: Sendable {
    public struct Candidate: Sendable {
        public let profileID: String
        public let sourceLabel: String
        public let cookieHeader: String
    }
    public struct Discovery: Sendable {
        public let candidates: [Candidate]
        public let failedProfileCount: Int
    }
    public struct ValidatedCandidate: Sendable {
        public let candidate: Candidate
        public let snapshot: CursorStatusSnapshot
        public let accountID: String
    }
    public enum Failure: Error { case browserUnavailable, missingAccountIdentity, accountMismatch }
    private let client: BrowserCookieClient
    public init(client: BrowserCookieClient = BrowserCookieClient()) { self.client = client }

    public func discover(deadline: Date = Date().addingTimeInterval(15)) throws -> Discovery {
        try Self.check(deadline)
        guard BrowserCookieAccessGate.shouldAttempt(.firefox) else { throw Failure.browserUnavailable }
        let query = BrowserCookieQuery(domains: ["cursor.com"], domainMatch: .exact, origin: .domainBased)
        let names: Set<String> = ["WorkosCursorSessionToken", "__Secure-next-auth.session-token",
                                 "next-auth.session-token", "wos-session", "__Secure-wos-session",
                                 "authjs.session-token", "__Secure-authjs.session-token"]
        var candidates: [Candidate] = []
        var failures = 0
        for store in self.client.stores(for: .firefox) {
            try Self.check(deadline)
            do {
                let records = try self.client.records(matching: query, in: store)
                try Self.check(deadline)
                let cookies = BrowserCookieClient.makeHTTPCookies(records, origin: query.origin).filter {
                    ($0.expiresDate == nil || $0.expiresDate! > Date()) && $0.path == "/"
                }
                guard cookies.contains(where: { cookie in
                    names.contains(cookie.name) || names.contains(where: { cookie.name.hasPrefix($0 + ".") })
                }) else { continue }
                let raw = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                guard raw.utf8.count <= 65_536, let header = CookieHeaderNormalizer.normalize(raw) else {
                    failures += 1
                    continue
                }
                candidates.append(Candidate(profileID: store.profile.id, sourceLabel: store.label, cookieHeader: header))
            } catch is CancellationError { throw CancellationError() }
            catch let error as URLError where error.code == .timedOut { throw error }
            catch { failures += 1 }
        }
        try Self.check(deadline)
        return Discovery(candidates: candidates, failedProfileCount: failures)
    }

    public func validate(_ candidate: Candidate, expectedAccountID: String? = nil,
                         transport: any ProviderHTTPTransport = ProviderHTTPClient.shared) async throws -> ValidatedCandidate {
        try Task.checkCancellation()
        let snapshot = try await CursorStatusProbe(browserDetection: BrowserDetection(), urlSession: transport)
            .fetch(cookieHeaderOverride: candidate.cookieHeader, allowCachedSessions: false, allowAppAuthFallback: false)
        try Task.checkCancellation()
        guard let id = snapshot.accountID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            throw Failure.missingAccountIdentity
        }
        if let expectedAccountID, id != expectedAccountID { throw Failure.accountMismatch }
        return ValidatedCandidate(candidate: candidate, snapshot: snapshot, accountID: id)
    }

    private static func check(_ deadline: Date) throws {
        try Task.checkCancellation()
        guard Date() < deadline else { throw URLError(.timedOut) }
    }
}
#endif
