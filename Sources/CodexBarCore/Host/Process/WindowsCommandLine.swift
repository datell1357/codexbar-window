#if os(Windows)
import Foundation

/// Encoding for CreateProcessW. Arguments are passed directly, never through cmd.exe.
enum WindowsCommandLine {
    static func make(executable: String, arguments: [String]) throws -> [UInt16] {
        guard !executable.isEmpty, !executable.contains("\""), !executable.utf16.contains(0),
              arguments.allSatisfy({ !$0.utf16.contains(0) })
        else { throw SubprocessRunnerError.launchFailed("Invalid Windows process arguments.") }
        // argv[0] follows the CRT's special executable-name rule rather than the
        // backslash escaping rule used for subsequent arguments.
        let command = (["\"\(executable)\""] + arguments.map(Self.quote)).joined(separator: " ")
        var units = Array(command.utf16)
        guard units.count < 32_767 else {
            throw SubprocessRunnerError.launchFailed("Windows process command line is too long.")
        }
        units.append(0)
        return units
    }

    static func environmentBlock(_ environment: [String: String]) throws -> [UInt16] {
        var names = Set<String>()
        var entries: [(String, String)] = []
        for (name, value) in environment {
            // Windows environment names are case-insensitive. Reject ambiguous
            // dictionaries instead of letting dictionary order choose a value.
            let folded = name.uppercased()
            let nameUnits = Array(name.utf16)
            let driveEntry = nameUnits.count == 3 && nameUnits[0] == 61 && nameUnits[2] == 58
                && ((65 ... 90).contains(nameUnits[1]) || (97 ... 122).contains(nameUnits[1]))
            guard !name.isEmpty, (!name.contains("=") || driveEntry), !name.utf16.contains(0), !value.utf16.contains(0),
                  names.insert(folded).inserted
            else { throw SubprocessRunnerError.launchFailed("Invalid Windows process environment.") }
            entries.append((name, value))
        }
        entries.sort { $0.0.uppercased() < $1.0.uppercased() }
        var result: [UInt16] = []
        for (name, value) in entries {
            result.append(contentsOf: "\(name)=\(value)".utf16)
            result.append(0)
        }
        // Even an explicitly empty environment needs two terminating NULs.
        if result.isEmpty { result.append(0) }
        result.append(0)
        return result
    }

    private static func quote(_ argument: String) -> String {
        var result = "\""
        var backslashes = 0
        for character in argument.unicodeScalars {
            if character == "\\" {
                backslashes += 1
                continue
            }
            if character == "\"" {
                result += String(repeating: "\\", count: backslashes * 2 + 1)
            } else {
                result += String(repeating: "\\", count: backslashes)
            }
            result.unicodeScalars.append(character)
            backslashes = 0
        }
        result += String(repeating: "\\", count: backslashes * 2)
        result += "\""
        return result
    }
}
#endif
