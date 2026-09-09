#if os(Windows)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct WindowsBrowserCookieModelTests {
    private func record(
        domain: String = ".example.com", expires: Date? = nil, secure: Bool = true) -> BrowserCookieRecord
    {
        BrowserCookieRecord(
            domain: domain, name: "session", path: "/", value: "synthetic",
            expires: expires, isSecure: secure, isHTTPOnly: true)
    }

    @Test
    func `retains raw domain and infers scope separately`() {
        let record = self.record(domain: " .Example.com ")
        #expect(record.domain == " .Example.com ")
        #expect(record.scope == .domain)
        #expect(self.record(domain: "example.com").scope == .hostOnly)
        #expect(BrowserCookieDomainMatcher.normalizeDomain(record.domain) == "Example.com")
    }

    @Test
    func `matching preserves upstream substring suffix and exact semantics`() {
        #expect(BrowserCookieDomainMatcher.matches(domain: ".EXAMPLE.com", patterns: [" example.COM "], match: .exact))
        #expect(!BrowserCookieDomainMatcher.matches(domain: "sub.example.com", patterns: ["example.com"], match: .exact))
        #expect(BrowserCookieDomainMatcher.matches(domain: "notexample.com", patterns: ["example.com"], match: .suffix))
        #expect(BrowserCookieDomainMatcher.matches(domain: "example.com.other", patterns: ["example.com"], match: .contains))
        #expect(BrowserCookieDomainMatcher.matches(domain: "anything", patterns: [], match: .exact))
    }

    @Test
    func `expiry boundary includes equality and session cookies`() {
        let now = Date(timeIntervalSince1970: 1000)
        let records = [self.record(), self.record(expires: now), self.record(expires: now.addingTimeInterval(-1))]
        #expect(BrowserCookieDomainMatcher.filterExpired(records, includeExpired: false, now: now).count == 2)
        #expect(BrowserCookieDomainMatcher.filterExpired(records, includeExpired: true, now: now).count == 3)
    }

    @Test
    func `HTTP conversion preserves cookie properties without browser access`() throws {
        let expiry = Date(timeIntervalSince1970: 4000000000)
        let cookies = BrowserCookieClient.makeHTTPCookies([self.record(expires: expiry)])
        let cookie = try #require(cookies.first)
        #expect(cookie.name == "session")
        #expect(cookie.value == "synthetic")
        #expect(cookie.isSecure)
        #expect(cookie.isHTTPOnly)
        #expect(cookie.expiresDate == expiry)
        let insecure = try #require(BrowserCookieClient.makeHTTPCookies([self.record(secure: false)]).first)
        #expect(!insecure.isSecure)
        #expect(BrowserCookieClient.makeHTTPCookies([self.record(domain: " . ")]).isEmpty)
    }
}
#endif
