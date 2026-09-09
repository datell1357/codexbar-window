#if os(Windows)
import Foundation

/// Defaults used by the Claude version probe, matching its original TTY launch.
/// PATH discovery and terminal transport are separate from these scalar defaults.
enum WindowsProbeEnvironment {
    static func claudeVersion(
        base: [String: String],
        home: String = NSHomeDirectory(),
        workingDirectory: URL) -> [String: String]
    {
        var result = base
        let defaults = [
            ("HOME", home),
            ("TERM", "xterm-256color"),
            ("COLORTERM", "truecolor"),
            ("LANG", "en_US.UTF-8"),
        ]
        for (name, fallback) in defaults {
            let value = CodexBarPlatformPaths.environmentValue(name, environment: base)
            result = result.filter { $0.key.uppercased() != name }
            result[name] = value.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        }
        // An explicitly empty CI value is preserved, as in TTYCommandRunner.
        let ci = CodexBarPlatformPaths.environmentValue("CI", environment: base)
        result = result.filter { $0.key.uppercased() != "CI" && $0.key.uppercased() != "PWD" }
        result["CI"] = ci ?? "0"
        result["PWD"] = workingDirectory.path
        return result
    }
}
#endif
