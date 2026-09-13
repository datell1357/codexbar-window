#if os(Windows)
import Foundation
import WinSDK

/// Read-only snapshot viewer. It never fetches or changes provider/account state.
enum WindowsProviderDetailsDialog {
    private static let className = "CodexBar.ProviderDetailsDialog"
    private static let textID: Int32 = 101
    private static let closeID: Int32 = 2
    private static let refreshID: Int32 = 3
    private static let expandID: Int32 = 4
    private static let linkBaseID: Int32 = 201

    struct Link {
        let title: String
        let url: String
    }
    enum Result {
        case closed
        case privacyChanged
        case openURL(String)
        case refreshAll
    }

    private static let privacyTimer: UINT_PTR = 1

    private final class Context {
        let hidePersonalInfo: Bool
        let text: String
        let expandedText: String?
        var expanded = false
        let links: [Link]
        var result: Result = .closed
        var closed = false
        var dpi: UINT = 96
        var font: HFONT?
        deinit { if let font { DeleteObject(font) } }
        func pixels(_ value: Int32) -> Int32 { MulDiv(value, Int32(self.dpi), 96) }
        init(text: String, links: [Link], hidePersonalInfo: Bool, expandedText: String?) {
            self.expandedText = expandedText
            self.text = text; self.links = Array(links.prefix(3)); self.hidePersonalInfo = hidePersonalInfo
        }
    }

    static func show(owner: HWND, title: String, text: String, links: [Link], hidePersonalInfo: Bool, expandedText: String? = nil) -> Result? {
        guard hidePersonalInfo == WindowsUsagePresentationSettings.load().hidePersonalInfo else { return .privacyChanged }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        let expanded = expandedText?.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        let context = Context(text: normalized, links: links, hidePersonalInfo: hidePersonalInfo, expandedText: expanded)
        let instance = GetModuleHandleW(nil)
        var klass = WNDCLASSEXW()
        klass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        klass.hInstance = instance
        klass.lpfnWndProc = Self.windowProc
        klass.hCursor = LoadCursorW(nil, IDC_ARROW)
        let name = Array(Self.className.utf16) + [0]
        let registered = name.withUnsafeBufferPointer {
            klass.lpszClassName = $0.baseAddress
            return RegisterClassExW(&klass)
        }
        guard registered != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS else { return nil }
        let caption = Array(title.utf16) + [0]
        let hwnd = name.withUnsafeBufferPointer { n in
            caption.withUnsafeBufferPointer { c in
                CreateWindowExW(DWORD(WS_EX_DLGMODALFRAME), n.baseAddress, c.baseAddress,
                                DWORD(WS_OVERLAPPEDWINDOW), Int32(bitPattern: 0x80000000), Int32(bitPattern: 0x80000000),
                                720, 540, owner, nil, instance, Unmanaged.passUnretained(context).toOpaque())
            }
        }
        guard let hwnd else { return nil }
        var initial = RECT(left: 0, top: 0, right: context.pixels(700), bottom: context.pixels(500))
        if AdjustWindowRectExForDpi(&initial, DWORD(WS_OVERLAPPEDWINDOW), 0,
                                   DWORD(WS_EX_DLGMODALFRAME), context.dpi) != 0 {
            let desiredWidth = initial.right - initial.left, desiredHeight = initial.bottom - initial.top
            if let area = Self.workArea(owner) {
                let width = min(desiredWidth, area.right - area.left)
                let height = min(desiredHeight, area.bottom - area.top)
                SetWindowPos(hwnd, nil, area.left + (area.right - area.left - width) / 2,
                             area.top + (area.bottom - area.top - height) / 2, width, height,
                             UINT(SWP_NOZORDER | SWP_NOACTIVATE))
            } else {
                SetWindowPos(hwnd, nil, 0, 0, desiredWidth, desiredHeight,
                             UINT(SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE))
            }
        }
        let ownerWasEnabled = IsWindowEnabled(owner) != 0
        if IsWindow(owner) != 0 { EnableWindow(owner, 0) }
        var succeeded = true
        withExtendedLifetime(context) {
            ShowWindow(hwnd, Int32(SW_SHOW)); UpdateWindow(hwnd)
            SetFocus(GetDlgItem(hwnd, Self.textID))
            var message = MSG()
            while !context.closed {
                let result = GetMessageW(&message, nil, 0, 0)
                if result == -1 { succeeded = false; break }
                if result == 0 { PostQuitMessage(Int32(message.wParam)); break }
                if Self.closeForPrivacyIfNeeded(hwnd, context: context) { break }
                let target = message.hwnd == hwnd || IsChild(hwnd, message.hwnd) != 0
                if target, message.message == UINT(WM_KEYDOWN) {
                    if message.wParam == WPARAM(VK_ESCAPE) {
                        DestroyWindow(hwnd); continue
                    }
                    if message.wParam == WPARAM(0x41), GetKeyState(Int32(VK_CONTROL)) < 0,
                       GetFocus() == GetDlgItem(hwnd, Self.textID) {
                        SendMessageW(GetDlgItem(hwnd, Self.textID), UINT(EM_SETSEL), 0, -1)
                        continue
                    }
                }
                if IsDialogMessageW(hwnd, &message) == 0 {
                    TranslateMessage(&message); DispatchMessageW(&message)
                }
            }
        }
        if IsWindow(hwnd) != 0 { DestroyWindow(hwnd) }
        if IsWindow(owner) != 0, ownerWasEnabled { EnableWindow(owner, 1); SetForegroundWindow(owner) }
        return succeeded ? context.result : nil
    }

