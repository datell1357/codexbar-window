#if os(Windows)
import Foundation

/// A resolved native image plus literal arguments inserted before the caller's argv.
/// Provider shim resolution can select an interpreter without introducing a shell.
struct WindowsLaunchTarget: Sendable {
    let executable: String
    let argumentPrefix: [String]

    init(executable: String, argumentPrefix: [String] = []) {
        self.executable = executable
        self.argumentPrefix = argumentPrefix
    }
}
#endif
