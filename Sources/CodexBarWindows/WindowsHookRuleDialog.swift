#if os(Windows)
import Foundation
import WinSDK
import CodexBarCore

/// Native hook rule form. Returns a validated rule; never saves or executes it.
public enum WindowsHookRuleDialog {
    public static func show(owner: HWND, draft: WindowsHookRuleDraft)
        -> HookRule?
    {
        let context = Context(initial: draft)
        let instance = GetModuleHandleW(nil)
        var klass = WNDCLASSEXW()
        klass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        klass.hInstance = instance; klass.lpfnWndProc = Self.windowProc
        klass.hCursor = LoadCursorW(nil, IDC_ARROW)
        let name = Array(Self.className.utf16) + [0]
        let registered = name.withUnsafeBufferPointer { klass.lpszClassName = $0.baseAddress; return RegisterClassExW(&klass) }
        if registered == 0, GetLastError() != ERROR_CLASS_ALREADY_EXISTS { return nil }
        let title = Array("Hook rule".utf16) + [0]
        var frame = RECT(left: 0, top: 0, right: 600, bottom: 540)
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
            ShowWindow(hwnd, Int32(SW_SHOW)); UpdateWindow(hwnd); SetFocus(GetDlgItem(hwnd, eventID))
            var message = MSG()
            while !context.closed {
                let result = GetMessageW(&message, nil, 0, 0)
                if result == -1 { context.closed = true; break }
                if result == 0 { PostQuitMessage(Int32(message.wParam)); context.closed = true; break }
                let target = message.hwnd == hwnd || IsChild(hwnd, message.hwnd) != 0
                if target, message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_ESCAPE) { context.cancel(); continue }
                if target, message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_RETURN) {
                    if GetFocus() == GetDlgItem(hwnd, argumentsID) {
                        TranslateMessage(&message); DispatchMessageW(&message); continue
                    }
                    if GetFocus() == GetDlgItem(hwnd, cancelID) { context.cancel() } else { context.save() }; continue
                }
                if IsDialogMessageW(hwnd, &message) == 0 { TranslateMessage(&message); DispatchMessageW(&message) }
            }
        }
        if IsWindow(hwnd) != 0 { DestroyWindow(hwnd) }
        if IsWindow(owner) != 0, context.ownerWasEnabled { EnableWindow(owner, 1); SetForegroundWindow(owner) }
        return context.result
    }

    private static let className = "CodexBar.HookRuleDialog"
    private static let eventID: Int32 = 101, providerID: Int32 = 102, executableID: Int32 = 103
    private static let argumentsID: Int32 = 104, thresholdID: Int32 = 105, timeoutID: Int32 = 106
    private static let enabledID: Int32 = 107, saveID: Int32 = 1, cancelID: Int32 = 2
    private static let events = HookEventType.allCases

    private final class Context {
        let initial: WindowsHookRuleDraft
        var window: HWND?; var result: HookRule?; var closed = false; var ownerWasEnabled = false
        init(initial: WindowsHookRuleDraft) { self.initial = initial }
        func cancel() { self.closed = true; if let window { DestroyWindow(window) } }
        func save() {
            guard let window else { return }
            var draft = self.initial
            let index = Int(SendMessageW(GetDlgItem(window, eventID), UINT(CB_GETCURSEL), 0, 0))
            guard events.indices.contains(index) else { return }
            draft.event = events[index]
            draft.enabled = SendMessageW(GetDlgItem(window, enabledID), UINT(BM_GETCHECK), 0, 0) == LRESULT(BST_CHECKED)
            let provider = readText(GetDlgItem(window, providerID)).trimmingCharacters(in: .whitespacesAndNewlines)
            draft.provider = provider.isEmpty ? nil : provider
            draft.executable = readText(GetDlgItem(window, executableID))
            draft.usedPercent = readText(GetDlgItem(window, thresholdID))
            draft.timeoutSeconds = readText(GetDlgItem(window, timeoutID))
            do {
                let text = readText(GetDlgItem(window, argumentsID))
                guard text.utf8.count <= 256 * 1024 else { throw WindowsHookSettingsFailure.invalidCommand }
                draft.arguments = try JSONDecoder().decode([String].self, from: Data(text.utf8))
                let rule = try draft.rule()
                self.result = rule; self.closed = true; DestroyWindow(window)
            } catch {
                let message = "Check the absolute executable path, provider ID, JSON argument array, used percent (0 < value <= 100), and timeout (0.1–300 seconds). Use a dot for decimals."
                message.withCString(encodedAs: UTF16.self) { text in
                    "Hook rule".withCString(encodedAs: UTF16.self) { title in
                        _ = MessageBoxW(window, text, title, UINT(MB_OK | MB_ICONWARNING))
                    }
                }
            }
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
        case UINT(WM_CREATE): return createControls(hwnd, context: context) ? 0 : -1
        case UINT(WM_COMMAND):
            switch Int32(wParam & 0xffff) {
            case saveID: context.save()
            case cancelID: context.cancel()
            case eventID:
                let index = Int(SendMessageW(GetDlgItem(hwnd, eventID), UINT(CB_GETCURSEL), 0, 0))
                EnableWindow(GetDlgItem(hwnd, thresholdID), events.indices.contains(index) && events[index] == .quotaLow ? 1 : 0)
            default: break
            }
            return 0
        case UINT(WM_CLOSE): context.cancel(); return 0
        case UINT(WM_NCDESTROY): context.closed = true; SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), 0); return 0
        default: return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }

    private static func createControls(_ hwnd: HWND, context: Context) -> Bool {
        let font = GetStockObject(DEFAULT_GUI_FONT)
        let draft = context.initial
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let encoded = try? encoder.encode(draft.arguments), let arguments = String(data: encoded, encoding: .utf8) else { return false }
        let controls: [HWND?] = [
            addLabel(hwnd, "Event", 18, 16, 100, 22, font),
            addControl(hwnd, "COMBOBOX", "", eventID, DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|CBS_DROPDOWNLIST|WS_VSCROLL), 18, 40, 330, 180, font),
            addControl(hwnd, "BUTTON", "Enabled", enabledID, DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_AUTOCHECKBOX), 400, 40, 150, 24, font),
            addLabel(hwnd, "Provider ID (blank = all providers)", 18, 78, 540, 22, font),
            addEdit(hwnd, draft.provider ?? "", providerID, 18, 102, 560, 24, 128, false, font),
            addLabel(hwnd, "Executable (absolute path, without surrounding quotes)", 18, 136, 560, 22, font),
            addEdit(hwnd, draft.executable, executableID, 18, 160, 560, 24, 4096, false, font),
            addLabel(hwnd, "Arguments (JSON string array; [] for none; no shell splitting)", 18, 194, 560, 22, font),
            addEdit(hwnd, arguments, argumentsID, 18, 218, 560, 130, 262144, true, font),
            addLabel(hwnd, "Used percent (blank = provider thresholds)", 18, 362, 355, 22, font),
            addEdit(hwnd, draft.usedPercent, thresholdID, 18, 388, 250, 24, 64, false, font),
            addLabel(hwnd, "Timeout seconds (0.1–300)", 318, 362, 260, 22, font),
            addEdit(hwnd, draft.timeoutSeconds, timeoutID, 318, 388, 260, 24, 64, false, font),
            addLabel(hwnd, "Use dot decimals. Saving this form does not run the command.", 18, 426, 560, 22, font),
            addButton(hwnd, "Save rule", saveID, 370, 480, 100, 28, font),
            addButton(hwnd, "Cancel", cancelID, 478, 480, 100, 28, font)
        ]
        guard controls.allSatisfy({ $0 != nil }) else { return false }
        for event in events {
            let result = event.rawValue.withCString(encodedAs: UTF16.self) {
                SendMessageW(GetDlgItem(hwnd, eventID), UINT(CB_ADDSTRING), 0, LPARAM(Int(bitPattern: $0)))
            }
            guard result != LRESULT(CB_ERR), result != LRESULT(CB_ERRSPACE) else { return false }
        }
        SendMessageW(GetDlgItem(hwnd, eventID), UINT(CB_SETCURSEL), WPARAM(events.firstIndex(of: draft.event) ?? 0), 0)
        SendMessageW(GetDlgItem(hwnd, enabledID), UINT(BM_SETCHECK), WPARAM(draft.enabled ? BST_CHECKED : BST_UNCHECKED), 0)
        EnableWindow(GetDlgItem(hwnd, thresholdID), draft.event == .quotaLow ? 1 : 0)
        return true
    }

    private static func readText(_ control: HWND?) -> String {
        guard let control else { return "" }
        let length = GetWindowTextLengthW(control)
        guard length >= 0, length <= 262144 else { return "" }
        var buffer = [WCHAR](repeating: 0, count: Int(length) + 1)
        let count = GetWindowTextW(control, &buffer, Int32(buffer.count))
        return String(decoding: buffer.prefix(Int(count)), as: UTF16.CodeUnit.self)
    }
    private static func addEdit(_ p: HWND, _ text: String, _ id: Int32, _ x: Int32, _ y: Int32, _ w: Int32, _ h: Int32, _ limit: Int, _ multiline: Bool, _ f: HGDIOBJ?) -> HWND? {
        let style = DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|WS_BORDER) | (multiline ? DWORD(ES_MULTILINE|ES_AUTOVSCROLL|WS_VSCROLL|ES_WANTRETURN) : DWORD(ES_AUTOHSCROLL))
        let handle = addControl(p, "EDIT", text, id, style, x, y, w, h, f)
        SendMessageW(handle, UINT(EM_SETLIMITTEXT), WPARAM(limit), 0)
        return handle
    }
    private static func addLabel(_ p: HWND,_ t:String,_ x:Int32,_ y:Int32,_ w:Int32,_ h:Int32,_ f:HGDIOBJ?)->HWND? { addControl(p,"STATIC",t,0,DWORD(WS_CHILD|WS_VISIBLE),x,y,w,h,f) }
    private static func addButton(_ p: HWND,_ t:String,_ id:Int32,_ x:Int32,_ y:Int32,_ w:Int32,_ h:Int32,_ f:HGDIOBJ?)->HWND? { addControl(p,"BUTTON",t,id,DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|(id == saveID ? BS_DEFPUSHBUTTON : BS_PUSHBUTTON)),x,y,w,h,f) }
    private static func addControl(_ p: HWND,_ k:String,_ t:String,_ id:Int32,_ s:DWORD,_ x:Int32,_ y:Int32,_ w:Int32,_ h:Int32,_ f:HGDIOBJ?)->HWND? { let n=Array(k.utf16)+[0], c=Array(t.utf16)+[0]; let h=n.withUnsafeBufferPointer { nn in c.withUnsafeBufferPointer { cc in CreateWindowExW(0,nn.baseAddress,cc.baseAddress,s,x,y,w,h,p,HMENU(bitPattern:Int(id)),GetModuleHandleW(nil),nil) } }; if let f { SendMessageW(h,UINT(WM_SETFONT),WPARAM(Int(bitPattern:f)),1) }; return h }
    private static func center(_ hwnd: HWND, owner: HWND) { var r=RECT(); GetWindowRect(hwnd,&r); var a=RECT(); let m=MonitorFromWindow(owner,UINT(MONITOR_DEFAULTTONEAREST)); var i=MONITORINFO(); i.cbSize=DWORD(MemoryLayout<MONITORINFO>.size); if m == nil || GetMonitorInfoW(m,&i)==0 { SystemParametersInfoW(UINT(SPI_GETWORKAREA),0,&a,0); i.rcWork=a }; let w=r.right-r.left,h=r.bottom-r.top; SetWindowPos(hwnd,nil,i.rcWork.left+(i.rcWork.right-i.rcWork.left-w)/2,i.rcWork.top+(i.rcWork.bottom-i.rcWork.top-h)/2,0,0,UINT(SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE)) }
}
#endif
