#if os(Windows)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
        var query = BrowserCookieQuery(domains: ["cursor.com"], domainMatch: .exact, origin: .domainBased)
        query.includePartitionedCookies = true
        query.deadline = deadline
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
                let partitions = Dictionary(grouping: records, by: \.storagePartition)
                for (index, partition) in partitions.keys.sorted().enumerated() {
                    try Self.check(deadline)
                    let cookies = BrowserCookieClient.makeHTTPCookies(partitions[partition] ?? [], origin: query.origin).filter {
                        ($0.expiresDate == nil || $0.expiresDate! > Date()) && $0.path == "/"
                    }
                    guard cookies.contains(where: { cookie in
                        names.contains(cookie.name) || names.contains(where: { cookie.name.hasPrefix($0 + ".") })
                    }) else { continue }
                    guard let header = Self.unambiguousHeader(cookies) else {
                        failures += 1
                        continue
                    }
                    candidates.append(Candidate(profileID: store.profile.id + "#partition-\(index)", sourceLabel: store.label + " session \(index + 1)", cookieHeader: header))
                }
            } catch is CancellationError { throw CancellationError() }
            catch let error as URLError where error.code == .timedOut { throw error }
            catch { failures += 1 }
        }
        try Self.check(deadline)
        return Discovery(candidates: candidates, failedProfileCount: failures)
    }

    /// Reject ambiguous host/domain duplicates and malformed header bytes; never choose an account by row order.
    private static func unambiguousHeader(_ cookies: [HTTPCookie]) -> String? {
        var values: [String: String] = [:]
        let namePunctuation = Set("!#$%&'*+-.^_`|~".utf8)
        for cookie in cookies {
            guard !cookie.name.isEmpty, cookie.name.utf8.allSatisfy({ byte in
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) ||
                    namePunctuation.contains(byte)
            }), cookie.value.utf8.allSatisfy({ byte in
                byte == 0x21 || (0x23...0x2B).contains(byte) || (0x2D...0x3A).contains(byte) ||
                    (0x3C...0x5B).contains(byte) || (0x5D...0x7E).contains(byte)
            }) else { return nil }
            if let previous = values[cookie.name], previous != cookie.value { return nil }
            values[cookie.name] = cookie.value
        }
        guard !values.isEmpty else { return nil }
        let header = values.keys.sorted().map { "\($0)=\(values[$0]!)" }.joined(separator: "; ")
        guard header.utf8.count <= 65_536 else { return nil }
        return header
    }

    /// Uses the import's shared deadline, rather than resetting a timeout for each profile.
    /// Cancellation is cooperative: the transport must finish draining its cancelled requests.
    public func validate(_ candidate: Candidate, deadline: Date,
                         transport: any ProviderHTTPTransport = ProviderHTTPClient.shared) async throws -> ValidatedCandidate {
        try Self.check(deadline)
        let remaining = min(60, max(0, deadline.timeIntervalSinceNow))
        let result = try await withThrowingTaskGroup(of: ValidatedCandidate.self) { group in
            group.addTask {
                try await self.validate(candidate, transport: transport)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
        // A response queued near the timer boundary must not create a fresh selection ticket.
        try Self.check(deadline)
        return result
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
