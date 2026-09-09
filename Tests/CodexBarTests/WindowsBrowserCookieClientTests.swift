#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

struct WindowsBrowserCookieClientTests {
    private let home = URL(fileURLWithPath: "C:/SyntheticHome", isDirectory: true)

    private func client(
        isRegularFile: (@Sendable (String) -> Bool)? = nil,
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
        let firstCompatibility = first.appendingPathComponent("compatibility.ini").path
        let secondCompatibility = second.appendingPathComponent("compatibility.ini").path
        let missingCompatibility = missing.appendingPathComponent("compatibility.ini").path
        let compatibility = "LastPlatformDir=C:\\Program Files\\Mozilla Firefox\n"
        let files = Set([registry, first.appendingPathComponent("cookies.sqlite").path,
                         second.appendingPathComponent("cookies.sqlite").path,
                         firstCompatibility, secondCompatibility, missingCompatibility])
        let directories = Set([first.path, second.path, missing.path])
        let regularFile = isRegularFile ?? { path in
            files.contains(path) || path.hasSuffix("firefox.exe")
        }
        return BrowserCookieClient(
            configuration: .init(homeDirectories: [home, home]),
            environment: [:],
            fileExists: { files.contains($0) },
            isRegularFile: regularFile,
            directoryContents: { directories.contains($0) ? [] : nil },
            readText: { path in
                if path == registry { return text }
                if path == firstCompatibility || path == secondCompatibility || path == missingCompatibility {
                    return compatibility
                }
                return nil
            },
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
    func `requires a regular Firefox executable and regular cookie database`() {
        let noExecutable = self.client(isRegularFile: { path in
            !path.hasSuffix("firefox.exe")
        }) { _, _ in [] }
        #expect(noExecutable.stores(for: .firefox).isEmpty)

        let nonRegularDatabase = self.client(isRegularFile: { path in
            path.hasSuffix("firefox.exe")
        }) { _, _ in [] }
        #expect(nonRegularDatabase.stores(for: .firefox).isEmpty)
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
