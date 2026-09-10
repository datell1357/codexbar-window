#if os(Windows)
import Foundation
import WinSDK

/// Minimal Win32 tray host.  The host owns every HWND/HMENU on the thread running
/// `run`; callers may publish rows from any thread through `postRows`.
public final class WindowsTrayHost: @unchecked Sendable {
    /// Callbacks run on the tray UI thread and must only enqueue work; provider
    /// fetches or other blocking operations should be scheduled asynchronously.
    public typealias RefreshHandler = @Sendable () -> Void
    public typealias PowerChangedHandler = @Sendable () -> Void
    public typealias PresentationSettingsChangedHandler = @Sendable () -> Void
    public typealias OptionalUsageSettingsChangedHandler = @Sendable () -> Void
    public typealias RefreshSettingsChangedHandler = @Sendable () -> Void
    public typealias QuitHandler = @Sendable () -> Void

    private static let wakeMessage = UINT(WM_APP) + 1
    private static let refreshCommand = UINT_PTR(0x7001)
    private static let quitCommand = UINT_PTR(0x7002)
    private static let usageBarsShowUsedCommand = UINT_PTR(0x7003)
    private static let resetTimesShowAbsoluteCommand = UINT_PTR(0x7004)
    private static let hidePersonalInfoCommand = UINT_PTR(0x7005)
    private static let showOptionalCreditsAndExtraUsageCommand = UINT_PTR(0x7006)
    private static let refreshFrequencyCommandBase = UINT_PTR(0x7010)
    private static let lowPowerModeOffCommand = UINT_PTR(0x7020)
    private static let lowPowerModeOnCommand = UINT_PTR(0x7021)
    private static let lowPowerModeAutomaticCommand = UINT_PTR(0x7022)
    private static let className = Array("CodexBar.WindowsTrayHost".utf16) + [0]
    private static let taskbarCreated: UINT = {
        "TaskbarCreated".withCString(encodedAs: UTF16.self) { RegisterWindowMessageW($0) }
    }()

    private let onRefresh: RefreshHandler
    private let onPowerChanged: PowerChangedHandler
    private let onMenuOpen: @Sendable () -> Void
    private let onPresentationSettingsChanged: PresentationSettingsChangedHandler
    private let onOptionalUsageSettingsChanged: OptionalUsageSettingsChangedHandler
    private let onRefreshSettingsChanged: RefreshSettingsChangedHandler
    private let onQuit: QuitHandler
    private let presentationDefaults: UserDefaults
    private let mailboxLock = NSLock()
    private var mailboxRows: [String] = []
    private var window: HWND?
    private var runReserved = false
    private var iconInstalled = false
    private var quitInvoked = false

    public init(
        onRefresh: @escaping RefreshHandler,
        onQuit: @escaping QuitHandler,
        onPowerChanged: @escaping PowerChangedHandler = {},
        onMenuOpen: @escaping @Sendable () -> Void = {},
        onPresentationSettingsChanged: @escaping PresentationSettingsChangedHandler = {},
        onOptionalUsageSettingsChanged: @escaping OptionalUsageSettingsChangedHandler = {},
        onRefreshSettingsChanged: @escaping RefreshSettingsChangedHandler = {})
    {
        self.onRefresh = onRefresh
        self.onQuit = onQuit
        self.onPowerChanged = onPowerChanged
        self.onMenuOpen = onMenuOpen
        self.onPresentationSettingsChanged = onPresentationSettingsChanged
        self.onOptionalUsageSettingsChanged = onOptionalUsageSettingsChanged
        self.onRefreshSettingsChanged = onRefreshSettingsChanged
        self.presentationDefaults = UserDefaults(suiteName: WindowsRefreshSettings.suiteName) ?? .standard
    }

