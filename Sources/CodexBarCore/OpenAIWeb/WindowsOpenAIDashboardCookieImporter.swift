#if os(Windows)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Acquires OpenAI cookie headers on Windows without probing the dashboard.
///
/// Each browser profile is represented by one candidate. Records from separate
/// profiles are never combined, so a later authority strategy can validate and
/// select a single account safely.
public struct WindowsOpenAIDashboardCookieImporter: Sendable {
    public struct FoundAccount: Sendable, Hashable {
        public let sourceLabel: String
        public let email: String

        public init(sourceLabel: String, email: String) {
            self.sourceLabel = sourceLabel
            self.email = email
        }
    }

    public struct Candidate: Sendable, Hashable {
        public let sourceLabel: String
        public let profileID: String?
        public let cookieHeader: String

        public init(sourceLabel: String, profileID: String? = nil, cookieHeader: String) {
            self.sourceLabel = sourceLabel
            self.profileID = profileID
            self.cookieHeader = cookieHeader
        }
    }

    public enum ImportError: LocalizedError, Sendable {
        case noCookiesFound
        case browserAccessDenied(details: String)
        case browserCookieLoadTimedOut(details: String)
        case browserCookieLoadFailed(details: String)
        case noMatchingAccount(found: [FoundAccount])
        case manualCookieHeaderInvalid

        public var errorDescription: String? {
            switch self {
            case .noCookiesFound:
                "No browser cookies found."
            case let .browserAccessDenied(details):
                "Browser cookie access denied. " + details
            case let .browserCookieLoadTimedOut(details):
                "Browser cookie loading timed out. " + details
            case let .browserCookieLoadFailed(details):
                "Browser cookie loading failed. " + details
            case let .noMatchingAccount(found):
                if found.isEmpty { return "No matching OpenAI web session found in browsers." }
                let display = found
                    .sorted { lhs, rhs in
                        if lhs.sourceLabel == rhs.sourceLabel { return lhs.email < rhs.email }
                        return lhs.sourceLabel < rhs.sourceLabel
                    }
                    .map { "\($0.sourceLabel)=\($0.email)" }
                    .joined(separator: ", ")
                return "OpenAI web session does not match Codex account. Found: \(display)."
            case .manualCookieHeaderInvalid:
                "Manual cookie header is missing a valid OpenAI session cookie."
            }
        }
    }

    public struct FetchedCandidate: Sendable {
        public let candidate: Candidate
        public let snapshot: OpenAIDashboardSnapshot

        public init(candidate: Candidate, snapshot: OpenAIDashboardSnapshot) {
            self.candidate = candidate
            self.snapshot = snapshot
        }
    }

    private let cookieClient: BrowserCookieClient
    private let importOrder: BrowserCookieImportOrder

    public init(
        cookieClient: BrowserCookieClient = BrowserCookieClient(),
        importOrder: BrowserCookieImportOrder = [.firefox])
    {
        self.cookieClient = cookieClient
        self.importOrder = importOrder
    }

