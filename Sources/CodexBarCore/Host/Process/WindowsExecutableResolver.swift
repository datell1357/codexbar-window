import Foundation

#if os(Windows)
/// Resolves a native Windows image for direct `CreateProcessW` use.
///
/// Shell scripts (`.cmd`/`.bat`) are intentionally not accepted here. Supporting
/// those requires an explicit `cmd.exe` launch policy and remains deferred.
enum WindowsExecutableResolver {
    /// Resolves `executable`, giving a valid explicit override priority over PATH.
    ///
    /// PATH is read case-insensitively on Windows and uses semicolon separators.
    /// A bare command is searched only in the supplied PATH; CreateProcess's
    /// implicit current-directory search is deliberately not reproduced.
    static func resolve(
        executable: String,
        override: String?,
        environment: [String: String],
        fileManager: FileManager = .default) -> String?
    {
        guard !executable.isEmpty, !executable.contains("\0") else { return nil }

        if let override,
           self.isSupportedPath(override),
           self.isRegularFile(atPath: override, fileManager: fileManager)
        {
            return override
        }

        if self.isExplicitPath(executable) {
            guard self.isSupportedPath(executable),
                  self.isRegularFile(atPath: executable, fileManager: fileManager)
            else { return nil }
            return executable
        }

        guard let rawPATH = CodexBarPlatformPaths.environmentValue("PATH", environment: environment),
              !rawPATH.contains("\0")
        else { return nil }

        let pathNames = self.candidateNames(for: executable)
        for rawDirectory in rawPATH.split(separator: ";", omittingEmptySubsequences: false) {
            let directory = self.unquotePathComponent(String(rawDirectory))
            guard !directory.isEmpty, !directory.contains("\0") else { continue }
            for name in pathNames {
                let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                    .appendingPathComponent(name).path
                if self.isRegularFile(atPath: candidate, fileManager: fileManager) {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func isExplicitPath(_ executable: String) -> Bool {
        executable.contains("/") || executable.contains("\\") ||
            (executable.count >= 2 && executable[executable.index(executable.startIndex, offsetBy: 1)] == ":")
    }

    private static func candidateNames(for executable: String) -> [String] {
        let lowercased = executable.lowercased()
        if lowercased.hasSuffix(".exe") || lowercased.hasSuffix(".com") {
            return [executable]
        }
        if lowercased.hasSuffix(".cmd") || lowercased.hasSuffix(".bat") {
            return []
        }
        // CreateProcess supports native .exe and .com images. Keep script
        // extensions out of this resolver rather than pretending they are direct images.
        return [executable + ".exe", executable + ".com"]
    }

    private static func isSupportedPath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.contains("\0") else { return false }
        let lowercased = path.lowercased()
        return lowercased.hasSuffix(".exe") || lowercased.hasSuffix(".com")
    }

    private static func unquotePathComponent(_ component: String) -> String {
        let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.first == "\"", trimmed.last == "\"" else { return trimmed }
        return String(trimmed.dropFirst().dropLast())
    }

    private static func isRegularFile(atPath path: String, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: path) else { return false }
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            return (attributes[.type] as? FileAttributeType) == .typeRegular
        } catch {
            return false
        }
    }
}
#endif
