#if os(Windows)
import Foundation
import CodexBarCore
import WinSDK

enum WindowsWindsurfBrowserAccountMenu {
    static func chooseBrowser(owner: HWND) -> Browser? {
        let browsers = WindowsWindsurfBrowserSessionImporter.supportedBrowsers
        guard let menu = CreatePopupMenu() else { return nil }
        defer { DestroyMenu(menu) }
        "Close the selected browser before importing".withCString(encodedAs: UTF16.self) {
            _ = AppendMenuW(menu, UINT(MF_STRING | MF_GRAYED), 0, $0)
        }
        for (index, browser) in browsers.enumerated() {
            let title = browser.rawValue + (browser == .chrome ? " (default)" : "")
            guard title.withCString(encodedAs: UTF16.self, {
                AppendMenuW(menu, UINT(MF_STRING), UINT_PTR(index + 1), $0)
            }) != 0 else { return nil }
        }
        var point = POINT()
        guard GetCursorPos(&point) != 0 else { return nil }
        SetForegroundWindow(owner)
        let command = TrackPopupMenu(menu, UINT(TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON),
            point.x, point.y, 0, owner, nil)
        PostMessageW(owner, UINT(WM_NULL), 0, 0)
        let index = Int(command) - 1
        guard browsers.indices.contains(index) else { return nil }
        return browsers[index]
    }

    static func choose(owner: HWND, rows: [WindowsUsageRuntime.WindsurfBrowserChoice],
                       failedCount: Int, omittedCount: Int) -> UUID? {
        guard !rows.isEmpty, rows.count <= 16, let menu = CreatePopupMenu() else { return nil }
        defer { DestroyMenu(menu) }
        let notice = "Choose a browser session with a plan response (unavailable: \(failedCount), not checked: \(omittedCount))"
        notice.withCString(encodedAs: UTF16.self) { _ = AppendMenuW(menu, UINT(MF_STRING | MF_GRAYED), 0, $0) }
        for (index, row) in rows.enumerated() {
            let title = "\(index + 1). " + row.title.replacingOccurrences(of: "&", with: "&&")
            guard title.withCString(encodedAs: UTF16.self, {
                AppendMenuW(menu, UINT(MF_STRING), UINT_PTR(index + 1), $0)
            }) != 0 else { return nil }
        }
        var point = POINT()
        guard GetCursorPos(&point) != 0 else { return nil }
        SetForegroundWindow(owner)
        let command = TrackPopupMenu(menu, UINT(TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON),
                                    point.x, point.y, 0, owner, nil)
        PostMessageW(owner, UINT(WM_NULL), 0, 0)
        let index = Int(command) - 1
        guard rows.indices.contains(index) else { return nil }
        return rows[index].id
    }
}
#endif
