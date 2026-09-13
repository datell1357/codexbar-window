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
    private static let searchID: Int32 = 102
    private static let findID: Int32 = 5
    private static let searchLabelID: Int32 = 103
    private static let sectionID: Int32 = 104
    private static let filterID: Int32 = 105
    private static let filterLabelID: Int32 = 106
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
        let isCurrent: @Sendable () -> Bool
        let text: String
        let expandedText: String?
        let sections: [WindowsSnapshotSection]
        var selectedSection: Int? = nil
        var visibleSections: [Int] = []
        var displayedText: String {
            if let selectedSection, self.sections.indices.contains(selectedSection) {
                return self.sections[selectedSection].text
            }
            return self.expanded ? (self.expandedText ?? self.text) : self.text
        }
        var expanded = false
        var searchOffset = 0
        var searchQuery = ""
        let links: [Link]
        var result: Result = .closed
        var closed = false
        var dpi: UINT = 96
        var font: HFONT?
        deinit { if let font { DeleteObject(font) } }
        func pixels(_ value: Int32) -> Int32 { MulDiv(value, Int32(self.dpi), 96) }
        init(text: String, links: [Link], hidePersonalInfo: Bool, expandedText: String?, sections: [WindowsSnapshotSection], isCurrent: @escaping @Sendable () -> Bool) {
            self.sections = sections
            self.isCurrent = isCurrent
            self.expandedText = expandedText
            self.text = text; self.links = Array(links.prefix(3)); self.hidePersonalInfo = hidePersonalInfo
        }
    }

    static func show(owner: HWND, title: String, text: String, links: [Link], hidePersonalInfo: Bool, expandedText: String? = nil, sections: [WindowsSnapshotSection] = [], isCurrent: @escaping @Sendable () -> Bool = { true }) -> Result? {
        guard isCurrent(), hidePersonalInfo == WindowsUsagePresentationSettings.load().hidePersonalInfo else { return .privacyChanged }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        let expanded = expandedText?.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        let context = Context(text: normalized, links: links, hidePersonalInfo: hidePersonalInfo, expandedText: expanded, sections: sections, isCurrent: isCurrent)
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
                    if message.wParam == WPARAM(0x46), GetKeyState(Int32(VK_CONTROL)) < 0 {
                        SetFocus(GetDlgItem(hwnd, Self.searchID))
                        SendMessageW(GetDlgItem(hwnd, Self.searchID), UINT(EM_SETSEL), 0, -1)
                        continue
                    }
                    if message.wParam == WPARAM(VK_F3) ||
                        (message.wParam == WPARAM(VK_RETURN) && GetFocus() == GetDlgItem(hwnd, Self.searchID)) {
                        Self.findNext(hwnd, context: context)
                        continue
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
            guard Self.addControl(hwnd, "STATIC", "&Find:", Self.searchLabelID, DWORD(WS_CHILD | WS_VISIBLE)) != nil,
                  let search = Self.addControl(hwnd, "EDIT", "", Self.searchID,
                    DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_BORDER | ES_AUTOHSCROLL)),
                  Self.addControl(hwnd, "BUTTON", "Find &next", Self.findID,
                    DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON)) != nil else { return -1 }
            if !context.sections.isEmpty {
                guard Self.addControl(hwnd, "COMBOBOX", "", Self.sectionID,
                    DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_VSCROLL | CBS_DROPDOWNLIST)) != nil,
                    Self.addControl(hwnd, "STATIC", "Filter &items:", Self.filterLabelID,
                        DWORD(WS_CHILD | WS_VISIBLE)) != nil,
                    let filter = Self.addControl(hwnd, "EDIT", "", Self.filterID,
                        DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_BORDER | ES_AUTOHSCROLL)) else { return -1 }
                SendMessageW(filter, UINT(EM_SETLIMITTEXT), 256, 0)
                guard Self.filterSections(hwnd, context: context) else { return -1 }
            }
            SendMessageW(search, UINT(EM_SETLIMITTEXT), 256, 0)
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
            if command == Self.filterID, Int32((wParam >> 16) & 0xffff) == Int32(EN_CHANGE) {
                if !Self.filterSections(hwnd, context: context) { DestroyWindow(hwnd) }
                return 0
            }
            if command == Self.sectionID, Int32((wParam >> 16) & 0xffff) == Int32(CBN_SELCHANGE) {
                let selected = Int(SendMessageW(GetDlgItem(hwnd, Self.sectionID), UINT(CB_GETCURSEL), 0, 0))
                guard selected >= 0, selected <= context.visibleSections.count else { return 0 }
                context.selectedSection = selected == 0 ? nil : context.visibleSections[selected - 1]
                context.searchOffset = 0
                (Array(context.displayedText.utf16) + [0]).withUnsafeBufferPointer {
                    _ = SetWindowTextW(GetDlgItem(hwnd, Self.textID), $0.baseAddress)
                }
                EnableWindow(GetDlgItem(hwnd, Self.expandID), selected == 0 ? 1 : 0)
                SendMessageW(GetDlgItem(hwnd, Self.textID), UINT(EM_SETSEL), 0, 0)
                SendMessageW(GetDlgItem(hwnd, Self.textID), UINT(EM_SCROLLCARET), 0, 0)
                return 0
            }
            if command == Self.findID { Self.findNext(hwnd, context: context); return 0 }
            if command == Self.closeID { DestroyWindow(hwnd); return 0 }
            if command == Self.expandID, context.selectedSection == nil, let expandedText = context.expandedText {
                context.expanded.toggle()
                context.searchOffset = 0
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

    /// Filter only already-redacted titles; hidden paths and session identifiers are not searched.
    private static func filterSections(_ hwnd: HWND, context: Context) -> Bool {
        var buffer = [WCHAR](repeating: 0, count: 257)
        let count = buffer.withUnsafeMutableBufferPointer {
            GetWindowTextW(GetDlgItem(hwnd, Self.filterID), $0.baseAddress, Int32($0.count))
        }
        let query = String(decoding: buffer.prefix(max(0, Int(count))), as: UTF16.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        context.visibleSections = context.sections.indices.filter {
            query.isEmpty || context.sections[$0].title.localizedCaseInsensitiveContains(query)
        }
        let picker = GetDlgItem(hwnd, Self.sectionID)
        SendMessageW(picker, UINT(CB_RESETCONTENT), 0, 0)
        let summaryTitle = context.visibleSections.isEmpty
            ? "Summary — no matching items" : "Summary — \(context.visibleSections.count) matching items"
        for title in [summaryTitle] + context.visibleSections.map({ context.sections[$0].title }) {
            let added = (Array(title.utf16) + [0]).withUnsafeBufferPointer {
                SendMessageW(picker, UINT(CB_ADDSTRING), 0, LPARAM(Int(bitPattern: $0.baseAddress)))
            }
            guard added != LRESULT(CB_ERR), added != LRESULT(CB_ERRSPACE) else { return false }
        }
        let position = context.selectedSection.flatMap { context.visibleSections.firstIndex(of: $0) }
        if position == nil { context.selectedSection = nil }
        SendMessageW(picker, UINT(CB_SETCURSEL), WPARAM(position.map { $0 + 1 } ?? 0), 0)
        EnableWindow(GetDlgItem(hwnd, Self.expandID), context.selectedSection == nil ? 1 : 0)
        context.searchOffset = 0
        (Array(context.displayedText.utf16) + [0]).withUnsafeBufferPointer {
            _ = SetWindowTextW(GetDlgItem(hwnd, Self.textID), $0.baseAddress)
        }
        return true
    }

    /// NSString ranges match the UTF-16 offsets used by the native EDIT selection messages.
    private static func findNext(_ hwnd: HWND, context: Context) {
        guard !Self.closeForPrivacyIfNeeded(hwnd, context: context) else { return }
        var buffer = [WCHAR](repeating: 0, count: 257)
        let count = buffer.withUnsafeMutableBufferPointer {
            GetWindowTextW(GetDlgItem(hwnd, Self.searchID), $0.baseAddress, Int32($0.count))
        }
        guard count > 0 else { SetFocus(GetDlgItem(hwnd, Self.searchID)); return }
        let query = String(decoding: buffer.prefix(Int(count)), as: UTF16.self)
        if context.searchQuery != query { context.searchQuery = query; context.searchOffset = 0 }
        let body = context.displayedText as NSString
        let start = min(context.searchOffset, body.length)
        var match = body.range(of: query, options: [.caseInsensitive], range: NSRange(location: start, length: body.length - start))
        if match.location == NSNotFound, start > 0 {
            match = body.range(of: query, options: [.caseInsensitive], range: NSRange(location: 0, length: start))
        }
        let caption: String
        if match.location == NSNotFound {
            context.searchOffset = 0
            caption = "No match"
        } else {
            context.searchOffset = match.location + match.length
            SendMessageW(GetDlgItem(hwnd, Self.textID), UINT(EM_SETSEL), WPARAM(match.location), LPARAM(context.searchOffset))
            SendMessageW(GetDlgItem(hwnd, Self.textID), UINT(EM_SCROLLCARET), 0, 0)
            SetFocus(GetDlgItem(hwnd, Self.textID))
            caption = "Find &next"
        }
        (Array(caption.utf16) + [0]).withUnsafeBufferPointer {
            _ = SetWindowTextW(GetDlgItem(hwnd, Self.findID), $0.baseAddress)
        }
    }

    private static func closeForPrivacyIfNeeded(_ hwnd: HWND, context: Context) -> Bool {
        guard !context.closed else { return false }
        if !context.isCurrent() {
            context.result = .closed
            ShowWindow(hwnd, Int32(SW_HIDE))
            DestroyWindow(hwnd)
            return true
        }
        guard context.hidePersonalInfo != WindowsUsagePresentationSettings.load().hidePersonalInfo else { return false }
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
        for id in [Self.textID, Self.closeID, Self.refreshID, Self.expandID, Self.searchID, Self.findID, Self.searchLabelID, Self.sectionID, Self.filterID, Self.filterLabelID, Self.linkBaseID,
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
        let labelWidth = min(px(44), available)
        let findWidth = min(px(120), max(1, available - labelWidth))
        let searchWidth = max(1, available - labelWidth - findWidth - px(16))
        MoveWindow(GetDlgItem(hwnd, Self.searchLabelID), px(12), px(16), labelWidth, px(24), 1)
        MoveWindow(GetDlgItem(hwnd, Self.searchID), px(12) + labelWidth, px(12), searchWidth, px(28), 1)
        MoveWindow(GetDlgItem(hwnd, Self.findID), px(12) + available - findWidth, px(12), findWidth, px(28), 1)
        let contentTop: Int32 = context.sections.isEmpty ? 48 : 120
        if !context.sections.isEmpty {
            let filterLabelWidth = min(px(100), available)
            MoveWindow(GetDlgItem(hwnd, Self.filterLabelID), px(12), px(52), filterLabelWidth, px(24), 1)
            MoveWindow(GetDlgItem(hwnd, Self.filterID), px(12) + filterLabelWidth, px(48),
                max(1, available - filterLabelWidth), px(28), 1)
            MoveWindow(GetDlgItem(hwnd, Self.sectionID), px(12), px(84), available, px(260), 1)
        }
        MoveWindow(GetDlgItem(hwnd, Self.textID), px(12), px(contentTop), available,
                   max(1, top - px(contentTop + 12)), 1)
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
