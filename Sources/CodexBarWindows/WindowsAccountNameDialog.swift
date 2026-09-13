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
            guard Self.control(hwnd, "STATIC", "&New account name", 100, 0, 16, 14, 400, 22) != nil,
                  let edit = Self.control(hwnd, "EDIT", "", 101, DWORD(WS_TABSTOP | WS_BORDER | ES_AUTOHSCROLL),
                                          16, 40, 410, 26),
                  Self.control(hwnd, "STATIC", "Only the name changes; credentials and selection stay the same.",
                               102, 0, 16, 76, 410, 40) != nil,
                  Self.control(hwnd, "BUTTON", "Save", 1, DWORD(WS_TABSTOP | BS_DEFPUSHBUTTON), 246, 126, 80, 28) != nil,
                  Self.control(hwnd, "BUTTON", "Cancel", 2, DWORD(WS_TABSTOP | BS_PUSHBUTTON), 336, 126, 90, 28) != nil else { return -1 }
            SendMessageW(edit, UINT(EM_SETLIMITTEXT), 160, 0)
            return 0
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