    private static let windowProc: WNDPROC = { hwnd, message, wParam, lParam in
        guard let hwnd else { return 0 }
        if message == UINT(WM_NCCREATE),
           let create = UnsafeMutableRawPointer(bitPattern: UInt(lParam))?.assumingMemoryBound(to: CREATESTRUCTW.self),
           let pointer = create.pointee.lpCreateParams {
            SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), LONG_PTR(Int(bitPattern: pointer)))
        }
        let pointer = GetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA))
        guard pointer != 0 else { return DefWindowProcW(hwnd, message, wParam, lParam) }
        let context = Unmanaged<Context>.fromOpaque(
            UnsafeRawPointer(bitPattern: UInt(pointer))!).takeUnretainedValue()
        switch message {
        case UINT(WM_CREATE):
            let dpi = GetDpiForWindow(hwnd)
            context.dpi = dpi == 0 ? 96 : dpi
            guard Self.addControl(hwnd, "EDIT", context.text, Self.textID,
                                  DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_BORDER | WS_VSCROLL |
                                        ES_MULTILINE | ES_AUTOVSCROLL | ES_READONLY)) != nil,
                  Self.addControl(hwnd, "BUTTON", "Close", Self.closeID,
                                  DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON)) != nil else {
                return -1
            }
            guard Self.addControl(hwnd, "BUTTON", "Refresh all && close", Self.refreshID,
                                  DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON)) != nil else {
                return -1
            }
            if context.expandedText != nil {
                guard Self.addControl(hwnd, "BUTTON", "Show &all rows", Self.expandID,
                                      DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON)) != nil else { return -1 }
            }
            for (index, link) in context.links.enumerated() {
                guard Self.addControl(hwnd, "BUTTON", link.title, Self.linkBaseID + Int32(index),
                                      DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON)) != nil else {
                    return -1
                }
            }
            guard SetTimer(hwnd, Self.privacyTimer, 250, nil) != 0 else { return -1 }
            Self.updateFont(hwnd, context: context)
            Self.layout(hwnd, context: context)
            return 0
        case UINT(WM_TIMER):
            if wParam == Self.privacyTimer { _ = Self.closeForPrivacyIfNeeded(hwnd, context: context) }
            return 0
        case UINT(WM_SIZE): Self.layout(hwnd, context: context); return 0
        case UINT(WM_DPICHANGED):
            let dpi = UINT(wParam & 0xffff)
            if dpi != 0 { context.dpi = dpi }
            Self.updateFont(hwnd, context: context)
            if let suggested = UnsafeRawPointer(bitPattern: UInt(lParam))?.assumingMemoryBound(to: RECT.self) {
                let rect = suggested.pointee
                SetWindowPos(hwnd, nil, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top,
                             UINT(SWP_NOZORDER | SWP_NOACTIVATE))
            }
            Self.layout(hwnd, context: context)
            return 0
        case UINT(WM_SETTINGCHANGE):
            Self.updateFont(hwnd, context: context)
            return DefWindowProcW(hwnd, message, wParam, lParam)
        case UINT(WM_SETFOCUS): SetFocus(GetDlgItem(hwnd, Self.textID)); return 0
        case UINT(WM_GETMINMAXINFO):
            if let limits = UnsafeMutableRawPointer(bitPattern: UInt(lParam))?.assumingMemoryBound(to: MINMAXINFO.self) {
                var frame = RECT(left: 0, top: 0, right: context.pixels(520), bottom: context.pixels(230))
                AdjustWindowRectExForDpi(&frame, DWORD(WS_OVERLAPPEDWINDOW), 0,
                                        DWORD(WS_EX_DLGMODALFRAME), context.dpi)
                limits.pointee.ptMinTrackSize.x = frame.right - frame.left
                limits.pointee.ptMinTrackSize.y = frame.bottom - frame.top
                if let area = Self.workArea(hwnd) {
                    limits.pointee.ptMinTrackSize.x = min(limits.pointee.ptMinTrackSize.x, area.right - area.left)
                    limits.pointee.ptMinTrackSize.y = min(limits.pointee.ptMinTrackSize.y, area.bottom - area.top)
                }
            }
            return 0
        case UINT(WM_COMMAND):
            guard !Self.closeForPrivacyIfNeeded(hwnd, context: context) else { return 0 }
            let command = Int32(wParam & 0xffff)
            if command == Self.closeID { DestroyWindow(hwnd); return 0 }
            if command == Self.expandID, let expandedText = context.expandedText {
                context.expanded.toggle()
                let body = Array((context.expanded ? expandedText : context.text).utf16) + [0]
                body.withUnsafeBufferPointer { _ = SetWindowTextW(GetDlgItem(hwnd, Self.textID), $0.baseAddress) }
                let caption = Array((context.expanded ? "Show &less" : "Show &all rows").utf16) + [0]
                caption.withUnsafeBufferPointer { _ = SetWindowTextW(GetDlgItem(hwnd, Self.expandID), $0.baseAddress) }
                SendMessageW(GetDlgItem(hwnd, Self.textID), UINT(EM_SETSEL), 0, 0)
                SendMessageW(GetDlgItem(hwnd, Self.textID), UINT(EM_SCROLLCARET), 0, 0)
                return 0
            }
            if command == Self.refreshID {
                context.result = .refreshAll
                DestroyWindow(hwnd)
                return 0
            }
            let index = Int(command - Self.linkBaseID)
            if context.links.indices.contains(index) {
                context.result = .openURL(context.links[index].url)
                DestroyWindow(hwnd)
            }
            return 0
        case UINT(WM_CLOSE): DestroyWindow(hwnd); return 0
        case UINT(WM_NCDESTROY):
            KillTimer(hwnd, Self.privacyTimer)
            context.closed = true
            SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), 0)
            return DefWindowProcW(hwnd, message, wParam, lParam)
        default: return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }

    private static func closeForPrivacyIfNeeded(_ hwnd: HWND, context: Context) -> Bool {
        guard !context.closed,
              context.hidePersonalInfo != WindowsUsagePresentationSettings.load().hidePersonalInfo else { return false }
        context.result = .privacyChanged
        ShowWindow(hwnd, Int32(SW_HIDE))
        DestroyWindow(hwnd)
        return true
    }

    private static func updateFont(_ hwnd: HWND, context: Context) {
        var metrics = NONCLIENTMETRICSW()
        metrics.cbSize = UINT(MemoryLayout<NONCLIENTMETRICSW>.size)
        guard SystemParametersInfoForDpi(UINT(SPI_GETNONCLIENTMETRICS), metrics.cbSize,
                                         &metrics, 0, context.dpi) != 0,
              let font = CreateFontIndirectW(&metrics.lfMessageFont) else { return }
        let previous = context.font
        context.font = font
        for id in [Self.textID, Self.closeID, Self.refreshID, Self.expandID, Self.linkBaseID,
                   Self.linkBaseID + 1, Self.linkBaseID + 2] {
            if let control = GetDlgItem(hwnd, id) {
                SendMessageW(control, UINT(WM_SETFONT), WPARAM(Int(bitPattern: font)), 1)
            }
        }
        if let previous { DeleteObject(previous) }
    }

    private static func layout(_ hwnd: HWND, context: Context) {
        let px = context.pixels
        var rect = RECT()
        guard GetClientRect(hwnd, &rect) != 0 else { return }
        let width = max(0, rect.right - rect.left), height = max(0, rect.bottom - rect.top)
        let available = max(1, width - px(24))
        var buttons: [(Int32, Int32)] = context.links.indices.map { (Self.linkBaseID + Int32($0), px(124)) }
        if context.expandedText != nil { buttons.append((Self.expandID, px(140))) }
        buttons.append((Self.refreshID, px(180)))
        buttons.append((Self.closeID, px(92)))
        var positions: [(Int32, Int32, Int32, Int32)] = []
        var x: Int32 = 0, row: Int32 = 0
        for (id, desired) in buttons {
            let buttonWidth = min(desired, available)
            if x > 0, x + buttonWidth > available { x = 0; row += 1 }
            positions.append((id, x, row, buttonWidth))
            x += buttonWidth + px(8)
        }
        let footer = (row + 1) * px(36) + px(12)
        let top = max(px(12), height - footer)
        MoveWindow(GetDlgItem(hwnd, Self.textID), px(12), px(12), available,
                   max(1, top - px(24)), 1)
        for (id, x, row, buttonWidth) in positions {
            MoveWindow(GetDlgItem(hwnd, id), px(12) + x, top + row * px(36), buttonWidth, px(28), 1)
        }
    }

    private static func workArea(_ hwnd: HWND) -> RECT? {
        let monitor = MonitorFromWindow(hwnd, UINT(MONITOR_DEFAULTTONEAREST))
        var info = MONITORINFO()
        info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        guard GetMonitorInfoW(monitor, &info) != 0,
              info.rcWork.right > info.rcWork.left, info.rcWork.bottom > info.rcWork.top else { return nil }
        return info.rcWork
    }

    private static func addControl(_ parent: HWND, _ klass: String, _ text: String,
                                   _ id: Int32, _ style: DWORD) -> HWND? {
        let name = Array(klass.utf16) + [0], caption = Array(text.utf16) + [0]
        let control = name.withUnsafeBufferPointer { n in
            caption.withUnsafeBufferPointer { c in
                CreateWindowExW(0, n.baseAddress, c.baseAddress, style, 0, 0, 1, 1,
                                parent, HMENU(bitPattern: Int(id)), GetModuleHandleW(nil), nil)
            }
        }
        if let font = GetStockObject(DEFAULT_GUI_FONT) {
            SendMessageW(control, UINT(WM_SETFONT), WPARAM(Int(bitPattern: font)), 1)
        }
        return control
    }
}
#endif
