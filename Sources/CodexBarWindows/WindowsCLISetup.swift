#if os(Windows)
import Foundation
import WinSDK

/// Installation guidance only: never executes the candidate or changes PATH.
enum WindowsCLISetup {
    static func guidance(hidePaths: Bool, cancelled: () -> Bool = { false }) -> String {
        var units = [UInt16](repeating: 0, count: 32768)
        let count = GetModuleFileNameW(nil, &units, DWORD(units.count))
        guard count > 0, count < DWORD(units.count) else {
            return "The app installation directory could not be read. Locate your Windows distribution and its CLI manually."
        }
        let executable = String(decoding: units.prefix(Int(count)), as: UTF16.self)
        guard let separator = executable.lastIndex(of: "\\"),
              !executable.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return "The app installation path is unsupported. Locate the CLI in your Windows distribution manually."
        }
        let directory = String(executable[..<separator])
        // SwiftPM product name plus the conventional distribution alias.
        let names = ["CodexBarCLI.exe", "codexbar.exe"]
        var available: [String] = []
        var lines: [String] = []
        for name in names {
            if cancelled() { return "CLI discovery cancelled." }
            let path = directory + "\\" + name
            let attributes = path.withCString(encodedAs: UTF16.self) { GetFileAttributesW($0) }
            if attributes == INVALID_FILE_ATTRIBUTES {
                let error = GetLastError()
                let missing = error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND
                lines.append(name + (missing ? ": not found beside this app" : ": could not inspect"))
            } else if attributes & DWORD(FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) != 0 {
                lines.append(name + ": unsupported directory or link")
            } else {
                available.append(path)
                lines.append(name + ": file present (execution not checked)")
            }
        }
        if !hidePaths { lines.insert("App directory: " + directory, at: 0) }
        else { lines.insert("Installation paths hidden by your privacy setting.", at: 0) }
        if let candidate = available.first {
            if !hidePaths {
                let literal = candidate.replacingOccurrences(of: "'", with: "''")
                lines.append("Optional PowerShell help command (not executed):\n& '" + literal + "' --help")
            }
            lines.append("Keep the CLI with its distribution libraries and resources. To use it from other directories, " +
                "add its containing folder to your user Path in Windows Environment Variables, then open a new terminal. " +
                "Check which copy your terminal resolves if another installation exists.")
        } else {
            lines.append("Obtain the complete Windows distribution containing the CLI and its libraries. " +
                "This app does not download or install the CLI yet. A CLI elsewhere on your computer is not ruled out.")
        }
        lines.append(self.pathGuidance(hidePaths: hidePaths, cancelled: cancelled))
        lines.append("Package aliases, shell resolution, binary identity and dependencies " +
            "were not checked. No command was run and no environment setting was changed.")
        return lines.joined(separator: "\n\n")
    }
    private static func pathGuidance(hidePaths: Bool, cancelled: () -> Bool) -> String {
        // Read only this process's PATH; newly edited user settings may require an app restart.
        var buffer = [UInt16](repeating: 0, count: 32768)
        let count = "PATH".withCString(encodedAs: UTF16.self) {
            GetEnvironmentVariableW($0, &buffer, DWORD(buffer.count))
        }
        guard count > 0, count < DWORD(buffer.count) else {
            return "Process PATH is empty, unavailable or too large to inspect."
        }
        let entries = String(decoding: buffer.prefix(Int(count)), as: UTF16.self)
            .split(separator: ";", omittingEmptySubsequences: false)
        var seen: Set<String> = []
        var matches: [String] = []
        var skipped = max(0, entries.count - 64)
        var failures = 0
        var matchCount = 0
        let started = GetTickCount64()
        for (index, entry) in entries.prefix(64).enumerated() {
            if cancelled() || GetTickCount64() - started > 200 {
                skipped += min(64, entries.count) - index
                break
            }
            var directory = String(entry).trimmingCharacters(in: .whitespaces)
            if directory.hasPrefix("\""), directory.hasSuffix("\""), directory.count >= 2 {
                directory = String(directory.dropFirst().dropLast())
            }
            let units = Array(directory.utf16)
            // Avoid relative, UNC, device, unresolved variable and network-drive probes.
            guard units.count >= 3, units.count <= 2048,
                  (65...90).contains(units[0]) || (97...122).contains(units[0]),
                  units[1] == 58, units[2] == 92,
                  !directory.contains("%"), !directory.contains("\""),
                  !directory.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                skipped += 1
                continue
            }
            let root = String(directory.prefix(3))
            guard root.withCString(encodedAs: UTF16.self, { GetDriveTypeW($0) }) == UINT(DRIVE_FIXED) else {
                skipped += 1
                continue
            }
            while directory.hasSuffix("\\") { directory.removeLast() }
            guard seen.insert(directory.lowercased()).inserted else { continue }
            for name in ["CodexBarCLI.exe", "codexbar.exe"] {
                let candidate = directory + "\\" + name
                let attributes = candidate.withCString(encodedAs: UTF16.self) { GetFileAttributesW($0) }
                if attributes == INVALID_FILE_ATTRIBUTES {
                    let error = GetLastError()
                    if error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND { failures += 1 }
                } else if attributes & DWORD(FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) == 0 {
                    matchCount += 1
                    if matches.count < 4 {
                        matches.append(hidePaths ? name + " (path hidden)" : String(candidate.prefix(240)))
                    }
                } else { failures += 1 }
            }
        }
        var summary = "Process PATH: \(matchCount) candidate file(s), \(skipped) skipped entry/entries, " +
            "\(failures) unreadable or unsupported candidate(s)."
        if !matches.isEmpty { summary += "\nFirst candidates (paths may be shortened):\n" + matches.joined(separator: "\n") }
        if matchCount > 1 {
            summary += "\nMultiple candidates exist; check the intended installation before changing PATH."
        }
        summary += "\nThis is a partial fixed-drive search in PATH order, not a shell command-resolution result. " +
            "Empty/relative/network entries and package aliases are not searched. Restart the app to inherit PATH changes."
        return summary
    }
}
#endif
