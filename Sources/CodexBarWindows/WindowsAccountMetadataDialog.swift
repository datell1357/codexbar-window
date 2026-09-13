#if os(Windows)
import Foundation
import WinSDK
import CodexBarCore

/// Edits account routing metadata only; no credential is received by this window.
enum WindowsAccountMetadataDialog {
    enum Result { case cancelled, privacyCancelled, failed, saved(WindowsTokenAccountMetadataPatch) }
    private static let privacyTimer: UINT_PTR = 1
    private static let className = "CodexBar.AccountMetadataDialog"
    private final class Context {
        let support: TokenAccountSupport
        let provider: UsageProvider
        let snapshot: WindowsTokenAccountMetadataSnapshot
        var selectedScope: String?
        var scopeEdited = false
        init(support: TokenAccountSupport, snapshot: WindowsTokenAccountMetadataSnapshot) {
            self.support = support; self.provider = snapshot.provider; self.snapshot = snapshot
            let scope = snapshot.usageScope?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "personal"
            self.selectedScope = ["personal", "team"].contains(scope) ? scope : nil
        }
        var result: Result = .cancelled
        var closed = false
        var dpi: UINT = 96
        var font: HFONT?
        deinit { if let font { DeleteObject(font) } }
        func pixels(_ value: Int32) -> Int32 { MulDiv(value, Int32(self.dpi), 96) }
    }
    static func show(owner: HWND, snapshot: WindowsTokenAccountMetadataSnapshot) -> Result {
        guard !WindowsUsagePresentationSettings.load().hidePersonalInfo else { return .privacyCancelled }
        guard let support = TokenAccountSupportCatalog.support(for: snapshot.provider),
              support.showsOrganizationField || support.showsTeamModeControls else { return .failed }
        // Refuse to silently truncate a legacy value while populating a bounded editor.
        for value in [snapshot.usageScope, snapshot.organizationID, snapshot.workspaceID].compactMap({ $0 }) {
            guard value.utf16.count <= 512, !value.contains("\0") else { return .failed }
        }
        let context = Context(support: support, snapshot: snapshot)
        let providerName = ProviderDescriptorRegistry.descriptor(for: snapshot.provider).metadata.displayName
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
        guard registered != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS else { return .failed }
        let caption = Array(("Edit account scope — " + providerName).utf16) + [0]
        let hwnd = name.withUnsafeBufferPointer { n in
            caption.withUnsafeBufferPointer { c in
                CreateWindowExW(DWORD(WS_EX_DLGMODALFRAME), n.baseAddress, c.baseAddress,
                    DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU), Int32(bitPattern: 0x80000000),
                    Int32(bitPattern: 0x80000000), 460, 210, owner, nil, instance,
                    Unmanaged.passUnretained(context).toOpaque())
            }
        }
        guard let hwnd else { return .failed }
        Self.place(hwnd, near: owner, context: context)
        let wasEnabled = IsWindowEnabled(owner) != 0
        EnableWindow(owner, 0)
        withExtendedLifetime(context) {
            ShowWindow(hwnd, Int32(SW_SHOW)); SetFocus(GetDlgItem(hwnd, context.support.showsTeamModeControls ? 105 : 107))
            var message = MSG()
            while !context.closed {
                let result = GetMessageW(&message, nil, 0, 0)
                if result == -1 { context.result = .failed; break }
                if result == 0 { PostQuitMessage(Int32(message.wParam)); break }
                let target = message.hwnd == hwnd || IsChild(hwnd, message.hwnd) != 0
                if target, message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_ESCAPE) {
                    DestroyWindow(hwnd); continue
                }
                if target, message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_RETURN) {
                    if GetFocus() == GetDlgItem(hwnd, 2) { DestroyWindow(hwnd) }
                    else { Self.save(hwnd, context: context) }
                    continue
                }
                if IsDialogMessageW(hwnd, &message) == 0 { TranslateMessage(&message); DispatchMessageW(&message) }
            }
        }
        if IsWindow(hwnd) != 0 { DestroyWindow(hwnd) }
        if IsWindow(owner) != 0, wasEnabled { EnableWindow(owner, 1); SetForegroundWindow(owner) }
        return context.result
    }
    private static func save(_ hwnd: HWND, context: Context) {
        guard !Self.closeForPrivacyIfNeeded(hwnd, context: context) else { return }
        func read(_ id: Int32, original: String?) -> String? {
            guard let edit = GetDlgItem(hwnd, id) else { return original }
            var buffer = [WCHAR](repeating: 0, count: 514)
            let count = GetWindowTextW(edit, &buffer, Int32(buffer.count))
            let text = String(decoding: buffer.prefix(Int(max(0, count))), as: UTF16.self)
            if text == (original ?? "") { return original }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let snapshot = context.snapshot
        let scope = context.provider == .zai
            ? (context.scopeEdited ? context.selectedScope : snapshot.usageScope)
            : read(105, original: snapshot.usageScope)
        let organization = read(107, original: snapshot.organizationID)
        let workspace = read(109, original: snapshot.workspaceID)
        let invalid = WindowsAccountInputRules.invalidField(label: "", token: "metadata", scope: scope,
            organization: organization, workspace: workspace)
        let issue = WindowsAccountInputRules.providerIssue(provider: context.provider, support: context.support,
            scope: scope, organization: organization, workspace: workspace)
        if let field = invalid ?? issue?.0 {
            let message = invalid != nil ? "Each field must be at most 512 characters without control characters." :
                (issue?.1 ?? "Check the account scope fields.")
            message.withCString(encodedAs: UTF16.self) { SetWindowTextW(GetDlgItem(hwnd, 102), $0) }
            let id: Int32
            switch field {
            case .scope: id = 105
            case .organization: id = 107
            case .workspace: id = 109
            case .label, .token: id = 107
            }
            SetFocus(GetDlgItem(hwnd, id)); return
        }
        context.result = .saved(snapshot.patch(usageScope: scope, organizationID: organization, workspaceID: workspace))
        DestroyWindow(hwnd)
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
            let dpi = GetDpiForWindow(hwnd)
            context.dpi = dpi == 0 ? 96 : dpi
            let rows: [(Int32, String, Int32, Bool, String?)] = [
                (106, "&Usage scope (personal/team)", 105, context.support.showsTeamModeControls, context.snapshot.usageScope),
                (108, "&Organization ID", 107, context.support.showsOrganizationField || context.support.showsTeamModeControls, context.snapshot.organizationID),
                (110, context.provider == .zai ? "&Project ID" : "&Workspace ID", 109, context.support.showsTeamModeControls, context.snapshot.workspaceID)]
            for (labelID, title, editID, visible, value) in rows where visible {
                if editID == 105, context.provider == .zai {
                    guard Self.control(hwnd, "STATIC", "Usage scope", labelID, 0, 0, 0, 1, 1) != nil,
                          Self.control(hwnd, "BUTTON", "&Personal", 105, DWORD(WS_TABSTOP | WS_GROUP | BS_AUTORADIOBUTTON), 0, 0, 1, 1) != nil,
                          Self.control(hwnd, "BUTTON", "&Team", 111, DWORD(WS_TABSTOP | BS_AUTORADIOBUTTON), 0, 0, 1, 1) != nil else { return -1 }
                    continue
                }
                guard Self.control(hwnd, "STATIC", title, labelID, 0, 0, 0, 1, 1) != nil,
                      let edit = Self.control(hwnd, "EDIT", value ?? "", editID,
                          DWORD(WS_TABSTOP | WS_BORDER | ES_AUTOHSCROLL), 0, 0, 1, 1) else { return -1 }
                SendMessageW(edit, UINT(EM_SETLIMITTEXT), 512, 0)
            }
            let guidance = context.provider == .zai
                ? "Team scope requires Organization ID and Project ID. Personal scope does not use them. Clearing a field removes its stored value."
                : "Edit this account's organization. Clearing a field removes its stored value. The credential and account selection are preserved."
            guard Self.control(hwnd, "STATIC", guidance, 102, 0, 0, 0, 1, 1) != nil,
                  Self.control(hwnd, "BUTTON", "Save", 1, DWORD(WS_TABSTOP | BS_DEFPUSHBUTTON), 0, 0, 1, 1) != nil,
                  Self.control(hwnd, "BUTTON", "Cancel", 2, DWORD(WS_TABSTOP | BS_PUSHBUTTON), 0, 0, 1, 1) != nil else { return -1 }
            guard SetTimer(hwnd, Self.privacyTimer, 250, nil) != 0 else { return -1 }
            Self.updateFont(hwnd, context: context)
            Self.updateScope(hwnd, context: context)
            Self.layout(hwnd, context: context)
            return 0
        case UINT(WM_TIMER):
            if wParam == Self.privacyTimer { _ = Self.closeForPrivacyIfNeeded(hwnd, context: context) }
            return 0
        case UINT(WM_ACTIVATE):
            if Self.closeForPrivacyIfNeeded(hwnd, context: context) { return 0 }
            return DefWindowProcW(hwnd, message, wParam, lParam)
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
            Self.layout(hwnd, context: context)
            return DefWindowProcW(hwnd, message, wParam, lParam)
        case UINT(WM_COMMAND):
            switch Int32(wParam & 0xffff) {
            case 1: Self.save(hwnd, context: context)
            case 2: DestroyWindow(hwnd)
            case 105, 111:
                if context.provider == .zai {
                    context.selectedScope = Int32(wParam & 0xffff) == 111 ? "team" : "personal"
                    context.scopeEdited = true
                    Self.updateScope(hwnd, context: context)
                }
            default: break
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
    /// Poll only the local presentation preference; never query credentials or providers.
    private static func closeForPrivacyIfNeeded(_ hwnd: HWND, context: Context) -> Bool {
        guard !context.closed, WindowsUsagePresentationSettings.load().hidePersonalInfo else { return false }
        context.result = .privacyCancelled
        // Hide first, then destroy the native fields. Discard every unsaved edit.
        ShowWindow(hwnd, Int32(SW_HIDE))
        DestroyWindow(hwnd)
        return true
    }

    private static func updateScope(_ hwnd: HWND, context: Context) {
        guard context.provider == .zai else { return }
        SendMessageW(GetDlgItem(hwnd, 105), UINT(BM_SETCHECK), WPARAM(context.selectedScope == "personal" ? BST_CHECKED : BST_UNCHECKED), 0)
        SendMessageW(GetDlgItem(hwnd, 111), UINT(BM_SETCHECK), WPARAM(context.selectedScope == "team" ? BST_CHECKED : BST_UNCHECKED), 0)
        for id in [Int32(107), 108, 109, 110] {
            EnableWindow(GetDlgItem(hwnd, id), context.selectedScope == "personal" ? 0 : 1)
        }
        let guidance: String
        switch context.selectedScope {
        case "personal": guidance = "Personal usage ignores organization and project fields. Stored values are preserved; choose Team to edit or clear them."
        case "team": guidance = "Team usage requires both Organization ID and Project ID. Your credential and account selection are preserved."
        default: guidance = "The stored scope is not recognized. Choose Personal or Team before saving."
        }
        guidance.withCString(encodedAs: UTF16.self) { SetWindowTextW(GetDlgItem(hwnd, 102), $0) }
    }

    private static func updateFont(_ hwnd: HWND, context: Context) {
        var metrics = NONCLIENTMETRICSW()
        metrics.cbSize = UINT(MemoryLayout<NONCLIENTMETRICSW>.size)
        guard SystemParametersInfoForDpi(UINT(SPI_GETNONCLIENTMETRICS), metrics.cbSize,
                                         &metrics, 0, context.dpi) != 0,
              let font = CreateFontIndirectW(&metrics.lfMessageFont) else { return }
        let previous = context.font
        context.font = font
        for id in [Int32(102), 105, 106, 107, 108, 109, 110, 111, 1, 2] {
            if let control = GetDlgItem(hwnd, id) {
                SendMessageW(control, UINT(WM_SETFONT), WPARAM(Int(bitPattern: font)), 1)
            }
        }
        if let previous { DeleteObject(previous) }
    }

    private static func layout(_ hwnd: HWND, context: Context) {
        var rect = RECT()
        guard GetClientRect(hwnd, &rect) != 0 else { return }
        let px = context.pixels
        let width = max(1, rect.right - rect.left - px(32))
        var y: Int32 = 14
        for (labelID, editID) in [(Int32(106), Int32(105)), (108, 107), (110, 109)] {
            guard let edit = GetDlgItem(hwnd, editID) else { continue }
            MoveWindow(GetDlgItem(hwnd, labelID), px(16), px(y), width, px(22), 1)
            if editID == 105, context.provider == .zai {
                let half = max(1, width / 2)
                MoveWindow(edit, px(16), px(y + 24), half, px(26), 1)
                MoveWindow(GetDlgItem(hwnd, 111), px(16) + half, px(y + 24), half, px(26), 1)
            } else { MoveWindow(edit, px(16), px(y + 24), width, px(26), 1) }
            y += 60
        }
        MoveWindow(GetDlgItem(hwnd, 102), px(16), px(y), width, px(60), 1)
        let buttonWidth = min(px(120), max(1, (width - px(10)) / 2))
        MoveWindow(GetDlgItem(hwnd, 1), px(16) + max(0, width - buttonWidth * 2 - px(10)), px(y + 70), buttonWidth, px(28), 1)
        MoveWindow(GetDlgItem(hwnd, 2), px(16) + max(0, width - buttonWidth), px(y + 70), buttonWidth, px(28), 1)
    }

    private static func place(_ hwnd: HWND, near owner: HWND, context: Context) {
        let extraRows = (context.support.showsTeamModeControls ? 2 : 0) +
            (context.support.showsOrganizationField || context.support.showsTeamModeControls ? 1 : 0)
        var frame = RECT(left: 0, top: 0, right: context.pixels(520), bottom: context.pixels(Int32(126 + extraRows * 60)))
        guard AdjustWindowRectExForDpi(&frame, DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU),
                                       0, DWORD(WS_EX_DLGMODALFRAME), context.dpi) != 0 else { return }
        var info = MONITORINFO()
        info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        let monitor = MonitorFromWindow(owner, UINT(MONITOR_DEFAULTTONEAREST))
        let desiredWidth = frame.right - frame.left, desiredHeight = frame.bottom - frame.top
        if GetMonitorInfoW(monitor, &info) != 0,
           info.rcWork.right > info.rcWork.left, info.rcWork.bottom > info.rcWork.top {
            let area = info.rcWork
            let width = min(desiredWidth, area.right - area.left), height = min(desiredHeight, area.bottom - area.top)
            SetWindowPos(hwnd, nil, area.left + (area.right - area.left - width) / 2,
                         area.top + (area.bottom - area.top - height) / 2, width, height,
                         UINT(SWP_NOZORDER | SWP_NOACTIVATE))
        } else {
            SetWindowPos(hwnd, nil, 0, 0, desiredWidth, desiredHeight,
                         UINT(SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE))
        }
    }

    private static func control(_ parent: HWND, _ klass: String, _ text: String, _ id: Int32,
                                _ style: DWORD, _ x: Int32, _ y: Int32, _ width: Int32, _ height: Int32) -> HWND? {
        let control = klass.withCString(encodedAs: UTF16.self) { name in
            text.withCString(encodedAs: UTF16.self) { caption in
                CreateWindowExW(0, name, caption, DWORD(WS_CHILD | WS_VISIBLE) | style,
                    x, y, width, height, parent, HMENU(bitPattern: Int(id)), GetModuleHandleW(nil), nil)
            }
        }
        if let font = GetStockObject(DEFAULT_GUI_FONT) {
            SendMessageW(control, UINT(WM_SETFONT), WPARAM(Int(bitPattern: font)), 1)
        }
        return control
    }
}
#endif
