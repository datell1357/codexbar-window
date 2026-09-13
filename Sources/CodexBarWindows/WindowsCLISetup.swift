#if os(Windows)
import Foundation
import WinSDK

/// Installation guidance only: never executes the candidate or changes PATH.
enum WindowsCLISetup {
    static func guidance(hidePaths: Bool) -> String {
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
        // SwiftPM product name plus the conventional distribution alias; no PATH search.
        let names = ["CodexBarCLI.exe", "codexbar.exe"]
        var available: [String] = []
        var lines: [String] = []
        for name in names {
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
        lines.append("Only sibling file attributes were inspected. PATH, package aliases, binary identity and dependencies " +
            "were not checked. No command was run and no environment setting was changed.")
        return lines.joined(separator: "\n\n")
    }
}
#endif
