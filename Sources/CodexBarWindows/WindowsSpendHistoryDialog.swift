#if os(Windows)
import Foundation
import WinSDK

/// Native daily cost history. Currency groups remain independent and missing days are not zero-filled.
enum WindowsSpendHistoryDialog {
    enum Result { case closed, refreshAll }
    private final class Context {
        let snapshot: WindowsSpendHistorySnapshot
        let privacy: Bool
        var currencyIndex = 0
        var selectedDay: Int?
        var result: Result = .closed
        var dpi: UINT = 96
        var closed = false
        var failed = false
        init(snapshot: WindowsSpendHistorySnapshot, privacy: Bool) { self.snapshot = snapshot; self.privacy = privacy }
        var currency: WindowsSpendHistorySnapshot.Currency { self.snapshot.currencies[self.currencyIndex] }
        func px(_ value: Int32) -> Int32 { MulDiv(value, Int32(self.dpi), 96) }
    }
    private static let className = "CodexBar.SpendHistoryDialog"

    static func show(owner: HWND, snapshot: WindowsSpendHistorySnapshot, hidePersonalInfo: Bool) -> Result? {
        guard !snapshot.currencies.isEmpty,
              hidePersonalInfo == WindowsUsagePresentationSettings.load().hidePersonalInfo else { return nil }
        let context = Context(snapshot: snapshot, privacy: hidePersonalInfo)
        var klass = WNDCLASSEXW()
        klass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        klass.hInstance = GetModuleHandleW(nil)
        klass.hCursor = LoadCursorW(nil, IDC_ARROW)
        klass.lpfnWndProc = Self.windowProc
        let name = Array(Self.className.utf16) + [UInt16(0)]
        let registered = name.withUnsafeBufferPointer { klass.lpszClassName = $0.baseAddress; return RegisterClassExW(&klass) }
        guard registered != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS else { return nil }
        let title = Array("Cost history — captured snapshot".utf16) + [UInt16(0)]
        let hwnd = name.withUnsafeBufferPointer { n in
            title.withUnsafeBufferPointer { t in
                CreateWindowExW(DWORD(WS_EX_DLGMODALFRAME), n.baseAddress, t.baseAddress,
                    DWORD(WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN), Int32(bitPattern: 0x80000000),
                    Int32(bitPattern: 0x80000000), 1000, 780, owner, nil, GetModuleHandleW(nil),
                    Unmanaged.passUnretained(context).toOpaque())
            }
        }
        guard let hwnd else { return nil }
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
        return context.failed ? nil : context.result
    }