    /// Returns manual, cached, or per-profile browser candidates according to the
    /// configured source. This method does not make network requests. Cancellation
    /// and deadline checks bound work between synchronous SQLite reads; they cannot
    /// interrupt a read already executing inside the synchronous reader.
    public func acquireCandidates(
        cookieSource: ProviderCookieSource,
        manualCookieHeader: String? = nil,
        preferCachedCookieHeader: Bool = true,
        cacheScope: CookieHeaderCache.Scope? = nil,
        deadline: Date? = nil,
        logger: ((String) -> Void)? = nil) async throws -> [Candidate]
    {
        try Task.checkCancellation()
        try Self.checkDeadline(deadline)
        guard cookieSource != .off else { return [] }

        if cookieSource == .manual {
            try Task.checkCancellation()
            try Self.checkDeadline(deadline)
            guard let header = CookieHeaderNormalizer.normalize(manualCookieHeader),
                  !CookieHeaderNormalizer.pairs(from: header).isEmpty
            else { throw ImportError.manualCookieHeaderInvalid }
            return [Candidate(sourceLabel: "Manual", cookieHeader: header)]
        }

        var candidates: [Candidate] = []
        if preferCachedCookieHeader {
            try Task.checkCancellation()
            try Self.checkDeadline(deadline)
            if let cached = CookieHeaderCache.loadSerialized(provider: .codex, scope: cacheScope),
               let header = CookieHeaderNormalizer.normalize(cached.cookieHeader),
               !CookieHeaderNormalizer.pairs(from: header).isEmpty
            {
                candidates.append(Candidate(sourceLabel: cached.sourceLabel, cookieHeader: header))
            }
            try Task.checkCancellation()
            try Self.checkDeadline(deadline)
        }

        var accessDenied: [String] = []
        var profileReadFailed = false
        let query = BrowserCookieQuery(
            domains: ["chatgpt.com"],
            domainMatch: .exact,
            origin: .domainBased)
        for browser in self.importOrder {
            try Task.checkCancellation()
            try Self.checkDeadline(deadline)
            let stores = self.cookieClient.stores(for: browser)
            try Task.checkCancellation()
            try Self.checkDeadline(deadline)
            for store in stores {
                do {
                    try Task.checkCancellation()
                    try Self.checkDeadline(deadline)
                    let records = try self.cookieClient.records(matching: query, in: store, logger: logger)
                    try Task.checkCancellation()
                    try Self.checkDeadline(deadline)
                    let cookies = BrowserCookieClient.makeHTTPCookies(records, origin: query.origin)
                    try Task.checkCancellation()
                    try Self.checkDeadline(deadline)
                    let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                    guard !header.isEmpty else { continue }
                    candidates.append(Candidate(
                        sourceLabel: store.label,
                        profileID: store.profile.id,
                        cookieHeader: header))
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as URLError where error.code == .timedOut {
                    throw error
                } catch let error as BrowserCookieError {
                    switch error {
                    case let .accessDenied(_, details): accessDenied.append(details)
                    case .notFound: break
                    case .loadFailed: profileReadFailed = true
                    }
                    logger?("\(store.label) cookie load failed: \(error.localizedDescription)")
                } catch {
                    profileReadFailed = true
                    logger?("\(store.label) cookie load failed: \(error.localizedDescription)")
                }
            }
        }

        if candidates.isEmpty {
            if !accessDenied.isEmpty {
                throw ImportError.browserAccessDenied(details: Array(Set(accessDenied)).sorted().joined(separator: " "))
            }
            if profileReadFailed {
                throw ImportError.browserCookieLoadFailed(details: "One or more browser profiles could not be read.")
            }
            throw ImportError.noCookiesFound
        }
        return candidates
    }

    /// Explicitly validates one candidate over HTTP and returns its partial dashboard snapshot.
    public func fetchSnapshot(
        for candidate: Candidate,
        expectedAccountEmail: String? = nil,
        cacheScope _: CookieHeaderCache.Scope? = nil,
        deadline: Date = Date().addingTimeInterval(10),
        transport: any ProviderHTTPTransport = ProviderHTTPClient.shared,
        logger: ((String) -> Void)? = nil) async throws -> FetchedCandidate
    {
        try Task.checkCancellation()
        try Self.checkDeadline(deadline)
        let snapshot: OpenAIDashboardSnapshot
        do {
            snapshot = try await OpenAIDashboardHTTPClient(
                cookieHeader: candidate.cookieHeader,
                deadline: deadline,
                transport: transport).fetchSnapshot()
        } catch OpenAIDashboardHTTPClient.FetchError.loginRequired {
            throw ImportError.noCookiesFound
        }

        try Task.checkCancellation()
        let signedInEmail = Self.normalizedEmail(snapshot.signedInEmail)
        let expectedEmail = Self.normalizedEmail(expectedAccountEmail)
        if let expectedEmail {
            guard let signedInEmail else { throw ImportError.noMatchingAccount(found: []) }
            guard signedInEmail == expectedEmail else {
                throw ImportError.noMatchingAccount(found: [
                    FoundAccount(
                        sourceLabel: candidate.sourceLabel,
                        email: snapshot.signedInEmail ?? signedInEmail)
                ])
            }
        }

        logger?("Validated OpenAI session from \(candidate.sourceLabel)\(signedInEmail.map { " (\($0))" } ?? "")")
        return FetchedCandidate(candidate: candidate, snapshot: snapshot)
    }

    private static func normalizedEmail(_ email: String?) -> String? {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else { return nil }
        return email.lowercased()
    }

    private static func checkDeadline(_ deadline: Date?) throws {
        if let deadline, deadline.timeIntervalSinceNow <= 0 { throw URLError(.timedOut) }
    }
}
#endif
