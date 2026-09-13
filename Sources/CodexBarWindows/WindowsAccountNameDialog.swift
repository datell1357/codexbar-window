#if os(Windows)
import Foundation
import WinSDK

/// Input begins empty so a redacted label can never be saved as the original name.
enum WindowsAccountNameDialog {
    enum Result { case cancelled, failed, saved(String) }
    private static let className = "CodexBar.AccountNameDialog"
    private final class Context {
        var result: Result = .cancelled
        var closed = false
        var dpi: UINT = 96
        var font: HFONT?
        deinit { if let font { DeleteObject(font) } }
        func pixels(_ value: Int32) -> Int32 { MulDiv(value, Int32(self.dpi), 96) }
    }
    static func show(owner: HWND) -> Result {
        let context = Context()
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
        let caption = Array("Rename saved account".utf16) + [0]
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
        var buffer = [WCHAR](repeating: 0, count: 162)
        let count = GetWindowTextW(GetDlgItem(hwnd, 101), &buffer, Int32(buffer.count))
        let label = String(decoding: buffer.prefix(Int(max(0, count))), as: UTF16.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.utf16.count <= 160,
              !label.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            "Enter a nonempty name of at most 160 characters, without control characters.".withCString(encodedAs: UTF16.self) {
                SetWindowTextW(GetDlgItem(hwnd, 102), $0)
            }
            SetFocus(GetDlgItem(hwnd, 101)); return
        }
        context.result = .saved(label)
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
            guard Self.control(hwnd, "STATIC", "&New account name", 100, 0, 16, 14, 400, 22) != nil,
                  let edit = Self.control(hwnd, "EDIT", "", 101, DWORD(WS_TABSTOP | WS_BORDER | ES_AUTOHSCROLL),
                                          16, 40, 410, 26),
                  Self.control(hwnd, "STATIC", "Only the name changes; credentials and selection stay the same.",
                               102, 0, 16, 76, 410, 40) != nil,
                  Self.control(hwnd, "BUTTON", "Save", 1, DWORD(WS_TABSTOP | BS_DEFPUSHBUTTON), 246, 126, 80, 28) != nil,
                  Self.control(hwnd, "BUTTON", "Cancel", 2, DWORD(WS_TABSTOP | BS_PUSHBUTTON), 336, 126, 90, 28) != nil else { return -1 }
            SendMessageW(edit, UINT(EM_SETLIMITTEXT), 160, 0)
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
        for id in [Int32(100), 101, 102, 1, 2] {
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
        MoveWindow(GetDlgItem(hwnd, 100), px(16), px(14), width, px(22), 1)
        MoveWindow(GetDlgItem(hwnd, 101), px(16), px(40), width, px(26), 1)
        MoveWindow(GetDlgItem(hwnd, 102), px(16), px(76), width, px(54), 1)
        let buttonWidth = min(px(90), max(1, (width - px(10)) / 2))
        MoveWindow(GetDlgItem(hwnd, 1), px(16) + max(0, width - buttonWidth * 2 - px(10)), px(140),
                   buttonWidth, px(28), 1)
        MoveWindow(GetDlgItem(hwnd, 2), px(16) + max(0, width - buttonWidth), px(140), buttonWidth, px(28), 1)
    }

    private static func place(_ hwnd: HWND, near owner: HWND, context: Context) {
        var frame = RECT(left: 0, top: 0, right: context.pixels(450), bottom: context.pixels(184))
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