    private static func closeForPrivacy(_ hwnd: HWND, context: Context) -> Bool {
        guard context.privacy != WindowsUsagePresentationSettings.load().hidePersonalInfo else { return false }
        ShowWindow(hwnd, Int32(SW_HIDE)); DestroyWindow(hwnd)
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
            for (id, label) in [(Int32(2), "Close"), (Int32(3), "Previous currency"), (Int32(4), "Next currency"), (Int32(5), "Refresh && close")] {
                guard Self.control(hwnd, kind: "BUTTON", title: label, id: id,
                    style: DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON)) != nil else { return -1 }
            }
            guard Self.control(hwnd, kind: "EDIT", title: context.currency.summary, id: 6,
                style: DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_BORDER | WS_VSCROLL | ES_MULTILINE | ES_READONLY)) != nil,
                  SetTimer(hwnd, 1, 250, nil) != 0 else { return -1 }
            Self.layout(hwnd, context: context)
            Self.updateDetails(hwnd, context: context)
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
            if Self.closeForPrivacy(hwnd, context: context) { return 0 }
            switch Int32(wParam & 0xffff) {
            case 2: DestroyWindow(hwnd); return 0
            case 3: context.currencyIndex = max(0, context.currencyIndex - 1); context.selectedDay = nil
            case 4: context.currencyIndex = min(context.snapshot.currencies.count - 1, context.currencyIndex + 1); context.selectedDay = nil
            case 5: context.result = .refreshAll; DestroyWindow(hwnd); return 0
            default: return 0
            }
            Self.updateDetails(hwnd, context: context)
            return 0
        case UINT(WM_LBUTTONUP):
            let x = Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: lParam)))
            let y = Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: lParam >> 16)))
            let bounds = Self.plotBounds(hwnd, context: context)
            if x >= bounds.left, x < bounds.right, y >= bounds.top, y < bounds.bottom, !context.currency.days.isEmpty {
                let fraction = Double(x - bounds.left) / Double(max(1, bounds.right - bounds.left))
                context.selectedDay = min(context.currency.days.count - 1, Int(fraction * Double(context.currency.days.count)))
                Self.updateDetails(hwnd, context: context)
            }
            return 0
        case UINT(WM_CLOSE): DestroyWindow(hwnd); return 0
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

    private static func updateDetails(_ hwnd: HWND, context: Context) {
        let currency = context.currency
        let selected = context.selectedDay.flatMap { currency.days.indices.contains($0) ? currency.days[$0].details : nil }
        let text = currency.summary + "\r\n\r\n" + (selected ?? "Select a day in the chart to inspect its known contributions.")
        text.withCString(encodedAs: UTF16.self) { SetWindowTextW(GetDlgItem(hwnd, 6), $0) }
        EnableWindow(GetDlgItem(hwnd, 3), context.currencyIndex > 0 ? 1 : 0)
        EnableWindow(GetDlgItem(hwnd, 4), context.currencyIndex + 1 < context.snapshot.currencies.count ? 1 : 0)
        InvalidateRect(hwnd, nil, 1)
    }

    private static func plotBounds(_ hwnd: HWND, context: Context) -> RECT {
        var area = RECT(); GetClientRect(hwnd, &area)
        return RECT(left: context.px(76), top: context.px(42), right: max(context.px(77), area.right - context.px(20)),
                    bottom: max(context.px(43), area.bottom - context.px(214)))
    }

    private static func paint(_ hwnd: HWND, context: Context) {
        var paint = PAINTSTRUCT()
        guard let dc = BeginPaint(hwnd, &paint) else { return }
        defer { EndPaint(hwnd, &paint) }
        FillRect(dc, &paint.rcPaint, GetSysColorBrush(COLOR_WINDOW))
        let bounds = Self.plotBounds(hwnd, context: context)
        let currency = context.currency
        guard !currency.days.isEmpty else { return }
        let width = Double(bounds.right - bounds.left), height = Double(bounds.bottom - bounds.top)
        let palette: [COLORREF] = [0x00D78E32, 0x0066A84A, 0x005C8FED, 0x00B56FA5, 0x0099B2B2, 0x00948BC7]
        for (index, day) in currency.days.enumerated() {
            let left = bounds.left + Int32(width * Double(index) / Double(currency.days.count))
            let right = max(left + 1, bounds.left + Int32(width * Double(index + 1) / Double(currency.days.count)) - 1)
            if day.segments.isEmpty {
                var tick = RECT(left: left, top: bounds.bottom - 2, right: right, bottom: bounds.bottom)
                FillRect(dc, &tick, GetSysColorBrush(COLOR_GRAYTEXT))
            }
            for segment in day.segments where segment.end > segment.start {
                guard let brush = CreateSolidBrush(palette[segment.paletteIndex % palette.count]) else { context.failed = true; continue }
                var bar = RECT(left: left, top: bounds.bottom - Int32(height * segment.end / currency.maximum),
                               right: right, bottom: bounds.bottom - Int32(height * segment.start / currency.maximum))
                FillRect(dc, &bar, brush); DeleteObject(brush)
            }
            if context.selectedDay == index {
                var selection = RECT(left: left, top: bounds.top, right: right, bottom: bounds.bottom)
                FrameRect(dc, &selection, GetSysColorBrush(COLOR_HIGHLIGHT))
            }
        }
        SetBkMode(dc, Int32(TRANSPARENT)); SetTextColor(dc, GetSysColor(COLOR_WINDOWTEXT))
        func text(_ label: String, _ rect: RECT) {
            var rect = rect
            var value = Array(label.utf16) + [UInt16(0)]
            value.withUnsafeMutableBufferPointer { _ = DrawTextW(dc, $0.baseAddress, -1, &rect, UINT(DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX)) }
        }
        text(currency.code + " · known daily costs", RECT(left: bounds.left, top: context.px(12), right: bounds.right, bottom: bounds.top))
        text(currency.maximumLabel, RECT(left: 0, top: bounds.top, right: bounds.left - 4, bottom: bounds.top + context.px(24)))
        text(currency.days.first?.label ?? "", RECT(left: bounds.left, top: bounds.bottom + 4, right: bounds.left + context.px(200), bottom: bounds.bottom + context.px(28)))
        text(currency.days.last?.label ?? "", RECT(left: max(bounds.left, bounds.right - context.px(200)), top: bounds.bottom + 4, right: bounds.right, bottom: bounds.bottom + context.px(28)))
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
