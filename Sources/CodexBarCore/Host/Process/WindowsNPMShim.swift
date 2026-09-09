#if os(Windows)
import Foundation

/// Recognizes the no-args, no-environment node template emitted by npm/cmd-shim.
///
/// This parser is deliberately text-only: it never evaluates batch syntax. The
/// returned path is the literal path following `%dp0%\\` in the invocation.
enum WindowsNPMShim {
    static func entryPath(in text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.contains("\r"), !normalized.contains("\0") else { return nil }

        let prefix = """
        @ECHO off
        GOTO start
        :find_dp0
        SET dp0=%~dp0
        EXIT /b
        :start
        SETLOCAL
        CALL :find_dp0

        IF EXIST "%dp0%\\node.exe" (
          SET "_prog=%dp0%\\node.exe"
        ) ELSE (
          SET "_prog=node"
        )

        endLocal & goto #_undefined_# 2>NUL || title %COMSPEC% & set PATHEXT=%PATHEXT:;.JS;=;% & "%_prog%"  "%dp0%\\
        """
        let suffix = "\" %*\n"
        guard normalized.hasPrefix(prefix), normalized.hasSuffix(suffix) else { return nil }

        let start = normalized.index(normalized.startIndex, offsetBy: prefix.count)
        let end = normalized.index(normalized.endIndex, offsetBy: -suffix.count)
        let path = String(normalized[start ..< end])
        guard self.isSafeRelativePath(path) else { return nil }
        return path
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("\\"), !path.contains(":") else {
            return false
        }
        let scalars = path.unicodeScalars
        guard !scalars.contains(where: { scalar in
            scalar.value < 0x20 || scalar.value == 0x7F ||
                scalar == "%" || scalar == "!" || scalar == "\"" ||
                scalar == "&" || scalar == "|" || scalar == "<" ||
                scalar == ">" || scalar == "^" || scalar == "\0"
        }) else {
            return false
        }
        return true
    }
}
#endif
