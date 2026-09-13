#if os(Windows)
import Foundation
import WinSDK

enum WindowsSpendSourceMenu {
    enum Result { case selected(WindowsSpendSourceMutation), cancelled, unavailable }

    static func show(owner: HWND, selection: WindowsSpendSourceSelection) -> Result {
        guard !selection.entries.isEmpty, selection.entries.count <= 4096,
              let menu = CreatePopupMenu() else { return .unavailable }
        defer { _ = DestroyMenu(menu) }
        func append(_ target: HMENU, _ id: UINT_PTR, _ text: String, _ checked: Bool = false) -> Bool {
            let label = text.replacingOccurrences(of: "&", with: "&&")
            return label.withCString(encodedAs: UTF16.self) {
                AppendMenuW(target, UINT(MF_STRING) | (checked ? UINT(MF_CHECKED) : 0), id, $0) != 0
            }
        }
        guard append(menu, 1, "Include all available sources"),
              append(menu, 2, "Exclude all available sources") else { return .unavailable }
        for start in stride(from: 0, to: selection.entries.count, by: 40) {
            let end = min(start + 40, selection.entries.count)
            let target: HMENU
            if selection.entries.count > 40 {
                guard let page = CreatePopupMenu() else { return .unavailable }
                let attached = "Sources \(start + 1)–\(end)".withCString(encodedAs: UTF16.self) {
                    AppendMenuW(menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: page)), $0)
                }
                guard attached != 0 else { _ = DestroyMenu(page); return .unavailable }
                target = page
            } else { target = menu }
            for index in start..<end {
                let entry = selection.entries[index]
                guard append(target, UINT_PTR(index + 10), entry.title, entry.included) else { return .unavailable }
            }
        }
        var point = POINT()
        guard GetCursorPos(&point) != 0 else { return .unavailable }
        _ = SetForegroundWindow(owner)
        let command = TrackPopupMenu(menu, UINT(TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON),
                                     point.x, point.y, 0, owner, nil)
        PostMessageW(owner, UINT(WM_NULL), 0, 0)
        if command == 0 { return .cancelled }
        if command == 1 { return .selected(.showAll) }
        if command == 2 { return .selected(.hideAll) }
        let index = Int(command) - 10
        guard selection.entries.indices.contains(index) else { return .unavailable }
        let entry = selection.entries[index]
        return .selected(.setIncluded(id: entry.id, included: !entry.included))
    }
}
#endif
