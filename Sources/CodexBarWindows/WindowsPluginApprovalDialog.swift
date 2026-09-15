#if os(Windows)
import Foundation
import WinSDK

/// Presents permissions without executing a plugin or persisting approval.
enum WindowsPluginApprovalDialog {
    enum Decision { case approve([String]), revoke, setEnabled(Bool) }
    static func show(owner: HWND, review: WindowsPluginApprovalReview)
        -> Decision?
    {
        let context = Context(review: review)
        let instance = GetModuleHandleW(nil)
        var klass = WNDCLASSEXW()
        klass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        klass.hInstance = instance; klass.lpfnWndProc = Self.windowProc
        klass.hCursor = LoadCursorW(nil, IDC_ARROW)
        let name = Array(Self.className.utf16) + [0]
        let registered = name.withUnsafeBufferPointer { klass.lpszClassName = $0.baseAddress; return RegisterClassExW(&klass) }
        if registered == 0, GetLastError() != ERROR_CLASS_ALREADY_EXISTS { return nil }
        let title = Array(context.localization.text("plugin_approvalTitle").utf16) + [0]
        var frame = RECT(left: 0, top: 0, right: 600, bottom: 570)
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

    private static let className = "CodexBar.PluginApprovalDialog"
    private static let detailsID: Int32 = 101, originsID: Int32 = 102, errorID: Int32 = 103
    private static let saveID: Int32 = 1, cancelID: Int32 = 2, revokeID: Int32 = 3, enabledID: Int32 = 4
    private final class Context {
        let review: WindowsPluginApprovalReview
        let localization = WindowsStatusLocalization.Snapshot()
        var window: HWND?; var result: Decision?; var closed = false; var ownerWasEnabled = false
        init(review: WindowsPluginApprovalReview) { self.review = review }
        func cancel() { closed = true; if let window { DestroyWindow(window) } }
        func toggleEnabled() {
            guard let window, let enabled = review.isEnabled,
                  enabled || (review.approvalAvailable && review.alreadyApproved) else { return }
            result = .setEnabled(!enabled); closed = true; DestroyWindow(window)
        }
        func revoke() {
            guard let window else { return }
            result = .revoke; closed = true; DestroyWindow(window)
        }
        func save() {
            guard let window, review.approvalAvailable else { return }
            var buffer = [WCHAR](repeating: 0, count: 16385)
            let count = GetWindowTextW(GetDlgItem(window, originsID), &buffer, Int32(buffer.count))
            let text = String(decoding: buffer.prefix(Int(count)), as: UTF16.CodeUnit.self)
            let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            guard lines.sorted() == review.binding.typedConfirmationOrigins.sorted() else {
                let message = Array(localization.text("plugin_originsMismatch").utf16) + [0]
                message.withUnsafeBufferPointer { _ = SetWindowTextW(GetDlgItem(window, errorID), $0.baseAddress) }
                SetFocus(GetDlgItem(window, originsID)); return
            }
            result = .approve(lines); closed = true; DestroyWindow(window)
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
            case saveID: context.save(); case cancelID: context.cancel(); case revokeID: context.revoke(); case enabledID: context.toggleEnabled()
            default: break
            }; return 0
        case UINT(WM_CLOSE): context.cancel(); return 0
        case UINT(WM_NCDESTROY): context.closed = true; SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), 0); return 0
        default: return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }

    private static func createControls(_ hwnd: HWND, context: Context) -> Bool {
        let review = context.review, binding = review.binding, l = context.localization
        // Escape control/bidi formatting visibly; never let plugin metadata impersonate permission headings.
        func visible(_ value: String) -> String {
            value.unicodeScalars.map { scalar in
                CharacterSet.controlCharacters.contains(scalar) || CharacterSet(charactersIn: "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}").contains(scalar)
                    ? "\\u{" + String(scalar.value, radix: 16) + "}" : String(scalar)
            }.joined()
        }
        let sections: [(String, [String])] = [
            (l.text("plugin_name"), [review.name, review.instanceID.rawValue]),
            (l.text("plugin_origins"), binding.origins),
            (l.text("plugin_authentication"), [binding.authMode] + (binding.authHeader.map { [$0] } ?? [])),
            (l.text("plugin_secrets"), binding.secretNames),
            (l.text("plugin_capabilities"), binding.capabilities),
            (l.text("plugin_cookieDomains"), binding.cookieDomains),
            (l.text("plugin_typedOrigins"), binding.typedConfirmationOrigins),
        ]
        let permissionDetails = sections.map { heading, values in
            heading + "\r\n" + (values.isEmpty ? l.text("plugin_none") : values.map(visible).joined(separator: "\r\n"))
        }.joined(separator: "\r\n\r\n")
        let details = (review.approvalAvailable ? "" : l.text("plugin_revokeOnly") + "\r\n\r\n") + permissionDetails
        // Refuse oversized reviews rather than approving permissions omitted from the visible text.
        guard details.utf16.count <= 60000 else { return false }
        let font = GetStockObject(DEFAULT_GUI_FONT)
        let usageState: String
        if review.isEnabled == nil {
            usageState = "plugin_usageUnknown"
        } else if review.isEnabled == true {
            if !review.approvalAvailable { usageState = "plugin_enabledUnavailable" }
            else if !review.alreadyApproved { usageState = "plugin_enabledNeedsApproval" }
            else { usageState = "plugin_enabled" }
        } else if !review.approvalAvailable {
            usageState = "plugin_disabledUnavailable"
        } else {
            usageState = review.alreadyApproved ? "plugin_disabled" : "plugin_approveBeforeEnable"
        }
        let controls: [HWND?] = [
            addControl(hwnd, "EDIT", details, detailsID,
                DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|WS_BORDER|WS_VSCROLL|ES_MULTILINE|ES_READONLY), 16, 16, 568, 310, font),
            addControl(hwnd, "STATIC", l.text("plugin_typeOriginsHelp"), 0,
                DWORD(WS_CHILD|WS_VISIBLE), 16, 338, 568, 36, font),
            addControl(hwnd, "EDIT", "", originsID,
                DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|WS_BORDER|WS_VSCROLL|ES_MULTILINE|ES_WANTRETURN), 16, 378, 568, 68, font),
            addControl(hwnd, "STATIC", "", errorID, DWORD(WS_CHILD|WS_VISIBLE), 16, 450, 568, 30, font),
            addControl(hwnd, "BUTTON", l.text(review.isEnabled == true ? "plugin_disable" : "plugin_enable"), enabledID,
                DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_PUSHBUTTON), 16, 486, 230, 28, font),
            addControl(hwnd, "STATIC", l.text(usageState), 0,
                DWORD(WS_CHILD|WS_VISIBLE), 258, 486, 326, 32, font),
            addControl(hwnd, "BUTTON", l.text("plugin_revoke"), revokeID,
                DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_PUSHBUTTON), 16, 526, 230, 28, font),
            addControl(hwnd, "BUTTON", l.text("plugin_approve"), saveID,
                DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_PUSHBUTTON), 350, 526, 112, 28, font),
            addControl(hwnd, "BUTTON", l.text("Cancel"), cancelID,
                DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_DEFPUSHBUTTON), 472, 526, 112, 28, font),
        ]
        guard controls.allSatisfy({ $0 != nil }) else { return false }
        SendMessageW(GetDlgItem(hwnd, originsID), UINT(EM_SETLIMITTEXT), 16384, 0)
        EnableWindow(GetDlgItem(hwnd, originsID), review.approvalAvailable && !binding.typedConfirmationOrigins.isEmpty ? 1 : 0)
        EnableWindow(GetDlgItem(hwnd, saveID), review.approvalAvailable ? 1 : 0)
        let canToggle = review.isEnabled != nil &&
            (review.isEnabled == true || (review.approvalAvailable && review.alreadyApproved))
        EnableWindow(GetDlgItem(hwnd, enabledID), canToggle ? 1 : 0)
        return true
    }
    private static func addControl(_ p: HWND,_ k:String,_ t:String,_ id:Int32,_ s:DWORD,_ x:Int32,_ y:Int32,_ w:Int32,_ h:Int32,_ f:HGDIOBJ?)->HWND? { let n=Array(k.utf16)+[0], c=Array(t.utf16)+[0]; let h=n.withUnsafeBufferPointer { nn in c.withUnsafeBufferPointer { cc in CreateWindowExW(0,nn.baseAddress,cc.baseAddress,s,x,y,w,h,p,HMENU(bitPattern:Int(id)),GetModuleHandleW(nil),nil) } }; if let f { SendMessageW(h,UINT(WM_SETFONT),WPARAM(Int(bitPattern:f)),1) }; return h }
    private static func center(_ hwnd: HWND, owner: HWND) { var r=RECT(); GetWindowRect(hwnd,&r); var a=RECT(); let m=MonitorFromWindow(owner,UINT(MONITOR_DEFAULTTONEAREST)); var i=MONITORINFO(); i.cbSize=DWORD(MemoryLayout<MONITORINFO>.size); if m == nil || GetMonitorInfoW(m,&i)==0 { SystemParametersInfoW(UINT(SPI_GETWORKAREA),0,&a,0); i.rcWork=a }; let w=r.right-r.left,h=r.bottom-r.top; SetWindowPos(hwnd,nil,i.rcWork.left+(i.rcWork.right-i.rcWork.left-w)/2,i.rcWork.top+(i.rcWork.bottom-i.rcWork.top-h)/2,0,0,UINT(SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE)) }
}
#endif
