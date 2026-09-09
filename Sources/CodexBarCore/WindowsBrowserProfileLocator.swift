#if os(Windows)
import Foundation

/// Discovers default-location profile directories only; this does not establish cookie import capability.
enum WindowsBrowserProfileLocator {
    static func profileDirectories(
        for browser: Browser,
        home: URL,
        environment: [String: String],
        fileExists: (String) -> Bool,
        directoryContents: (String) -> [String]?) -> [URL]
    {
        guard let relativePath = self.defaultUserDataRelativePath(for: browser) else { return [] }
        let root = CodexBarPlatformPaths.localAppDataURL(home: home, environment: environment)
            .appendingPathComponent(relativePath, isDirectory: true)
        guard fileExists(root.path), let names = directoryContents(root.path) else { return [] }

        // Preserve the upstream Chromium profile-name heuristic. Confirm candidates are readable directories;
        // cookie databases and Local State are never opened here. Custom policy/command-line roots remain unsupported.
        return names.sorted().compactMap { name in
            guard !name.contains("/"), !name.contains("\\"), !name.contains(":"), !name.contains("\0"),
                  name == "Default" || name.hasPrefix("Profile ") || name.hasPrefix("user-")
            else { return nil }
            let profile = root.appendingPathComponent(name, isDirectory: true)
            guard directoryContents(profile.path) != nil else { return nil }
            return profile
        }
    }

    // Vendor source links and intentionally unsupported identities are recorded in docs/windows-port/STATIC-QA-025.ko.md.
    private static func defaultUserDataRelativePath(for browser: Browser) -> String? {
        switch browser {
        case .chrome: "Google/Chrome/User Data"
        case .chromeBeta: "Google/Chrome Beta/User Data"
        case .chromeCanary: "Google/Chrome SxS/User Data"
        case .chromium: "Chromium/User Data"
        case .edge: "Microsoft/Edge/User Data"
        case .edgeBeta: "Microsoft/Edge Beta/User Data"
        case .edgeCanary: "Microsoft/Edge SxS/User Data"
        default: nil
        }
    }
}
#endif
