#if os(Windows)
import Foundation

/// Matches a warm provider process to the exact native image and, for npm
/// shims, the exact JavaScript entry point selected by the resolver.
enum WindowsWarmProcessMatcher {
    static func matches(imagePath: String, commandLine: String, expectedBinaryPath: String,
                        environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard self.isSafeAbsolutePath(imagePath), self.isSafeAbsolutePath(expectedBinaryPath),
              let command = WindowsCommandResolver.resolve(executable: expectedBinaryPath, override: nil, environment: environment),
              self.isSafeAbsolutePath(command.target.executable),
              let image = WindowsFileIdentity.snapshot(atPath: imagePath),
              let executable = WindowsFileIdentity.snapshot(atPath: command.target.executable),
              image.volumeSerialNumber == executable.volumeSerialNumber,
              image.fileIndex == executable.fileIndex else { return false }
        let arguments = self.arguments(from: commandLine)
        guard !arguments.isEmpty else { return false }
        guard !command.target.argumentPrefix.isEmpty else { return true }
        guard arguments.count > command.target.argumentPrefix.count else { return false }
        for (index, expected) in command.target.argumentPrefix.enumerated() {
            let actual = arguments[index + 1]
            guard self.isSafeAbsolutePath(actual),
                  let actualIdentity = WindowsFileIdentity.snapshot(atPath: actual),
                  self.isSafeAbsolutePath(expected),
                  let expectedIdentity = WindowsFileIdentity.snapshot(atPath: expected),
                  actualIdentity.volumeSerialNumber == expectedIdentity.volumeSerialNumber,
                  actualIdentity.fileIndex == expectedIdentity.fileIndex else { return false }
        }
        return true
    }

    private static func isSafeAbsolutePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.contains("\0"), !path.hasPrefix("\\\\.\\"), !path.hasPrefix("\\\\?\\") else { return false }
        let units = Array(path.utf16)
        if units.count >= 3,
           ((65 ... 90).contains(units[0]) || (97 ... 122).contains(units[0])),
           units[1] == 58, units[2] == 92 || units[2] == 47 { return true }
        guard path.hasPrefix("\\\\") else { return false }
        let components = path.dropFirst(2).split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\\" || $0 == "/" })
        return components.count >= 2 && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    /// Parses the CreateProcess/CRT quoting rules without invoking a shell.
    private static func arguments(from commandLine: String) -> [String] {
        guard !commandLine.contains("\0") else { return [] }
        let units = Array(commandLine.utf16)
        var result: [String] = []
        var index = 0
        while index < units.count {
            while index < units.count, units[index] == 32 || units[index] == 9 { index += 1 }
            guard index < units.count else { break }
            var value: [UInt16] = []
            var quoted = false
            let firstArgument = result.isEmpty
            while index < units.count {
                let unit = units[index]
                if unit == 32 || unit == 9 {
                    if !quoted { break }
                    value.append(unit); index += 1; continue
                }
                if unit == 34 {
                    if firstArgument, value.isEmpty {
                        index += 1
                        while index < units.count, units[index] != 34 {
                            value.append(units[index]); index += 1
                        }
                        guard index < units.count else { return [] }
                        index += 1
                        continue
                    }
                    // Inside a quoted argument, two adjacent quotes encode a
                    // literal quote; otherwise a quote toggles quoted mode.
                    if quoted, index + 1 < units.count, units[index + 1] == 34 {
                        value.append(34); index += 2
                    } else { quoted.toggle(); index += 1 }
                    continue
                }
                if unit == 92 {
                    var slashes = 0
                    while index < units.count, units[index] == 92 { slashes += 1; index += 1 }
                    if index < units.count, units[index] == 34 {
                        value.append(contentsOf: repeatElement(92, count: slashes / 2))
                        if slashes % 2 == 0, quoted, index + 1 < units.count, units[index + 1] == 34 {
                            value.append(34); index += 2
                        } else if slashes % 2 == 0 { quoted.toggle(); index += 1 }
                        else { value.append(34); index += 1 }
                    } else { value.append(contentsOf: repeatElement(92, count: slashes)) }
                    continue
                }
                value.append(unit); index += 1
            }
            guard !quoted else { return [] }
            result.append(String(decoding: value, as: UTF16.self))
            while index < units.count, units[index] == 32 || units[index] == 9 { index += 1 }
        }
        return result
    }
}
#endif
