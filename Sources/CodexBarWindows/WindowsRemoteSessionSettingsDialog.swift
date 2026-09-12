#if os(Windows)
import CodexBarCore
import Foundation
import WinSDK

public enum WindowsRemoteSessionSettingsDialog {
    private static let className = "CodexBar.RemoteSessionSettings"
    private static let enabledID: Int32 = 101, discoveryID: Int32 = 102, listID: Int32 = 103
    private static let hostID: Int32 = 104, pathID: Int32 = 105, windowsID: Int32 = 106, posixID: Int32 = 107
    private static let applyID: Int32 = 108, newID: Int32 = 109, removeID: Int32 = 110
    private static let saveID: Int32 = 1, cancelID: Int32 = 2

    public static func show(owner: HWND, settings: WindowsRemoteSessionSettings) -> WindowsRemoteSessionSettings? {
        let context = Context(settings: settings)
        var klass = WNDCLASSEXW()
        klass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        klass.hInstance = GetModuleHandleW(nil); klass.lpfnWndProc = Self.windowProc
        klass.hCursor = LoadCursorW(nil, IDC_ARROW)
        let name = Array(self.className.utf16) + [0]
        let atom = name.withUnsafeBufferPointer { klass.lpszClassName = $0.baseAddress; return RegisterClassExW(&klass) }
        if atom == 0, GetLastError() != ERROR_CLASS_ALREADY_EXISTS { return nil }
        let title = Array("Remote sessions".utf16) + [0]
        let window = name.withUnsafeBufferPointer { n in
            title.withUnsafeBufferPointer { t in
                CreateWindowExW(DWORD(WS_EX_DLGMODALFRAME), n.baseAddress, t.baseAddress,
                                DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU), CW_USEDEFAULT, CW_USEDEFAULT,
                                700, 435, owner, nil, GetModuleHandleW(nil), Unmanaged.passUnretained(context).toOpaque())
            }
        }
        guard let window else { return nil }
        context.window = window
        let restoreOwner = IsWindowEnabled(owner) != 0
        EnableWindow(owner, 0)
        withExtendedLifetime(context) {
            ShowWindow(window, SW_SHOW); UpdateWindow(window)
            var message = MSG()
            while !context.closed {
                let result = GetMessageW(&message, nil, 0, 0)
                if result == 0 { PostQuitMessage(Int32(message.wParam)); break }
                if result < 0 { break }
                let belongs = message.hwnd == window || IsChild(window, message.hwnd) != 0
                if belongs, message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_ESCAPE) {
                    context.close(); continue
                }
                if IsDialogMessageW(window, &message) == 0 { TranslateMessage(&message); DispatchMessageW(&message) }
            }
        }
        if IsWindow(window) != 0 { DestroyWindow(window) }
        if IsWindow(owner) != 0, restoreOwner { EnableWindow(owner, 1); SetForegroundWindow(owner) }
        return context.result
    }

    private final class Context {
        var settings: WindowsRemoteSessionSettings
        var selected: Int?
        var window: HWND?
        var closed = false
        var result: WindowsRemoteSessionSettings?
        init(settings: WindowsRemoteSessionSettings) { self.settings = settings }

        func install(_ window: HWND) -> Bool {
            self.window = window
            control(window, "BUTTON", "Enable remote session access", enabledID, 16, 14, 300, 24, DWORD(BS_AUTOCHECKBOX))
            control(window, "BUTTON", "Discover online Tailscale hosts", discoveryID, 16, 42, 300, 24, DWORD(BS_AUTOCHECKBOX))
            setChecked(window, enabledID, self.settings.enabled); setChecked(window, discoveryID, self.settings.discoverTailscale)
            control(window, "LISTBOX", "", listID, 16, 78, 245, 245, DWORD(WS_BORDER | WS_VSCROLL | LBS_NOTIFY))
            control(window, "STATIC", "Host (user@host)", 0, 280, 80, 390, 20, 0)
            control(window, "EDIT", "", hostID, 280, 103, 390, 25, DWORD(WS_BORDER | ES_AUTOHSCROLL))
            control(window, "BUTTON", "Windows", windowsID, 280, 142, 140, 24, DWORD(BS_AUTORADIOBUTTON | WS_GROUP))
            control(window, "BUTTON", "POSIX (Linux / macOS)", posixID, 425, 142, 245, 24, DWORD(BS_AUTORADIOBUTTON))
            control(window, "STATIC", "Remote CLI path (optional; otherwise PATH)", 0, 280, 179, 390, 20, 0)
            control(window, "EDIT", "", pathID, 280, 203, 390, 25, DWORD(WS_BORDER | ES_AUTOHSCROLL | WS_GROUP))
            control(window, "BUTTON", "Add / update host", applyID, 280, 249, 180, 28, DWORD(BS_PUSHBUTTON))
            control(window, "BUTTON", "New", newID, 470, 249, 85, 28, DWORD(BS_PUSHBUTTON))
            control(window, "BUTTON", "Remove", removeID, 565, 249, 105, 28, DWORD(BS_PUSHBUTTON))
            control(window, "STATIC", "Uses SSH batch mode. Unknown hosts must have an OS selected.", 0, 16, 337, 650, 20, 0)
            control(window, "BUTTON", "Save", saveID, 480, 367, 90, 28, DWORD(BS_DEFPUSHBUTTON))
            control(window, "BUTTON", "Cancel", cancelID, 580, 367, 90, 28, DWORD(BS_PUSHBUTTON))
            guard [enabledID, discoveryID, listID, hostID, pathID, windowsID, posixID,
                   applyID, newID, removeID, saveID, cancelID].allSatisfy({ GetDlgItem(window, $0) != nil })
            else { return false }
            SendMessageW(GetDlgItem(window, hostID), UINT(EM_SETLIMITTEXT), 1024, 0)
            SendMessageW(GetDlgItem(window, pathID), UINT(EM_SETLIMITTEXT), 4096, 0)
            self.reloadList()
            return true
        }

        func reloadList() {
            guard let window else { return }
            let list = GetDlgItem(window, listID)
            SendMessageW(list, UINT(LB_RESETCONTENT), 0, 0)
            for target in self.settings.targets {
                target.configurationValue.withCString(encodedAs: UTF16.self) {
                    _ = SendMessageW(list, UINT(LB_ADDSTRING), 0, LPARAM(Int(bitPattern: $0)))
                }
            }
        }

        func selectHost() {
            guard let window else { return }
            let index = Int(SendMessageW(GetDlgItem(window, listID), UINT(LB_GETCURSEL), 0, 0))
            guard self.settings.targets.indices.contains(index) else { return }
            if self.hasDraftChanges(), !self.applyHost(allowBlank: true) {
                let previous = self.selected.map { WPARAM($0) } ?? WPARAM.max
                SendMessageW(GetDlgItem(window, listID), UINT(LB_SETCURSEL), previous, 0)
                return
            }
            self.selected = index
            SendMessageW(GetDlgItem(window, listID), UINT(LB_SETCURSEL), WPARAM(index), 0)
            let target = self.settings.targets[index]
            setText(window, hostID, target.host); setText(window, pathID, target.executablePath ?? "")
            setChecked(window, windowsID, target.platform == .windows); setChecked(window, posixID, target.platform == .posix)
        }

        func hasDraftChanges() -> Bool {
            guard let window, let host = text(window, hostID, limit: 1024),
                  let path = text(window, pathID, limit: 4096) else { return true }
            let platform: RemoteSessionPlatform = checked(window, windowsID) ? .windows :
                (checked(window, posixID) ? .posix : .unspecified)
            if let selected, self.settings.targets.indices.contains(selected) {
                let original = self.settings.targets[selected]
                return host != original.host || path != (original.executablePath ?? "") || platform != original.platform
            }
            return !host.isEmpty || !path.isEmpty
        }

        func newHost() {
            guard let window else { return }
            self.selected = nil
            setText(window, hostID, ""); setText(window, pathID, "")
            setChecked(window, windowsID, false); setChecked(window, posixID, false)
            SendMessageW(GetDlgItem(window, listID), UINT(LB_SETCURSEL), WPARAM.max, 0)
            SetFocus(GetDlgItem(window, hostID))
        }

        func applyHost(allowBlank: Bool) -> Bool {
            guard let window, let rawHost = text(window, hostID, limit: 1024),
                  let rawPath = text(window, pathID, limit: 4096) else { return false }
            let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
            if host.isEmpty, rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               allowBlank, self.selected == nil { return true }
            let platform: RemoteSessionPlatform = checked(window, windowsID) ? .windows :
                (checked(window, posixID) ? .posix : .unspecified)
            let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = RemoteSessionTarget(host: host, platform: platform, executablePath: path.isEmpty ? nil : path)
            if let error = target.configurationError { report(window, error); return false }
            if self.settings.targets.enumerated().contains(where: { $0.offset != self.selected && $0.element.id == target.id }) {
                report(window, "This host is already configured."); return false
            }
            if let selected = self.selected { self.settings.targets[selected] = target }
            else {
                guard self.settings.targets.count < 32 else { report(window, "Up to 32 hosts can be configured."); return false }
                self.settings.targets.append(target); self.selected = self.settings.targets.count - 1
            }
            self.reloadList()
            if let selected = self.selected { SendMessageW(GetDlgItem(window, listID), UINT(LB_SETCURSEL), WPARAM(selected), 0) }
            return true
        }

        func removeHost() {
            guard let selected, self.settings.targets.indices.contains(selected) else { return }
            self.settings.targets.remove(at: selected); self.reloadList(); self.newHost()
        }

        func save() {
            guard let window, self.applyHost(allowBlank: true) else { return }
            guard self.settings.targets.allSatisfy({ $0.configurationError == nil }) else {
                report(window, "Select an OS for every saved host before saving."); return
            }
            self.settings.enabled = checked(window, enabledID)
            self.settings.discoverTailscale = checked(window, discoveryID)
            self.result = self.settings; self.close()
        }

        func close() { self.closed = true; if let window, IsWindow(window) != 0 { DestroyWindow(window) } }
    }

    private static let windowProc: WNDPROC = { window, message, wParam, lParam in
        guard let window else { return DefWindowProcW(window, message, wParam, lParam) }
        if message == UINT(WM_NCCREATE), let pointer = UnsafeRawPointer(bitPattern: Int(lParam)) {
            let creation = pointer.assumingMemoryBound(to: CREATESTRUCTW.self).pointee
            if let context = creation.lpCreateParams {
                SetWindowLongPtrW(window, Int32(GWLP_USERDATA), LONG_PTR(Int(bitPattern: context)))
            }
        }
        let value = GetWindowLongPtrW(window, Int32(GWLP_USERDATA))
        guard value != 0, let pointer = UnsafeRawPointer(bitPattern: Int(value)) else {
            return DefWindowProcW(window, message, wParam, lParam)
        }
        let context = Unmanaged<Context>.fromOpaque(pointer).takeUnretainedValue()
        if message == UINT(WM_CREATE) { return context.install(window) ? 0 : -1 }
        if message == UINT(WM_CLOSE) { context.close(); return 0 }
        if message == UINT(WM_COMMAND) {
            let id = Int32(wParam & 0xFFFF), notification = Int32((wParam >> 16) & 0xFFFF)
            if id == listID, notification == Int32(LBN_SELCHANGE) { context.selectHost(); return 0 }
            switch id {
            case applyID: _ = context.applyHost(allowBlank: false)
            case newID: context.newHost()
            case removeID: context.removeHost()
            case saveID: context.save()
            case cancelID: context.close()
            default: break
            }
            return 0
        }
        if message == UINT(WM_NCDESTROY) { context.closed = true; SetWindowLongPtrW(window, Int32(GWLP_USERDATA), 0) }
        return DefWindowProcW(window, message, wParam, lParam)
    }

    private static func control(_ owner: HWND, _ kind: String, _ label: String, _ id: Int32,
                                _ x: Int32, _ y: Int32, _ width: Int32, _ height: Int32, _ style: DWORD) {
        let handle = kind.withCString(encodedAs: UTF16.self) { k in label.withCString(encodedAs: UTF16.self) { t in
            CreateWindowExW(0, k, t, DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP) | style,
                            x, y, width, height, owner, HMENU(bitPattern: Int(id)), GetModuleHandleW(nil), nil)
        } }
        if let font = GetStockObject(DEFAULT_GUI_FONT) {
            SendMessageW(handle, UINT(WM_SETFONT), WPARAM(Int(bitPattern: font)), 1)
        }
    }
    private static func checked(_ window: HWND, _ id: Int32) -> Bool {
        SendMessageW(GetDlgItem(window, id), UINT(BM_GETCHECK), 0, 0) == LRESULT(BST_CHECKED)
    }
    private static func setChecked(_ window: HWND, _ id: Int32, _ checked: Bool) {
        SendMessageW(GetDlgItem(window, id), UINT(BM_SETCHECK), checked ? WPARAM(BST_CHECKED) : WPARAM(BST_UNCHECKED), 0)
    }
    private static func setText(_ window: HWND, _ id: Int32, _ value: String) {
        value.withCString(encodedAs: UTF16.self) { _ = SetWindowTextW(GetDlgItem(window, id), $0) }
    }
    private static func text(_ window: HWND, _ id: Int32, limit: Int) -> String? {
        let handle = GetDlgItem(window, id), count = Int(GetWindowTextLengthW(GetDlgItem(window, id)))
        guard count >= 0, count <= limit else { report(window, "Input is too long."); return nil }
        var buffer = [UInt16](repeating: 0, count: count + 1)
        let copied = GetWindowTextW(handle, &buffer, Int32(buffer.count))
        return String(decoding: buffer.prefix(Int(copied)), as: UTF16.self)
    }
    private static func report(_ window: HWND, _ message: String) {
        message.withCString(encodedAs: UTF16.self) { text in
            "Remote sessions".withCString(encodedAs: UTF16.self) { title in
                _ = MessageBoxW(window, text, title, UINT(MB_OK | MB_ICONERROR))
            }
        }
    }
}
#endif
