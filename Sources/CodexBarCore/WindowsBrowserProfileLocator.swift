#if os(Windows)
import Foundation

/// Discovers profile directories from default roots; this does not establish cookie import capability.
enum WindowsBrowserProfileLocator {
    static func profileDirectories(
        for browser: Browser,
        home: URL,
        environment: [String: String],
        fileExists: (String) -> Bool,
        directoryContents: (String) -> [String]?,
        readText: ((String) -> String?)? = nil) -> [URL]
    {
        if browser == .firefox {
            let root = CodexBarPlatformPaths.roamingAppDataURL(home: home, environment: environment)
                .appendingPathComponent("Mozilla/Firefox", isDirectory: true)
            let registry = root.appendingPathComponent("profiles.ini", isDirectory: false)
            guard fileExists(registry.path),
                  let contents = (readText ?? self.readProfileRegistry)(registry.path)
            else { return [] }
            return WindowsFirefoxProfiles.profileDirectories(in: contents, relativeTo: root)
                .filter { directoryContents($0.path) != nil }
        }

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

    private static func readProfileRegistry(at path: String) -> String? {
        let maximumBytes = 1024 * 1024
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maximumBytes + 1), data.count <= maximumBytes else { return nil }
        if data.starts(with: [0xFF, 0xFE]) {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        return String(data: data, encoding: .utf8)
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
