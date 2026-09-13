#if os(Windows)
import Foundation
import WinSDK

enum WindowsMenuShortcut: String, CaseIterable {
    case controlAltC, controlShiftC, controlAltB, controlShiftB
    var title: String {
        switch self {
        case .controlAltC: "Ctrl+Alt+C"
        case .controlShiftC: "Ctrl+Shift+C"
        case .controlAltB: "Ctrl+Alt+B"
        case .controlShiftB: "Ctrl+Shift+B"
        }
    }
    var modifiers: UINT {
        UINT(MOD_CONTROL | MOD_NOREPEAT) |
            ([Self.controlAltC, .controlAltB].contains(self) ? UINT(MOD_ALT) : UINT(MOD_SHIFT))
    }
    var key: UINT { [Self.controlAltC, .controlShiftC].contains(self) ? 0x43 : 0x42 }
    static func load(_ defaults: UserDefaults) -> Self {
        Self(rawValue: defaults.string(forKey: "windowsMenuShortcut") ?? "") ?? .controlAltC
    }
}
#endif
