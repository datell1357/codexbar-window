// Adapted from SweetCookieKit 0.5.2, d5ea6d92298779ec0c3ddf7d3d99da186a305e14.
// Copyright (c) 2026 Peter Steinberger. MIT; see docs/windows-port/SweetCookieKit-LICENSE.txt.
#if os(Windows)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension BrowserCookieClient {
    public static func makeHTTPCookies(
        _ records: [BrowserCookieRecord],
        origin: BrowserCookieOriginStrategy = .domainBased) -> [HTTPCookie]
    {
        records.compactMap { record in
            let domain = BrowserCookieDomainMatcher.normalizeDomain(record.domain)
            guard !domain.isEmpty else { return nil }
            var props: [HTTPCookiePropertyKey: Any] = [
                .domain: domain,
                .path: record.path,
                .name: record.name,
                .value: record.value,
            ]
            // FoundationNetworking accepts a nonempty String for Secure, not Darwin's Bool representation.
            if record.isSecure {
                props[.secure] = "TRUE"
            }
            if let originURL = origin.resolve(domain: domain) {
                props[.originURL] = originURL
            }
            if record.isHTTPOnly {
                props[.init("HttpOnly")] = "TRUE"
            }
            if let expires = record.expires {
                props[.expires] = expires
            }
            return HTTPCookie(properties: props)
        }
    }

}

enum BrowserCookieDomainMatcher {
    static func scope(forStoredDomain domain: String) -> BrowserCookieScope {
        domain.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(".") ? .domain : .hostOnly
    }

    static func normalizeDomain(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(".") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    static func matches(domain: String, patterns: [String], match: BrowserCookieDomainMatch) -> Bool {
        guard !patterns.isEmpty else { return true }
        let haystack = self.normalizeDomain(domain).lowercased()
        return patterns.contains { pattern in
            let needle = self.normalizeDomain(pattern).lowercased()
            switch match {
            case .contains:
                return haystack.contains(needle)
            case .suffix:
                return haystack.hasSuffix(needle)
            case .exact:
                return haystack == needle
            }
        }
    }

    static func filterExpired(
        _ records: [BrowserCookieRecord],
        includeExpired: Bool,
        now: Date) -> [BrowserCookieRecord]
    {
        guard !includeExpired else { return records }
        return records.filter { record in
            guard let expires = record.expires else { return true }
            return expires >= now
        }
    }

    static func chromeExpiryDate(expiresUTC: Int64) -> Date? {
        guard expiresUTC > 0 else { return nil }
        let seconds = (Double(expiresUTC) / 1_000_000.0) - 11_644_473_600.0
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

}
#endif
