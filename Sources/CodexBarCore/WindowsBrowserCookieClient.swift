// Adapted from SweetCookieKit 0.5.2, d5ea6d92298779ec0c3ddf7d3d99da186a305e14.
// Copyright (c) 2026 Peter Steinberger. MIT; see docs/windows-port/SweetCookieKit-LICENSE.txt.
#if os(Windows)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Windows cookie store discovery and loading. Currently supports Firefox's registered profiles only.
public struct BrowserCookieClient: Sendable {
    public struct Configuration: Sendable {
        public var homeDirectories: [URL]

        public init(homeDirectories: [URL] = BrowserCookieClient.defaultHomeDirectories()) {
            self.homeDirectories = homeDirectories
        }
    }

    public let configuration: Configuration
    private let environment: [String: String]
    private var environmentHome: URL?
    private let fileExists: @Sendable (String) -> Bool
    private let isRegularFile: @Sendable (String) -> Bool
    private let directoryContents: @Sendable (String) -> [String]?
    private let readText: (@Sendable (String) -> String?)?
    private let reader: @Sendable (URL, BrowserCookieQuery) throws -> [BrowserCookieRecord]

    public init(configuration: Configuration = Configuration()) {
        self.init(
            configuration: configuration,
            environment: ProcessInfo.processInfo.environment,
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            isRegularFile: { path in
                (try? FileManager.default.attributesOfItem(atPath: path)[.type]) as? FileAttributeType == .typeRegular
            },
            directoryContents: { try? FileManager.default.contentsOfDirectory(atPath: $0) },
            readText: nil,
            reader: { try WindowsFirefoxCookieReader.read(from: $0, query: $1) })
        // APPDATA belongs to the current user; it must not redirect another configured user's home.
        self.environmentHome = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    /// Injected environment applies to all supplied homes, avoiding dependence on the running user's profile.
    init(
        configuration: Configuration,
        environment: [String: String],
        fileExists: @escaping @Sendable (String) -> Bool,
        isRegularFile: @escaping @Sendable (String) -> Bool,
        directoryContents: @escaping @Sendable (String) -> [String]?,
        readText: (@Sendable (String) -> String?)?,
        reader: @escaping @Sendable (URL, BrowserCookieQuery) throws -> [BrowserCookieRecord])
    {
        self.configuration = configuration
        self.environment = environment
        self.environmentHome = nil
        self.fileExists = fileExists
        self.isRegularFile = isRegularFile
        self.directoryContents = directoryContents
        self.readText = readText
        self.reader = reader
    }

    public func stores(for browser: Browser) -> [BrowserCookieStore] {
        guard browser == .firefox else { return [] }
        var seen = Set<String>()
        return self.configuration.homeDirectories.flatMap { home -> [BrowserCookieStore] in
            let environment = self.environmentHome == nil || home.standardizedFileURL == self.environmentHome
                ? self.environment : [:]
            return WindowsBrowserProfileLocator.profileDirectories(
                for: browser,
                home: home,
                environment: environment,
                fileExists: self.fileExists,
                directoryContents: self.directoryContents,
                readText: self.readText).sorted { lhs, rhs in
                    let left = Self.profileSortKey(lhs.lastPathComponent)
                    let right = Self.profileSortKey(rhs.lastPathComponent)
                    return left.rank == right.rank ? left.name < right.name : left.rank < right.rank
                }.compactMap { directory in
                    let profileURL = directory.standardizedFileURL
                    let databaseURL = profileURL.appendingPathComponent("cookies.sqlite", isDirectory: false)
                    guard self.isRegularFile(databaseURL.path),
                          WindowsFirefoxProfileSelection.hasInstalledApplication(
                              profile: profileURL, readText: self.readText, isRegularFile: self.isRegularFile),
                          WindowsFirefoxProfileSelection.includes(profile: profileURL, readText: self.readText),
                          seen.insert(profileURL.path).inserted else { return nil }
                    let name = profileURL.lastPathComponent
                    return BrowserCookieStore(
                        browser: browser,
                        profile: BrowserProfile(id: profileURL.path, name: name),
                        kind: .primary,
                        label: "Firefox \(name)",
                        databaseURL: databaseURL)
                }
        }
    }

    public func codexBarRecords(
        matching query: BrowserCookieQuery, in browser: Browser,
        logger: ((String) -> Void)? = nil) throws -> [BrowserCookieStoreRecords]
    {
        guard BrowserCookieAccessGate.shouldAttempt(browser) else { return [] }
        return try self.records(matching: query, in: browser, logger: logger)
    }

    public func stores(in browsers: [Browser]) -> [BrowserCookieStore] {
        browsers.flatMap { self.stores(for: $0) }
    }

    private static func profileSortKey(_ name: String) -> (rank: Int, name: String) {
        let lower = name.lowercased()
        if lower.contains("default-release") { return (0, lower) }
        if lower.contains("default") { return (1, lower) }
        return (2, lower)
    }

    public func records(
        matching query: BrowserCookieQuery,
        in browsers: [Browser],
        logger: ((String) -> Void)? = nil) throws -> [BrowserCookieStoreRecords]
    {
        try browsers.flatMap { try self.records(matching: query, in: $0, logger: logger) }
    }

    public func records(
        matching query: BrowserCookieQuery,
        in browser: Browser,
        logger: ((String) -> Void)? = nil) throws -> [BrowserCookieStoreRecords]
    {
        let stores = self.stores(for: browser)
        guard !stores.isEmpty else {
            throw BrowserCookieError.notFound(
                browser: browser,
                details: browser == .firefox ? "Firefox cookie store not found." : "Browser cookie store not found.")
        }
        return try stores.compactMap { store in
            let records = try self.records(matching: query, in: store, logger: logger)
            guard !records.isEmpty else { return nil }
            return BrowserCookieStoreRecords(store: store, records: records)
        }
    }

    public func records(
        matching query: BrowserCookieQuery,
        in store: BrowserCookieStore,
        logger: ((String) -> Void)? = nil) throws -> [BrowserCookieRecord]
    {
        guard store.browser == .firefox, store.kind == .primary else {
            throw BrowserCookieError.loadFailed(
                browser: store.browser,
                details: "This browser cookie store is not implemented on Windows.")
        }
        guard let databaseURL = store.databaseURL else {
            throw BrowserCookieError.notFound(
                browser: store.browser,
                details: "Missing cookie DB for \(store.label)")
        }
        do {
            let records = try self.reader(databaseURL, query)
            return BrowserCookieDomainMatcher.filterExpired(
                records, includeExpired: query.includeExpired, now: query.referenceDate)
        } catch let error as BrowserCookieError {
            throw error
        } catch {
            throw BrowserCookieError.loadFailed(
                browser: store.browser,
                details: "Firefox cookie load failed: \(error.localizedDescription)")
        }
    }

    public func cookies(
        matching query: BrowserCookieQuery,
        in store: BrowserCookieStore,
        logger: ((String) -> Void)? = nil) throws -> [HTTPCookie]
    {
        Self.makeHTTPCookies(try self.records(matching: query, in: store, logger: logger), origin: query.origin)
    }

    public func cookies(
        matching query: BrowserCookieQuery,
        in browser: Browser,
        logger: ((String) -> Void)? = nil) throws -> [HTTPCookie]
    {
        try self.records(matching: query, in: browser, logger: logger).flatMap { $0.cookies(origin: query.origin) }
    }

    public func cookies(
        matching query: BrowserCookieQuery,
        in browsers: [Browser],
        logger: ((String) -> Void)? = nil) throws -> [HTTPCookie]
    {
        try self.records(matching: query, in: browsers, logger: logger).flatMap { $0.cookies(origin: query.origin) }
    }

    public static func defaultHomeDirectories() -> [URL] {
        let environment = ProcessInfo.processInfo.environment
        var homes = [FileManager.default.homeDirectoryForCurrentUser]
        for key in ["USERPROFILE", "HOME"] {
            if let path = CodexBarPlatformPaths.environmentValue(key, environment: environment),
               Self.isAbsoluteHomePath(path)
            {
                homes.append(URL(fileURLWithPath: path, isDirectory: true))
            }
        }
        var seen = Set<String>()
        return homes.map(\.standardizedFileURL).filter { seen.insert($0.path).inserted }
    }

    private static func isAbsoluteHomePath(_ path: String) -> Bool {
        guard !path.contains("\0") else { return false }
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let prefix = Array(normalized.utf8.prefix(3))
        if prefix.count == 3,
           (65...90).contains(prefix[0]) || (97...122).contains(prefix[0]),
           prefix[1] == 58, prefix[2] == 47
        {
            return true
        }
        return normalized.hasPrefix("//") && normalized.dropFirst(2).split(separator: "/").count >= 2
    }
}
#endif
