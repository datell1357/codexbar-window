#if os(Windows)
import Foundation

/// A resolved native image plus literal arguments inserted before the caller's argv.
/// Provider shim resolution can select an interpreter without introducing a shell.
struct WindowsLaunchTarget: Sendable {
    let executable: String
    let argumentPrefix: [String]
    let removesJavaScriptPathExtension: Bool

    init(
        executable: String,
        argumentPrefix: [String] = [],
        removesJavaScriptPathExtension: Bool = false)
    {
        self.executable = executable
        self.argumentPrefix = argumentPrefix
        self.removesJavaScriptPathExtension = removesJavaScriptPathExtension
    }
    func environment(from base: [String: String]) -> [String: String] {
        guard self.removesJavaScriptPathExtension else { return base }
        let pathExt = CodexBarPlatformPaths.environmentValue("PATHEXT", environment: base)
        var result = base.filter { $0.key.uppercased() != "PATHEXT" }
        if let pathExt {
            let updated = pathExt.replacingOccurrences(of: ";.JS;", with: ";", options: .caseInsensitive)
            if !updated.isEmpty { result["PATHEXT"] = updated }
        }
        return result
    }
}
#endif
