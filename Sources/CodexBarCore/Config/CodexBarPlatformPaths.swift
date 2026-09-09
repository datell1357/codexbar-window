import Foundation

/// Platform-owned locations for CodexBar's user data and executable resources.
enum CodexBarPlatformPaths {
    static func localAppDataURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL
    {
        #if os(Windows)
        if let raw = self.environmentValue("LOCALAPPDATA", environment: environment)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           (raw as NSString).isAbsolutePath
        {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
        }
        return home.appendingPathComponent("AppData/Local", isDirectory: true)
        #else
        return home
        #endif
    }

    /// Windows inherits case-insensitive environment keys; injected dictionaries may preserve mixed case.
    static func environmentValue(_ name: String, environment: [String: String]) -> String? {
        if let exact = environment[name] { return exact }
        #if os(Windows)
        return environment.keys.sorted().first { $0.uppercased() == name.uppercased() }
            .flatMap { environment[$0] }
        #else
        return nil
        #endif
    }

    static func codexBarDataDirectory(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL
    {
        self.localAppDataURL(home: home, environment: environment)
            .appendingPathComponent("CodexBar", isDirectory: true)
    }
}
