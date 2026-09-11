#if os(Windows)
import Foundation
import WinSDK
import CodexBarCore

/// Native editor for one provider's session and weekly quota-warning overrides.
public enum WindowsProviderQuotaWarningDialog {
    public static func show(
        owner: HWND,
        providerName: String,
        session: WindowsProviderQuotaWarningLaneDraft,
        weekly: WindowsProviderQuotaWarningLaneDraft) -> WindowsProviderQuotaWarningPatch?
    {
        let context = Context(providerName: providerName, session: session, weekly: weekly)
        let instance = GetModuleHandleW(nil)
        var klass = WNDCLASSEXW()
        klass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        klass.hInstance = instance
        klass.lpfnWndProc = Self.windowProc
        klass.hCursor = LoadCursorW(nil, IDC_ARROW)
        let className = Array(Self.className.utf16) + [0]
        let registered = className.withUnsafeBufferPointer { name in
            klass.lpszClassName = name.baseAddress
            return RegisterClassExW(&klass)
        }
        if registered == 0, GetLastError() != ERROR_CLASS_ALREADY_EXISTS {
            Self.report("could not register provider quota-warning dialog class")
            return nil
        }
        let title = Array("Quota warnings — \(providerName)".utf16) + [0]
        var frame = RECT(left: 0, top: 0, right: 470, bottom: 330)
        AdjustWindowRectEx(&frame, DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX), 0,
                           DWORD(WS_EX_DLGMODALFRAME))
        let hwnd: HWND? = className.withUnsafeBufferPointer { name in
            title.withUnsafeBufferPointer { caption in
                CreateWindowExW(DWORD(WS_EX_DLGMODALFRAME), name.baseAddress, caption.baseAddress,
                                 DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX),
                                 0, 0, frame.right - frame.left, frame.bottom - frame.top, owner, nil,
                                 instance, Unmanaged.passUnretained(context).toOpaque())
            }
        }
        guard let hwnd else { Self.report("could not create provider quota-warning dialog"); return nil }
        context.window = hwnd
        context.ownerWasEnabled = IsWindowEnabled(owner) != 0
        Self.center(hwnd, owner: owner)
        if IsWindow(owner) != 0 { EnableWindow(owner, 0) }
        withExtendedLifetime(context) {
            ShowWindow(hwnd, Int32(SW_SHOW)); UpdateWindow(hwnd); SetFocus(GetDlgItem(hwnd, Self.sessionGlobalID))
            var message = MSG()
            while !context.closed {
                let result = GetMessageW(&message, nil, 0, 0)
                if result == -1 {
                    Self.report("provider quota-warning dialog message loop failed")
                    context.closed = true
                    break
                }
                if result == 0 {
                    // Repost WM_QUIT so the enclosing application loop also terminates.
                    PostQuitMessage(Int32(message.wParam)); context.closed = true; break
                }
                let target = message.hwnd == hwnd || IsChild(hwnd, message.hwnd) != 0
                if target, message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_ESCAPE) {
                    context.closed = true; DestroyWindow(hwnd); continue
                }
                if target, message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_RETURN) {
                    if GetFocus() == GetDlgItem(hwnd, Self.cancelID) { context.closed = true; DestroyWindow(hwnd) }
                    else { context.save() }
                    continue
                }
                if IsDialogMessageW(hwnd, &message) == 0 { TranslateMessage(&message); DispatchMessageW(&message) }
            }
        }
        if IsWindow(hwnd) != 0 { DestroyWindow(hwnd) }
        if IsWindow(owner) != 0, context.ownerWasEnabled { EnableWindow(owner, 1); SetForegroundWindow(owner) }
        return context.result
    }

    private static let className = "CodexBar.ProviderQuotaWarningDialog"
    private static let sessionGlobalID: Int32 = 101, sessionCustomID: Int32 = 102, sessionOffID: Int32 = 103
    private static let weeklyGlobalID: Int32 = 111, weeklyCustomID: Int32 = 112, weeklyOffID: Int32 = 113
    private static let sessionUpperID: Int32 = 121, sessionLowerID: Int32 = 122
    private static let weeklyUpperID: Int32 = 131, weeklyLowerID: Int32 = 132
    private static let saveID: Int32 = 1, cancelID: Int32 = 2

    private final class Context {
        let name: String
        var session: WindowsProviderQuotaWarningLaneDraft
        var weekly: WindowsProviderQuotaWarningLaneDraft
        var window: HWND?
        var result: WindowsProviderQuotaWarningPatch?
        var closed = false
        var ownerWasEnabled = false
        init(providerName: String, session: WindowsProviderQuotaWarningLaneDraft,
             weekly: WindowsProviderQuotaWarningLaneDraft) {
            self.name = providerName; self.session = session; self.weekly = weekly
        }
        func save() {
            guard let window, commitFields() else { return }
            result = WindowsProviderQuotaWarningPatch(session: session, weekly: weekly)
            closed = true; DestroyWindow(window)
        }
        func commitFields() -> Bool {
            guard let window else { return false }
            guard let s = Self.readPair(window, upperID: WindowsProviderQuotaWarningDialog.sessionUpperID,
                                        lowerID: WindowsProviderQuotaWarningDialog.sessionLowerID),
                  let w = Self.readPair(window, upperID: WindowsProviderQuotaWarningDialog.weeklyUpperID,
                                        lowerID: WindowsProviderQuotaWarningDialog.weeklyLowerID) else {
                Self.report("provider quota-warning thresholds must be empty or one/two digits")
                return false
            }
            if session.mode == .custom { session.setThresholds(upper: s.0, lower: s.1) }
            if weekly.mode == .custom { weekly.setThresholds(upper: w.0, lower: w.1) }
            return true
        }
        func select(_ mode: WindowsProviderQuotaWarningMode, weeklyLane: Bool) {
            guard commitFields() else {
                WindowsProviderQuotaWarningDialog.restoreSelection(window: window, session: session, weekly: weekly)
                return
            }
            if weeklyLane { weekly.selectMode(mode) } else { session.selectMode(mode) }
            WindowsProviderQuotaWarningDialog.updateControls(window: window, session: session, weekly: weekly)
        }
        private static func readPair(_ window: HWND, upperID: Int32, lowerID: Int32) -> (Int?, Int?)? {
            guard let upper = integerText(GetDlgItem(window, upperID)),
                  let lower = integerText(GetDlgItem(window, lowerID)) else {
                return nil
            }
            return (upper, lower)
        }
        private static func integerText(_ control: HWND?) -> Int?? {
            guard let control else { return nil }
            var buffer = [WCHAR](repeating: 0, count: 8)
            let count = GetWindowTextW(control, &buffer, Int32(buffer.count))
            let text = String(decoding: buffer.prefix(Int(count)), as: UTF16.CodeUnit.self)
            if text.isEmpty { return .some(nil) }
            guard text.count <= 2, text.allSatisfy(\.isNumber), let value = Int(text), value <= 99 else { return nil }
            return .some(value)
        }
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
        case UINT(WM_CREATE): return Self.createControls(hwnd, context: context) ? 0 : -1
        case UINT(WM_COMMAND):
            let command = Int32(wParam & 0xffff)
            switch command {
            case saveID: context.save()
            case cancelID: context.closed = true; DestroyWindow(hwnd)
            case sessionGlobalID: context.select(.global, weeklyLane: false)
            case sessionCustomID: context.select(.custom, weeklyLane: false)
            case sessionOffID: context.select(.off, weeklyLane: false)
            case weeklyGlobalID: context.select(.global, weeklyLane: true)
            case weeklyCustomID: context.select(.custom, weeklyLane: true)
            case weeklyOffID: context.select(.off, weeklyLane: true)
            default: break
            }
            return 0
        case UINT(WM_CLOSE): context.closed = true; DestroyWindow(hwnd); return 0
        case UINT(WM_NCDESTROY): context.closed = true; SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), 0); return 0
        default: return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }

    private static func createControls(_ hwnd: HWND, context: Context) -> Bool {
        let font = GetStockObject(DEFAULT_GUI_FONT)
        let controls: [HWND?] = [
            addLabel(hwnd, "Session window", 18, 18, 180, 22, font),
            addRadio(hwnd, "Global", sessionGlobalID, 18, 48, context.session.mode == .global, font),
            addRadio(hwnd, "Custom", sessionCustomID, 100, 48, context.session.mode == .custom, font),
            addRadio(hwnd, "Off", sessionOffID, 190, 48, context.session.mode == .off, font),
            addLabel(hwnd, "Upper", 285, 48, 70, 22, font),
            addEdit(hwnd, sessionUpperID, 340, 46, context.session.thresholds.first, font),
            addLabel(hwnd, "Lower", 285, 78, 70, 22, font),
            addEdit(hwnd, sessionLowerID, 340, 76, context.session.thresholds.dropFirst().first, font),
            addLabel(hwnd, "Weekly window", 18, 118, 180, 22, font),
            addRadio(hwnd, "Global", weeklyGlobalID, 18, 148, context.weekly.mode == .global, font),
            addRadio(hwnd, "Custom", weeklyCustomID, 100, 148, context.weekly.mode == .custom, font),
            addRadio(hwnd, "Off", weeklyOffID, 190, 148, context.weekly.mode == .off, font),
            addLabel(hwnd, "Upper", 285, 148, 70, 22, font),
            addEdit(hwnd, weeklyUpperID, 340, 146, context.weekly.thresholds.first, font),
            addLabel(hwnd, "Lower", 285, 178, 70, 22, font),
            addEdit(hwnd, weeklyLowerID, 340, 176, context.weekly.thresholds.dropFirst().first, font),
            addLabel(hwnd, "Custom thresholds override the global defaults.", 18, 220, 400, 22, font),
            addButton(hwnd, "Save", saveID, 270, 265, 80, 28, font),
            addButton(hwnd, "Cancel", cancelID, 360, 265, 80, 28, font),
        ]
        guard controls.allSatisfy({ $0 != nil }) else { return false }
        updateControls(window: hwnd, session: context.session, weekly: context.weekly)
        return true
    }

    private static func updateControls(window: HWND?, session: WindowsProviderQuotaWarningLaneDraft,
                                       weekly: WindowsProviderQuotaWarningLaneDraft) {
        guard let window else { return }
        let pairs: [(WindowsProviderQuotaWarningLaneDraft, Int32, Int32, Int32, Int32, Int32)] = [
            (session, sessionGlobalID, sessionCustomID, sessionOffID, sessionUpperID, sessionLowerID),
            (weekly, weeklyGlobalID, weeklyCustomID, weeklyOffID, weeklyUpperID, weeklyLowerID)
        ]
        for (draft, globalID, customID, offID, upperID, lowerID) in pairs {
            let modeID: Int32 = draft.mode == .global ? globalID : draft.mode == .custom ? customID : offID
            for id in [globalID, customID, offID] {
                SendMessageW(GetDlgItem(window, id), UINT(BM_SETCHECK),
                             WPARAM(id == modeID ? BST_CHECKED : BST_UNCHECKED), 0)
            }
            let editable = draft.mode == .custom
            EnableWindow(GetDlgItem(window, upperID), editable ? 1 : 0)
            EnableWindow(GetDlgItem(window, lowerID), editable ? 1 : 0)
            let values = [draft.thresholds.first, draft.thresholds.dropFirst().first]
            for (id, value) in zip([upperID, lowerID], values) {
                let text = Array((value.map(String.init) ?? "").utf16) + [0]
                text.withUnsafeBufferPointer { SetWindowTextW(GetDlgItem(window, id), $0.baseAddress) }
            }
        }
    }

    private static func restoreSelection(window: HWND?, session: WindowsProviderQuotaWarningLaneDraft,
                                         weekly: WindowsProviderQuotaWarningLaneDraft) {
        guard let window else { return }
        let lanes: [(WindowsProviderQuotaWarningLaneDraft, [Int32])] = [
            (session, [sessionGlobalID, sessionCustomID, sessionOffID]),
            (weekly, [weeklyGlobalID, weeklyCustomID, weeklyOffID])
        ]
        for (draft, ids) in lanes {
            let selected = draft.mode == .global ? 0 : draft.mode == .custom ? 1 : 2
            for (index, id) in ids.enumerated() {
                SendMessageW(GetDlgItem(window, id), UINT(BM_SETCHECK),
                             WPARAM(index == selected ? BST_CHECKED : BST_UNCHECKED), 0)
            }
        }
        for id in [sessionUpperID, sessionLowerID, weeklyUpperID, weeklyLowerID]
            where Context.integerText(GetDlgItem(window, id)) == nil {
            SetFocus(GetDlgItem(window, id)); break
        }
    }

    private static func addLabel(_ parent: HWND, _ text: String, _ x: Int32, _ y: Int32,
                                 _ width: Int32, _ height: Int32, _ font: HGDIOBJ?) -> HWND? {
        addControl(parent, "STATIC", text, 0, DWORD(WS_CHILD | WS_VISIBLE), x, y, width, height, font)
    }
    private static func addRadio(_ parent: HWND, _ text: String, _ id: Int32, _ x: Int32, _ y: Int32,
                                 _ checked: Bool, _ font: HGDIOBJ?) -> HWND? {
        let group: DWORD = (id == sessionGlobalID || id == weeklyGlobalID) ? DWORD(WS_GROUP) : 0
        let style = DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_AUTORADIOBUTTON) | group
        let control = addControl(parent, "BUTTON", text, id, style, x, y, 80, 24, font)
        SendMessageW(control, UINT(BM_SETCHECK), WPARAM(checked ? BST_CHECKED : BST_UNCHECKED), 0); return control
    }
    private static func addEdit(_ parent: HWND, _ id: Int32, _ x: Int32, _ y: Int32,
                                _ value: Int?, _ font: HGDIOBJ?) -> HWND? {
        let style = DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_BORDER | ES_NUMBER | ES_AUTOHSCROLL)
        let control = addControl(parent, "EDIT", value.map(String.init) ?? "", id,
                                 style, x, y, 80, 24, font)
        SendMessageW(control, UINT(EM_SETLIMITTEXT), 2, 0); return control
    }
    private static func addButton(_ parent: HWND, _ text: String, _ id: Int32, _ x: Int32, _ y: Int32,
                                  _ width: Int32, _ height: Int32, _ font: HGDIOBJ?) -> HWND? {
        let button = id == saveID ? BS_DEFPUSHBUTTON : BS_PUSHBUTTON
        return addControl(parent, "BUTTON", text, id,
                          DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | button), x, y, width, height, font)
    }
    private static func addControl(_ parent: HWND, _ klass: String, _ text: String, _ id: Int32,
                                   _ style: DWORD, _ x: Int32, _ y: Int32, _ width: Int32,
                                   _ height: Int32, _ font: HGDIOBJ?) -> HWND? {
        let name = Array(klass.utf16) + [0], caption = Array(text.utf16) + [0]
        let control = name.withUnsafeBufferPointer { n in
            caption.withUnsafeBufferPointer { c in
                CreateWindowExW(0, n.baseAddress, c.baseAddress, style, x, y, width, height,
                                parent, HMENU(bitPattern: Int(id)), GetModuleHandleW(nil), nil)
            }
        }
        if let font { SendMessageW(control, UINT(WM_SETFONT), WPARAM(Int(bitPattern: font)), 1) }
        return control
    }
    private static func center(_ hwnd: HWND, owner: HWND) {
        var rect = RECT(); GetWindowRect(hwnd, &rect)
        var area = RECT(); let monitor = MonitorFromWindow(owner, UINT(MONITOR_DEFAULTTONEAREST))
        var info = MONITORINFO(); info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        if monitor == nil || GetMonitorInfoW(monitor, &info) == 0 {
            SystemParametersInfoW(UINT(SPI_GETWORKAREA), 0, &area, 0)
        } else { area = info.rcWork }
        if area.right <= area.left || area.bottom <= area.top {
            area = RECT(left: 0, top: 0, right: 1920, bottom: 1080)
        }
        let width = rect.right - rect.left, height = rect.bottom - rect.top
        let x = max(area.left, area.left + ((area.right - area.left) - width) / 2)
        let y = max(area.top, area.top + ((area.bottom - area.top) - height) / 2)
        SetWindowPos(hwnd, nil, x, y, 0, 0, UINT(SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE))
    }
    private static func report(_ message: String) {
        FileHandle.standardError.write(Data("CodexBar: \(message)\n".utf8))
    }
}
#endif
