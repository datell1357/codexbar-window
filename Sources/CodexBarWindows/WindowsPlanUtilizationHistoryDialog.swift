#if os(Windows)
import CodexBarCore
import Foundation
import WinSDK

/// Captured quota history with native controls and a textual equivalent for every plotted point.
enum WindowsPlanUtilizationHistoryDialog {
    enum Result { case closed, refresh, invalidated }
    private final class Context {
        let snapshot: WindowsPlanUtilizationHistorySnapshot
        let hostIsCurrent: @Sendable () -> Bool
        let localization = WindowsStatusLocalization.Snapshot()
        var seriesIndex = 0
        var selectedIndex: Int?
        var dpi: UINT = 96
        var font: HFONT?
        var closed = false
        var failed = false
        var result: Result = .closed

        init(snapshot: WindowsPlanUtilizationHistorySnapshot, isCurrent: @escaping @Sendable () -> Bool) {
            self.snapshot = snapshot
            self.hostIsCurrent = isCurrent
        }
        var series: PlanUtilizationHistoryChart.Series? {
            self.snapshot.series.indices.contains(self.seriesIndex) ? self.snapshot.series[self.seriesIndex] : nil
        }
        var isCurrent: Bool { self.hostIsCurrent() && self.snapshot.isCurrent() }
        func px(_ value: Int32) -> Int32 { MulDiv(value, Int32(self.dpi), 96) }
        func text(_ key: String) -> String { self.localization.text(key) }
        func seriesTitle(_ series: PlanUtilizationHistoryChart.Series) -> String {
            let key = "plan_history_series_" + series.name
            let label = self.text(key)
            var title = label == key ? series.name : label
            if let provider = self.snapshot.providerID.firstPartyProvider {
                let metadata = ProviderDescriptorRegistry.descriptor(for: provider).metadata
                let providerLabel: String? = switch series.name {
                case "session": metadata.sessionLabel == "Session" ? nil : metadata.sessionLabel
                case "weekly": metadata.weeklyLabel == "Weekly" ? nil : metadata.weeklyLabel
                case "monthly": metadata.opusLabel
                case "opus": metadata.opusLabel
                default: nil
                }
                if let providerLabel { title = self.text(providerLabel) }
            }
            let number = NumberFormatter()
            number.locale = Locale(identifier: self.localization.language)
            number.numberStyle = .decimal
            let minutes = number.string(from: NSNumber(value: series.windowMinutes)) ?? String(series.windowMinutes)
            return self.text("plan_history_seriesTitle").replacingOccurrences(of: "{series}", with: title)
                .replacingOccurrences(of: "{minutes}", with: minutes)
        }
        func date(_ date: Date, short: Bool = false) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: self.localization.language)
            formatter.timeZone = .current
            formatter.setLocalizedDateFormatFromTemplate(short ? "MMM d" : "yMMMdjm")
            return formatter.string(from: date)
        }
        func pointText(_ point: PlanUtilizationHistoryChart.Point) -> String {
            let value: String
            if point.isObserved {
                let formatter = NumberFormatter()
                formatter.locale = Locale(identifier: self.localization.language)
                formatter.numberStyle = .percent
                formatter.maximumFractionDigits = 1
                value = formatter.string(from: NSNumber(value: point.usedPercent / 100)) ?? "\(point.usedPercent)%"
            } else { value = self.text("plan_history_missing") }
            return "\(self.date(point.date)): \(value)"
        }
    }
    private static let className = "CodexBar.PlanUtilizationHistoryDialog"
    private static let controlIDs: [Int32] = [10, 11, 6, 4, 5, 7, 2, 3]

    static func show(owner: HWND, snapshot: WindowsPlanUtilizationHistorySnapshot,
                     isCurrent: @escaping @Sendable () -> Bool) -> Result? {
        let context = Context(snapshot: snapshot, isCurrent: isCurrent)
        defer { if let font = context.font { DeleteObject(font) } }
        guard context.isCurrent else { return .invalidated }
        var klass = WNDCLASSEXW()
        klass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        klass.hInstance = GetModuleHandleW(nil)
        klass.hCursor = LoadCursorW(nil, IDC_ARROW)
        klass.lpfnWndProc = Self.windowProc
        let name = Array(Self.className.utf16) + [UInt16(0)]
        let registered = name.withUnsafeBufferPointer { klass.lpszClassName = $0.baseAddress; return RegisterClassExW(&klass) }
        guard registered != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS else { return nil }
        let title = Array((snapshot.title + " — " + context.text("plan_history_title")).utf16) + [UInt16(0)]
        let hwnd = name.withUnsafeBufferPointer { n in title.withUnsafeBufferPointer { t in
            CreateWindowExW(DWORD(WS_EX_DLGMODALFRAME), n.baseAddress, t.baseAddress,
                DWORD(WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN), Int32(bitPattern: 0x80000000),
                Int32(bitPattern: 0x80000000), 960, 720, owner, nil, GetModuleHandleW(nil),
                Unmanaged.passUnretained(context).toOpaque())
        } }
        guard let hwnd else { return nil }
        var monitor = MONITORINFO()
        monitor.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        if GetMonitorInfoW(MonitorFromWindow(owner, DWORD(MONITOR_DEFAULTTONEAREST)), &monitor) != 0 {
            let area = monitor.rcWork
            let width = min(context.px(960), area.right - area.left)
            let height = min(context.px(720), area.bottom - area.top)
            SetWindowPos(hwnd, nil, area.left + (area.right - area.left - width) / 2,
                area.top + (area.bottom - area.top - height) / 2, width, height, UINT(SWP_NOZORDER))
        }
        let wasEnabled = IsWindowEnabled(owner) != 0
        guard context.isCurrent else { DestroyWindow(hwnd); return .invalidated }
        EnableWindow(owner, 0)
        ShowWindow(hwnd, Int32(SW_SHOW)); UpdateWindow(hwnd)
        SetFocus(GetDlgItem(hwnd, 2))
        var message = MSG()
        while !context.closed {
            let status = GetMessageW(&message, nil, 0, 0)
            if status == -1 { context.failed = true; break }
            if status == 0 { PostQuitMessage(Int32(message.wParam)); break }
            if Self.closeIfInvalid(hwnd, context: context) { break }
            if message.message == UINT(WM_KEYDOWN), message.hwnd == hwnd || IsChild(hwnd, message.hwnd) != 0 {
                if message.wParam == WPARAM(VK_ESCAPE) { DestroyWindow(hwnd); continue }
                let focus = GetFocus()
                if focus == GetDlgItem(hwnd, 6), message.wParam == WPARAM(0x41), GetKeyState(Int32(VK_CONTROL)) < 0 {
                    SendMessageW(focus, UINT(EM_SETSEL), 0, -1); continue
                }
                if focus != GetDlgItem(hwnd, 6), focus != GetDlgItem(hwnd, 11) {
                    if message.wParam == WPARAM(VK_LEFT) { Self.select(-1, hwnd: hwnd, context: context); continue }
                    if message.wParam == WPARAM(VK_RIGHT) { Self.select(1, hwnd: hwnd, context: context); continue }
                    if message.wParam == WPARAM(VK_HOME), let series = context.series, !series.points.isEmpty {
                        context.selectedIndex = 0; Self.updateDetails(hwnd, context: context); continue
                    }
                    if message.wParam == WPARAM(VK_END), let series = context.series, !series.points.isEmpty {
                        context.selectedIndex = series.points.count - 1; Self.updateDetails(hwnd, context: context); continue
                    }
                }
            }
            if IsDialogMessageW(hwnd, &message) == 0 { TranslateMessage(&message); DispatchMessageW(&message) }
        }
        if IsWindow(hwnd) != 0 { DestroyWindow(hwnd) }
        if IsWindow(owner) != 0, wasEnabled { EnableWindow(owner, 1); SetForegroundWindow(owner) }
        return context.failed ? nil : context.result
    }

    private static func closeIfInvalid(_ hwnd: HWND, context: Context) -> Bool {
        guard !context.isCurrent else { return false }
        context.result = .invalidated
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
            guard Self.control(hwnd, kind: "STATIC", title: context.text("plan_history_seriesLabel"), id: 10,
                style: DWORD(WS_CHILD | WS_VISIBLE)) != nil,
                  let combo = Self.control(hwnd, kind: "COMBOBOX", title: "", id: 11,
                    style: DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_VSCROLL | CBS_DROPDOWNLIST)),
                  Self.control(hwnd, kind: "EDIT", title: "", id: 6,
                    style: DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_BORDER | WS_VSCROLL | ES_MULTILINE | ES_READONLY)) != nil else { return -1 }
            for (index, series) in context.snapshot.series.enumerated() {
                let inserted = context.seriesTitle(series).withCString(encodedAs: UTF16.self) {
                    SendMessageW(combo, UINT(CB_ADDSTRING), 0, LPARAM(Int(bitPattern: $0)))
                }
                guard inserted == LRESULT(index) else { return -1 }
            }
            if !context.snapshot.series.isEmpty, SendMessageW(combo, UINT(CB_SETCURSEL), 0, 0) != 0 { return -1 }
            for (id, key) in [(Int32(4), "plan_history_previous"), (Int32(5), "plan_history_next"),
                              (Int32(7), "plan_history_clear"), (Int32(2), "plan_history_close"),
                              (Int32(3), "plan_history_refresh")] {
                guard Self.control(hwnd, kind: "BUTTON", title: context.text(key), id: id,
                    style: DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON)) != nil else { return -1 }
            }
            guard SetTimer(hwnd, 1, 250, nil) != 0 else { return -1 }
            Self.updateFont(hwnd, context: context)
            Self.layout(hwnd, context: context); Self.updateDetails(hwnd, context: context)
            return 0
        case UINT(WM_TIMER): _ = Self.closeIfInvalid(hwnd, context: context); return 0
        case UINT(WM_GETMINMAXINFO):
            if let info = UnsafeMutableRawPointer(bitPattern: UInt(lParam))?.assumingMemoryBound(to: MINMAXINFO.self) {
                var monitor = MONITORINFO()
                monitor.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
                if GetMonitorInfoW(MonitorFromWindow(hwnd, DWORD(MONITOR_DEFAULTTONEAREST)), &monitor) != 0 {
                    info.pointee.ptMinTrackSize.x = min(context.px(640), monitor.rcWork.right - monitor.rcWork.left)
                    info.pointee.ptMinTrackSize.y = min(context.px(540), monitor.rcWork.bottom - monitor.rcWork.top)
                }
            }
            return 0
        case UINT(WM_SIZE): Self.layout(hwnd, context: context); return 0
        case UINT(WM_DPICHANGED):
            let dpi = UINT(wParam & 0xffff); if dpi != 0 { context.dpi = dpi }
            if let value = UnsafeRawPointer(bitPattern: UInt(lParam))?.assumingMemoryBound(to: RECT.self) {
                let rect = value.pointee
                SetWindowPos(hwnd, nil, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top,
                    UINT(SWP_NOZORDER | SWP_NOACTIVATE))
            }
            Self.updateFont(hwnd, context: context); Self.layout(hwnd, context: context); return 0
        case UINT(WM_SETTINGCHANGE), UINT(WM_SYSCOLORCHANGE), UINT(WM_THEMECHANGED):
            Self.updateFont(hwnd, context: context); InvalidateRect(hwnd, nil, 1); return 0
        case UINT(WM_PAINT):
            if !Self.closeIfInvalid(hwnd, context: context) { Self.paint(hwnd, context: context) }
            return 0
        case UINT(WM_COMMAND):
            if Self.closeIfInvalid(hwnd, context: context) { return 0 }
            switch Int32(wParam & 0xffff) {
            case 2: DestroyWindow(hwnd); return 0
            case 3: context.result = .refresh; DestroyWindow(hwnd); return 0
            case 4: Self.select(-1, hwnd: hwnd, context: context); return 0
            case 5: Self.select(1, hwnd: hwnd, context: context); return 0
            case 7: context.selectedIndex = nil
            case 11:
                guard UINT((wParam >> 16) & 0xffff) == UINT(CBN_SELCHANGE) else { return 0 }
                let selected = Int(SendMessageW(GetDlgItem(hwnd, 11), UINT(CB_GETCURSEL), 0, 0))
                guard context.snapshot.series.indices.contains(selected) else { return 0 }
                context.seriesIndex = selected; context.selectedIndex = nil
            default: return 0
            }
            Self.updateDetails(hwnd, context: context); return 0
        case UINT(WM_MOUSEMOVE), UINT(WM_LBUTTONUP):
            if Self.closeIfInvalid(hwnd, context: context) { return 0 }
            let x = Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: lParam)))
            let y = Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: lParam >> 16)))
            let bounds = Self.plotBounds(hwnd, context: context)
            if x >= bounds.left, x < bounds.right, y >= bounds.top, y < bounds.bottom, let series = context.series {
                let index = Int(Double(x - bounds.left) / Double(max(1, bounds.right - bounds.left)) *
                    Double(PlanUtilizationHistoryChart.maximumPoints))
                let selected = series.points.indices.contains(index) ? index : nil
                if context.selectedIndex != selected {
                    context.selectedIndex = selected
                    Self.updateDetails(hwnd, context: context)
                }
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
        let margin = context.px(16), gap = context.px(8), height = context.px(32)
        let width = max(1, rect.right - 2 * margin)
        MoveWindow(GetDlgItem(hwnd, 10), margin, margin, context.px(100), height, 1)
        MoveWindow(GetDlgItem(hwnd, 11), margin + context.px(108), margin, max(1, width - context.px(108)), context.px(230), 1)
        let bottom = max(margin, rect.bottom - margin - height)
        let buttonWidth = max(1, (width - gap) / 2)
        for (index, id) in [Int32(2), Int32(3)].enumerated() {
            MoveWindow(GetDlgItem(hwnd, id), margin + Int32(index) * (buttonWidth + gap), bottom, buttonWidth, height, 1)
        }
        let navigation = max(margin, bottom - height - gap)
        let navigationWidth = max(1, (width - 2 * gap) / 3)
        for (index, id) in [Int32(4), Int32(5), Int32(7)].enumerated() {
            MoveWindow(GetDlgItem(hwnd, id), margin + Int32(index) * (navigationWidth + gap), navigation, navigationWidth, height, 1)
        }
        let detailsTop = max(context.px(140), navigation - gap - context.px(190))
        MoveWindow(GetDlgItem(hwnd, 6), margin, detailsTop, width, max(1, navigation - gap - detailsTop), 1)
        InvalidateRect(hwnd, nil, 1)
    }

    private static func select(_ direction: Int, hwnd: HWND, context: Context) {
        guard let series = context.series, !series.points.isEmpty else { return }
        if let selected = context.selectedIndex { context.selectedIndex = max(0, min(series.points.count - 1, selected + direction)) }
        else { context.selectedIndex = direction < 0 ? series.points.count - 1 : 0 }
        Self.updateDetails(hwnd, context: context)
    }

    private static func updateDetails(_ hwnd: HWND, context: Context) {
        var lines = [context.text("plan_history_capture").replacingOccurrences(of: "{date}", with: context.date(context.snapshot.usageCapturedAt)),
                     context.text("plan_history_legend")]
        if context.snapshot.restoredExactOwnership { lines.append(context.text("plan_history_recoveryExact")) }
        if let series = context.series, !series.points.isEmpty {
            lines.append(context.seriesTitle(series))
            if series.name == "weekly", series.windowMinutes == SessionEquivalentForecastCore.weeklyWindowMinutes,
               let forecast = context.snapshot.sessionEquivalentForecast {
                lines.append(context.text("plan_forecast_asOf").replacingOccurrences(of: "{date}",
                    with: context.date(context.snapshot.loadedAt)))
                lines.append(contentsOf: WindowsSessionEquivalentForecastText.lines(
                    forecast, workDays: context.snapshot.forecastWorkDays, localization: context.localization))
            }
            if let index = context.selectedIndex, series.points.indices.contains(index) {
                lines.append(context.text("plan_history_selected") + " " + context.pointText(series.points[index]))
            } else { lines.append(context.text("plan_history_selectHint")) }
            lines.append("")
            lines.append(contentsOf: series.points.map(context.pointText))
        } else { lines.append(context.text("plan_history_empty")) }
        let updated = lines.joined(separator: "\r\n").withCString(encodedAs: UTF16.self) {
            SetWindowTextW(GetDlgItem(hwnd, 6), $0)
        }
        guard updated != 0 else { context.failed = true; DestroyWindow(hwnd); return }
        let count = context.series?.points.count ?? 0
        EnableWindow(GetDlgItem(hwnd, 11), context.snapshot.series.count > 1 ? 1 : 0)
        EnableWindow(GetDlgItem(hwnd, 4), count > 0 && context.selectedIndex != 0 ? 1 : 0)
        EnableWindow(GetDlgItem(hwnd, 5), count > 0 && context.selectedIndex != count - 1 ? 1 : 0)
        EnableWindow(GetDlgItem(hwnd, 7), context.selectedIndex != nil ? 1 : 0)
        InvalidateRect(hwnd, nil, 1)
    }

    private static func plotBounds(_ hwnd: HWND, context: Context) -> RECT {
        var area = RECT(); GetClientRect(hwnd, &area)
        return RECT(left: context.px(62), top: context.px(72), right: max(context.px(63), area.right - context.px(22)),
            bottom: max(context.px(92), area.bottom - context.px(328)))
    }

    private static func paint(_ hwnd: HWND, context: Context) {
        var paint = PAINTSTRUCT()
        guard let dc = BeginPaint(hwnd, &paint) else { return }
        defer { EndPaint(hwnd, &paint) }
        FillRect(dc, &paint.rcPaint, GetSysColorBrush(COLOR_WINDOW))
        let previousFont = context.font.flatMap { SelectObject(dc, $0) }
        defer { if let previousFont { SelectObject(dc, previousFont) } }
        SetBkMode(dc, Int32(TRANSPARENT)); SetTextColor(dc, GetSysColor(COLOR_WINDOWTEXT))
        func text(_ label: String, _ rect: RECT) {
            var rect = rect, value = Array(label.utf16) + [UInt16(0)]
            value.withUnsafeMutableBufferPointer { _ = DrawTextW(dc, $0.baseAddress, -1, &rect, UINT(DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX)) }
        }
        let bounds = Self.plotBounds(hwnd, context: context)
        guard let series = context.series, !series.points.isEmpty else { text(context.text("plan_history_empty"), bounds); return }
        let width = Double(bounds.right - bounds.left), height = Double(bounds.bottom - bounds.top)
        let slots = Double(PlanUtilizationHistoryChart.maximumPoints)
        for percent in [0, 50, 100] {
            let y = bounds.bottom - Int32(height * Double(percent) / 100)
            text("\(percent)%", RECT(left: context.px(8), top: y - context.px(10), right: bounds.left - 4, bottom: y + context.px(14)))
            var line = RECT(left: bounds.left, top: y, right: bounds.right, bottom: y + 1)
            FillRect(dc, &line, GetSysColorBrush(COLOR_3DSHADOW))
        }
        for point in series.points {
            let left = bounds.left + Int32(width * (Double(point.index) + 0.2) / slots)
            let right = max(left + 1, bounds.left + Int32(width * (Double(point.index) + 0.8) / slots))
            var track = RECT(left: left, top: bounds.top, right: right, bottom: bounds.bottom)
            if point.isObserved {
                FillRect(dc, &track, GetSysColorBrush(COLOR_3DFACE))
                var bar = RECT(left: left, top: bounds.bottom - max(context.px(2), Int32(height * point.usedPercent / 100)),
                    right: right, bottom: bounds.bottom)
                FillRect(dc, &bar, GetSysColorBrush(COLOR_HIGHLIGHT))
            } else {
                text("–", RECT(left: left, top: bounds.bottom - context.px(19), right: right, bottom: bounds.bottom + 2))
            }
            if context.selectedIndex == point.index { FrameRect(dc, &track, GetSysColorBrush(COLOR_WINDOWTEXT)) }
        }
        for index in series.axisIndexes where series.points.indices.contains(index) {
            let x = bounds.left + Int32(width * (Double(index) + 0.5) / slots)
            let labelWidth = min(context.px(94), bounds.right - bounds.left)
            let left = max(bounds.left, min(bounds.right - labelWidth, x - labelWidth / 2))
            text(context.date(series.points[index].date, short: true),
                RECT(left: left, top: bounds.bottom + context.px(8), right: left + labelWidth, bottom: bounds.bottom + context.px(32)))
        }
    }

    private static func updateFont(_ hwnd: HWND, context: Context) {
        var metrics = NONCLIENTMETRICSW()
        metrics.cbSize = UINT(MemoryLayout<NONCLIENTMETRICSW>.size)
        guard SystemParametersInfoForDpi(UINT(SPI_GETNONCLIENTMETRICS), metrics.cbSize, &metrics, 0, context.dpi) != 0,
              let font = CreateFontIndirectW(&metrics.lfMessageFont) else { return }
        let previous = context.font
        context.font = font
        for id in Self.controlIDs { SendMessageW(GetDlgItem(hwnd, id), UINT(WM_SETFONT), WPARAM(Int(bitPattern: font)), 1) }
        if let previous { DeleteObject(previous) }
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
