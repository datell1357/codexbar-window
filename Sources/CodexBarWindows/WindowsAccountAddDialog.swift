#if os(Windows)
import Foundation
import WinSDK
import CodexBarCore

/// Explicit manual credential input. No clipboard read, authentication probe or save occurs here.
enum WindowsAccountAddDialog {
    struct Draft { let label: String; let token: String; let scope: String?; let organization: String?; let workspace: String? }
    enum Result { case cancelled, failed, saved(Draft) }
    private static let className = "CodexBar.AccountAddDialog"
    private final class Context {
        let support: TokenAccountSupport
        init(support: TokenAccountSupport) { self.support = support }
        var result: Result = .cancelled
        var closed = false
        var dpi: UINT = 96
        var font: HFONT?
        deinit { if let font { DeleteObject(font) } }
        func pixels(_ value: Int32) -> Int32 { MulDiv(value, Int32(self.dpi), 96) }
    }
    static func show(owner: HWND, providerName: String, support: TokenAccountSupport) -> Result {
        let context = Context(support: support)
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
        guard registered != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS else { return .failed }
        let caption = Array(("Add saved account — " + providerName).utf16) + [0]
        let hwnd = name.withUnsafeBufferPointer { n in
            caption.withUnsafeBufferPointer { c in
                CreateWindowExW(DWORD(WS_EX_DLGMODALFRAME), n.baseAddress, c.baseAddress,
                    DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU), Int32(bitPattern: 0x80000000),
                    Int32(bitPattern: 0x80000000), 460, 210, owner, nil, instance,
                    Unmanaged.passUnretained(context).toOpaque())
            }
        }
        guard let hwnd else { return .failed }
        Self.place(hwnd, near: owner, context: context)
        let wasEnabled = IsWindowEnabled(owner) != 0
        EnableWindow(owner, 0)
        withExtendedLifetime(context) {
            ShowWindow(hwnd, Int32(SW_SHOW)); SetFocus(GetDlgItem(hwnd, 101))
            var message = MSG()
            while !context.closed {
                let result = GetMessageW(&message, nil, 0, 0)
                if result == -1 { context.result = .failed; break }
                if result == 0 { PostQuitMessage(Int32(message.wParam)); break }
                let target = message.hwnd == hwnd || IsChild(hwnd, message.hwnd) != 0
                if target, message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_ESCAPE) {
                    DestroyWindow(hwnd); continue
                }
                if target, message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_RETURN) {
                    if GetFocus() == GetDlgItem(hwnd, 2) { DestroyWindow(hwnd) }
                    else { Self.save(hwnd, context: context) }
                    continue
                }
                if IsDialogMessageW(hwnd, &message) == 0 { TranslateMessage(&message); DispatchMessageW(&message) }
            }
        }
        if IsWindow(hwnd) != 0 { DestroyWindow(hwnd) }
        if IsWindow(owner) != 0, wasEnabled { EnableWindow(owner, 1); SetForegroundWindow(owner) }
        return context.result
    }
    private static func save(_ hwnd: HWND, context: Context) {
        func read(_ id: Int32, limit: Int) -> String {
            var buffer = [WCHAR](repeating: 0, count: limit + 2)
            let count = GetWindowTextW(GetDlgItem(hwnd, id), &buffer, Int32(buffer.count))
            return String(decoding: buffer.prefix(Int(max(0, count))), as: UTF16.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let label = read(101, limit: 160), token = read(103, limit: 65_536)
        func optional(_ id: Int32) -> String? { let text = read(id, limit: 512); return text.isEmpty ? nil : text }
        guard label.utf16.count <= 160, !token.isEmpty, token.utf8.count <= 65_536, !token.contains("\0") else {
            "Enter a credential and a name up to 160 characters. Credential size must not exceed 64 KiB.".withCString(encodedAs: UTF16.self) {
                SetWindowTextW(GetDlgItem(hwnd, 102), $0)
            }
            SetFocus(GetDlgItem(hwnd, 103)); return
        }
        context.result = .saved(.init(label: label, token: token,
            scope: context.support.showsTeamModeControls ? optional(105) : nil,
            organization: context.support.showsOrganizationField || context.support.showsTeamModeControls ? optional(107) : nil,
            workspace: context.support.showsTeamModeControls ? optional(109) : nil))
        DestroyWindow(hwnd)
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
        let context = Unmanaged<Context>.fromOpaque(UnsafeRawPointer(bitPattern: UInt(pointer))!).takeUnretainedValue()
        switch message {
        case UINT(WM_CREATE):
            let dpi = GetDpiForWindow(hwnd)
            context.dpi = dpi == 0 ? 96 : dpi
            let rows: [(Int32, String, Int32, Bool)] = [
                (100, "&Account name (optional)", 101, true),
                (104, "&Credential", 103, true),
                (106, "Usage scope (personal/team)", 105, context.support.showsTeamModeControls),
                (108, "Organization ID (optional)", 107, context.support.showsOrganizationField || context.support.showsTeamModeControls),
                (110, "Workspace ID (optional)", 109, context.support.showsTeamModeControls)]
            for (labelID, title, editID, visible) in rows where visible {
                guard Self.control(hwnd, "STATIC", title, labelID, 0, 0, 0, 1, 1) != nil,
                      let edit = Self.control(hwnd, "EDIT", "", editID,
                          DWORD(WS_TABSTOP | WS_BORDER | ES_AUTOHSCROLL) | (editID == 103 ? DWORD(ES_PASSWORD) : 0),
                          0, 0, 1, 1) else { return -1 }
                SendMessageW(edit, UINT(EM_SETLIMITTEXT), WPARAM(editID == 103 ? 65_536 : editID == 101 ? 160 : 512), 0)
            }
            let source = context.support.requiresManualCookieSource ? " Manual credential source will be selected." : ""
            guard Self.control(hwnd, "STATIC", "Adds and selects this account. Windows protects saved credentials." + source,
                               102, 0, 0, 0, 1, 1) != nil,
                  Self.control(hwnd, "BUTTON", "Add account", 1, DWORD(WS_TABSTOP | BS_DEFPUSHBUTTON), 0, 0, 1, 1) != nil,
                  Self.control(hwnd, "BUTTON", "Cancel", 2, DWORD(WS_TABSTOP | BS_PUSHBUTTON), 0, 0, 1, 1) != nil else { return -1 }
            Self.updateFont(hwnd, context: context)
            Self.layout(hwnd, context: context)
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
            Self.layout(hwnd, context: context)
            return DefWindowProcW(hwnd, message, wParam, lParam)
        case UINT(WM_COMMAND):
            switch Int32(wParam & 0xffff) {
            case 1: Self.save(hwnd, context: context)
            case 2: DestroyWindow(hwnd)
            default: break
            }
            return 0
        case UINT(WM_CLOSE): DestroyWindow(hwnd); return 0
        case UINT(WM_NCDESTROY):
            context.closed = true
            SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), 0)
            return DefWindowProcW(hwnd, message, wParam, lParam)
        default: return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }
    private static func updateFont(_ hwnd: HWND, context: Context) {
        var metrics = NONCLIENTMETRICSW()
        metrics.cbSize = UINT(MemoryLayout<NONCLIENTMETRICSW>.size)
        guard SystemParametersInfoForDpi(UINT(SPI_GETNONCLIENTMETRICS), metrics.cbSize,
                                         &metrics, 0, context.dpi) != 0,
              let font = CreateFontIndirectW(&metrics.lfMessageFont) else { return }
        let previous = context.font
        context.font = font
        for id in [Int32(100), 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 1, 2] {
            if let control = GetDlgItem(hwnd, id) {
                SendMessageW(control, UINT(WM_SETFONT), WPARAM(Int(bitPattern: font)), 1)
            }
        }
        if let previous { DeleteObject(previous) }
    }

    private static func layout(_ hwnd: HWND, context: Context) {
        var rect = RECT()
        guard GetClientRect(hwnd, &rect) != 0 else { return }
        let px = context.pixels
        let width = max(1, rect.right - rect.left - px(32))
        var y: Int32 = 14
        for (labelID, editID) in [(Int32(100), Int32(101)), (104, 103), (106, 105), (108, 107), (110, 109)] {
            guard let edit = GetDlgItem(hwnd, editID) else { continue }
            MoveWindow(GetDlgItem(hwnd, labelID), px(16), px(y), width, px(22), 1)
            MoveWindow(edit, px(16), px(y + 24), width, px(26), 1)
            y += 60
        }
        MoveWindow(GetDlgItem(hwnd, 102), px(16), px(y), width, px(60), 1)
        let buttonWidth = min(px(120), max(1, (width - px(10)) / 2))
        MoveWindow(GetDlgItem(hwnd, 1), px(16) + max(0, width - buttonWidth * 2 - px(10)), px(y + 70), buttonWidth, px(28), 1)
        MoveWindow(GetDlgItem(hwnd, 2), px(16) + max(0, width - buttonWidth), px(y + 70), buttonWidth, px(28), 1)
    }

    private static func place(_ hwnd: HWND, near owner: HWND, context: Context) {
        let extraRows = (context.support.showsTeamModeControls ? 2 : 0) +
            (context.support.showsOrganizationField || context.support.showsTeamModeControls ? 1 : 0)
        var frame = RECT(left: 0, top: 0, right: context.pixels(520), bottom: context.pixels(Int32(246 + extraRows * 60)))
        guard AdjustWindowRectExForDpi(&frame, DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU),
                                       0, DWORD(WS_EX_DLGMODALFRAME), context.dpi) != 0 else { return }
        var info = MONITORINFO()
        info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        let monitor = MonitorFromWindow(owner, UINT(MONITOR_DEFAULTTONEAREST))
        let desiredWidth = frame.right - frame.left, desiredHeight = frame.bottom - frame.top
        if GetMonitorInfoW(monitor, &info) != 0,
           info.rcWork.right > info.rcWork.left, info.rcWork.bottom > info.rcWork.top {
            let area = info.rcWork
            let width = min(desiredWidth, area.right - area.left), height = min(desiredHeight, area.bottom - area.top)
            SetWindowPos(hwnd, nil, area.left + (area.right - area.left - width) / 2,
                         area.top + (area.bottom - area.top - height) / 2, width, height,
                         UINT(SWP_NOZORDER | SWP_NOACTIVATE))
        } else {
            SetWindowPos(hwnd, nil, 0, 0, desiredWidth, desiredHeight,
                         UINT(SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE))
        }
    }

    private static func control(_ parent: HWND, _ klass: String, _ text: String, _ id: Int32,
                                _ style: DWORD, _ x: Int32, _ y: Int32, _ width: Int32, _ height: Int32) -> HWND? {
        let control = klass.withCString(encodedAs: UTF16.self) { name in
            text.withCString(encodedAs: UTF16.self) { caption in
                CreateWindowExW(0, name, caption, DWORD(WS_CHILD | WS_VISIBLE) | style,
                    x, y, width, height, parent, HMENU(bitPattern: Int(id)), GetModuleHandleW(nil), nil)
            }
        }
        if let font = GetStockObject(DEFAULT_GUI_FONT) {
            SendMessageW(control, UINT(WM_SETFONT), WPARAM(Int(bitPattern: font)), 1)
        }
        return control
    }
}
#endif
