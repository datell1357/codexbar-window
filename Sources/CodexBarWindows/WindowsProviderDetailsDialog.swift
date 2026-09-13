#if os(Windows)
import Foundation
import WinSDK

/// Read-only snapshot viewer. It never fetches or changes provider/account state.
enum WindowsProviderDetailsDialog {
    private static let className = "CodexBar.ProviderDetailsDialog"
    private static let textID: Int32 = 101
    private static let closeID: Int32 = 2

    private final class Context {
        let text: String
        var closed = false
        init(text: String) { self.text = text }
    }

    static func show(owner: HWND, title: String, text: String) -> Bool {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        let context = Context(text: normalized)
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
        guard registered != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS else { return false }
        let caption = Array(title.utf16) + [0]
        let hwnd = name.withUnsafeBufferPointer { n in
            caption.withUnsafeBufferPointer { c in
                CreateWindowExW(DWORD(WS_EX_DLGMODALFRAME), n.baseAddress, c.baseAddress,
                                DWORD(WS_OVERLAPPEDWINDOW), Int32(bitPattern: 0x80000000), Int32(bitPattern: 0x80000000),
                                720, 540, owner, nil, instance, Unmanaged.passUnretained(context).toOpaque())
            }
        }
        guard let hwnd else { return false }
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
        return succeeded
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
            guard Self.addControl(hwnd, "EDIT", context.text, Self.textID,
                                  DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_BORDER | WS_VSCROLL |
                                        ES_MULTILINE | ES_AUTOVSCROLL | ES_READONLY)) != nil,
                  Self.addControl(hwnd, "BUTTON", "Close", Self.closeID,
                                  DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON)) != nil else {
                return -1
            }
            Self.layout(hwnd)
            return 0
        case UINT(WM_SIZE): Self.layout(hwnd); return 0
        case UINT(WM_SETFOCUS): SetFocus(GetDlgItem(hwnd, Self.textID)); return 0
        case UINT(WM_COMMAND):
            if Int32(wParam & 0xffff) == Self.closeID { DestroyWindow(hwnd) }
            return 0
        case UINT(WM_CLOSE): DestroyWindow(hwnd); return 0
        case UINT(WM_NCDESTROY):
            context.closed = true
            SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), 0)
            return DefWindowProcW(hwnd, message, wParam, lParam)
        default: return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }

    private static func layout(_ hwnd: HWND) {
        var rect = RECT()
        guard GetClientRect(hwnd, &rect) != 0 else { return }
        let width = max(0, rect.right - rect.left), height = max(0, rect.bottom - rect.top)
        MoveWindow(GetDlgItem(hwnd, Self.textID), 12, 12, max(1, width - 24), max(1, height - 64), 1)
        MoveWindow(GetDlgItem(hwnd, Self.closeID), max(12, width - 104), max(12, height - 40), 92, 28, 1)
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
