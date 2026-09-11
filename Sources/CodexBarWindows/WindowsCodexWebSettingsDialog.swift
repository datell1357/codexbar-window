#if os(Windows)
import Foundation
import WinSDK
import CodexBarCore

/// Native Win32 editor for Codex source and web-cookie settings.
public enum WindowsCodexWebSettingsDialog {
    public static func show(owner: HWND, settings: WindowsCodexWebSettingsSnapshot)
        -> WindowsCodexWebSettingsPatch?
    {
        let context = Context(initial: settings)
        let instance = GetModuleHandleW(nil)
        var klass = WNDCLASSEXW()
        klass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        klass.hInstance = instance; klass.lpfnWndProc = Self.windowProc
        klass.hCursor = LoadCursorW(nil, IDC_ARROW)
        let name = Array(Self.className.utf16) + [0]
        let registered = name.withUnsafeBufferPointer { klass.lpszClassName = $0.baseAddress; return RegisterClassExW(&klass) }
        if registered == 0, GetLastError() != ERROR_CLASS_ALREADY_EXISTS { return nil }
        let title = Array("Codex web settings".utf16) + [0]
        var frame = RECT(left: 0, top: 0, right: 470, bottom: 330)
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
            ShowWindow(hwnd, Int32(SW_SHOW)); UpdateWindow(hwnd); SetFocus(GetDlgItem(hwnd, sourceAutoID))
            var message = MSG()
            while !context.closed {
                let result = GetMessageW(&message, nil, 0, 0)
                if result == -1 { context.closed = true; break }
                if result == 0 { PostQuitMessage(Int32(message.wParam)); context.closed = true; break }
                let target = message.hwnd == hwnd || IsChild(hwnd, message.hwnd) != 0
                if target, message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_ESCAPE) { context.cancel(); continue }
                if target, message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_RETURN) {
                    if GetFocus() == GetDlgItem(hwnd, cancelID) { context.cancel() } else { context.save() }; continue
                }
                if IsDialogMessageW(hwnd, &message) == 0 { TranslateMessage(&message); DispatchMessageW(&message) }
            }
        }
        if IsWindow(hwnd) != 0 { DestroyWindow(hwnd) }
        if IsWindow(owner) != 0, context.ownerWasEnabled { EnableWindow(owner, 1); SetForegroundWindow(owner) }
        return context.result
    }

    private static let className = "CodexBar.CodexWebSettingsDialog"
    private static let sourceAutoID: Int32 = 101, sourceWebID: Int32 = 102, sourceCLIID: Int32 = 103
    private static let sourceOAuthID: Int32 = 104, sourcePATID: Int32 = 105
    private static let cookieAutoID: Int32 = 111, cookieManualID: Int32 = 112, cookieOffID: Int32 = 113
    private static let headerID: Int32 = 121, saveID: Int32 = 1, cancelID: Int32 = 2

    private final class Context {
        let initial: WindowsCodexWebSettingsSnapshot
        var window: HWND?; var result: WindowsCodexWebSettingsPatch?; var closed = false; var ownerWasEnabled = false
        init(initial: WindowsCodexWebSettingsSnapshot) { self.initial = initial }
        func cancel() { closed = true; if let window { DestroyWindow(window) } }
        func save() {
            guard let window else { return }
            let source = readSource(window), cookie = readCookie(window)
            if source == .web, cookie == .off {
                report("Web source requires cookies to be Auto or Manual."); return
            }
            var patch = WindowsCodexWebSettingsPatch(sourceMode: source == initial.sourceMode ? nil : source,
                                                     cookieSource: cookie == initial.cookieSource ? nil : cookie)
            let header = readText(GetDlgItem(window, WindowsCodexWebSettingsDialog.headerID))
            if !header.isEmpty {
                guard header.count <= 16_384,
                      let normalized = CookieHeaderNormalizer.normalize(header),
                      !CookieHeaderNormalizer.pairs(from: normalized).isEmpty else {
                    report("Manual cookie header is invalid."); return
                }
                patch = WindowsCodexWebSettingsPatch(sourceMode: patch.sourceMode, cookieSource: patch.cookieSource,
                                                     manualHeader: .replace(normalized))
            } else if cookie == .manual, !initial.hasStoredManualHeader {
                report("Manual cookie source requires a cookie header."); return
            }
            result = patch; closed = true; DestroyWindow(window)
        }
    }

    private static let windowProc: WNDPROC = { hwnd, message, wParam, lParam in
        guard let hwnd else { return 0 }
        if message == UINT(WM_NCCREATE), let create = UnsafeMutableRawPointer(bitPattern: UInt(lParam))?.assumingMemoryBound(to: CREATESTRUCTW.self), let pointer = create.pointee.lpCreateParams {
            SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), LONG_PTR(Int(bitPattern: pointer)))
        }
        let pointer = GetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA)); guard pointer != 0 else { return DefWindowProcW(hwnd, message, wParam, lParam) }
        let context = Unmanaged<Context>.fromOpaque(UnsafeRawPointer(bitPattern: UInt(pointer))!).takeUnretainedValue()
        switch message {
        case UINT(WM_CREATE): return createControls(hwnd, context: context) ? 0 : -1
        case UINT(WM_COMMAND):
            switch Int32(wParam & 0xffff) {
            case saveID: context.save(); case cancelID: context.cancel()
            default: updateCookieHeader(window: hwnd)
            }; return 0
        case UINT(WM_CLOSE): context.cancel(); return 0
        case UINT(WM_NCDESTROY): context.closed = true; SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), 0); return 0
        default: return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }

    private static func createControls(_ hwnd: HWND, context: Context) -> Bool {
        let font = GetStockObject(DEFAULT_GUI_FONT)
        let source = context.initial.sourceMode
        let cookie = context.initial.cookieSource
        let controls: [HWND?] = [
            addLabel(hwnd, "Source", 18, 16, 100, 22, font),
            addRadio(hwnd, "Auto", sourceAutoID, 18, 42, source == .auto, font), addRadio(hwnd, "Web", sourceWebID, 92, 42, source == .web, font),
            addRadio(hwnd, "CLI", sourceCLIID, 166, 42, source == .cli, font), addRadio(hwnd, "OAuth API", sourceOAuthID, 240, 42, source == .oauth, font), addRadio(hwnd, "PAT", sourcePATID, 340, 42, source == .api, font),
            addLabel(hwnd, "Cookie source", 18, 82, 130, 22, font), addRadio(hwnd, "Auto", cookieAutoID, 18, 108, cookie == .auto, font),
            addRadio(hwnd, "Manual", cookieManualID, 92, 108, cookie == .manual, font), addRadio(hwnd, "Off", cookieOffID, 180, 108, cookie == .off, font),
            addLabel(hwnd, "Manual cookie header (optional)", 18, 148, 240, 22, font), addPasswordEdit(hwnd, headerID, 18, 172, font),
            addLabel(hwnd, context.initial.hasStoredManualHeader ? "A manual cookie is already stored." : "No manual cookie is stored.", 18, 202, 390, 22, font),
            addLabel(hwnd, "Stored in the local config file. Choose Web for this source.", 18, 226, 420, 22, font),
            addButton(hwnd, "Save", saveID, 280, 266, 80, 28, font), addButton(hwnd, "Cancel", cancelID, 370, 266, 80, 28, font)
        ]
        guard controls.allSatisfy({ $0 != nil }) else { return false }; updateCookieHeader(window: hwnd); return true
    }

    private static func updateCookieHeader(window: HWND) { let cookie = readCookie(window); EnableWindow(GetDlgItem(window, headerID), cookie == .manual ? 1 : 0) }
    private static func readSource(_ window: HWND) -> ProviderSourceMode { let ids: [(Int32, ProviderSourceMode)] = [(sourceAutoID,.auto),(sourceWebID,.web),(sourceCLIID,.cli),(sourceOAuthID,.oauth),(sourcePATID,.api)]; return ids.first { SendMessageW(GetDlgItem(window,$0.0),UINT(BM_GETCHECK),0,0) == LRESULT(BST_CHECKED) }!.1 }
    private static func readCookie(_ window: HWND) -> ProviderCookieSource { let ids: [(Int32, ProviderCookieSource)] = [(cookieAutoID,.auto),(cookieManualID,.manual),(cookieOffID,.off)]; return ids.first { SendMessageW(GetDlgItem(window,$0.0),UINT(BM_GETCHECK),0,0) == LRESULT(BST_CHECKED) }!.1 }
    private static func readText(_ control: HWND?) -> String { guard let control else { return "" }; var buffer = [WCHAR](repeating: 0, count: 16_385); let count = GetWindowTextW(control, &buffer, Int32(buffer.count)); return String(decoding: buffer.prefix(Int(count)), as: UTF16.CodeUnit.self) }

    private static func addLabel(_ p: HWND,_ t:String,_ x:Int32,_ y:Int32,_ w:Int32,_ h:Int32,_ f:HGDIOBJ?)->HWND? { addControl(p,"STATIC",t,0,DWORD(WS_CHILD|WS_VISIBLE),x,y,w,h,f) }
    private static func addRadio(_ p: HWND,_ t:String,_ id:Int32,_ x:Int32,_ y:Int32,_ c:Bool,_ f:HGDIOBJ?)->HWND? { let first = id == sourceAutoID || id == cookieAutoID; let s = DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_AUTORADIOBUTTON) | (first ? DWORD(WS_GROUP) : 0); let h=addControl(p,"BUTTON",t,id,s,x,y,90,24,f); SendMessageW(h,UINT(BM_SETCHECK),WPARAM(c ? BST_CHECKED : BST_UNCHECKED),0); return h }
    private static func addPasswordEdit(_ p: HWND,_ id:Int32,_ x:Int32,_ y:Int32,_ f:HGDIOBJ?)->HWND? { let h=addControl(p,"EDIT","",id,DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|WS_BORDER|ES_PASSWORD|ES_AUTOHSCROLL),x,y,430,24,f); SendMessageW(h,UINT(EM_SETLIMITTEXT),16_384,0); return h }
    private static func addButton(_ p: HWND,_ t:String,_ id:Int32,_ x:Int32,_ y:Int32,_ w:Int32,_ h:Int32,_ f:HGDIOBJ?)->HWND? { addControl(p,"BUTTON",t,id,DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|(id == saveID ? BS_DEFPUSHBUTTON : BS_PUSHBUTTON)),x,y,w,h,f) }
    private static func addControl(_ p: HWND,_ k:String,_ t:String,_ id:Int32,_ s:DWORD,_ x:Int32,_ y:Int32,_ w:Int32,_ h:Int32,_ f:HGDIOBJ?)->HWND? { let n=Array(k.utf16)+[0], c=Array(t.utf16)+[0]; let h=n.withUnsafeBufferPointer { nn in c.withUnsafeBufferPointer { cc in CreateWindowExW(0,nn.baseAddress,cc.baseAddress,s,x,y,w,h,p,HMENU(bitPattern:Int(id)),GetModuleHandleW(nil),nil) } }; if let f { SendMessageW(h,UINT(WM_SETFONT),WPARAM(Int(bitPattern:f)),1) }; return h }
    private static func center(_ hwnd: HWND, owner: HWND) { var r=RECT(); GetWindowRect(hwnd,&r); var a=RECT(); let m=MonitorFromWindow(owner,UINT(MONITOR_DEFAULTTONEAREST)); var i=MONITORINFO(); i.cbSize=DWORD(MemoryLayout<MONITORINFO>.size); if m == nil || GetMonitorInfoW(m,&i)==0 { SystemParametersInfoW(UINT(SPI_GETWORKAREA),0,&a,0); i.rcWork=a }; let w=r.right-r.left,h=r.bottom-r.top; SetWindowPos(hwnd,nil,i.rcWork.left+(i.rcWork.right-i.rcWork.left-w)/2,i.rcWork.top+(i.rcWork.bottom-i.rcWork.top-h)/2,0,0,UINT(SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE)) }
    private static func report(_ message:String) { FileHandle.standardError.write(Data((message+"\n").utf8)) }
}
#endif