    /// Blocks on the Win32 message loop until the host receives WM_CLOSE or Quit.
    public func run() throws {
        self.mailboxLock.lock()
        let alreadyRunning = self.runReserved
        if !alreadyRunning { self.runReserved = true }
        self.mailboxLock.unlock()
        guard !alreadyRunning else { throw TrayError.alreadyRunning }
        defer {
            self.mailboxLock.lock()
            self.runReserved = false
            self.mailboxLock.unlock()
        }
        guard Self.taskbarCreated != 0 else { throw TrayError.win32(GetLastError()) }
        let instance = GetModuleHandleW(nil)
        var windowClass = WNDCLASSEXW()
        windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        windowClass.hInstance = instance
        windowClass.lpfnWndProc = Self.windowProc
        let atom = Self.className.withUnsafeBufferPointer { name in
            windowClass.lpszClassName = name.baseAddress
            return RegisterClassExW(&windowClass)
        }
        if atom == 0 {
            let error = GetLastError()
            // RegisterClassEx reports ERROR_CLASS_ALREADY_EXISTS when a previous
            // host instance registered this process-wide class.
            if error != ERROR_CLASS_ALREADY_EXISTS { throw TrayError.win32(error) }
        }

        let hwnd = Self.className.withUnsafeBufferPointer { name in
            CreateWindowExW(
                0, name.baseAddress, name.baseAddress, DWORD(WS_OVERLAPPED),
                0, 0, 0, 0, nil, nil, instance, Unmanaged.passUnretained(self).toOpaque())
        }
        guard let hwnd else { throw TrayError.win32(GetLastError()) }
        self.mailboxLock.lock()
        self.window = hwnd
        self.mailboxLock.unlock()
        defer {
            self.removeIcon(hwnd)
            if IsWindow(hwnd) != 0 { DestroyWindow(hwnd) }
            self.mailboxLock.lock()
            self.window = nil
            self.mailboxLock.unlock()
        }

        try self.installIcon(hwnd)
        var message = MSG()
        while true {
            let result = GetMessageW(&message, nil, 0, 0)
            if result == -1 { throw TrayError.win32(GetLastError()) }
            if result == 0 { break }
            TranslateMessage(&message)
            DispatchMessageW(&message)
        }
    }

    /// Replaces the rows displayed by the next tray popup and wakes the UI thread.
    public func postRows(_ rows: [String]) {
        self.mailboxLock.lock()
        self.mailboxRows = rows
        let hwnd = self.window
        self.mailboxLock.unlock()
        if let hwnd { PostMessageW(hwnd, Self.wakeMessage, 0, 0) }
    }

    private func installIcon(_ hwnd: HWND) throws {
        var data = NOTIFYICONDATAW()
        data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        data.hWnd = hwnd
        data.uID = 1
        data.uFlags = UINT(NIF_MESSAGE | NIF_ICON)
        data.uCallbackMessage = UINT(WM_USER) + 1
        data.hIcon = LoadIconW(nil, IDI_APPLICATION)
        guard Shell_NotifyIconW(DWORD(NIM_ADD), &data) != 0 else {
            throw TrayError.win32(GetLastError())
        }
        self.iconInstalled = true
    }

    private func removeIcon(_ hwnd: HWND) {
        guard self.iconInstalled else { return }
        var data = NOTIFYICONDATAW()
        data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        data.hWnd = hwnd
        data.uID = 1
        _ = Shell_NotifyIconW(DWORD(NIM_DELETE), &data)
        self.iconInstalled = false
    }

