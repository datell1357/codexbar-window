// Adapted from SweetCookieKit 0.5.2, d5ea6d92298779ec0c3ddf7d3d99da186a305e14.
// Copyright (c) 2026 Peter Steinberger. MIT; see docs/windows-port/SweetCookieKit-LICENSE.txt.
#if os(Windows)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Domain matching strategy for cookie queries.
public enum BrowserCookieDomainMatch: Sendable {
    /// Match when the cookie's domain contains the pattern.
    case contains
    /// Match when the cookie's domain ends with the pattern (suffix match).
    case suffix
    /// Match when the cookie's domain exactly matches the pattern.
    case exact
}

/// Maps a cookie domain to an origin URL when building `HTTPCookie` values.
public enum BrowserCookieOriginStrategy: Sendable {
    /// Use `https://{domain}`.
    case domainBased
    /// Always use the provided origin URL.
    case fixed(URL)
    /// Custom resolver that maps domain → origin URL.
    case custom(@Sendable (String) -> URL?)

    func resolve(domain: String) -> URL? {
        switch self {
        case .domainBased:
            URL(string: "https://\(domain)")
        case let .fixed(url):
            url
        case let .custom(resolver):
            resolver(domain)
        }
    }
}

/// Query definition for fetching browser cookies.
public struct BrowserCookieQuery: Sendable {
    /// Domain patterns to match (empty = no filtering).
    public var domains: [String]
    /// Matching strategy for domains.
    public var domainMatch: BrowserCookieDomainMatch
    /// Origin URL resolver for building `HTTPCookie` values.
    public var origin: BrowserCookieOriginStrategy
    /// Include expired cookies when true.
    public var includeExpired: Bool
    /// Reference date used to filter expired cookies.
    public var referenceDate: Date

    /// Creates a query for filtering and converting cookies.
    /// - Parameters:
    ///   - domains: Domain patterns to match (empty = no filtering).
    ///   - domainMatch: Domain matching strategy for `domains`.
    ///   - origin: Origin URL strategy used when converting to `HTTPCookie`.
    ///   - includeExpired: Whether expired cookies should be included.
    ///   - referenceDate: "Now" date used to filter expired cookies when `includeExpired == false`.
    public init(
        domains: [String] = [],
        domainMatch: BrowserCookieDomainMatch = .contains,
        origin: BrowserCookieOriginStrategy = .domainBased,
        includeExpired: Bool = false,
        referenceDate: Date = Date())
    {
        self.domains = domains
        self.domainMatch = domainMatch
        self.origin = origin
        self.includeExpired = includeExpired
        self.referenceDate = referenceDate
    }
}

/// A browser profile identifier.
public struct BrowserProfile: Sendable, Hashable {
    /// Stable identifier for the profile (often a filesystem path or derived key).
    public let id: String
    /// Human-readable profile name.
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Which cookie store a browser profile represents.
public enum BrowserCookieStoreKind: String, Sendable {
    /// Primary/regular cookie database for a profile.
    case primary
    /// Auxiliary store used by some Chromium variants (e.g. "Network" cookies).
    case network
    /// Safari cookie store.
    case safari
}

/// A concrete cookie store for a browser profile.
public struct BrowserCookieStore: Sendable, Hashable {
    /// Browser family and distribution.
    public let browser: Browser
    /// Browser profile metadata.
    public let profile: BrowserProfile
    /// Cookie store kind (e.g., primary vs network).
    public let kind: BrowserCookieStoreKind
    /// Human-readable label for UI or logs.
    public let label: String
    /// Backing cookie database URL when applicable.
    public let databaseURL: URL?

    public init(
        browser: Browser,
        profile: BrowserProfile,
        kind: BrowserCookieStoreKind,
        label: String,
        databaseURL: URL?)
    {
        self.browser = browser
        self.profile = profile
        self.kind = kind
        self.label = label
        self.databaseURL = databaseURL
    }
}

/// The browser's domain-matching policy for a cookie.
public enum BrowserCookieScope: Sendable, Equatable {
    /// The cookie is sent only to the exact host that created it.
    case hostOnly
    /// The cookie is sent to its domain and matching subdomains.
    case domain
}

/// A browser cookie record normalized for cross-browser handling.
public struct BrowserCookieRecord: Sendable {
    /// Stored domain; normalization is performed separately during matching and HTTP conversion.
    public let domain: String
    /// Whether the browser stored this as an exact-host or domain cookie.
    public let scope: BrowserCookieScope
    public let name: String
    public let path: String
    public let value: String
    /// Cookie expiry date, or `nil` for session cookies.
    public let expires: Date?
    public let isSecure: Bool
    public let isHTTPOnly: Bool

    public init(
        domain: String,
        name: String,
        path: String,
        value: String,
        expires: Date?,
        isSecure: Bool,
        isHTTPOnly: Bool)
    {
        self.init(
            domain: domain,
            name: name,
            path: path,
            value: value,
            expires: expires,
            isSecure: isSecure,
            isHTTPOnly: isHTTPOnly,
            scope: domain.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(".") ? .domain : .hostOnly)
    }

    public init(
        domain: String,
        name: String,
        path: String,
        value: String,
        expires: Date?,
        isSecure: Bool,
        isHTTPOnly: Bool,
        scope: BrowserCookieScope)
    {
        self.domain = domain
        self.scope = scope
        self.name = name
        self.path = path
        self.value = value
        self.expires = expires
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
    }
}

/// Cookie records loaded from a specific browser store.
public struct BrowserCookieStoreRecords: Sendable {
    /// Cookie store that produced these records.
    public let store: BrowserCookieStore
    /// Cookie records from the store.
    public let records: [BrowserCookieRecord]

    public init(store: BrowserCookieStore, records: [BrowserCookieRecord]) {
        self.store = store
        self.records = records
    }

    /// Convenience access to the store label.
    public var label: String {
        self.store.label
    }

    /// Convenience access to the store's browser.
    public var browser: Browser {
        self.store.browser
    }

    /// Converts the contained records into `HTTPCookie` values.
    /// - Parameter origin: Origin URL strategy used when building `HTTPCookie`.
    public func cookies(origin: BrowserCookieOriginStrategy = .domainBased) -> [HTTPCookie] {
        BrowserCookieClient.makeHTTPCookies(self.records, origin: origin)
    }
}

/// Errors raised when reading browser cookies.
public enum BrowserCookieError: LocalizedError, Sendable {
    /// No cookie store found for the requested browser.
    case notFound(browser: Browser, details: String)
    /// Access denied (for example Full Disk Access / Keychain denied).
    case accessDenied(browser: Browser, details: String)
    /// Store found but loading/parsing failed.
    case loadFailed(browser: Browser, details: String)

    public var errorDescription: String? {
        switch self {
        case let .notFound(_, details), let .accessDenied(_, details), let .loadFailed(_, details):
            details
        }
    }

    /// Browser that produced the error.
    public var browser: Browser {
        switch self {
        case let .notFound(browser, _), let .accessDenied(browser, _), let .loadFailed(browser, _):
            browser
        }
    }

    /// Optional guidance for user-facing permission errors.
    public var accessDeniedHint: String? {
        switch self {
        case let .accessDenied(_, details):
            details
        case .notFound, .loadFailed:
            nil
        }
    }
}

#endif
