#if os(Windows)
import Foundation
import WinSDK
import CodexBarCore

/// Native hook rule form. Returns a validated rule; never saves or executes it.
public enum WindowsHookRuleDialog {
    public static func show(owner: HWND, draft: WindowsHookRuleDraft, isCurrent: (() -> Bool)? = nil)
        -> HookRule?
    {
        let context = Context(initial: draft, owner: owner, isCurrent: isCurrent)
        guard context.inputContextIsValid else { return nil }
        let instance = GetModuleHandleW(nil)
        var klass = WNDCLASSEXW()
        klass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        klass.hInstance = instance; klass.lpfnWndProc = Self.windowProc
        klass.hCursor = LoadCursorW(nil, IDC_ARROW)
        let name = Array(Self.className.utf16) + [0]
        let registered = name.withUnsafeBufferPointer { klass.lpszClassName = $0.baseAddress; return RegisterClassExW(&klass) }
        if registered == 0, GetLastError() != ERROR_CLASS_ALREADY_EXISTS { return nil }
        let title = Array(WindowsStatusLocalization.text("Hook rule").utf16) + [0]
        var frame = RECT(left: 0, top: 0, right: context.pixels(600), bottom: context.pixels(540))
        AdjustWindowRectExForDpi(&frame, DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_HSCROLL | WS_VSCROLL), 0,
                           DWORD(WS_EX_DLGMODALFRAME), context.dpi)
        let hwnd: HWND? = name.withUnsafeBufferPointer { n in
            title.withUnsafeBufferPointer { t in
                CreateWindowExW(DWORD(WS_EX_DLGMODALFRAME), n.baseAddress, t.baseAddress,
                                DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_HSCROLL | WS_VSCROLL),
                                0, 0, frame.right - frame.left, frame.bottom - frame.top, owner, nil,
                                instance, Unmanaged.passUnretained(context).toOpaque())
            }
        }
        guard let hwnd else { return nil }
        context.window = hwnd; context.ownerWasEnabled = IsWindowEnabled(owner) != 0
        center(hwnd, owner: owner); if IsWindow(owner) != 0 { EnableWindow(owner, 0) }
        withExtendedLifetime(context) {
            ShowWindow(hwnd, Int32(SW_SHOW)); UpdateWindow(hwnd); layout(context: context)
            SetFocus(GetDlgItem(hwnd, eventID)); revealFocus(context: context)
            var message = MSG()
            while !context.closed {
                let result = GetMessageW(&message, nil, 0, 0)
                if result == -1 { context.closed = true; break }
                if result == 0 { PostQuitMessage(Int32(message.wParam)); context.closed = true; break }
                guard context.inputContextIsValid else { context.cancel(); break }
                let previousFocus = GetFocus()
                defer {
                    // Combo-box cancellation may restore selection after its notification callback.
                    context.synchronizeArgumentSelection()
                    if !context.closed, GetFocus() != previousFocus { revealFocus(context: context) }
                }
                let target = message.hwnd == hwnd || IsChild(hwnd, message.hwnd) != 0
                if target, message.message == UINT(WM_KEYDOWN),
                   message.wParam == WPARAM(VK_RETURN) || message.wParam == WPARAM(VK_ESCAPE),
                   let focus = GetFocus(),
                   focus == GetDlgItem(hwnd, eventID) || focus == GetDlgItem(hwnd, providerID) || focus == GetDlgItem(hwnd, argumentChoiceID),
                   SendMessageW(focus, UINT(CB_GETDROPPEDSTATE), 0, 0) != 0 {
                    TranslateMessage(&message); DispatchMessageW(&message); continue
                }
                if target, message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_ESCAPE) { context.cancel(); continue }
                if target, message.message == UINT(WM_KEYDOWN), message.wParam == WPARAM(VK_RETURN) {
                    if GetFocus() == GetDlgItem(hwnd, argumentsID) {
                        TranslateMessage(&message); DispatchMessageW(&message); continue
                    }
                    if GetFocus() == GetDlgItem(hwnd, browseID) { context.browseExecutable() }
                    else if GetFocus() == GetDlgItem(hwnd, addArgumentID) { context.addArgument() }
                    else if GetFocus() == GetDlgItem(hwnd, removeArgumentID) { context.removeArgument() }
                    else if GetFocus() == GetDlgItem(hwnd, cancelID) { context.cancel() }
                    else { context.save() }
                    continue
                }
                if IsDialogMessageW(hwnd, &message) == 0 { TranslateMessage(&message); DispatchMessageW(&message) }
            }
        }
        if IsWindow(hwnd) != 0 { DestroyWindow(hwnd) }
        if IsWindow(owner) != 0, context.ownerWasEnabled { EnableWindow(owner, 1); SetForegroundWindow(owner) }
        return context.inputContextIsValid ? context.result : nil
    }

    private static let contextTimer = UINT_PTR(1)
    private static let className = "CodexBar.HookRuleDialog"
    private static let eventID: Int32 = 101, providerID: Int32 = 102, executableID: Int32 = 103
    private static let argumentsID: Int32 = 104, thresholdID: Int32 = 105, timeoutID: Int32 = 106
    private static let enabledID: Int32 = 107, browseID: Int32 = 108, saveID: Int32 = 1, cancelID: Int32 = 2
    private static let argumentChoiceID: Int32 = 109, addArgumentID: Int32 = 110, removeArgumentID: Int32 = 111
    private static let events = HookEventType.allCases
    private static let providers = UsageProvider.allCases.sorted { $0.rawValue < $1.rawValue }

    private final class Context {
        let initial: WindowsHookRuleDraft
        var dpi: UINT
        var font: HFONT?
        var controls: [(handle: HWND, bounds: RECT, isLabel: Bool, isButton: Bool, textInset: Int32)] = []
        var scrollX: Int32 = 0
        var scrollY: Int32 = 0
        var needsRestorePlacement = false
        var argumentValues: [String]
        var selectedArgument: Int?
        var argumentDirty = false
        var loadingArgument = false
        func pixels(_ value: Int32) -> Int32 { Int32((Int64(value) * Int64(self.dpi) + 48) / 96) }
        let owner: HWND
        let expectedPrivacy: Bool
        let isCurrent: (() -> Bool)?
        var inputContextIsValid: Bool {
            IsWindow(self.owner) != 0 &&
                WindowsUsagePresentationSettings.load().hidePersonalInfo == self.expectedPrivacy &&
                (self.isCurrent?() ?? true)
        }
        var window: HWND?; var result: HookRule?; var closed = false; var ownerWasEnabled = false
        init(initial: WindowsHookRuleDraft, owner: HWND, isCurrent: (() -> Bool)?) {
            self.initial = initial; self.owner = owner; self.isCurrent = isCurrent
            self.argumentValues = initial.arguments
            let dpi = GetDpiForWindow(owner); self.dpi = dpi == 0 ? 96 : dpi
            self.expectedPrivacy = WindowsUsagePresentationSettings.load().hidePersonalInfo
        }
        func cancel() {
            self.result = nil; self.closed = true
            if let window { DestroyWindow(window) }
        }
        func report(_ failure: WindowsHookSettingsFailure, argumentIndex: Int? = nil) {
            guard let window else { return }
            let message: String
            let field: Int32
            switch failure {
            case .invalidExecutable:
                message = WindowsStatusLocalization.text("Choose an absolute executable path without surrounding quotes."); field = executableID
            case .invalidProvider:
                message = WindowsStatusLocalization.text("Choose a supported provider or the all-providers option."); field = providerID
            case .invalidThreshold:
                message = WindowsStatusLocalization.text("Enter used percent greater than 0 and at most 100, or leave it blank to use provider thresholds. Use a dot decimal separator."); field = thresholdID
            case .invalidTimeout:
                message = WindowsStatusLocalization.text("Enter a timeout from 0.1 to 300 seconds using a dot decimal separator."); field = timeoutID
            default:
                message = (argumentIndex.map { "Argument \($0 + 1) is invalid. " } ?? "") + WindowsStatusLocalization.text("Use at most 32 arguments. Each argument may use up to 4096 UTF-8 bytes; the complete command may use up to 32 KiB. NUL characters are not supported."); field = argumentsID
            }
            message.withCString(encodedAs: UTF16.self) { text in
                WindowsStatusLocalization.text("Hook rule").withCString(encodedAs: UTF16.self) { title in
                    _ = MessageBoxW(window, text, title, UINT(MB_OK | MB_ICONWARNING))
                }
            }
            if self.inputContextIsValid, IsWindow(window) != 0 {
                SetFocus(GetDlgItem(window, field)); revealFocus(context: self)
            }
            else { self.cancel() }
        }

        func browseExecutable() {
            guard self.inputContextIsValid, !self.closed, let window else { return }
            var path = [WCHAR](repeating: 0, count: 32768)
            let filter = Array("Programs (*.exe;*.com)\0*.exe;*.com\0All files (*.*)\0*.*\0\0".utf16)
            var options = OPENFILENAMEW()
            options.lStructSize = DWORD(MemoryLayout<OPENFILENAMEW>.size)
            options.hwndOwner = window; options.nFilterIndex = 1
            options.Flags = DWORD(OFN_EXPLORER | OFN_NOCHANGEDIR | OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST)
            let accepted = path.withUnsafeMutableBufferPointer { buffer in
                filter.withUnsafeBufferPointer { filters in
                    options.lpstrFile = buffer.baseAddress; options.nMaxFile = DWORD(buffer.count)
                    options.lpstrFilter = filters.baseAddress
                    return GetOpenFileNameW(&options)
                }
            }
            let dialogError = accepted == 0 ? CommDlgExtendedError() : 0
            guard !self.closed, IsWindow(window) != 0 else { return }
            guard self.inputContextIsValid else { self.cancel(); return }
            if accepted == 0 {
                if dialogError != 0 {
                    WindowsStatusLocalization.text("Windows could not open the executable selection dialog.").withCString(encodedAs: UTF16.self) { text in
                        WindowsStatusLocalization.text("Hook rule").withCString(encodedAs: UTF16.self) { title in
                            _ = MessageBoxW(window, text, title, UINT(MB_OK | MB_ICONWARNING))
                        }
                    }
                }
                return
            }
            let selected = String(decoding: path.prefix { $0 != 0 }, as: UTF16.self)
            guard !selected.isEmpty, selected.utf8.count <= HookRule.maximumStringBytes,
                  (selected as NSString).isAbsolutePath else { self.report(.invalidExecutable); return }
            selected.withCString(encodedAs: UTF16.self) { _ = SetWindowTextW(GetDlgItem(window, executableID), $0) }
            SetFocus(GetDlgItem(window, executableID)); revealFocus(context: self)
        }

        func captureArgument() {
            guard self.argumentDirty, let window, let index = self.selectedArgument,
                  self.argumentValues.indices.contains(index) else { return }
            self.argumentValues[index] = readText(GetDlgItem(window, argumentsID))
            self.argumentDirty = false
        }

        func showArgument(_ index: Int?) {
            guard let window else { return }
            self.selectedArgument = index.flatMap { self.argumentValues.indices.contains($0) ? $0 : nil }
            self.loadingArgument = true
            let value = self.selectedArgument.map { self.argumentValues[$0] } ?? ""
            value.withCString(encodedAs: UTF16.self) { _ = SetWindowTextW(GetDlgItem(window, argumentsID), $0) }
            self.loadingArgument = false; self.argumentDirty = false
            EnableWindow(GetDlgItem(window, argumentsID), self.selectedArgument == nil ? 0 : 1)
            EnableWindow(GetDlgItem(window, removeArgumentID), self.selectedArgument == nil ? 0 : 1)
            EnableWindow(GetDlgItem(window, addArgumentID), self.argumentValues.count < HookRule.maximumArgumentCount ? 1 : 0)
        }

        func rebuildArguments(select index: Int?) -> Bool {
            guard let window else { return false }
            let choice = GetDlgItem(window, argumentChoiceID)
            SendMessageW(choice, UINT(CB_RESETCONTENT), 0, 0)
            for offset in self.argumentValues.indices {
                let result = "\(offset + 1)".withCString(encodedAs: UTF16.self) {
                    SendMessageW(choice, UINT(CB_ADDSTRING), 0, LPARAM(Int(bitPattern: $0)))
                }
                guard result != LRESULT(CB_ERR), result != LRESULT(CB_ERRSPACE) else { return false }
            }
            if let index, self.argumentValues.indices.contains(index) {
                SendMessageW(choice, UINT(CB_SETCURSEL), WPARAM(index), 0)
            }
            self.showArgument(index)
            return true
        }

        func synchronizeArgumentSelection() {
            guard !self.closed, let window, IsWindow(window) != 0 else { return }
            let index = Int(SendMessageW(GetDlgItem(window, argumentChoiceID), UINT(CB_GETCURSEL), 0, 0))
            let selected: Int? = self.argumentValues.indices.contains(index) ? index : nil
            guard selected != self.selectedArgument else { return }
            self.captureArgument()
            self.showArgument(selected)
        }

        func addArgument() {
            guard self.inputContextIsValid, !self.closed,
                  self.argumentValues.count < HookRule.maximumArgumentCount else { return }
            self.captureArgument(); self.argumentValues.append("")
            guard self.rebuildArguments(select: self.argumentValues.count - 1) else { self.cancel(); return }
            if let window { SetFocus(GetDlgItem(window, argumentsID)); revealFocus(context: self) }
        }

        func removeArgument() {
            guard self.inputContextIsValid, !self.closed, let index = self.selectedArgument,
                  self.argumentValues.indices.contains(index) else { return }
            self.argumentValues.remove(at: index); self.argumentDirty = false
            let next = self.argumentValues.isEmpty ? nil : min(index, self.argumentValues.count - 1)
            guard self.rebuildArguments(select: next) else { self.cancel(); return }
            if let window { SetFocus(GetDlgItem(window, next == nil ? addArgumentID : argumentChoiceID)) }
        }

        func save() {
            guard self.inputContextIsValid else { self.cancel(); return }
            guard let window else { return }
            var draft = self.initial
            let index = Int(SendMessageW(GetDlgItem(window, eventID), UINT(CB_GETCURSEL), 0, 0))
            guard events.indices.contains(index) else { return }
            draft.event = events[index]
            draft.enabled = SendMessageW(GetDlgItem(window, enabledID), UINT(BM_GETCHECK), 0, 0) == LRESULT(BST_CHECKED)
            let providerIndex = Int(SendMessageW(GetDlgItem(window, providerID), UINT(CB_GETCURSEL), 0, 0))
            guard (0...providers.count).contains(providerIndex) else { self.report(.invalidProvider); return }
            draft.provider = providerIndex == 0 ? nil : providers[providerIndex - 1].rawValue
            draft.executable = readText(GetDlgItem(window, executableID))
            draft.usedPercent = readText(GetDlgItem(window, thresholdID))
            draft.timeoutSeconds = readText(GetDlgItem(window, timeoutID))
            do {
                self.captureArgument()
                draft.arguments = self.argumentValues
                let rule = try draft.rule()
                guard self.inputContextIsValid else { self.cancel(); return }
                self.result = rule; self.closed = true; DestroyWindow(window)
            } catch let failure as WindowsHookSettingsFailure {
                if case .invalidCommand = failure, let index = draft.firstInvalidArgumentIndex {
                    guard self.rebuildArguments(select: index) else { self.cancel(); return }
                    self.report(failure, argumentIndex: index)
                } else {
                    self.report(failure)
                }
            } catch {
                self.report(.invalidCommand)
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
        case UINT(WM_CREATE):
            guard context.inputContextIsValid, createControls(hwnd, context: context),
                  SetTimer(hwnd, contextTimer, 250, nil) != 0 else { return -1 }
            updateFont(context: context)
            return 0
        case UINT(WM_SIZE):
            if wParam == WPARAM(SIZE_MINIMIZED) {
                context.needsRestorePlacement = true
                return 0
            }
            if context.needsRestorePlacement, IsIconic(hwnd) == 0 {
                var restored = RECT()
                if GetWindowRect(hwnd, &restored) != 0 {
                    // Clear before SetWindowPos, which can synchronously send WM_SIZE again.
                    context.needsRestorePlacement = false
                    fitToWorkArea(hwnd, proposed: restored)
                }
                layout(context: context)
                revealFocus(context: context)
            } else {
                layout(context: context)
            }
            return 0
        case UINT(WM_HSCROLL), UINT(WM_VSCROLL):
            scroll(hwnd, context: context, horizontal: message == UINT(WM_HSCROLL), action: UINT(wParam & 0xffff))
            return 0
        case UINT(WM_MOUSEWHEEL):
            let delta = Int32(Int16(truncatingIfNeeded: wParam >> 16))
            context.scrollY -= delta * context.pixels(48) / 120
            layout(context: context)
            return 0
        case UINT(WM_DPICHANGED):
            let dpi = UINT(wParam & 0xffff)
            if dpi != 0 {
                let previous = context.dpi
                context.scrollX = Int32(Int64(context.scrollX) * Int64(dpi) / Int64(previous))
                context.scrollY = Int32(Int64(context.scrollY) * Int64(dpi) / Int64(previous))
                context.dpi = dpi
            }
            updateFont(context: context)
            if IsIconic(hwnd) != 0 {
                context.needsRestorePlacement = true
                return 0
            }
            if let suggested = UnsafeRawPointer(bitPattern: UInt(lParam))?.assumingMemoryBound(to: RECT.self) {
                fitToWorkArea(hwnd, proposed: suggested.pointee)
            }
            layout(context: context)
            revealFocus(context: context)
            return 0
        case UINT(WM_SETTINGCHANGE), UINT(WM_DISPLAYCHANGE):
            if message == UINT(WM_SETTINGCHANGE) { updateFont(context: context) }
            if IsIconic(hwnd) == 0 {
                var current = RECT()
                if GetWindowRect(hwnd, &current) != 0 { fitToWorkArea(hwnd, proposed: current) }
                layout(context: context)
                revealFocus(context: context)
            } else {
                context.needsRestorePlacement = true
            }
            return DefWindowProcW(hwnd, message, wParam, lParam)
        case UINT(WM_TIMER):
            if wParam == WPARAM(contextTimer), !context.inputContextIsValid { context.cancel() }
            return 0
        case UINT(WM_COMMAND):
            switch Int32(wParam & 0xffff) {
            case saveID: context.save()
            case cancelID: context.cancel()
            case browseID: context.browseExecutable()
            case addArgumentID: context.addArgument()
            case removeArgumentID: context.removeArgument()
            case argumentsID:
                if UINT((wParam >> 16) & 0xffff) == UINT(EN_CHANGE), !context.loadingArgument { context.argumentDirty = true }
            case argumentChoiceID:
                if UINT((wParam >> 16) & 0xffff) == UINT(CBN_SELCHANGE) {
                    context.synchronizeArgumentSelection()
                }
            case eventID:
                let index = Int(SendMessageW(GetDlgItem(hwnd, eventID), UINT(CB_GETCURSEL), 0, 0))
                EnableWindow(GetDlgItem(hwnd, thresholdID), events.indices.contains(index) && events[index] == .quotaLow ? 1 : 0)
            default: break
            }
            return 0
        case UINT(WM_CLOSE): context.cancel(); return 0
        case UINT(WM_NCDESTROY):
            _ = KillTimer(hwnd, contextTimer)
            if let font = context.font { DeleteObject(font); context.font = nil }
            context.controls.removeAll()
            context.closed = true; SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), 0); return 0
        default: return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }

    private static func createControls(_ hwnd: HWND, context: Context) -> Bool {
        let font = GetStockObject(DEFAULT_GUI_FONT)
        let draft = context.initial
        guard draft.arguments.count <= HookRule.maximumArgumentCount else { return false }
        context.window = hwnd
        let controls: [HWND?] = [
            addLabel(hwnd, WindowsStatusLocalization.text("hooks_event"), 18, 16, 100, 22, font),
            addControl(hwnd, "COMBOBOX", "", eventID, DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|CBS_DROPDOWNLIST|WS_VSCROLL), 18, 40, 330, 180, font),
            addControl(hwnd, "BUTTON", WindowsStatusLocalization.text("hooks_rule_enabled"), enabledID, DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_AUTOCHECKBOX|BS_MULTILINE), 400, 40, 150, 24, font),
            addLabel(hwnd, WindowsStatusLocalization.text("hooks_provider"), 18, 78, 540, 22, font),
            addControl(hwnd, "COMBOBOX", "", providerID, DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|CBS_DROPDOWNLIST|WS_VSCROLL), 18, 102, 560, 240, font),
            addLabel(hwnd, WindowsStatusLocalization.text("hooks_executable") + WindowsStatusLocalization.text(" (absolute path, without surrounding quotes)"), 18, 136, 560, 22, font),
            addEdit(hwnd, draft.executable, executableID, 18, 160, 446, 24, 4096, false, font),
            addButton(hwnd, WindowsStatusLocalization.text("Browse…"), browseID, 478, 160, 100, 28, font),
            addLabel(hwnd, WindowsStatusLocalization.text("hooks_arguments_placeholder") + WindowsStatusLocalization.text(" (one value per item; empty values are kept)"), 18, 194, 560, 22, font),
            addControl(hwnd, "COMBOBOX", "", argumentChoiceID, DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|CBS_DROPDOWNLIST|WS_VSCROLL), 18, 218, 200, 180, font),
            addButton(hwnd, WindowsStatusLocalization.text("Add argument"), addArgumentID, 232, 218, 166, 28, font),
            addButton(hwnd, WindowsStatusLocalization.text("Remove argument"), removeArgumentID, 410, 218, 168, 28, font),
            addEdit(hwnd, "", argumentsID, 18, 256, 560, 92, 262144, true, font),
            addLabel(hwnd, WindowsStatusLocalization.text("hooks_threshold") + WindowsStatusLocalization.text(" % (blank = provider thresholds)"), 18, 362, 355, 22, font),
            addEdit(hwnd, draft.usedPercent, thresholdID, 18, 388, 250, 24, 64, false, font),
            addLabel(hwnd, WindowsStatusLocalization.text("Timeout seconds (0.1–300)"), 318, 362, 260, 22, font),
            addEdit(hwnd, draft.timeoutSeconds, timeoutID, 318, 388, 260, 24, 64, false, font),
            addLabel(hwnd, WindowsStatusLocalization.text("Use dot decimals. Saving this form does not run the command."), 18, 426, 560, 22, font),
            addButton(hwnd, WindowsStatusLocalization.text("Save"), saveID, 370, 480, 100, 28, font),
            addButton(hwnd, WindowsStatusLocalization.text("Cancel"), cancelID, 478, 480, 100, 28, font)
        ]
        guard controls.allSatisfy({ $0 != nil }),
              context.rebuildArguments(select: draft.arguments.isEmpty ? nil : 0) else { return false }
        for event in events {
            let result = event.rawValue.withCString(encodedAs: UTF16.self) {
                SendMessageW(GetDlgItem(hwnd, eventID), UINT(CB_ADDSTRING), 0, LPARAM(Int(bitPattern: $0)))
            }
            guard result != LRESULT(CB_ERR), result != LRESULT(CB_ERRSPACE) else { return false }
        }
        let providerLabels = [WindowsStatusLocalization.text("hooks_any_provider")] + providers.map { ProviderDescriptorRegistry.descriptor(for: $0).metadata.displayName + " (" + $0.rawValue + ")" }
        for label in providerLabels {
            let result = label.withCString(encodedAs: UTF16.self) {
                SendMessageW(GetDlgItem(hwnd, providerID), UINT(CB_ADDSTRING), 0, LPARAM(Int(bitPattern: $0)))
            }
            guard result != LRESULT(CB_ERR), result != LRESULT(CB_ERRSPACE) else { return false }
        }
        // An unknown stored ID must require explicit selection, never silently widen to all providers.
        let providerIndex = draft.provider.flatMap { id in providers.firstIndex { $0.rawValue == id }.map { $0 + 1 } }
        if draft.provider == nil || providerIndex != nil {
            SendMessageW(GetDlgItem(hwnd, providerID), UINT(CB_SETCURSEL), WPARAM(providerIndex ?? 0), 0)
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
    private static func addLabel(_ p: HWND,_ t:String,_ x:Int32,_ y:Int32,_ w:Int32,_ h:Int32,_ f:HGDIOBJ?)->HWND? { addControl(p,"STATIC",t,0,DWORD(WS_CHILD|WS_VISIBLE|SS_NOPREFIX),x,y,w,h,f) }
    private static func addButton(_ p: HWND,_ t:String,_ id:Int32,_ x:Int32,_ y:Int32,_ w:Int32,_ h:Int32,_ f:HGDIOBJ?)->HWND? { addControl(p,"BUTTON",t,id,DWORD(WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_MULTILINE|(id == saveID ? BS_DEFPUSHBUTTON : BS_PUSHBUTTON)),x,y,w,h,f) }
    private static func addControl(_ parent: HWND, _ kind: String, _ text: String, _ id: Int32,
                                   _ style: DWORD, _ x: Int32, _ y: Int32, _ width: Int32, _ height: Int32,
                                   _ fallbackFont: HGDIOBJ?) -> HWND? {
        let pointer = GetWindowLongPtrW(parent, Int32(GWLP_USERDATA))
        guard pointer != 0, let raw = UnsafeRawPointer(bitPattern: UInt(pointer)) else { return nil }
        let context = Unmanaged<Context>.fromOpaque(raw).takeUnretainedValue()
        let handle = kind.withCString(encodedAs: UTF16.self) { klass in
            text.withCString(encodedAs: UTF16.self) { title in
                CreateWindowExW(0, klass, title, style, context.pixels(x), context.pixels(y),
                    context.pixels(width), context.pixels(height), parent, HMENU(bitPattern: Int(id)), GetModuleHandleW(nil), nil)
            }
        }
        if let handle {
            context.controls.append((handle, RECT(left: x, top: y, right: x + width, bottom: y + height), kind == "STATIC", kind == "BUTTON", kind == "BUTTON" ? (id == enabledID ? 28 : 16) : 0))
            if let fallbackFont { SendMessageW(handle, UINT(WM_SETFONT), WPARAM(Int(bitPattern: fallbackFont)), 1) }
        }
        return handle
    }

    private static func layout(context: Context) {
        guard let window = context.window, IsIconic(window) == 0 else { return }
        var client = RECT()
        guard GetClientRect(window, &client) != 0 else { return }
        // Wrapping controls share row growth so labels, actions, and subsequent fields stay aligned.
        var rowGrowth: [Int32: Int32] = [:]
        if let dc = GetDC(window) {
            let font = context.font ?? GetStockObject(DEFAULT_GUI_FONT)
            let previous = font.map { SelectObject(dc, $0) }
            for control in context.controls where control.isLabel || control.isButton {
                let r = control.bounds
                var measured = RECT(left: 0, top: 0, right: max(1, context.pixels(r.right - r.left - control.textInset)), bottom: 0)
                var text = Array(readText(control.handle).utf16) + [WCHAR(0)]
                let height = text.withUnsafeMutableBufferPointer {
                    DrawTextW(dc, $0.baseAddress, -1, &measured, UINT(DT_CALCRECT | DT_WORDBREAK) | (control.isLabel ? UINT(DT_NOPREFIX) : 0))
                }
                if height > 0 {
                    let growth = max(0, measured.bottom - measured.top + context.pixels(control.isButton ? 12 : 2) - context.pixels(r.bottom - r.top))
                    rowGrowth[r.top] = max(rowGrowth[r.top] ?? 0, growth)
                }
            }
            if let previous { SelectObject(dc, previous) }
            ReleaseDC(window, dc)
        }
        func update(_ bar: Int32, extent: Int32, page: Int32, position: inout Int32) {
            position = max(0, min(position, max(0, extent - page)))
            var info = SCROLLINFO()
            info.cbSize = UINT(MemoryLayout<SCROLLINFO>.size)
            info.fMask = UINT(SIF_RANGE | SIF_PAGE | SIF_POS | SIF_DISABLENOSCROLL)
            info.nMin = 0; info.nMax = max(0, extent - 1)
            info.nPage = UINT(max(1, page)); info.nPos = position
            SetScrollInfo(window, bar, &info, 1)
        }
        update(Int32(SB_HORZ), extent: context.pixels(600), page: client.right, position: &context.scrollX)
        update(Int32(SB_VERT), extent: context.pixels(540) + rowGrowth.values.reduce(0, +), page: client.bottom, position: &context.scrollY)
        for control in context.controls {
            let r = control.bounds
            let precedingGrowth = rowGrowth.reduce(Int32(0)) { total, row in
                total + (row.key < r.top ? row.value : 0)
            }
            let height = context.pixels(r.bottom - r.top) + ((control.isLabel || control.isButton) ? (rowGrowth[r.top] ?? 0) : 0)
            SetWindowPos(control.handle, nil, context.pixels(r.left) - context.scrollX,
                context.pixels(r.top) + precedingGrowth - context.scrollY, context.pixels(r.right - r.left),
                height, UINT(SWP_NOZORDER | SWP_NOACTIVATE))
        }
    }

    /// Reveal only on focus changes so scrolling does not snap back to the active field.
    private static func revealFocus(context: Context) {
        guard !context.closed, let window = context.window, IsWindow(window) != 0, IsIconic(window) == 0,
              let focus = GetFocus(), IsChild(window, focus) != 0 else { return }
        var bounds = RECT(), client = RECT()
        guard GetWindowRect(focus, &bounds) != 0, GetClientRect(window, &client) != 0,
              client.right > 0, client.bottom > 0 else { return }
        var origin = POINT(x: bounds.left, y: bounds.top)
        guard ScreenToClient(window, &origin) != 0 else { return }
        let margin = context.pixels(8)
        func adjustment(start: Int32, size: Int32, viewport: Int32) -> Int32 {
            // Oversized controls expose their leading edge; their own scrolling handles content.
            if size + margin * 2 > viewport || start < margin { return start - margin }
            if start + size > viewport - margin { return start + size - viewport + margin }
            return 0
        }
        let dx = adjustment(start: origin.x, size: bounds.right - bounds.left, viewport: client.right)
        let dy = adjustment(start: origin.y, size: bounds.bottom - bounds.top, viewport: client.bottom)
        guard dx != 0 || dy != 0 else { return }
        context.scrollX += dx; context.scrollY += dy
        layout(context: context)
    }

    private static func scroll(_ window: HWND, context: Context, horizontal: Bool, action: UINT) {
        var info = SCROLLINFO()
        info.cbSize = UINT(MemoryLayout<SCROLLINFO>.size); info.fMask = UINT(SIF_ALL)
        guard GetScrollInfo(window, horizontal ? Int32(SB_HORZ) : Int32(SB_VERT), &info) != 0 else { return }
        var position = horizontal ? context.scrollX : context.scrollY
        switch action {
        case UINT(SB_LINEUP): position -= context.pixels(24)
        case UINT(SB_LINEDOWN): position += context.pixels(24)
        case UINT(SB_PAGEUP): position -= Int32(info.nPage)
        case UINT(SB_PAGEDOWN): position += Int32(info.nPage)
        case UINT(SB_THUMBPOSITION), UINT(SB_THUMBTRACK): position = info.nTrackPos
        case UINT(SB_TOP): position = 0
        case UINT(SB_BOTTOM): position = info.nMax
        default: return
        }
        if horizontal { context.scrollX = position } else { context.scrollY = position }
        layout(context: context)
    }

    private static func updateFont(context: Context) {
        var metrics = NONCLIENTMETRICSW()
        metrics.cbSize = UINT(MemoryLayout<NONCLIENTMETRICSW>.size)
        guard SystemParametersInfoForDpi(UINT(SPI_GETNONCLIENTMETRICS), metrics.cbSize, &metrics, 0, context.dpi) != 0,
              let font = CreateFontIndirectW(&metrics.lfMessageFont) else { return }
        let previous = context.font
        context.font = font
        for control in context.controls {
            SendMessageW(control.handle, UINT(WM_SETFONT), WPARAM(Int(bitPattern: font)), 1)
        }
        if let previous { DeleteObject(previous) }
    }
    /// Use the destination rectangle rather than the owner's monitor during DPI transitions.
    private static func fitToWorkArea(_ hwnd: HWND, proposed: RECT) {
        var rect = proposed
        var monitor = MONITORINFO(); monitor.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        let handle = MonitorFromRect(&rect, UINT(MONITOR_DEFAULTTONEAREST))
        if handle == nil || GetMonitorInfoW(handle, &monitor) == 0 {
            guard SystemParametersInfoW(UINT(SPI_GETWORKAREA), 0, &monitor.rcWork, 0) != 0 else { return }
        }
        let work = monitor.rcWork
        guard work.right > work.left, work.bottom > work.top else { return }
        let width = min(max(1, rect.right - rect.left), work.right - work.left)
        let height = min(max(1, rect.bottom - rect.top), work.bottom - work.top)
        let x = min(max(rect.left, work.left), work.right - width)
        let y = min(max(rect.top, work.top), work.bottom - height)
        var current = RECT()
        if GetWindowRect(hwnd, &current) != 0,
           current.left == x, current.top == y,
           current.right - current.left == width, current.bottom - current.top == height { return }
        SetWindowPos(hwnd, nil, x, y, width, height, UINT(SWP_NOZORDER | SWP_NOACTIVATE))
    }

    private static func center(_ hwnd: HWND, owner: HWND) {
        var rect = RECT()
        guard GetWindowRect(hwnd, &rect) != 0 else { return }
        var monitor = MONITORINFO(); monitor.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        let handle = MonitorFromWindow(owner, UINT(MONITOR_DEFAULTTONEAREST))
        if handle == nil || GetMonitorInfoW(handle, &monitor) == 0 {
            guard SystemParametersInfoW(UINT(SPI_GETWORKAREA), 0, &monitor.rcWork, 0) != 0 else { return }
        }
        let work = monitor.rcWork
        let width = min(rect.right - rect.left, max(1, work.right - work.left))
        let height = min(rect.bottom - rect.top, max(1, work.bottom - work.top))
        SetWindowPos(hwnd, nil, work.left + (work.right - work.left - width) / 2,
            work.top + (work.bottom - work.top - height) / 2, width, height, UINT(SWP_NOZORDER | SWP_NOACTIVATE))
    }
}
#endif
