#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

struct WindowsBrowserCookieClientTests {
    private let home = URL(fileURLWithPath: "C:/SyntheticHome", isDirectory: true)

    private func client(
        reader: @escaping @Sendable (URL, BrowserCookieQuery) throws -> [BrowserCookieRecord]) -> BrowserCookieClient
    {
        let home = self.home
        let root = home.appendingPathComponent("AppData/Roaming/Mozilla/Firefox", isDirectory: true)
        let first = root.appendingPathComponent("Profiles/a.default-release", isDirectory: true)
        let second = root.appendingPathComponent("Profiles/b.work", isDirectory: true)
        let missing = root.appendingPathComponent("Profiles/c.missing", isDirectory: true)
        let registry = root.appendingPathComponent("profiles.ini").path
        let text = """
        [Profile0]
        Name=Work
        IsRelative=1
        Path=Profiles/b.work
        [Profile1]
        Name=Default
        IsRelative=1
        Path=Profiles/a.default-release
        [Profile2]
        Name=MissingCookieDB
        IsRelative=1
        Path=Profiles/c.missing
        """
        let files = Set([registry, first.appendingPathComponent("cookies.sqlite").path,
                         second.appendingPathComponent("cookies.sqlite").path])
        let directories = Set([first.path, second.path, missing.path])
        return BrowserCookieClient(
            configuration: .init(homeDirectories: [home, home]),
            environment: [:],
            fileExists: { files.contains($0) },
            directoryContents: { directories.contains($0) ? [] : nil },
            readText: { $0 == registry ? text : nil },
            reader: reader)
    }

    @Test
    func `discovers distinct existing stores in upstream preference order without loading cookies`() {
        let client = self.client { _, _ in
            Issue.record("Store enumeration must not load cookie values")
            return []
        }
        let stores = client.stores(for: .firefox)
        #expect(stores.map(\.profile.name) == ["a.default-release", "b.work"])
        #expect(stores.map(\.label) == ["Firefox a.default-release", "Firefox b.work"])
        #expect(stores.allSatisfy { $0.kind == .primary && $0.browser == .firefox })
        #expect(client.stores(for: .chrome).isEmpty)
    }

    @Test
    func `passes query and keeps profile records separate while omitting empty query results`() throws {
        let reference = Date(timeIntervalSince1970: 1000)
        let client = self.client { url, query in
            #expect(query.domains == ["example.com"])
            #expect(query.referenceDate == reference)
            if url.deletingLastPathComponent().lastPathComponent == "b.work" { return [] }
            return [BrowserCookieRecord(
                domain: "example.com", name: "session", path: "/", value: "synthetic",
                expires: nil, isSecure: true, isHTTPOnly: true)]
        }
        let results = try client.records(
            matching: BrowserCookieQuery(domains: ["example.com"], referenceDate: reference), in: Browser.firefox)
        #expect(results.count == 1)
        #expect(results.first?.store.profile.name == "a.default-release")
        #expect(client.stores(for: .firefox).count == 2)
    }

    @Test
    func `reader failures propagate instead of returning earlier profile results`() throws {
        let client = self.client { url, _ in
            if url.deletingLastPathComponent().lastPathComponent == "b.work" {
                throw BrowserCookieError.loadFailed(browser: .firefox, details: "Synthetic failure")
            }
            return [BrowserCookieRecord(
                domain: "example.com", name: "session", path: "/", value: "synthetic",
                expires: nil, isSecure: true, isHTTPOnly: true)]
        }
        #expect(throws: BrowserCookieError.self) {
            try client.records(matching: BrowserCookieQuery(), in: Browser.firefox)
        }
        #expect(throws: BrowserCookieError.self) {
            try client.records(matching: BrowserCookieQuery(), in: Browser.chrome)
        }
    }
}
#endif
