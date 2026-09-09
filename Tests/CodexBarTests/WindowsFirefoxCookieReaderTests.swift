#if os(Windows)
import CSQLite3
import Foundation
import Testing
@testable import CodexBarCore

struct WindowsFirefoxCookieReaderTests {
    private func database() throws -> OpaquePointer {
        var database: OpaquePointer?
        guard sqlite3_open(":memory:", &database) == SQLITE_OK, let database else {
            sqlite3_close(database)
            throw FixtureError.open
        }
        return database
    }

    private func populate(_ database: OpaquePointer) throws {
        let sql = """
        CREATE TABLE moz_cookies(host TEXT, name TEXT, path TEXT, value TEXT, expiry INTEGER, isSecure INTEGER, isHttpOnly INTEGER);
        INSERT INTO moz_cookies VALUES('.example.com','domain','/','synthetic',1000,1,1);
        INSERT INTO moz_cookies VALUES('example.com','session','/','synthetic',0,0,0);
        INSERT INTO moz_cookies VALUES('example.com','expired','/','synthetic',999,1,0);
        INSERT INTO moz_cookies VALUES('EXAMPLE.com','uppercase','/','synthetic',0,0,0);
        INSERT INTO moz_cookies VALUES('notexample.com','suffix','/','synthetic',0,0,0);
        INSERT INTO moz_cookies VALUES('example.com',NULL,'/','synthetic',0,0,0);
        INSERT INTO moz_cookies VALUES('exa''mple.test','quote','/','synthetic',0,0,0);
        """
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw FixtureError.populate }
    }

    @Test
    func `exact SQL matching preserves expiry scope and null row rules`() throws {
        let database = try self.database()
        defer { sqlite3_close(database) }
        try self.populate(database)
        let query = BrowserCookieQuery(
            domains: ["example.com"], domainMatch: .exact, referenceDate: Date(timeIntervalSince1970: 1000))
        let records = try WindowsFirefoxCookieReader.read(database: database, query: query)
        #expect(Set(records.map(\.name)) == ["domain", "session"])
        let domain = try #require(records.first { $0.name == "domain" })
        #expect(domain.domain == "example.com")
        #expect(domain.scope == .domain)
        #expect(domain.isSecure && domain.isHTTPOnly)
        #expect(records.first { $0.name == "session" }?.scope == .hostOnly)
    }

    @Test
    func `SQL wildcard and quoted patterns retain their intended meaning`() throws {
        let database = try self.database()
        defer { sqlite3_close(database) }
        try self.populate(database)
        let all = try WindowsFirefoxCookieReader.read(
            database: database, query: BrowserCookieQuery(domains: ["%"], includeExpired: true))
        #expect(all.count == 6)
        let quote = try WindowsFirefoxCookieReader.read(
            database: database, query: BrowserCookieQuery(domains: ["exa'mple.test"], domainMatch: .exact))
        #expect(quote.map(\.name) == ["quote"])
        let suffix = try WindowsFirefoxCookieReader.read(
            database: database, query: BrowserCookieQuery(domains: ["example.com"], domainMatch: .suffix, includeExpired: true))
        #expect(Set(suffix.map(\.name)) == ["domain", "session", "expired", "uppercase", "suffix"])
    }

    @Test
    func `missing schema and embedded NUL pattern are failures`() throws {
        let database = try self.database()
        defer { sqlite3_close(database) }
        #expect(throws: BrowserCookieError.self) {
            try WindowsFirefoxCookieReader.read(database: database, query: BrowserCookieQuery())
        }
        try self.populate(database)
        #expect(throws: BrowserCookieError.self) {
            try WindowsFirefoxCookieReader.read(database: database, query: BrowserCookieQuery(domains: ["example\0.com"]))
        }
    }

    private enum FixtureError: Error {
        case open
        case populate
    }
}
#endif
