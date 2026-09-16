#if os(Windows)
import Foundation
import WinSDK

/// No candidate or declaration is preselected. Raw account keys never enter UI controls.
enum WindowsPlanHistoryOwnershipDialog {
    enum Result { case cancelled, invalidated, failed, selected(UUID) }
    private static let className = "CodexBar.PlanHistoryOwnershipDialog"
    private final class Context {
        let review: WindowsPlanHistoryOwnershipReview
        let hostIsCurrent: @Sendable () -> Bool
        let localization = WindowsStatusLocalization.Snapshot()
        var selected: Int?
        var result: Result = .cancelled
        var closed = false
        var dpi: UINT = 96
        var font: HFONT?
        init(review: WindowsPlanHistoryOwnershipReview, isCurrent: @escaping @Sendable () -> Bool) {
            self.review = review; self.hostIsCurrent = isCurrent
        }
        var isCurrent: Bool { self.hostIsCurrent() && self.review.isCurrent() }
        func px(_ value: Int32) -> Int32 { MulDiv(value, Int32(self.dpi), 96) }
        func text(_ key: String) -> String { self.localization.text(key) }
        func number(_ value: Int) -> String {
            let formatter = NumberFormatter(); formatter.locale = Locale(identifier: self.localization.language)
            formatter.numberStyle = .decimal
            return formatter.string(from: NSNumber(value: value)) ?? String(value)
        }
        func date(_ value: Date?) -> String {
            guard let value else { return self.text("history_owner_noDate") }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: self.localization.language)
            formatter.timeZone = .current; formatter.setLocalizedDateFormatFromTemplate("yMMMdjm")
            return formatter.string(from: value)
        }
        func label(_ index: Int) -> String {
            let candidate = self.review.candidates[index]
            return self.text(candidate.unassigned ? "history_owner_unassigned" : "history_owner_group")
                .replacingOccurrences(of: "{number}", with: self.number(index + 1)) + " · " + String(candidate.fingerprint.prefix(16))
        }
    }

    static func show(owner: HWND, review: WindowsPlanHistoryOwnershipReview,
                     isCurrent: @escaping @Sendable () -> Bool) -> Result {
        let context = Context(review: review, isCurrent: isCurrent)
        defer { if let font = context.font { DeleteObject(font) } }
        guard context.isCurrent else { return .invalidated }
        var klass = WNDCLASSEXW()
        klass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        klass.hInstance = GetModuleHandleW(nil); klass.hCursor = LoadCursorW(nil, IDC_ARROW)
        klass.hbrBackground = GetSysColorBrush(COLOR_WINDOW); klass.lpfnWndProc = Self.windowProc
        let name = Array(Self.className.utf16) + [UInt16(0)]
        let registered = name.withUnsafeBufferPointer { klass.lpszClassName = $0.baseAddress; return RegisterClassExW(&klass) }
        guard registered != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS else { return .failed }
        let title = Array(context.text("history_owner_title").utf16) + [UInt16(0)]
        let window = name.withUnsafeBufferPointer { n in title.withUnsafeBufferPointer { t in
            CreateWindowExW(DWORD(WS_EX_DLGMODALFRAME), n.baseAddress, t.baseAddress,
                DWORD(WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN), Int32(bitPattern: 0x80000000),
                Int32(bitPattern: 0x80000000), 760, 640, owner, nil, GetModuleHandleW(nil),
                Unmanaged.passUnretained(context).toOpaque())
        } }
        guard let window else { return .failed }
        var monitor = MONITORINFO(); monitor.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        if GetMonitorInfoW(MonitorFromWindow(owner, DWORD(MONITOR_DEFAULTTONEAREST)), &monitor) != 0 {
            let area = monitor.rcWork
            let width = min(context.px(760), area.right - area.left), height = min(context.px(640), area.bottom - area.top)
            SetWindowPos(window, nil, area.left + (area.right - area.left - width) / 2,
                area.top + (area.bottom - area.top - height) / 2, width, height, UINT(SWP_NOZORDER))
        }
        let wasEnabled = IsWindowEnabled(owner) != 0
        guard context.isCurrent else { DestroyWindow(window); return .invalidated }
        EnableWindow(owner, 0); ShowWindow(window, Int32(SW_SHOW)); UpdateWindow(window)
        SetFocus(GetDlgItem(window, 11))
        var message = MSG()
        while !context.closed {
            let status = GetMessageW(&message, nil, 0, 0)
            if status == -1 { context.result = .failed; break }
            if status == 0 { PostQuitMessage(Int32(message.wParam)); break }
            if Self.closeIfInvalid(window, context: context) { break }
            if message.message == UINT(WM_KEYDOWN), message.hwnd == window || IsChild(window, message.hwnd) != 0 {
                if message.wParam == WPARAM(VK_ESCAPE) { DestroyWindow(window); continue }
                if GetFocus() == GetDlgItem(window, 12), message.wParam == WPARAM(0x41), GetKeyState(Int32(VK_CONTROL)) < 0 {
                    SendMessageW(GetDlgItem(window, 12), UINT(EM_SETSEL), 0, -1); continue
                }
            }
            if IsDialogMessageW(window, &message) == 0 { TranslateMessage(&message); DispatchMessageW(&message) }
        }
        if IsWindow(window) != 0 { DestroyWindow(window) }
        if IsWindow(owner) != 0, wasEnabled { EnableWindow(owner, 1); SetForegroundWindow(owner) }
        return context.result
    }

    private static func closeIfInvalid(_ hwnd: HWND, context: Context) -> Bool {
        guard !context.isCurrent else { return false }
        context.result = .invalidated; ShowWindow(hwnd, Int32(SW_HIDE)); DestroyWindow(hwnd)
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
            let base = DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP)
            guard Self.control(hwnd, kind: "STATIC", text: context.text("history_owner_source"), id: 10,
                style: DWORD(WS_CHILD | WS_VISIBLE)) != nil,
                  let combo = Self.control(hwnd, kind: "COMBOBOX", text: "", id: 11,
                    style: base | DWORD(WS_VSCROLL | CBS_DROPDOWNLIST)),
                  Self.control(hwnd, kind: "EDIT", text: "", id: 12,
                    style: base | DWORD(WS_BORDER | WS_VSCROLL | ES_MULTILINE | ES_READONLY)) != nil,
                  Self.control(hwnd, kind: "BUTTON", text: context.text("history_owner_ack"), id: 13,
                    style: base | DWORD(BS_AUTOCHECKBOX | BS_MULTILINE)) != nil,
                  Self.control(hwnd, kind: "BUTTON", text: context.text("history_owner_apply"), id: 1,
                    style: base | DWORD(BS_PUSHBUTTON)) != nil,
                  Self.control(hwnd, kind: "BUTTON", text: context.text("history_owner_cancel"), id: 2,
                    style: base | DWORD(BS_DEFPUSHBUTTON)) != nil else { return -1 }
            for index in context.review.candidates.indices {
                let inserted = context.label(index).withCString(encodedAs: UTF16.self) {
                    SendMessageW(combo, UINT(CB_ADDSTRING), 0, LPARAM(Int(bitPattern: $0)))
                }
                guard inserted == LRESULT(index) else { return -1 }
            }
            guard SetTimer(hwnd, 1, 250, nil) != 0 else { return -1 }
            Self.updateFont(hwnd, context: context); Self.layout(hwnd, context: context); Self.update(hwnd, context: context)
            return 0
        case UINT(WM_TIMER): _ = Self.closeIfInvalid(hwnd, context: context); return 0
        case UINT(WM_COMMAND):
            if Self.closeIfInvalid(hwnd, context: context) { return 0 }
            switch Int32(wParam & 0xffff) {
            case 2: DestroyWindow(hwnd)
            case 1:
                guard let index = context.selected, context.review.candidates.indices.contains(index),
                      SendMessageW(GetDlgItem(hwnd, 13), UINT(BM_GETCHECK), 0, 0) == LRESULT(BST_CHECKED) else { return 0 }
                context.result = .selected(context.review.candidates[index].id); DestroyWindow(hwnd)
            case 11:
                guard UINT((wParam >> 16) & 0xffff) == UINT(CBN_SELCHANGE) else { return 0 }
                let index = Int(SendMessageW(GetDlgItem(hwnd, 11), UINT(CB_GETCURSEL), 0, 0))
                context.selected = context.review.candidates.indices.contains(index) ? index : nil
                SendMessageW(GetDlgItem(hwnd, 13), UINT(BM_SETCHECK), WPARAM(BST_UNCHECKED), 0)
                Self.update(hwnd, context: context)
            case 13: Self.update(hwnd, context: context)
            default: break
            }
            return 0
        case UINT(WM_GETMINMAXINFO):
            if let info = UnsafeMutableRawPointer(bitPattern: UInt(lParam))?.assumingMemoryBound(to: MINMAXINFO.self) {
                var monitor = MONITORINFO(); monitor.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
                if GetMonitorInfoW(MonitorFromWindow(hwnd, DWORD(MONITOR_DEFAULTTONEAREST)), &monitor) != 0 {
                    info.pointee.ptMinTrackSize.x = min(context.px(520), monitor.rcWork.right - monitor.rcWork.left)
                    info.pointee.ptMinTrackSize.y = min(context.px(440), monitor.rcWork.bottom - monitor.rcWork.top)
                }
            }
            return 0
        case UINT(WM_SIZE): Self.layout(hwnd, context: context); return 0
        case UINT(WM_DPICHANGED):
            let dpi = UINT(wParam & 0xffff); if dpi != 0 { context.dpi = dpi }
            if let rect = UnsafeRawPointer(bitPattern: UInt(lParam))?.assumingMemoryBound(to: RECT.self) {
                let value = rect.pointee
                SetWindowPos(hwnd, nil, value.left, value.top, value.right - value.left, value.bottom - value.top,
                    UINT(SWP_NOZORDER | SWP_NOACTIVATE))
            }
            Self.updateFont(hwnd, context: context); Self.layout(hwnd, context: context); return 0
        case UINT(WM_SETTINGCHANGE), UINT(WM_THEMECHANGED), UINT(WM_SYSCOLORCHANGE):
            Self.updateFont(hwnd, context: context); InvalidateRect(hwnd, nil, 1); return 0
        case UINT(WM_CLOSE): DestroyWindow(hwnd); return 0
        case UINT(WM_DESTROY): KillTimer(hwnd, 1); context.closed = true; return 0
        default: return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }

    private static func update(_ hwnd: HWND, context: Context) {
        var lines = [context.text("history_owner_target").replacingOccurrences(of: "{account}", with: Self.display(context.review.targetTitle)),
                     context.text("history_owner_guidance")]
        if let index = context.selected, context.review.candidates.indices.contains(index) {
            let candidate = context.review.candidates[index]
            lines += [context.label(index), context.text("history_owner_fingerprint") + ": " + candidate.fingerprint]
            for series in candidate.series {
                let name = String(Self.display(series.name).prefix(120))
                lines.append(context.text("history_owner_series").replacingOccurrences(of: "{series}", with: name)
                    .replacingOccurrences(of: "{minutes}", with: context.number(series.minutes))
                    .replacingOccurrences(of: "{count}", with: context.number(series.count))
                    .replacingOccurrences(of: "{first}", with: context.date(series.first))
                    .replacingOccurrences(of: "{last}", with: context.date(series.last)))
            }
        } else { lines.append(context.text("history_owner_choose")) }
        lines += [context.text("history_owner_fileHash") + ": " + context.review.documentSHA256]
        lines.joined(separator: "\r\n\r\n").withCString(encodedAs: UTF16.self) { SetWindowTextW(GetDlgItem(hwnd, 12), $0) }
        let checked = SendMessageW(GetDlgItem(hwnd, 13), UINT(BM_GETCHECK), 0, 0) == LRESULT(BST_CHECKED)
        EnableWindow(GetDlgItem(hwnd, 1), context.selected != nil && checked ? 1 : 0)
    }

    private static func layout(_ hwnd: HWND, context: Context) {
        var rect = RECT(); GetClientRect(hwnd, &rect)
        let margin = context.px(16), gap = context.px(8), height = context.px(32)
        let width = max(1, rect.right - 2 * margin), bottom = max(margin, rect.bottom - margin - height)
        MoveWindow(GetDlgItem(hwnd, 10), margin, margin, width, context.px(24), 1)
        MoveWindow(GetDlgItem(hwnd, 11), margin, margin + context.px(28), width, context.px(240), 1)
        let top = margin + context.px(68), ack = max(top + height, bottom - context.px(56) - gap)
        MoveWindow(GetDlgItem(hwnd, 12), margin, top, width, max(1, ack - gap - top), 1)
        MoveWindow(GetDlgItem(hwnd, 13), margin, ack, width, context.px(56), 1)
        let buttonWidth = max(1, (width - gap) / 2)
        MoveWindow(GetDlgItem(hwnd, 1), margin, bottom, buttonWidth, height, 1)
        MoveWindow(GetDlgItem(hwnd, 2), margin + buttonWidth + gap, bottom, buttonWidth, height, 1)
    }

    private static func updateFont(_ hwnd: HWND, context: Context) {
        var metrics = NONCLIENTMETRICSW(); metrics.cbSize = UINT(MemoryLayout<NONCLIENTMETRICSW>.size)
        guard SystemParametersInfoForDpi(UINT(SPI_GETNONCLIENTMETRICS), metrics.cbSize, &metrics, 0, context.dpi) != 0,
              let font = CreateFontIndirectW(&metrics.lfMessageFont) else { return }
        let previous = context.font; context.font = font
        for id in [Int32(1), 2, 10, 11, 12, 13] {
            SendMessageW(GetDlgItem(hwnd, id), UINT(WM_SETFONT), WPARAM(Int(bitPattern: font)), 1)
        }
        if let previous { DeleteObject(previous) }
    }

    private static func control(_ parent: HWND, kind: String, text: String, id: Int32, style: DWORD) -> HWND? {
        kind.withCString(encodedAs: UTF16.self) { klass in text.withCString(encodedAs: UTF16.self) { label in
            CreateWindowExW(0, klass, label, style, 0, 0, 1, 1, parent,
                HMENU(bitPattern: Int(id)), GetModuleHandleW(nil), nil)
        } }
    }

    private static func display(_ text: String) -> String {
        text.unicodeScalars.map { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: "u{" + String(scalar.value, radix: 16) + "}"
            default: String(scalar)
            }
        }.joined()
    }
}
#endif
