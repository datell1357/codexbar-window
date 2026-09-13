#if os(Windows)
import Foundation

/// Discovery only: this never reads LevelDB records, cookies, encryption keys or credentials.
enum WindowsChromiumLocalStorageProfiles {
    struct Profile: Sendable {
        let id: String
        let browser: Browser
        let label: String
        let directory: URL
    }

    struct Discovery: Sendable {
        let profiles: [Profile]
        let omittedCount: Int
    }

    enum Failure: Error { case timedOut }

    static func discover(
        browsers: [Browser] = [.chrome],
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        deadline: Date = Date().addingTimeInterval(15)) throws -> Discovery
    {
        let manager = FileManager.default
        var profiles: [Profile] = []
        var seen = Set<String>()
        var omitted = 0
        // Keep browser order explicit; no fallback to a different browser is hidden in discovery.
        for browser in browsers {
            try self.check(deadline)
            guard browser != .firefox else { continue }
            let directories = WindowsBrowserProfileLocator.profileDirectories(
                for: browser, home: home, environment: environment,
                fileExists: { path in
                    !Task.isCancelled && Date() < deadline && manager.fileExists(atPath: path)
                },
                directoryContents: { path in
                    guard !Task.isCancelled, Date() < deadline else { return nil }
                    return try? manager.contentsOfDirectory(atPath: path)
                })
            for (index, directory) in directories.enumerated() {
                try self.check(deadline)
                let storage = directory.appendingPathComponent("Local Storage", isDirectory: true)
                    .appendingPathComponent("leveldb", isDirectory: true)
                let identity = storage.standardizedFileURL.path.lowercased()
                guard seen.insert(identity).inserted else { continue }
                let attributes = try? storage.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard attributes?.isDirectory == true, attributes?.isSymbolicLink != true else { continue }
                guard profiles.count < 64 else { omitted += 1; continue }
                // Labels contain no profile display names or local filesystem paths.
                profiles.append(Profile(id: browser.rawValue + ":" + directory.lastPathComponent,
                    browser: browser, label: browser.rawValue + " profile \(index + 1)", directory: storage))
            }
        }
        try self.check(deadline)
        return Discovery(profiles: profiles, omittedCount: omitted)
    }

    private static func check(_ deadline: Date) throws {
        try Task.checkCancellation()
        guard Date() < deadline else { throw Failure.timedOut }
    }
}
#endif
