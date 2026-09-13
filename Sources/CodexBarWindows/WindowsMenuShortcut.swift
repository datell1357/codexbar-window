#if os(Windows)
import Foundation
import WinSDK

struct WindowsMenuShortcut: Equatable, RawRepresentable, CaseIterable {
    enum Modifier: String, CaseIterable {
        case controlAlt, controlShift
        var title: String { self == .controlAlt ? "Ctrl+Alt" : "Ctrl+Shift" }
        var flags: UINT { UINT(MOD_CONTROL | MOD_NOREPEAT) | (self == .controlAlt ? UINT(MOD_ALT) : UINT(MOD_SHIFT)) }
    }
    let modifier: Modifier
    let key: UINT
    init?(modifier: Modifier, key: UINT) {
        guard (0x41...0x5A).contains(key) || (0x30...0x39).contains(key) else { return nil }
        self.modifier = modifier
        self.key = key
    }
    static let controlAltC = Self(modifier: .controlAlt, key: 0x43)!
    init?(rawValue: String) {
        let legacy: [String: (Modifier, UINT)] = [
            "controlAltC": (.controlAlt, 0x43), "controlShiftC": (.controlShift, 0x43),
            "controlAltB": (.controlAlt, 0x42), "controlShiftB": (.controlShift, 0x42),
        ]
        if let (modifier, key) = legacy[rawValue] { self.init(modifier: modifier, key: key); return }
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "v1", let modifier = Modifier(rawValue: String(parts[1])),
              let key = UINT(parts[2]) else { return nil }
        self.init(modifier: modifier, key: key)
    }
    var rawValue: String { "v1:\(self.modifier.rawValue):\(self.key)" }
    var title: String { self.modifier.title + "+" + String(UnicodeScalar(self.key)!) }
    var modifiers: UINT { self.modifier.flags }
    static var allCases: [Self] {
        Modifier.allCases.flatMap { modifier in
            (Array(UInt32(0x41)...UInt32(0x5A)) + Array(UInt32(0x30)...UInt32(0x39)))
                .compactMap { Self(modifier: modifier, key: $0) }
        }
    }
    static func load(_ defaults: UserDefaults) -> Self {
        Self(rawValue: defaults.string(forKey: "windowsMenuShortcut") ?? "") ?? .controlAltC
    }
}
#endif