    private func popup() {
        guard let hwnd = self.window, let menu = CreatePopupMenu() else { return }
        self.onMenuOpen()
        self.mailboxLock.lock()
        let rows = self.mailboxRows
        self.mailboxLock.unlock()
        for (index, row) in rows.enumerated() {
            let title = Array(row.utf16) + [0]
            title.withUnsafeBufferPointer { text in
                _ = AppendMenuW(menu, UINT(MF_STRING | MF_GRAYED), UINT_PTR(index + 1), text.baseAddress)
            }
        }
        if !rows.isEmpty { _ = AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil) }
        let showUsed = self.presentationDefaults.object(forKey: "usageBarsShowUsed") as? Bool ?? false
        let showAbsolute = self.presentationDefaults.object(forKey: "resetTimesShowAbsolute") as? Bool ?? false
        let hidePersonalInfo = self.presentationDefaults.object(forKey: "hidePersonalInfo") as? Bool ?? false
        let showOptionalCreditsAndExtraUsage = self.presentationDefaults
            .object(forKey: "showOptionalCreditsAndExtraUsage") as? Bool ?? true
        let showUsedFlags = UINT(MF_STRING) | (showUsed ? UINT(MF_CHECKED) : 0)
        let showAbsoluteFlags = UINT(MF_STRING) | (showAbsolute ? UINT(MF_CHECKED) : 0)
        let hidePersonalInfoFlags = UINT(MF_STRING) | (hidePersonalInfo ? UINT(MF_CHECKED) : 0)
        let showOptionalCreditsAndExtraUsageFlags = UINT(MF_STRING)
            | (showOptionalCreditsAndExtraUsage ? UINT(MF_CHECKED) : 0)
        "Show used usage".withCString(encodedAs: UTF16.self) {
            _ = AppendMenuW(menu, showUsedFlags, Self.usageBarsShowUsedCommand, $0)
        }
        "Show reset times as clock".withCString(encodedAs: UTF16.self) {
            _ = AppendMenuW(menu, showAbsoluteFlags, Self.resetTimesShowAbsoluteCommand, $0)
        }
        "Hide personal info".withCString(encodedAs: UTF16.self) {
            _ = AppendMenuW(menu, hidePersonalInfoFlags, Self.hidePersonalInfoCommand, $0)
        }
        "Show credits + extra usage".withCString(encodedAs: UTF16.self) {
            _ = AppendMenuW(
                menu, showOptionalCreditsAndExtraUsageFlags, Self.showOptionalCreditsAndExtraUsageCommand, $0)
        }
        self.appendRefreshFrequencyMenu(to: menu)
        self.appendLowPowerModeMenu(to: menu)
        _ = AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil)
        "Refresh".withCString(encodedAs: UTF16.self) { _ = AppendMenuW(menu, UINT(MF_STRING), Self.refreshCommand, $0) }
        "Quit".withCString(encodedAs: UTF16.self) { _ = AppendMenuW(menu, UINT(MF_STRING), Self.quitCommand, $0) }
        _ = SetForegroundWindow(hwnd)
        var point = POINT()
        guard GetCursorPos(&point) != 0 else {
            _ = DestroyMenu(menu)
            return
        }
        _ = TrackPopupMenu(menu, UINT(TPM_RIGHTBUTTON), point.x, point.y, 0, hwnd, nil)
        _ = DestroyMenu(menu)
        _ = PostMessageW(hwnd, WM_NULL, 0, 0)
    }

    private func invokeQuit() {
        guard !self.quitInvoked else { return }
        self.quitInvoked = true
        self.onQuit()
        PostQuitMessage(0)
    }

    private func togglePresentationSetting(forKey key: String) {
        let current = self.presentationDefaults.object(forKey: key) as? Bool ?? false
        self.presentationDefaults.set(!current, forKey: key)
        self.onPresentationSettingsChanged()
    }

    private func toggleOptionalUsageSetting() {
        let current = self.presentationDefaults.object(forKey: "showOptionalCreditsAndExtraUsage") as? Bool ?? true
        self.presentationDefaults.set(!current, forKey: "showOptionalCreditsAndExtraUsage")
        self.onOptionalUsageSettingsChanged()
    }

    private static func frequencyCommand(for frequency: WindowsRefreshSettings.Frequency) -> UINT_PTR {
        switch frequency {
        case .manual: Self.refreshFrequencyCommandBase + 0
        case .oneMinute: Self.refreshFrequencyCommandBase + 1
        case .twoMinutes: Self.refreshFrequencyCommandBase + 2
        case .fiveMinutes: Self.refreshFrequencyCommandBase + 3
        case .fifteenMinutes: Self.refreshFrequencyCommandBase + 4
        case .thirtyMinutes: Self.refreshFrequencyCommandBase + 5
        case .adaptive: Self.refreshFrequencyCommandBase + 6
        case .adaptiveAgentAware: Self.refreshFrequencyCommandBase + 7
        }
    }

    private func appendRefreshFrequencyMenu(to menu: HMENU) {
        guard let submenu = CreatePopupMenu() else { return }
        let settings = WindowsRefreshSettings.load(userDefaults: self.presentationDefaults)
        let frequencies: [(WindowsRefreshSettings.Frequency, String, Bool)] = [
            (.manual, "Manual", true),
            (.oneMinute, "1 minute", true),
            (.twoMinutes, "2 minutes", true),
            (.fiveMinutes, "5 minutes", true),
            (.fifteenMinutes, "15 minutes", true),
            (.thirtyMinutes, "30 minutes", true),
            (.adaptive, "Adaptive", true)
        ] + (settings.frequency == .adaptiveAgentAware
            ? [(.adaptiveAgentAware, "Adaptive (agent-aware unavailable)", false)]
            : [])
        for (frequency, label, selectable) in frequencies {
            let checked = settings.frequency == frequency ? UINT(MF_CHECKED) : 0
            let disabled = selectable ? 0 : UINT(MF_GRAYED)
            let flags = UINT(MF_STRING) | checked | disabled
            let appended = label.withCString(encodedAs: UTF16.self) {
                AppendMenuW(submenu, flags, Self.frequencyCommand(for: frequency), $0)
            }
            guard appended != 0 else {
                _ = DestroyMenu(submenu)
                return
            }
        }
        let title = Array("Refresh frequency".utf16) + [0]
        let attached = title.withUnsafeBufferPointer { text in
            AppendMenuW(menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: submenu)), text.baseAddress)
        }
        if attached == 0 { _ = DestroyMenu(submenu) }
    }

    private func selectRefreshFrequency(_ frequency: WindowsRefreshSettings.Frequency) {
        guard frequency != .adaptiveAgentAware else { return }
        let current = WindowsRefreshSettings.load(userDefaults: self.presentationDefaults).frequency
        guard current != frequency else { return }
        self.presentationDefaults.set(frequency.rawValue, forKey: "refreshFrequency")
        self.onRefreshSettingsChanged()
    }

    private static func lowPowerModeCommand(for preference: WindowsRefreshSettings.LowPowerModePreference) -> UINT_PTR {
        switch preference {
        case .off: Self.lowPowerModeOffCommand
        case .on: Self.lowPowerModeOnCommand
        case .automatic: Self.lowPowerModeAutomaticCommand
        }
    }

    private func appendLowPowerModeMenu(to menu: HMENU) {
        guard let submenu = CreatePopupMenu() else { return }
        let settings = WindowsRefreshSettings.load(userDefaults: self.presentationDefaults)
        let preferences: [(WindowsRefreshSettings.LowPowerModePreference, String)] = [
            (.off, "Off"),
            (.on, "On"),
            (.automatic, "Automatic")
        ]
        for (preference, label) in preferences {
            let checked = settings.lowPowerModePreference == preference ? UINT(MF_CHECKED) : 0
            let appended = label.withCString(encodedAs: UTF16.self) {
                AppendMenuW(
                    submenu,
                    UINT(MF_STRING) | checked,
                    Self.lowPowerModeCommand(for: preference),
                    $0)
            }
            guard appended != 0 else {
                _ = DestroyMenu(submenu)
                return
            }
        }
        let title = Array("Background low power mode".utf16) + [0]
        let attached = title.withUnsafeBufferPointer { text in
            AppendMenuW(menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: submenu)), text.baseAddress)
        }
        if attached == 0 { _ = DestroyMenu(submenu) }
    }

    private func selectLowPowerModePreference(_ preference: WindowsRefreshSettings.LowPowerModePreference) {
        let current = WindowsRefreshSettings.load(userDefaults: self.presentationDefaults).lowPowerModePreference
        guard current != preference else { return }
        self.presentationDefaults.set(preference.rawValue, forKey: "backgroundWorkLowPowerModePreference")
        self.onRefreshSettingsChanged()
    }

    private static let windowProc: WNDPROC = { hwnd, message, wParam, lParam in
        guard let hwnd else { return DefWindowProcW(hwnd, message, wParam, lParam) }
        let pointer = GetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA))
        guard pointer != 0 else {
            if message == UINT(WM_NCCREATE), let create = UnsafeMutableRawPointer(bitPattern: UInt(lParam))?.assumingMemoryBound(to: CREATESTRUCTW.self), let owner = create.pointee.lpCreateParams {
                SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), LONG_PTR(Int(bitPattern: owner)))
            }
            return DefWindowProcW(hwnd, message, wParam, lParam)
        }
        let host = Unmanaged<WindowsTrayHost>.fromOpaque(UnsafeRawPointer(bitPattern: UInt(pointer))!).takeUnretainedValue()
        if message == Self.wakeMessage { return 0 }
        if message == Self.taskbarCreated {
            if (try? host.installIcon(hwnd)) == nil { host.invokeQuit() }
            return 0
        }
        // WM_POWERBROADCAST is delivered on this window's UI thread. Keep the
        // callback nonblocking: the application schedules its refresh work.
        // PBT_APMPOWERSTATUSCHANGE covers AC/battery transitions and
        // PBT_APMRESUMEAUTOMATIC covers resume from suspend/hibernate.
        // Battery-saver setting notifications still require explicit
        // RegisterPowerSettingNotification registration, which is not wired yet.
        if message == UINT(WM_POWERBROADCAST),
           wParam == WPARAM(PBT_APMPOWERSTATUSCHANGE)
            || wParam == WPARAM(PBT_APMRESUMEAUTOMATIC)
        {
            host.onPowerChanged()
            return 1
        }
        if message == UINT(WM_CLOSE) { host.invokeQuit(); DestroyWindow(hwnd); return 0 }
        if message == UINT(WM_COMMAND) {
            switch UINT_PTR(wParam & 0xffff) {
            case Self.refreshCommand: host.onRefresh()
            case Self.quitCommand: host.invokeQuit()
            case Self.usageBarsShowUsedCommand: host.togglePresentationSetting(forKey: "usageBarsShowUsed")
            case Self.resetTimesShowAbsoluteCommand: host.togglePresentationSetting(forKey: "resetTimesShowAbsolute")
            case Self.hidePersonalInfoCommand: host.togglePresentationSetting(forKey: "hidePersonalInfo")
            case Self.showOptionalCreditsAndExtraUsageCommand: host.toggleOptionalUsageSetting()
            case Self.lowPowerModeOffCommand: host.selectLowPowerModePreference(.off)
            case Self.lowPowerModeOnCommand: host.selectLowPowerModePreference(.on)
            case Self.lowPowerModeAutomaticCommand: host.selectLowPowerModePreference(.automatic)
            case let command where command >= Self.refreshFrequencyCommandBase
                                  && command <= Self.refreshFrequencyCommandBase + 7:
                let index = command - Self.refreshFrequencyCommandBase
                let frequency = WindowsRefreshSettings.Frequency.allCases[Int(index)]
                host.selectRefreshFrequency(frequency)
            default: break
            }
            return 0
        }
        if message == UINT(WM_USER) + 1, lParam == LPARAM(WM_RBUTTONUP) || lParam == LPARAM(WM_LBUTTONUP) {
            host.popup(); return 0
        }
        if message == UINT(WM_DESTROY) { PostQuitMessage(0); return 0 }
        if message == UINT(WM_NCDESTROY) {
            SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), 0)
            return DefWindowProcW(hwnd, message, wParam, lParam)
        }
        return DefWindowProcW(hwnd, message, wParam, lParam)
    }

    public enum TrayError: Error, Sendable { case alreadyRunning; case win32(UInt32) }
}
#endif
