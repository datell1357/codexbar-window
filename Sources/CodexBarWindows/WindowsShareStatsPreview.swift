#if os(Windows)
import Foundation
import WinSDK

/// A modal, immutable share snapshot. Saving and copying use exactly the previewed raster.
enum WindowsShareStatsPreview {
    struct Image: Sendable {
        let png: Data
        let dib: Data
        let filename: String
        let text: String
    }
    private final class Context {
        let image: Image
        let privacy: Bool
        let isCurrent: @Sendable () -> Bool
        var dpi: UINT = 96
        var closed = false
        var failed = false
        var childDialogOpen = false
        var closePending = false
        init(image: Image, privacy: Bool, isCurrent: @escaping @Sendable () -> Bool) {
            self.isCurrent = isCurrent
            self.image = image; self.privacy = privacy }
        func px(_ value: Int32) -> Int32 { MulDiv(value, Int32(self.dpi), 96) }
    }
    private static let className = "CodexBar.ShareStatsPreview"

    static func show(owner: HWND, image: Image, hidePersonalInfo: Bool, isCurrent: @escaping @Sendable () -> Bool = { true }) -> Bool {
        guard image.dib.count == 40 + 1200 * 630 * 4, !image.png.isEmpty,
              image.png.count <= 16 * 1024 * 1024, image.text.utf16.count <= 65536,
              isCurrent(), hidePersonalInfo == WindowsUsagePresentationSettings.load().hidePersonalInfo else { return false }
        let context = Context(image: image, privacy: hidePersonalInfo, isCurrent: isCurrent)
        var klass = WNDCLASSEXW()
        klass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        klass.hInstance = GetModuleHandleW(nil)
        klass.hCursor = LoadCursorW(nil, IDC_ARROW)
        klass.lpfnWndProc = Self.windowProc
        let name = Array(Self.className.utf16) + [UInt16(0)]
        let registered = name.withUnsafeBufferPointer { klass.lpszClassName = $0.baseAddress; return RegisterClassExW(&klass) }
        guard registered != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS else { return false }
        let title = Array("Share Stats preview — captured snapshot".utf16) + [UInt16(0)]
        let hwnd = name.withUnsafeBufferPointer { n in
            title.withUnsafeBufferPointer { t in
                CreateWindowExW(DWORD(WS_EX_DLGMODALFRAME), n.baseAddress, t.baseAddress,
                    DWORD(WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN), Int32(bitPattern: 0x80000000),
                    Int32(bitPattern: 0x80000000), 1000, 780, owner, nil, GetModuleHandleW(nil),
                    Unmanaged.passUnretained(context).toOpaque())
            }
        }
        guard let hwnd else { return false }
        var monitor = MONITORINFO()
        monitor.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        if GetMonitorInfoW(MonitorFromWindow(owner, DWORD(MONITOR_DEFAULTTONEAREST)), &monitor) != 0 {
            let area = monitor.rcWork
            let width = min(context.px(1000), area.right - area.left)
            let height = min(context.px(780), area.bottom - area.top)
            SetWindowPos(hwnd, nil, area.left + (area.right - area.left - width) / 2,
                         area.top + (area.bottom - area.top - height) / 2, width, height, UINT(SWP_NOZORDER))
        }
        let wasEnabled = IsWindowEnabled(owner) != 0
        EnableWindow(owner, 0)
        ShowWindow(hwnd, Int32(SW_SHOW)); UpdateWindow(hwnd)
        SetFocus(GetDlgItem(hwnd, 2))
        var message = MSG()
        while !context.closed {
            let result = GetMessageW(&message, nil, 0, 0)
            if result == -1 { context.failed = true; break }
            if result == 0 { PostQuitMessage(Int32(message.wParam)); break }
            if Self.closeForPrivacy(hwnd, context: context) { break }
            if message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_ESCAPE),
               message.hwnd == hwnd || IsChild(hwnd, message.hwnd) != 0 {
                DestroyWindow(hwnd); continue
            }
            if IsDialogMessageW(hwnd, &message) == 0 { TranslateMessage(&message); DispatchMessageW(&message) }
        }
        if IsWindow(hwnd) != 0 { DestroyWindow(hwnd) }
        if IsWindow(owner) != 0, wasEnabled { EnableWindow(owner, 1); SetForegroundWindow(owner) }
        return !context.failed
    }

    private static func closeForPrivacy(_ hwnd: HWND, context: Context) -> Bool {
        guard !context.closed else { return true }
        guard context.closePending || !context.isCurrent() ||
            context.privacy != WindowsUsagePresentationSettings.load().hidePersonalInfo else { return false }
        context.closePending = true
        ShowWindow(hwnd, Int32(SW_HIDE))
        // Common dialogs dispatch owner timers while their nested message loop is active.
        // Keep the owner handle alive until that dialog has returned.
        if !context.childDialogOpen { DestroyWindow(hwnd) }
        return true
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
            let dpi = GetDpiForWindow(hwnd); context.dpi = dpi == 0 ? 96 : dpi
            for (id, label) in [(Int32(2), "Close"), (Int32(3), "Save PNG…"), (Int32(4), "Copy image"), (Int32(5), "Copy text")] {
                guard Self.control(hwnd, kind: "BUTTON", title: label, id: id,
                    style: DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON)) != nil else { return -1 }
            }
            guard Self.control(hwnd, kind: "EDIT", title: context.image.text, id: 6,
                style: DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_BORDER | WS_VSCROLL | ES_MULTILINE | ES_READONLY)) != nil,
                  SetTimer(hwnd, 1, 250, nil) != 0 else { return -1 }
            Self.layout(hwnd, context: context)
            return 0
        case UINT(WM_TIMER): _ = Self.closeForPrivacy(hwnd, context: context); return 0
        case UINT(WM_SIZE): Self.layout(hwnd, context: context); return 0
        case UINT(WM_DPICHANGED):
            let dpi = UINT(wParam & 0xffff); if dpi != 0 { context.dpi = dpi }
            if let value = UnsafeRawPointer(bitPattern: UInt(lParam))?.assumingMemoryBound(to: RECT.self) {
                let rect = value.pointee
                SetWindowPos(hwnd, nil, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top,
                             UINT(SWP_NOZORDER | SWP_NOACTIVATE))
            }
            Self.layout(hwnd, context: context)
            return 0
        case UINT(WM_PAINT): Self.paint(hwnd, context: context); return 0
        case UINT(WM_COMMAND):
            guard !context.childDialogOpen else { return 0 }
            if Self.closeForPrivacy(hwnd, context: context) { return 0 }
            let error: String?
            switch Int32(wParam & 0xffff) {
            case 2: DestroyWindow(hwnd); return 0
            case 3:
                context.childDialogOpen = true
                error = WindowsShareStatsExporter.savePNG(context.image.png, filename: context.image.filename,
                    owner: hwnd, hidePersonalInfo: context.privacy, isCurrent: context.isCurrent)
                context.childDialogOpen = false
                if Self.closeForPrivacy(hwnd, context: context) { return 0 }
            case 4: error = WindowsClipboard.writeImage(png: context.image.png, dib: context.image.dib, owner: hwnd, isCurrent: context.isCurrent)
            case 5: error = WindowsClipboard.write(context.image.text, owner: hwnd, isCurrent: context.isCurrent)
            default: return 0
            }
            if let error, IsWindow(hwnd) != 0 {
                context.childDialogOpen = true
                error.withCString(encodedAs: UTF16.self) { body in
                    "Share Stats".withCString(encodedAs: UTF16.self) { MessageBoxW(hwnd, body, $0, UINT(MB_OK | MB_ICONERROR)) }
                }
                context.childDialogOpen = false
                _ = Self.closeForPrivacy(hwnd, context: context)
            }
            return 0
        case UINT(WM_CLOSE):
            context.closePending = true
            _ = Self.closeForPrivacy(hwnd, context: context)
            return 0
        case UINT(WM_DESTROY): KillTimer(hwnd, 1); context.closed = true; return 0
        case UINT(WM_NCDESTROY): SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), 0)
        default: break
        }
        return DefWindowProcW(hwnd, message, wParam, lParam)
    }

    private static func layout(_ hwnd: HWND, context: Context) {
        var rect = RECT(); GetClientRect(hwnd, &rect)
        let margin = context.px(16), button = context.px(32), gap = context.px(8)
        let available = max(4, rect.right - 2 * margin - 3 * gap)
        let width = available / 4
        let top = max(margin, rect.bottom - margin - button)
        for index in 0..<4 {
            MoveWindow(GetDlgItem(hwnd, Int32(index + 2)), margin + Int32(index) * (width + gap),
                       top, width, button, 1)
        }
        let textTop = max(margin, top - gap - context.px(110))
        MoveWindow(GetDlgItem(hwnd, 6), margin, textTop, max(1, rect.right - 2 * margin), max(1, top - gap - textTop), 1)
        InvalidateRect(hwnd, nil, 1)
    }

    private static func paint(_ hwnd: HWND, context: Context) {
        var paint = PAINTSTRUCT()
        guard let dc = BeginPaint(hwnd, &paint) else { return }
        defer { EndPaint(hwnd, &paint) }
        FillRect(dc, &paint.rcPaint, GetSysColorBrush(COLOR_WINDOW))
        var area = RECT(); GetClientRect(hwnd, &area)
        let width = max(0, area.right - context.px(32)), height = max(0, area.bottom - context.px(198))
        guard width > 0, height > 0 else { return }
        let scale = min(Double(width) / 1200, Double(height) / 630)
        let targetWidth = Int32(1200 * scale), targetHeight = Int32(630 * scale)
        var info = BITMAPINFO()
        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = 1200; info.bmiHeader.biHeight = 630
        info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32; info.bmiHeader.biCompression = DWORD(BI_RGB)
        SetStretchBltMode(dc, Int32(COLORONCOLOR))
        let result = context.image.dib.withUnsafeBytes { bytes in
            StretchDIBits(dc, (area.right - targetWidth) / 2, context.px(16), targetWidth, targetHeight,
                          0, 0, 1200, 630, bytes.baseAddress!.advanced(by: 40), &info, UINT(DIB_RGB_COLORS), DWORD(SRCCOPY))
        }
        if result == 0 || result == -1 { context.failed = true }
    }

    private static func control(_ parent: HWND, kind: String, title: String, id: Int32, style: DWORD) -> HWND? {
        let klass = Array(kind.utf16) + [UInt16(0)], label = Array(title.utf16) + [UInt16(0)]
        let hwnd = klass.withUnsafeBufferPointer { k in label.withUnsafeBufferPointer { t in
            CreateWindowExW(0, k.baseAddress, t.baseAddress, style, 0, 0, 1, 1, parent,
                            HMENU(bitPattern: Int(id)), GetModuleHandleW(nil), nil)
        } }
        if let font = GetStockObject(DEFAULT_GUI_FONT) { SendMessageW(hwnd, UINT(WM_SETFONT), WPARAM(Int(bitPattern: font)), 1) }
        return hwnd
    }
}
#endif
