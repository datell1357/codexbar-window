#if os(Windows)
import Foundation
import WinSDK

/// Keep/replace/remove are explicit; an empty secret input never silently removes a stored secret.
enum WindowsPluginSettingsDialog {
    static func show(owner: HWND, snapshot: WindowsPluginSettingsSnapshot)
        -> [String: WindowsPluginSettingChange]?
    {
        let context = Context(snapshot: snapshot)
        let instance = GetModuleHandleW(nil)
        var klass = WNDCLASSEXW()
        klass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        klass.hInstance = instance; klass.lpfnWndProc = Self.windowProc
        klass.hCursor = LoadCursorW(nil, IDC_ARROW)
        let name = Array(Self.className.utf16) + [0]
        let registered = name.withUnsafeBufferPointer { klass.lpszClassName = $0.baseAddress; return RegisterClassExW(&klass) }
        if registered == 0, GetLastError() != ERROR_CLASS_ALREADY_EXISTS { return nil }
        let title = Array(context.localization.text("plugin_settingsTitle").utf16) + [0]
        var frame = RECT(left: 0, top: 0, right: 600, bottom: 390)
        AdjustWindowRectEx(&frame, DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX), 0,
                           DWORD(WS_EX_DLGMODALFRAME))
        let hwnd: HWND? = name.withUnsafeBufferPointer { n in
            title.withUnsafeBufferPointer { t in
                CreateWindowExW(DWORD(WS_EX_DLGMODALFRAME), n.baseAddress, t.baseAddress,
                                DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX),
                                0, 0, frame.right - frame.left, frame.bottom - frame.top, owner, nil,
                                instance, Unmanaged.passUnretained(context).toOpaque())
            }
        }
        guard let hwnd else { return nil }
        context.window = hwnd; context.ownerWasEnabled = IsWindowEnabled(owner) != 0
        center(hwnd, owner: owner); if IsWindow(owner) != 0 { EnableWindow(owner, 0) }
        withExtendedLifetime(context) {
            ShowWindow(hwnd, Int32(SW_SHOW)); UpdateWindow(hwnd); SetFocus(GetDlgItem(hwnd, cancelID))
            var message = MSG()
            while !context.closed {
                let result = GetMessageW(&message, nil, 0, 0)
                if result == -1 { context.closed = true; break }
                if result == 0 { PostQuitMessage(Int32(message.wParam)); context.closed = true; break }
                let target = message.hwnd == hwnd || IsChild(hwnd, message.hwnd) != 0
                if target, message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_ESCAPE) { context.cancel(); continue }
                if target, message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_RETURN),
                   GetFocus() == GetDlgItem(hwnd, saveID) { context.save(); continue }
                if IsDialogMessageW(hwnd, &message) == 0 { TranslateMessage(&message); DispatchMessageW(&message) }
            }
        }
        if IsWindow(hwnd) != 0 { DestroyWindow(hwnd) }
        if IsWindow(owner) != 0, context.ownerWasEnabled { EnableWindow(owner, 1); SetForegroundWindow(owner) }
        return context.result
    }

    private static let className = "CodexBar.PluginSettingsDialog"
    private static let fieldID: Int32 = 101, modeID: Int32 = 102, valueID: Int32 = 103
    private static let helpID: Int32 = 104, errorID: Int32 = 105, saveID: Int32 = 1, cancelID: Int32 = 2
    private final class Context {
        let snapshot: WindowsPluginSettingsSnapshot
        let localization = WindowsStatusLocalization.Snapshot()
        var window: HWND?; var closed = false; var ownerWasEnabled = false
        var result: [String: WindowsPluginSettingChange]?
        var changes: [String: WindowsPluginSettingChange] = [:]
        var selected = 0
        init(snapshot: WindowsPluginSettingsSnapshot) { self.snapshot = snapshot }
        func cancel() { changes.removeAll(); closed = true; if let window { DestroyWindow(window) } }
        func save() {
            guard capture(), let window else { return }
            result = changes; changes.removeAll(); closed = true; DestroyWindow(window)
        }
        func capture() -> Bool {
            guard let window, snapshot.fields.indices.contains(selected) else { return true }
            let field = snapshot.fields[selected]
            let mode = SendMessageW(GetDlgItem(window, modeID), UINT(CB_GETCURSEL), 0, 0)
            switch mode {
            case 0: changes[field.key] = nil
            case 2: changes[field.key] = .remove
            case 1:
                var buffer = [WCHAR](repeating: 0, count: 16385)
                let count = GetWindowTextW(GetDlgItem(window, valueID), &buffer, Int32(buffer.count))
                let value = String(decoding: buffer.prefix(Int(count)), as: UTF16.CodeUnit.self)
                guard value.utf8.count <= 16384, !value.contains("\0") else {
                    setText(GetDlgItem(window, errorID), localization.text("plugin_valueTooLong")); return false
                }
                changes[field.key] = .replace(value)
            default: return false
            }
            setText(GetDlgItem(window, errorID), "")
            return true
        }
        func chooseField() {
            guard let window else { return }
            let next = Int(SendMessageW(GetDlgItem(window, fieldID), UINT(CB_GETCURSEL), 0, 0))
            guard snapshot.fields.indices.contains(next), capture() else {
                SendMessageW(GetDlgItem(window, fieldID), UINT(CB_SETCURSEL), WPARAM(selected), 0); return
            }
            selected = next; displayField()
        }
        func displayField() {
            guard let window, snapshot.fields.indices.contains(selected) else { return }
            let field = snapshot.fields[selected]
            let secret = field.kind == .secure
            var mode = 0
            var value = secret ? "" : (snapshot.values[field.key] ?? "")
            if let change = changes[field.key] {
                switch change { case let .replace(replacement): mode = 1; value = replacement
                case .remove: mode = 2; value = "" }
            }
            // Clear before changing masking mode so a previous secret never appears in a plain field.
            setText(GetDlgItem(window, valueID), "")
            SendMessageW(GetDlgItem(window, valueID), UINT(EM_SETPASSWORDCHAR), secret ? 0x25CF : 0, 0)
            setText(GetDlgItem(window, valueID), value)
            guard SendMessageW(GetDlgItem(window, modeID), UINT(CB_SETCURSEL), WPARAM(mode), 0) == LRESULT(mode) else {
                cancel(); return
            }
            let status = secret ? localization.text(snapshot.storedSecretKeys.contains(field.key) ?
                "plugin_secretStored" : "plugin_secretMissing") : ""
            setText(GetDlgItem(window, helpID), safe(field.subtitle ?? "") + "\r\n" + status)
            updateMode()
        }
        func updateMode() {
            guard let window else { return }
            let replacing = SendMessageW(GetDlgItem(window, modeID), UINT(CB_GETCURSEL), 0, 0) == 1
            EnableWindow(GetDlgItem(window, valueID), replacing ? 1 : 0)
        }
    }
    private static let windowProc: WNDPROC = { hwnd, message, wParam, lParam in
        guard let hwnd else { return 0 }
        if message == UINT(WM_NCCREATE), let create = UnsafeMutableRawPointer(bitPattern: UInt(lParam))?.assumingMemoryBound(to: CREATESTRUCTW.self), let pointer = create.pointee.lpCreateParams {
            SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), LONG_PTR(Int(bitPattern: pointer)))
        }
        let pointer = GetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA))
        guard pointer != 0 else { return DefWindowProcW(hwnd, message, wParam, lParam) }
        let context = Unmanaged<Context>.fromOpaque(UnsafeRawPointer(bitPattern: UInt(pointer))!).takeUnretainedValue()
        switch message {
        case UINT(WM_CREATE): context.window = hwnd; return createControls(hwnd, context: context) ? 0 : -1
        case UINT(WM_COMMAND):
            let id = Int32(wParam & 0xffff), notification = (wParam >> 16) & 0xffff
            if id == fieldID, notification == WPARAM(CBN_SELCHANGE) { context.chooseField() }
            else if id == modeID, notification == WPARAM(CBN_SELCHANGE) { context.updateMode() }
            else if id == saveID { context.save() }
            else if id == cancelID { context.cancel() }
            return 0
        case UINT(WM_CLOSE): context.cancel(); return 0
        case UINT(WM_NCDESTROY): context.closed = true; SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), 0); return 0
        default: return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }
    private static func createControls(_ hwnd: HWND, context: Context) -> Bool {
        guard context.snapshot.fields.count <= 32 else { return false }
        let font = GetStockObject(DEFAULT_GUI_FONT), l = context.localization
        let controls: [HWND?] = [
            addControl(hwnd,"STATIC",l.text("plugin_selectSetting"),0,DWORD(WS_CHILD|WS_VISIBLE),16,16,568,24,font),
            addControl(hwnd,"COMBOBOX","",fieldID,DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|CBS_DROPDOWNLIST|WS_VSCROLL),16,42,568,260,font),
            addControl(hwnd,"STATIC","",helpID,DWORD(WS_CHILD|WS_VISIBLE),16,78,568,88,font),
            addControl(hwnd,"COMBOBOX","",modeID,DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|CBS_DROPDOWNLIST),16,174,568,160,font),
            addControl(hwnd,"EDIT","",valueID,DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|WS_BORDER|ES_AUTOHSCROLL),16,212,568,28,font),
            addControl(hwnd,"STATIC",l.text("plugin_settingsHelp"),0,DWORD(WS_CHILD|WS_VISIBLE),16,252,568,44,font),
            addControl(hwnd,"STATIC","",errorID,DWORD(WS_CHILD|WS_VISIBLE),16,298,568,32,font),
            addControl(hwnd,"BUTTON",l.text("Save"),saveID,DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_PUSHBUTTON),350,344,112,28,font),
            addControl(hwnd,"BUTTON",l.text("Cancel"),cancelID,DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_DEFPUSHBUTTON),472,344,112,28,font),
        ]
        guard controls.allSatisfy({ $0 != nil }) else { return false }
        for (index, field) in context.snapshot.fields.enumerated() {
            guard appendChoice(hwnd, id: fieldID, text: safe(field.title) + " [" + field.key + "]", expectedIndex: index) else { return false }
        }
        for (index, key) in ["plugin_keepValue", "plugin_replaceValue", "plugin_removeValue"].enumerated() {
            guard appendChoice(hwnd, id: modeID, text: l.text(key), expectedIndex: index) else { return false }
        }
        if !context.snapshot.fields.isEmpty {
            guard SendMessageW(GetDlgItem(hwnd, fieldID), UINT(CB_SETCURSEL), 0, 0) == 0 else { return false }
        }
        SendMessageW(GetDlgItem(hwnd, valueID), UINT(EM_SETLIMITTEXT), 16384, 0)
        if context.snapshot.fields.isEmpty {
            setText(GetDlgItem(hwnd, helpID), l.text("plugin_noSettings"))
            for id in [fieldID, modeID, valueID, saveID] { EnableWindow(GetDlgItem(hwnd, id), 0) }
        } else { context.displayField() }
        return true
    }
    private static func safe(_ text: String) -> String {
        text.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) || (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
                ? "\\u{" + String(scalar.value, radix: 16) + "}" : String(scalar)
        }.joined()
    }
    private static func setText(_ hwnd: HWND?, _ text: String) {
        text.withCString(encodedAs: UTF16.self) { _ = SetWindowTextW(hwnd, $0) }
    }
    private static func appendChoice(_ hwnd: HWND, id: Int32, text: String, expectedIndex: Int) -> Bool {
        let inserted = text.withCString(encodedAs: UTF16.self) {
            SendMessageW(GetDlgItem(hwnd, id), UINT(CB_ADDSTRING), 0, LPARAM(Int(bitPattern: $0)))
        }
        // Negative results include CB_ERR/CB_ERRSPACE. Exact index also guards accidental sorting.
        return inserted == LRESULT(expectedIndex)
    }
    private static func addControl(_ p: HWND,_ k:String,_ t:String,_ id:Int32,_ s:DWORD,_ x:Int32,_ y:Int32,_ w:Int32,_ h:Int32,_ f:HGDIOBJ?)->HWND? { let n=Array(k.utf16)+[0], c=Array(t.utf16)+[0]; let h=n.withUnsafeBufferPointer { nn in c.withUnsafeBufferPointer { cc in CreateWindowExW(0,nn.baseAddress,cc.baseAddress,s,x,y,w,h,p,HMENU(bitPattern:Int(id)),GetModuleHandleW(nil),nil) } }; if let f { SendMessageW(h,UINT(WM_SETFONT),WPARAM(Int(bitPattern:f)),1) }; return h }
    private static func center(_ hwnd: HWND, owner: HWND) { var r=RECT(); GetWindowRect(hwnd,&r); var a=RECT(); let m=MonitorFromWindow(owner,UINT(MONITOR_DEFAULTTONEAREST)); var i=MONITORINFO(); i.cbSize=DWORD(MemoryLayout<MONITORINFO>.size); if m == nil || GetMonitorInfoW(m,&i)==0 { SystemParametersInfoW(UINT(SPI_GETWORKAREA),0,&a,0); i.rcWork=a }; let w=r.right-r.left,h=r.bottom-r.top; SetWindowPos(hwnd,nil,i.rcWork.left+(i.rcWork.right-i.rcWork.left-w)/2,i.rcWork.top+(i.rcWork.bottom-i.rcWork.top-h)/2,0,0,UINT(SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE)) }
}
#endif
