#if os(Windows)
import Foundation
import WinSDK
import CodexBarCore

/// Native Win32 editor for the two quota-warning lanes.
public enum WindowsQuotaWarningSettingsDialog {
    public static func show(owner: HWND, settings: WindowsQuotaWarningSettings)
        -> WindowsQuotaWarningSettings?
    {
        let context = Context(settings: settings)
        let instance = GetModuleHandleW(nil)
        var windowClass = WNDCLASSEXW()
        windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        windowClass.hInstance = instance
        windowClass.lpfnWndProc = Self.windowProc
        windowClass.hCursor = LoadCursorW(nil, IDC_ARROW)
        let className = Array(Self.className.utf16) + [0]
        let registered = className.withUnsafeBufferPointer { name in
            windowClass.lpszClassName = name.baseAddress
            return RegisterClassExW(&windowClass)
        }
        if registered == 0, GetLastError() != ERROR_CLASS_ALREADY_EXISTS {
            Self.report("could not register quota-warning dialog class")
            return nil
        }

        let title = Array("Quota warning settings".utf16) + [0]
        var frame = RECT(left: 0, top: 0, right: 420, bottom: 290)
        AdjustWindowRectEx(&frame, DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX), 0,
                           DWORD(WS_EX_DLGMODALFRAME))
        let hwnd: HWND? = className.withUnsafeBufferPointer { name in
            title.withUnsafeBufferPointer { caption in
                CreateWindowExW(
                    DWORD(WS_EX_DLGMODALFRAME), name.baseAddress, caption.baseAddress,
                    DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX),
                    0, 0, frame.right - frame.left, frame.bottom - frame.top, owner, nil, instance,
                    Unmanaged.passUnretained(context).toOpaque())
            }
        }
        guard let hwnd else {
            Self.report("could not create quota-warning dialog")
            return nil
        }
        context.window = hwnd
        context.ownerWasEnabled = IsWindowEnabled(owner) != 0
        Self.center(hwnd, owner: owner)
        if IsWindow(owner) != 0 { EnableWindow(owner, 0) }
        withExtendedLifetime(context) {
            ShowWindow(hwnd, Int32(SW_SHOW))
            UpdateWindow(hwnd)
            SetFocus(GetDlgItem(hwnd, Self.sessionEnabledID))

            var message = MSG()
            while !context.closed {
                let result = GetMessageW(&message, nil, 0, 0)
                if result == -1 {
                    Self.report("quota-warning dialog message loop failed")
                    context.closed = true
                    break
                }
                if result == 0 { PostQuitMessage(Int32(message.wParam)); context.closed = true; break }
                let targetsDialog = message.hwnd == hwnd || IsChild(hwnd, message.hwnd) != 0
                if targetsDialog, message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_ESCAPE) {
                    context.closed = true
                    DestroyWindow(hwnd)
                    continue
                }
                if targetsDialog, message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_RETURN) {
                    if GetFocus() == GetDlgItem(hwnd, Self.cancelID) {
                        context.closed = true
                        DestroyWindow(hwnd)
                    } else {
                        context.save()
                    }
                    continue
                }
                if IsDialogMessageW(hwnd, &message) == 0 {
                    TranslateMessage(&message); DispatchMessageW(&message)
                }
            }
        }
        if IsWindow(hwnd) != 0 { DestroyWindow(hwnd) }
        if IsWindow(owner) != 0, context.ownerWasEnabled { EnableWindow(owner, 1); SetForegroundWindow(owner) }
        return context.result
    }

    private static let className = "CodexBar.QuotaWarningSettingsDialog"
    private static let sessionEnabledID: Int32 = 101
    private static let weeklyEnabledID: Int32 = 102
    private static let sessionWarningID: Int32 = 111
    private static let sessionCriticalID: Int32 = 112
    private static let weeklyWarningID: Int32 = 121
    private static let weeklyCriticalID: Int32 = 122
    private static let saveID: Int32 = 1
    private static let cancelID: Int32 = 2

    private final class Context {
        let initial: WindowsQuotaWarningSettings
        var window: HWND?
        var result: WindowsQuotaWarningSettings?
        var closed = false
        var ownerWasEnabled = false

        init(settings: WindowsQuotaWarningSettings) { self.initial = settings }

        func save() {
            guard let window else { return }
            let session = Self.readPair(window, enabledID: WindowsQuotaWarningSettingsDialog.sessionEnabledID,
                                        upperID: WindowsQuotaWarningSettingsDialog.sessionWarningID,
                                        lowerID: WindowsQuotaWarningSettingsDialog.sessionCriticalID)
            let weekly = Self.readPair(window, enabledID: WindowsQuotaWarningSettingsDialog.weeklyEnabledID,
                                       upperID: WindowsQuotaWarningSettingsDialog.weeklyWarningID,
                                       lowerID: WindowsQuotaWarningSettingsDialog.weeklyCriticalID)
            result = WindowsQuotaWarningSettings(
                notificationsEnabled: initial.notificationsEnabled,
                sessionThresholds: session.thresholds,
                weeklyThresholds: weekly.thresholds,
                sessionEnabled: session.enabled,
                weeklyEnabled: weekly.enabled)
            closed = true
            DestroyWindow(window)
        }

        private static func readPair(_ window: HWND, enabledID: Int32, upperID: Int32, lowerID: Int32)
            -> (enabled: Bool, thresholds: [Int])
        {
            let enabled = SendMessageW(GetDlgItem(window, enabledID), UINT(BM_GETCHECK), 0, 0) == LRESULT(BST_CHECKED)
            let upper = integerText(GetDlgItem(window, upperID))
            let lower = integerText(GetDlgItem(window, lowerID))
            return (enabled, QuotaWarningThresholds.resolved(upper: upper, lower: lower))
        }

        private static func integerText(_ control: HWND?) -> Int? {
            guard let control else { return nil }
            var buffer = [WCHAR](repeating: 0, count: 8)
            let count = GetWindowTextW(control, &buffer, Int32(buffer.count))
            let text = String(decoding: buffer.prefix(Int(count)), as: UTF16.CodeUnit.self)
            let filtered = String(text.filter(\.isNumber).prefix(2))
            return filtered.isEmpty ? nil : Int(filtered)
        }
    }

    private static let windowProc: WNDPROC = { hwnd, message, wParam, lParam in
        guard let hwnd else { return 0 }
        if message == UINT(WM_NCCREATE),
           let create = UnsafeMutableRawPointer(bitPattern: UInt(lParam))?.assumingMemoryBound(to: CREATESTRUCTW.self),
           let pointer = create.pointee.lpCreateParams
        {
            SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), LONG_PTR(Int(bitPattern: pointer)))
        }
        let pointer = GetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA))
        guard pointer != 0 else { return DefWindowProcW(hwnd, message, wParam, lParam) }
        let context = Unmanaged<Context>.fromOpaque(UnsafeRawPointer(bitPattern: UInt(pointer))!).takeUnretainedValue()

        switch message {
        case UINT(WM_CREATE):
            return Self.createControls(hwnd, context: context) ? 0 : -1
        case UINT(WM_COMMAND):
            let command = Int32(wParam & 0xffff)
            if command == Self.saveID { context.save(); return 0 }
            if command == Self.cancelID { context.closed = true; DestroyWindow(hwnd); return 0 }
            return 0
        case UINT(WM_CLOSE):
            context.closed = true
            DestroyWindow(hwnd)
            return 0
        case UINT(WM_KEYDOWN):
            if wParam == WPARAM(VK_RETURN) { context.save(); return 0 }
            if wParam == WPARAM(VK_ESCAPE) { context.closed = true; DestroyWindow(hwnd); return 0 }
            return DefWindowProcW(hwnd, message, wParam, lParam)
        case UINT(WM_NCDESTROY):
            context.closed = true
            SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), 0)
            return 0
        default:
            return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }

    private static func createControls(_ hwnd: HWND, context: Context) -> Bool {
        let font = GetStockObject(DEFAULT_GUI_FONT)
        let controls: [HWND?] = [
            addLabel(hwnd, "Session window", 18, 18, 150, 22, font), addLabel(hwnd, "Warning", 190, 18, 80, 22, font),
            addLabel(hwnd, "Critical", 290, 18, 80, 22, font),
            addCheck(hwnd, "Enabled", sessionEnabledID, 18, 48, context.initial.sessionEnabled, font),
            addEdit(hwnd, sessionWarningID, 190, 46, context.initial.sessionThresholds.first, font),
            addEdit(hwnd, sessionCriticalID, 290, 46, context.initial.sessionThresholds.dropFirst().first, font),
            addLabel(hwnd, "Weekly window", 18, 88, 150, 22, font),
            addCheck(hwnd, "Enabled", weeklyEnabledID, 18, 118, context.initial.weeklyEnabled, font),
            addEdit(hwnd, weeklyWarningID, 190, 116, context.initial.weeklyThresholds.first, font),
            addEdit(hwnd, weeklyCriticalID, 290, 116, context.initial.weeklyThresholds.dropFirst().first, font),
        ]
        guard controls.allSatisfy({ $0 != nil }) else { return false }
        let alertText = context.initial.notificationsEnabled ? "Alerts: enabled" : "Alerts: disabled"
        let footer = [
            addLabel(hwnd, alertText, 18, 158, 350, 22, font),
            addLabel(hwnd, "Provider-specific settings override these global defaults.", 18, 182, 370, 22, font),
            addLabel(hwnd, "0 disables warnings; depleted-only notifications are separate.", 18, 198, 370, 22, font),
            addButton(hwnd, "Save", saveID, 220, 242, 80, 28, font),
            addButton(hwnd, "Cancel", cancelID, 310, 242, 80, 28, font),
        ]
        return footer.allSatisfy({ $0 != nil })
    }

    private static func addLabel(_ parent: HWND, _ text: String, _ x: Int32, _ y: Int32, _ width: Int32,
                                 _ height: Int32, _ font: HGDIOBJ?) -> HWND? {
        addControl(parent, "STATIC", text, 0, DWORD(WS_CHILD | WS_VISIBLE), x, y, width, height, font)
    }

    private static func addCheck(_ parent: HWND, _ text: String, _ id: Int32, _ x: Int32, _ y: Int32,
                                 _ checked: Bool, _ font: HGDIOBJ?) -> HWND? {
        let style = DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_AUTOCHECKBOX)
        let control = addControl(parent, "BUTTON", text, id, style,
                                 x, y, 150, 24, font)
        SendMessageW(control, UINT(BM_SETCHECK), WPARAM(checked ? BST_CHECKED : BST_UNCHECKED), 0)
        return control
    }

    private static func addEdit(
        _ parent: HWND, _ id: Int32, _ x: Int32, _ y: Int32, _ value: Int?, _ font: HGDIOBJ?) -> HWND?
    {
        let control = addControl(parent, "EDIT", value.map(String.init) ?? "", id,
                                 DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_BORDER | ES_NUMBER | ES_AUTOHSCROLL),
                                 x, y, 80, 24, font)
        SendMessageW(control, UINT(EM_SETLIMITTEXT), 2, 0)
        return control
    }

    private static func addButton(_ parent: HWND, _ text: String, _ id: Int32, _ x: Int32, _ y: Int32,
                                  _ width: Int32, _ height: Int32, _ font: HGDIOBJ?) -> HWND? {
        let buttonStyle = id == Self.saveID ? BS_DEFPUSHBUTTON : BS_PUSHBUTTON
        return addControl(parent, "BUTTON", text, id, DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP | buttonStyle),
                          x, y, width, height, font)
    }

    @discardableResult
    private static func addControl(_ parent: HWND, _ className: String, _ text: String, _ id: Int32, _ style: DWORD,
                                   _ x: Int32, _ y: Int32, _ width: Int32, _ height: Int32, _ font: HGDIOBJ?) -> HWND? {
        let cls = Array(className.utf16) + [0]
        let caption = Array(text.utf16) + [0]
        let control = cls.withUnsafeBufferPointer { clsBuffer in
            caption.withUnsafeBufferPointer { textBuffer in
                CreateWindowExW(0, clsBuffer.baseAddress, textBuffer.baseAddress, style, x, y, width, height,
                                parent, HMENU(bitPattern: Int(id)), GetModuleHandleW(nil), nil)
            }
        }
        if let font { SendMessageW(control, UINT(WM_SETFONT), WPARAM(Int(bitPattern: font)), 1) }
        return control
    }

    private static func center(_ hwnd: HWND, owner: HWND) {
        var rect = RECT()
        GetWindowRect(hwnd, &rect)
        var area = RECT()
        let monitor = MonitorFromWindow(owner, UINT(MONITOR_DEFAULTTONEAREST))
        var info = MONITORINFO()
        info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        if monitor == nil || GetMonitorInfoW(monitor, &info) == 0 {
            SystemParametersInfoW(UINT(SPI_GETWORKAREA), 0, &area, 0)
        } else {
            area = info.rcWork
        }
        if area.right <= area.left || area.bottom <= area.top {
            area = RECT(left: 0, top: 0, right: 1920, bottom: 1080)
        }
        let width = rect.right - rect.left
        let height = rect.bottom - rect.top
        let x = max(area.left, min(area.right - width, area.left + ((area.right - area.left) - width) / 2))
        let y = max(area.top, min(area.bottom - height, area.top + ((area.bottom - area.top) - height) / 2))
        SetWindowPos(hwnd, nil, x, y, 0, 0, UINT(SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE))
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write(Data("CodexBar: \(message)\n".utf8))
    }
}
#endif
