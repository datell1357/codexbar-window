#if os(Windows)
import Foundation
import WinSDK

/// Native daily cost history. Currency groups remain independent and missing days are not zero-filled.
enum WindowsSpendHistoryDialog {
    enum Result { case closed, refreshAll; case inspectHours(day: Date, currency: String, generation: UInt64) }
    private final class Context {
        let snapshot: WindowsSpendHistorySnapshot
        let privacy: Bool
        var currencyIndex = 0
        var selectedDay: Int?
        var result: Result = .closed
        var dpi: UINT = 96
        var closed = false
        var failed = false
        init(snapshot: WindowsSpendHistorySnapshot, privacy: Bool) {
            self.snapshot = snapshot; self.privacy = privacy
            self.currencyIndex = snapshot.series.firstIndex { $0.code == snapshot.preferredSeriesCode } ?? 0
        }
        var currency: WindowsSpendHistorySnapshot.Series { self.snapshot.series[self.currencyIndex] }
        func px(_ value: Int32) -> Int32 { MulDiv(value, Int32(self.dpi), 96) }
    }
    private static let className = "CodexBar.SpendHistoryDialog"

    static func show(owner: HWND, snapshot: WindowsSpendHistorySnapshot, hidePersonalInfo: Bool) -> Result? {
        guard !snapshot.series.isEmpty,
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
        let title = Array((snapshot.title + " — captured snapshot").utf16) + [UInt16(0)]
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
            if message.message == UINT(WM_KEYDOWN), GetFocus() != GetDlgItem(hwnd, 6),
               message.hwnd == hwnd || IsChild(hwnd, message.hwnd) != 0 {
                if message.wParam == WPARAM(VK_LEFT) { Self.selectDay(-1, hwnd: hwnd, context: context); continue }
                if message.wParam == WPARAM(VK_RIGHT) { Self.selectDay(1, hwnd: hwnd, context: context); continue }
                if message.wParam == WPARAM(VK_HOME), !context.currency.days.isEmpty {
                    context.selectedDay = 0; Self.updateDetails(hwnd, context: context); continue
                }
                if message.wParam == WPARAM(VK_END), !context.currency.days.isEmpty {
                    context.selectedDay = context.currency.days.count - 1; Self.updateDetails(hwnd, context: context); continue
                }
            }
            if message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(0x41),
               GetFocus() == GetDlgItem(hwnd, 6), GetKeyState(Int32(VK_CONTROL)) < 0 {
                SendMessageW(GetDlgItem(hwnd, 6), UINT(EM_SETSEL), 0, -1); continue
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
            for (id, label) in [(Int32(2), "Close"), (Int32(3), "Previous currency"), (Int32(4), "Next currency"), (Int32(5), "Refresh && close"), (Int32(7), context.snapshot.kind == .hourly ? "&Previous hour" : "&Previous day"), (Int32(8), context.snapshot.kind == .hourly ? "&Next hour" : "&Next day"), (Int32(9), "&Clear selection"), (Int32(10), "&Hourly details")] {
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
            case 4: context.currencyIndex = min(context.snapshot.series.count - 1, context.currencyIndex + 1); context.selectedDay = nil
            case 5: context.result = .refreshAll; DestroyWindow(hwnd); return 0
            case 7: Self.selectDay(-1, hwnd: hwnd, context: context); return 0
            case 8: Self.selectDay(1, hwnd: hwnd, context: context); return 0
            case 9: context.selectedDay = nil
            case 10:
                guard context.snapshot.kind == .cost, let index = context.selectedDay,
                      context.currency.days.indices.contains(index), let day = context.currency.days[index].date else { return 0 }
                context.result = .inspectHours(day: day, currency: context.currency.code, generation: context.snapshot.generation)
                DestroyWindow(hwnd); return 0
            default: return 0
            }
            Self.updateDetails(hwnd, context: context)
            return 0
        case UINT(WM_LBUTTONUP):
            let x = Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: lParam)))
            let y = Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: lParam >> 16)))
            if context.snapshot.kind == .tokens {
                let grid = Self.activityGrid(hwnd, context: context)
                if x >= grid.left, y >= grid.top, x < grid.left + grid.cell * Int32(grid.columns), y < grid.top + grid.cell * 7 {
                    let row = Int((y - grid.top) / grid.cell), column = Int((x - grid.left) / grid.cell)
                    context.selectedDay = context.currency.days.firstIndex { $0.activity?.row == row && $0.activity?.column == column }
                    Self.updateDetails(hwnd, context: context)
                }
                return 0
            }
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
        for id: Int32 in [3, 4] { ShowWindow(GetDlgItem(hwnd, id), context.snapshot.kind == .tokens ? Int32(SW_HIDE) : Int32(SW_SHOW)) }
        for index in 0..<4 {
            MoveWindow(GetDlgItem(hwnd, Int32(index + 2)), margin + Int32(index) * (width + gap),
                       top, width, button, 1)
        }
        if context.snapshot.kind == .tokens {
            let half = max(1, (rect.right - 2 * margin - gap) / 2)
            MoveWindow(GetDlgItem(hwnd, 2), margin, top, half, button, 1)
            MoveWindow(GetDlgItem(hwnd, 5), margin + half + gap, top, half, button, 1)
        }
        let navigationTop = max(margin, top - button - gap)
        let navigationCount: Int32 = context.snapshot.kind == .cost ? 4 : 3
        ShowWindow(GetDlgItem(hwnd, 10), context.snapshot.kind == .cost ? Int32(SW_SHOW) : Int32(SW_HIDE))
        let navigationWidth = max(1, (rect.right - 2 * margin - (navigationCount - 1) * gap) / navigationCount)
        for index in 0..<Int(navigationCount) {
            MoveWindow(GetDlgItem(hwnd, Int32(index + 7)), margin + Int32(index) * (navigationWidth + gap),
                       navigationTop, navigationWidth, button, 1)
        }
        let textTop = max(margin, navigationTop - gap - context.px(110))
        MoveWindow(GetDlgItem(hwnd, 6), margin, textTop, max(1, rect.right - 2 * margin), max(1, navigationTop - gap - textTop), 1)
        InvalidateRect(hwnd, nil, 1)
    }

    private static func selectDay(_ direction: Int, hwnd: HWND, context: Context) {
        guard !context.currency.days.isEmpty else { return }
        if let selected = context.selectedDay {
            context.selectedDay = max(0, min(context.currency.days.count - 1, selected + direction))
        } else {
            context.selectedDay = direction < 0 ? context.currency.days.count - 1 : 0
        }
        Self.updateDetails(hwnd, context: context)
    }

    private static func updateDetails(_ hwnd: HWND, context: Context) {
        let currency = context.currency
        let selected = context.selectedDay.flatMap { currency.days.indices.contains($0) ? currency.days[$0].details : nil }
        let text = currency.summary + "\r\n\r\n" + (selected ?? "Select a day in the chart to inspect its known contributions.")
        text.withCString(encodedAs: UTF16.self) { SetWindowTextW(GetDlgItem(hwnd, 6), $0) }
        EnableWindow(GetDlgItem(hwnd, 7), !currency.days.isEmpty && context.selectedDay != 0 ? 1 : 0)
        EnableWindow(GetDlgItem(hwnd, 8), !currency.days.isEmpty && context.selectedDay != currency.days.count - 1 ? 1 : 0)
        EnableWindow(GetDlgItem(hwnd, 10), context.snapshot.kind == .cost && context.selectedDay != nil ? 1 : 0)
        EnableWindow(GetDlgItem(hwnd, 9), context.selectedDay != nil ? 1 : 0)
        EnableWindow(GetDlgItem(hwnd, 3), context.currencyIndex > 0 ? 1 : 0)
        EnableWindow(GetDlgItem(hwnd, 4), context.currencyIndex + 1 < context.snapshot.series.count ? 1 : 0)
        InvalidateRect(hwnd, nil, 1)
    }

    private static func plotBounds(_ hwnd: HWND, context: Context) -> RECT {
        var area = RECT(); GetClientRect(hwnd, &area)
        return RECT(left: context.px(76), top: context.px(102), right: max(context.px(77), area.right - context.px(20)),
                    bottom: max(context.px(103), area.bottom - context.px(254)))
    }

    private static func paint(_ hwnd: HWND, context: Context) {
        var paint = PAINTSTRUCT()
        guard let dc = BeginPaint(hwnd, &paint) else { return }
        defer { EndPaint(hwnd, &paint) }
        FillRect(dc, &paint.rcPaint, GetSysColorBrush(COLOR_WINDOW))
        if context.snapshot.kind == .tokens { Self.paintActivity(hwnd, dc: dc, context: context); return }
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
        let columnWidth = max(1, (bounds.right - bounds.left) / 3)
        for (index, item) in currency.legend.enumerated() {
            let x = bounds.left + Int32(index % 3) * columnWidth
            let y = context.px(42 + Int32(index / 3) * 24)
            if let brush = CreateSolidBrush(palette[item.paletteIndex % palette.count]) {
                var swatch = RECT(left: x, top: y + 2, right: x + context.px(12), bottom: y + context.px(14))
                FillRect(dc, &swatch, brush); DeleteObject(brush)
            }
            text("[\(item.paletteIndex + 1)] " + item.caption,
                 RECT(left: x + context.px(18), top: y, right: x + columnWidth - 4, bottom: y + context.px(22)))
        }
        text(currency.code + (context.snapshot.kind == .hourly ? " · known hourly costs" : " · known daily costs"), RECT(left: bounds.left, top: context.px(12), right: bounds.right, bottom: bounds.top))
        text(currency.maximumLabel, RECT(left: 0, top: bounds.top, right: bounds.left - 4, bottom: bounds.top + context.px(24)))
        text(currency.days.first?.label ?? "", RECT(left: bounds.left, top: bounds.bottom + 4, right: bounds.left + context.px(200), bottom: bounds.bottom + context.px(28)))
        text(currency.days.last?.label ?? "", RECT(left: max(bounds.left, bounds.right - context.px(200)), top: bounds.bottom + 4, right: bounds.right, bottom: bounds.bottom + context.px(28)))
    }

    private static func activityGrid(_ hwnd: HWND, context: Context) -> (left: Int32, top: Int32, cell: Int32, columns: Int) {
        let bounds = Self.plotBounds(hwnd, context: context)
        let columns = max(1, (context.currency.days.compactMap { $0.activity?.column }.max() ?? 0) + 1)
        let cell = max(1, min((bounds.right - bounds.left) / Int32(columns), (bounds.bottom - bounds.top) / 7))
        return (bounds.left, bounds.top, cell, columns)
    }

    private static func paintActivity(_ hwnd: HWND, dc: HDC, context: Context) {
        let grid = Self.activityGrid(hwnd, context: context)
        let bounds = Self.plotBounds(hwnd, context: context)
        let colors: [COLORREF] = [0x00F0F0F0, 0x00B0B0B0, 0x00E3F2E8, 0x00B8DEA9, 0x0086BF70, 0x004A973D, 0x00245C18]
        SetBkMode(dc, Int32(TRANSPARENT)); SetTextColor(dc, GetSysColor(COLOR_WINDOWTEXT))
        func text(_ value: String, rect: RECT) {
            var rect = rect
            var units = Array(value.utf16) + [UInt16(0)]
            units.withUnsafeMutableBufferPointer { _ = DrawTextW(dc, $0.baseAddress, -1, &rect, UINT(DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX)) }
        }
        for (index, day) in context.currency.days.enumerated() {
            guard let cell = day.activity, colors.indices.contains(cell.level) else { continue }
            let x = grid.left + Int32(cell.column) * grid.cell, y = grid.top + Int32(cell.row) * grid.cell
            var rect = RECT(left: x, top: y, right: x + max(1, grid.cell - 1), bottom: y + max(1, grid.cell - 1))
            guard let brush = CreateSolidBrush(colors[cell.level]) else { context.failed = true; continue }
            FillRect(dc, &rect, brush); DeleteObject(brush)
            if cell.level == 0 { FrameRect(dc, &rect, GetSysColorBrush(COLOR_GRAYTEXT)) }
            if context.selectedDay == index { FrameRect(dc, &rect, GetSysColorBrush(COLOR_HIGHLIGHT)) }
        }
        text("Tracked token activity", rect: RECT(left: bounds.left, top: context.px(12), right: bounds.right, bottom: context.px(36)))
        let captions = ["Unscanned", "Unknown", "Zero", "Low", "Medium", "High", "Highest"]
        let column = max(1, (bounds.right - bounds.left) / 4)
        for index in colors.indices {
            let x = bounds.left + Int32(index % 4) * column, y = context.px(42 + Int32(index / 4) * 24)
            if let brush = CreateSolidBrush(colors[index]) {
                var swatch = RECT(left: x, top: y + 2, right: x + context.px(12), bottom: y + context.px(14))
                FillRect(dc, &swatch, brush); DeleteObject(brush)
            }
            text(captions[index], rect: RECT(left: x + context.px(18), top: y, right: x + column - 4, bottom: y + context.px(22)))
        }
        for (row, label) in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].enumerated() {
            let y = grid.top + Int32(row) * grid.cell
            text(label, rect: RECT(left: 0, top: y, right: grid.left - 4, bottom: y + grid.cell))
        }
        let bottom = grid.top + grid.cell * 7 + 4
        text(context.currency.days.first?.label ?? "", rect: RECT(left: bounds.left, top: bottom, right: bounds.left + context.px(200), bottom: bottom + context.px(24)))
        text(context.currency.days.last?.label ?? "", rect: RECT(left: max(bounds.left, bounds.right - context.px(200)), top: bottom, right: bounds.right, bottom: bottom + context.px(24)))
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
