#if os(Windows)
import Foundation
import WinSDK
import CodexBarCore

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
    public typealias SessionQuotaNotificationSettingsChangedHandler = @Sendable () -> Void
    public typealias QuotaWarningSettingsChangedHandler = @Sendable (WindowsQuotaWarningSettings) -> Void
    public typealias PredictivePaceWarningSettingsChangedHandler =
        @Sendable (WindowsPredictivePaceWarningSettings) -> Void
    public typealias ProviderQuotaWarningLoadHandler = @Sendable (UInt64, ProviderInstanceID) -> Void
    public typealias ProviderQuotaWarningSaveHandler = @Sendable (UInt64, ProviderInstanceID, WindowsProviderQuotaWarningPatch) -> Void
    public typealias CodexWebSettingsLoadHandler = @Sendable (UInt64) -> Void
    public typealias CodexWebSettingsSaveHandler = @Sendable (UInt64, WindowsCodexWebSettingsPatch) -> Void
    public typealias QuitHandler = @Sendable () -> Void

    private static let wakeMessage = UINT(WM_APP) + 1
    private static let refreshCommand = UINT_PTR(0x7001)
    private static let quitCommand = UINT_PTR(0x7002)
    private static let usageBarsShowUsedCommand = UINT_PTR(0x7003)
    private static let resetTimesShowAbsoluteCommand = UINT_PTR(0x7004)
    private static let hidePersonalInfoCommand = UINT_PTR(0x7005)
    private static let showOptionalCreditsAndExtraUsageCommand = UINT_PTR(0x7006)
    private static let sessionQuotaNotificationsCommand = UINT_PTR(0x7007)
    private static let quotaWarningNotificationsCommand = UINT_PTR(0x7008)
    private static let quotaWarningSoundCommand = UINT_PTR(0x7009)
    private static let quotaWarningSettingsCommand = UINT_PTR(0x700A)
    private static let quotaWarningOnScreenAlertCommand = UINT_PTR(0x700B)
    private static let predictivePaceWarningNotificationsCommand = UINT_PTR(0x700C)
    private static let historicalTrackingCommand = UINT_PTR(0x700D)
    private static let codexWebSettingsCommand = UINT_PTR(0x700E)
    private static let weeklyProgressWorkDaysCommandBase = UINT_PTR(0x7060)
    private static let providerQuotaWarningCommandBase = UINT_PTR(0x7400)
    private static let refreshFrequencyCommandBase = UINT_PTR(0x7010)
    private static let lowPowerModeOffCommand = UINT_PTR(0x7020)
    private static let lowPowerModeOnCommand = UINT_PTR(0x7021)
    private static let lowPowerModeAutomaticCommand = UINT_PTR(0x7022)
    private static let statusCommandBase = UINT_PTR(0x7100)
    private static let dashboardCommandBase = UINT_PTR(0x7200)
    private static let changelogCommandBase = UINT_PTR(0x7300)
    private static let className = Array("CodexBar.WindowsTrayHost".utf16) + [0]
    private static let powerSavingStatusGUID = GUID(
        Data1: 0xE00958C0,
        Data2: 0xC213,
        Data3: 0x4ACE,
        Data4: (0xAC, 0x77, 0xFE, 0xCC, 0xED, 0x2E, 0xEE, 0xA5))
    private static let taskbarCreated: UINT = {
        "TaskbarCreated".withCString(encodedAs: UTF16.self) { RegisterWindowMessageW($0) }
    }()

    private let onRefresh: RefreshHandler
    private let onPowerChanged: PowerChangedHandler
    private let onMenuOpen: @Sendable () -> Void
    private let onPresentationSettingsChanged: PresentationSettingsChangedHandler
    private let onOptionalUsageSettingsChanged: OptionalUsageSettingsChangedHandler
    private let onRefreshSettingsChanged: RefreshSettingsChangedHandler
    private let onSessionQuotaNotificationSettingsChanged: SessionQuotaNotificationSettingsChangedHandler
    private let onQuotaWarningSettingsChanged: QuotaWarningSettingsChangedHandler
    private let onProviderQuotaWarningLoad: ProviderQuotaWarningLoadHandler
    private let onProviderQuotaWarningSave: ProviderQuotaWarningSaveHandler
    private let onCodexWebSettingsLoad: CodexWebSettingsLoadHandler
    private let onCodexWebSettingsSave: CodexWebSettingsSaveHandler
    private let onPredictivePaceWarningSettingsChanged: PredictivePaceWarningSettingsChangedHandler
    private let onQuit: QuitHandler
    private let presentationDefaults: UserDefaults
    private let mailboxLock = NSLock()
    private var mailboxRows: [String] = []
    private var mailboxMenuEntries: [WindowsTrayMenuEntry] = []
    private var mailboxSessionQuotaNotifications: [WindowsSessionQuotaNotification] = []
    private var mailboxQuotaWarningNotifications: [WindowsQuotaWarningNotification] = []
    private var mailboxPredictivePaceWarningNotifications: [WindowsPredictivePaceWarningNotification] = []
    private var popupStatusCommands: [UINT_PTR: String] = [:]
    private var popupDashboardCommands: [UINT_PTR: String] = [:]
    private var popupChangelogCommands: [UINT_PTR: String] = [:]
    private var popupProviderQuotaWarningCommands: [UINT_PTR: ProviderInstanceID] = [:]
    private var popupProviderQuotaWarningNames: [ProviderInstanceID: String] = [:]
    private enum ProviderEditorPhase {
        case idle
        case loading(UInt64, ProviderInstanceID, String)
        case editing(UInt64, ProviderInstanceID, String)
        case saving(UInt64, ProviderInstanceID, String, WindowsProviderQuotaWarningPatch)
    }
    private var providerEditorPhase: ProviderEditorPhase = .idle
    private var nextProviderEditorRequestID: UInt64 = 1
    private enum ProviderEditorRequestKind: Equatable { case load, save }
    private struct ProviderEditorExpectedRequest {
        let requestID: UInt64
        let providerID: ProviderInstanceID
        let kind: ProviderEditorRequestKind
    }
    private struct ProviderEditorMailbox {
        let requestID: UInt64
        let providerID: ProviderInstanceID
        let kind: ProviderEditorRequestKind
        let result: WindowsProviderQuotaWarningLoadResult?
        let saveResult: WindowsProviderQuotaWarningSaveResult?
    }
    private var providerEditorExpectedRequest: ProviderEditorExpectedRequest?
    private var providerEditorMailbox: ProviderEditorMailbox?
    private enum CodexWebSettingsEditorPhase {
        case idle
        case loading(UInt64)
        case editing(UInt64)
        case saving(UInt64)
    }
    private var codexWebSettingsEditorPhase: CodexWebSettingsEditorPhase = .idle
    private var nextCodexWebSettingsRequestID: UInt64 = 1
    private enum CodexWebSettingsEditorRequestKind: Equatable { case load, save }
    private struct CodexWebSettingsEditorExpectedRequest {
        let requestID: UInt64
        let kind: CodexWebSettingsEditorRequestKind
    }
    private struct CodexWebSettingsEditorMailbox {
        let requestID: UInt64
        let kind: CodexWebSettingsEditorRequestKind
        let result: WindowsCodexWebSettingsLoadResult?
        let saveResult: WindowsCodexWebSettingsSaveResult?
    }
    private var codexWebSettingsEditorExpectedRequest: CodexWebSettingsEditorExpectedRequest?
    private var codexWebSettingsEditorMailbox: CodexWebSettingsEditorMailbox?
    private var window: HWND?
    // Accessed only on the tray UI thread. The overlay owns its HWND and is
    // dismissed before the tray window is destroyed.
    private var quotaWarningOverlay: WindowsQuotaWarningOverlay?
    private enum WarningOverlayOwner: Equatable { case threshold, predictive }
    private var quotaWarningOverlayOwner: WarningOverlayOwner?
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
        onRefreshSettingsChanged: @escaping RefreshSettingsChangedHandler = {},
        onSessionQuotaNotificationSettingsChanged: @escaping SessionQuotaNotificationSettingsChangedHandler = {},
        onQuotaWarningSettingsChanged: @escaping QuotaWarningSettingsChangedHandler = {},
        onProviderQuotaWarningLoad: @escaping ProviderQuotaWarningLoadHandler = { _, _ in },
        onProviderQuotaWarningSave: @escaping ProviderQuotaWarningSaveHandler = { _, _, _ in },
        onCodexWebSettingsLoad: @escaping CodexWebSettingsLoadHandler = { _ in },
        onCodexWebSettingsSave: @escaping CodexWebSettingsSaveHandler = { _, _ in },
        onPredictivePaceWarningSettingsChanged: @escaping PredictivePaceWarningSettingsChangedHandler = { _ in })
    {
        self.onRefresh = onRefresh
        self.onQuit = onQuit
        self.onPowerChanged = onPowerChanged
        self.onMenuOpen = onMenuOpen
        self.onPresentationSettingsChanged = onPresentationSettingsChanged
        self.onOptionalUsageSettingsChanged = onOptionalUsageSettingsChanged
        self.onRefreshSettingsChanged = onRefreshSettingsChanged
        self.onSessionQuotaNotificationSettingsChanged = onSessionQuotaNotificationSettingsChanged
        self.onQuotaWarningSettingsChanged = onQuotaWarningSettingsChanged
        self.onProviderQuotaWarningLoad = onProviderQuotaWarningLoad
        self.onProviderQuotaWarningSave = onProviderQuotaWarningSave
        self.onCodexWebSettingsLoad = onCodexWebSettingsLoad
        self.onCodexWebSettingsSave = onCodexWebSettingsSave
        self.onPredictivePaceWarningSettingsChanged = onPredictivePaceWarningSettingsChanged
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
        var powerNotification: HPOWERNOTIFY?
        defer {
            self.mailboxLock.lock()
            self.providerEditorExpectedRequest = nil
            self.providerEditorMailbox = nil
            self.codexWebSettingsEditorExpectedRequest = nil
            self.codexWebSettingsEditorMailbox = nil
            self.mailboxSessionQuotaNotifications.removeAll(keepingCapacity: false)
            self.mailboxQuotaWarningNotifications.removeAll(keepingCapacity: false)
            self.mailboxPredictivePaceWarningNotifications.removeAll(keepingCapacity: false)
            self.mailboxLock.unlock()
            self.quotaWarningOverlay?.dismiss()
            self.quotaWarningOverlay = nil
            self.quotaWarningOverlayOwner = nil
            self.removeIcon(hwnd)
            if let powerNotification {
                if UnregisterPowerSettingNotification(powerNotification) == 0 {
                    let error = GetLastError()
                    FileHandle.standardError.write(
                        Data("CodexBar: failed to unregister Battery Saver notification (Win32 error \(error))\n".utf8))
                }
            }
            if IsWindow(hwnd) != 0 { DestroyWindow(hwnd) }
            self.mailboxLock.lock()
            self.window = nil
            self.mailboxLock.unlock()
        }

        var powerSetting = Self.powerSavingStatusGUID
        powerNotification = withUnsafePointer(to: &powerSetting) { setting in
            RegisterPowerSettingNotification(hwnd, setting, 0)
        }
        guard powerNotification != nil else {
            let error = GetLastError()
            FileHandle.standardError.write(
                Data("CodexBar: failed to register Battery Saver notification (Win32 error \(error))\n".utf8))
            throw TrayError.win32(error)
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
        self.postRows(rows, menuEntries: [])
    }

    /// Publishes rows and structured provider actions atomically. The action
    /// list is copied into the next popup, preventing a refreshed snapshot from
    /// reusing command IDs that belonged to an older menu.
    public func postRows(_ rows: [String], menuEntries: [WindowsTrayMenuEntry]) {
        self.mailboxLock.lock()
        self.mailboxRows = rows
        self.mailboxMenuEntries = menuEntries
        let hwnd = self.window
        self.mailboxLock.unlock()
        if let hwnd { PostMessageW(hwnd, Self.wakeMessage, 0, 0) }
    }

    /// Queues a session quota event from any thread. Delivery is bounded and
    /// performed only by the tray UI thread once the icon exists.
    public func postSessionQuotaNotification(_ notification: WindowsSessionQuotaNotification) {
        self.mailboxLock.lock()
        guard !self.quitInvoked else {
            self.mailboxLock.unlock()
            return
        }
        if self.mailboxSessionQuotaNotifications.count >= 16 {
            self.mailboxSessionQuotaNotifications.removeFirst()
        }
        self.mailboxSessionQuotaNotifications.append(notification)
        let hwnd = self.window
        self.mailboxLock.unlock()
        if let hwnd { PostMessageW(hwnd, Self.wakeMessage, 0, 0) }
    }

    /// Queues a threshold warning from any thread. Delivery is bounded and
    /// performed only by the tray UI thread once the icon exists.
    public func postQuotaWarningNotification(_ notification: WindowsQuotaWarningNotification) {
        self.mailboxLock.lock()
        guard !self.quitInvoked else {
            self.mailboxLock.unlock()
            return
        }
        if self.mailboxQuotaWarningNotifications.count >= 16 {
            self.mailboxQuotaWarningNotifications.removeFirst()
        }
        self.mailboxQuotaWarningNotifications.append(notification)
        let hwnd = self.window
        self.mailboxLock.unlock()
        if let hwnd { PostMessageW(hwnd, Self.wakeMessage, 0, 0) }
    }

    public func postPredictivePaceWarningNotification(
        _ notification: WindowsPredictivePaceWarningNotification)
    {
        self.mailboxLock.lock()
        guard !self.quitInvoked else { self.mailboxLock.unlock(); return }
        if self.mailboxPredictivePaceWarningNotifications.count >= 16 {
            self.mailboxPredictivePaceWarningNotifications.removeFirst()
        }
        self.mailboxPredictivePaceWarningNotifications.append(notification)
        let hwnd = self.window
        self.mailboxLock.unlock()
        if let hwnd { PostMessageW(hwnd, Self.wakeMessage, 0, 0) }
    }

    public func postProviderQuotaWarningLoad(
        requestID: UInt64, providerID: ProviderInstanceID, result: WindowsProviderQuotaWarningLoadResult)
    {
        self.mailboxLock.lock()
        guard !self.quitInvoked else { self.mailboxLock.unlock(); return }
        guard let expected = self.providerEditorExpectedRequest,
              expected.requestID == requestID,
              expected.providerID == providerID,
              expected.kind == .load,
              self.providerEditorMailbox == nil else { self.mailboxLock.unlock(); return }
        self.providerEditorMailbox = .init(
            requestID: requestID, providerID: providerID, kind: .load, result: result, saveResult: nil)
        let hwnd = self.window
        self.mailboxLock.unlock()
        if let hwnd { PostMessageW(hwnd, Self.wakeMessage, 0, 0) }
    }

    public func postProviderQuotaWarningSave(
        requestID: UInt64, providerID: ProviderInstanceID, result: WindowsProviderQuotaWarningSaveResult)
    {
        self.mailboxLock.lock()
        guard !self.quitInvoked else { self.mailboxLock.unlock(); return }
        guard let expected = self.providerEditorExpectedRequest,
              expected.requestID == requestID,
              expected.providerID == providerID,
              expected.kind == .save,
              self.providerEditorMailbox == nil else { self.mailboxLock.unlock(); return }
        self.providerEditorMailbox = .init(
            requestID: requestID, providerID: providerID, kind: .save, result: nil, saveResult: result)
        let hwnd = self.window
        self.mailboxLock.unlock()
        if let hwnd { PostMessageW(hwnd, Self.wakeMessage, 0, 0) }
    }

    public func postCodexWebSettingsLoad(
        requestID: UInt64, result: WindowsCodexWebSettingsLoadResult)
    {
        self.mailboxLock.lock()
        guard !self.quitInvoked else { self.mailboxLock.unlock(); return }
        guard let expected = self.codexWebSettingsEditorExpectedRequest,
              expected.requestID == requestID, expected.kind == .load,
              self.codexWebSettingsEditorMailbox == nil else { self.mailboxLock.unlock(); return }
        self.codexWebSettingsEditorMailbox = .init(requestID: requestID, kind: .load, result: result, saveResult: nil)
        let hwnd = self.window
        self.mailboxLock.unlock()
        if let hwnd { PostMessageW(hwnd, Self.wakeMessage, 0, 0) }
    }

    public func postCodexWebSettingsSave(
        requestID: UInt64, result: WindowsCodexWebSettingsSaveResult)
    {
        self.mailboxLock.lock()
        guard !self.quitInvoked else { self.mailboxLock.unlock(); return }
        guard let expected = self.codexWebSettingsEditorExpectedRequest,
              expected.requestID == requestID, expected.kind == .save,
              self.codexWebSettingsEditorMailbox == nil else { self.mailboxLock.unlock(); return }
        self.codexWebSettingsEditorMailbox = .init(requestID: requestID, kind: .save, result: nil, saveResult: result)
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
        self.drainSessionQuotaNotifications()
        self.drainQuotaWarningNotifications()
        self.drainPredictivePaceWarningNotifications()
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
        let menuEntries = self.mailboxMenuEntries
        self.mailboxLock.unlock()
        self.popupStatusCommands.removeAll(keepingCapacity: true)
        self.popupDashboardCommands.removeAll(keepingCapacity: true)
        self.popupChangelogCommands.removeAll(keepingCapacity: true)
        self.popupProviderQuotaWarningCommands.removeAll(keepingCapacity: true)
        self.popupProviderQuotaWarningNames.removeAll(keepingCapacity: true)
        for (index, row) in rows.enumerated() {
            let title = Array(row.utf16) + [0]
            title.withUnsafeBufferPointer { text in
                _ = AppendMenuW(menu, UINT(MF_STRING | MF_GRAYED), UINT_PTR(index + 1), text.baseAddress)
            }
        }
        if !rows.isEmpty { _ = AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil) }
        if !menuEntries.isEmpty, let statusMenu = CreatePopupMenu() {
            var statusItemsAppended = true
            for (index, entry) in menuEntries.enumerated() {
                let command = Self.statusCommandBase + UINT_PTR(index)
                self.popupStatusCommands[command] = entry.statusURL
                let flags = UINT(MF_STRING) | (entry.isEnabled ? 0 : UINT(MF_GRAYED))
                let title = Array(entry.displayTitle.utf16) + [0]
                let appended = title.withUnsafeBufferPointer { text in
                    AppendMenuW(statusMenu, flags, command, text.baseAddress)
                }
                if appended == 0 { statusItemsAppended = false; break }
            }
            let title = Array("Provider status".utf16) + [0]
            let attached = statusItemsAppended && AppendMenuW(
                menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: statusMenu)), title) != 0
            if !attached {
                _ = DestroyMenu(statusMenu)
            }
        }
        let dashboardEntries = menuEntries.filter(\.dashboardVisible)
        if !dashboardEntries.isEmpty, let dashboardMenu = CreatePopupMenu() {
            var itemsAppended = true
            for (index, entry) in dashboardEntries.enumerated() {
                let command = Self.dashboardCommandBase + UINT_PTR(index)
                if let dashboardURL = entry.dashboardURL {
                    self.popupDashboardCommands[command] = dashboardURL
                }
                let flags = UINT(MF_STRING) | (entry.dashboardURL == nil ? UINT(MF_GRAYED) : 0)
                let suffix = entry.dashboardURL == nil ? " dashboard (unavailable)" : " dashboard"
                let title = Array((entry.title + suffix).utf16) + [0]
                let appended = title.withUnsafeBufferPointer { text in
                    AppendMenuW(dashboardMenu, flags, command, text.baseAddress)
                }
                if appended == 0 { itemsAppended = false; break }
            }
            let title = Array("Provider dashboards".utf16) + [0]
            let attached = itemsAppended && AppendMenuW(
                menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: dashboardMenu)), title) != 0
            if !attached { _ = DestroyMenu(dashboardMenu) }
        }
        let changelogEnabled = self.presentationDefaults.object(forKey: "providerChangelogLinksEnabled") as? Bool ?? false
        // The Win32 tray has no selected provider target while its popup is
        // open. Preserve the preference by exposing the eligible first-party
        // links together in one submenu; each URL remains metadata-driven.
        let changelogEntries = changelogEnabled ? menuEntries.filter { $0.changelogVisible } : []
        if !changelogEntries.isEmpty, let changelogMenu = CreatePopupMenu() {
            var itemsAppended = true
            for (index, entry) in changelogEntries.enumerated() {
                let command = Self.changelogCommandBase + UINT_PTR(index)
                if let changelogURL = entry.changelogURL {
                    self.popupChangelogCommands[command] = changelogURL
                }
                let flags = UINT(MF_STRING) | (entry.changelogURL == nil ? UINT(MF_GRAYED) : 0)
                let title = Array((entry.title + " changelog").utf16) + [0]
                let appended = title.withUnsafeBufferPointer { text in
                    AppendMenuW(changelogMenu, flags, command, text.baseAddress)
                }
                if appended == 0 { itemsAppended = false; break }
            }
            let title = Array("Provider changelogs".utf16) + [0]
            let attached = itemsAppended && AppendMenuW(
                menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: changelogMenu)), title) != 0
            if !attached { _ = DestroyMenu(changelogMenu) }
        }
        let providerEntries = menuEntries.reduce(into: [ProviderInstanceID: WindowsTrayMenuEntry]()) { result, entry in
            guard let id = ProviderInstanceID(rawValue: entry.providerID), result[id] == nil else { return }
            result[id] = entry
        }
        if !providerEntries.isEmpty, let providerMenu = CreatePopupMenu() {
            var appended = true
            let editorBusy: Bool = { if case .idle = self.providerEditorPhase { return false }; return true }()
            for (index, pair) in providerEntries.sorted(by: { $0.key.rawValue < $1.key.rawValue }).enumerated() {
                let command = Self.providerQuotaWarningCommandBase + UINT_PTR(index)
                self.popupProviderQuotaWarningCommands[command] = pair.key
                self.popupProviderQuotaWarningNames[pair.key] = pair.value.title
                let title = Array((pair.value.title + "…").utf16) + [0]
                let flags = UINT(MF_STRING) | (editorBusy ? UINT(MF_GRAYED) : 0)
                if title.withUnsafeBufferPointer({ AppendMenuW(providerMenu, flags, command, $0.baseAddress) }) == 0 {
                    appended = false; break
                }
            }
            let title = Array("Provider quota warnings".utf16) + [0]
            if !appended || title.withUnsafeBufferPointer({ AppendMenuW(menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: providerMenu)), $0.baseAddress) }) == 0 {
                _ = DestroyMenu(providerMenu)
            }
        }
        let showUsed = self.presentationDefaults.object(forKey: "usageBarsShowUsed") as? Bool ?? false
        let showAbsolute = self.presentationDefaults.object(forKey: "resetTimesShowAbsolute") as? Bool ?? false
        let hidePersonalInfo = self.presentationDefaults.object(forKey: "hidePersonalInfo") as? Bool ?? false
        let showOptionalCreditsAndExtraUsage = self.presentationDefaults
            .object(forKey: "showOptionalCreditsAndExtraUsage") as? Bool ?? true
        let sessionQuotaNotificationsEnabled = self.presentationDefaults
            .object(forKey: "sessionQuotaNotificationsEnabled") as? Bool ?? true
        let quotaWarningNotificationsEnabled = self.presentationDefaults
            .object(forKey: "quotaWarningNotificationsEnabled") as? Bool ?? false
        let predictivePaceWarningNotificationsEnabled = self.presentationDefaults
            .object(forKey: "predictivePaceWarningNotificationsEnabled") as? Bool ?? false
        let quotaWarningSoundEnabled = self.presentationDefaults
            .object(forKey: "quotaWarningSoundEnabled") as? Bool ?? true
        let quotaWarningOnScreenAlertEnabled = self.presentationDefaults
            .object(forKey: "quotaWarningOnScreenAlertEnabled") as? Bool ?? false
        let showUsedFlags = UINT(MF_STRING) | (showUsed ? UINT(MF_CHECKED) : 0)
        let showAbsoluteFlags = UINT(MF_STRING) | (showAbsolute ? UINT(MF_CHECKED) : 0)
        let hidePersonalInfoFlags = UINT(MF_STRING) | (hidePersonalInfo ? UINT(MF_CHECKED) : 0)
        let showOptionalCreditsAndExtraUsageFlags = UINT(MF_STRING)
            | (showOptionalCreditsAndExtraUsage ? UINT(MF_CHECKED) : 0)
        let sessionQuotaNotificationsFlags = UINT(MF_STRING)
            | (sessionQuotaNotificationsEnabled ? UINT(MF_CHECKED) : 0)
        let quotaWarningNotificationsFlags = UINT(MF_STRING)
            | (quotaWarningNotificationsEnabled ? UINT(MF_CHECKED) : 0)
        let quotaWarningSoundFlags = UINT(MF_STRING)
            | (quotaWarningSoundEnabled ? UINT(MF_CHECKED) : 0)
        let quotaWarningOnScreenAlertFlags = UINT(MF_STRING)
            | (quotaWarningOnScreenAlertEnabled ? UINT(MF_CHECKED) : 0)
        let predictivePaceWarningNotificationsFlags = UINT(MF_STRING)
            | (predictivePaceWarningNotificationsEnabled ? UINT(MF_CHECKED) : 0)
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
        "Session quota notifications".withCString(encodedAs: UTF16.self) {
            _ = AppendMenuW(menu, sessionQuotaNotificationsFlags, Self.sessionQuotaNotificationsCommand, $0)
        }
        "Quota threshold notifications".withCString(encodedAs: UTF16.self) {
            _ = AppendMenuW(menu, quotaWarningNotificationsFlags, Self.quotaWarningNotificationsCommand, $0)
        }
        "Predictive pace warning notifications".withCString(encodedAs: UTF16.self) {
            _ = AppendMenuW(
                menu, predictivePaceWarningNotificationsFlags,
                Self.predictivePaceWarningNotificationsCommand, $0)
        }
        let historicalTrackingEnabled = self.presentationDefaults
            .object(forKey: "historicalTrackingEnabled") as? Bool ?? false
        "Historical tracking".withCString(encodedAs: UTF16.self) {
            let flags = UINT(MF_STRING) | (historicalTrackingEnabled ? UINT(MF_CHECKED) : 0)
            _ = AppendMenuW(menu, flags, Self.historicalTrackingCommand, $0)
        }
        self.appendWeeklyProgressWorkDaysMenu(to: menu)
        if quotaWarningNotificationsEnabled || predictivePaceWarningNotificationsEnabled {
            "Warning notification sound".withCString(encodedAs: UTF16.self) {
                _ = AppendMenuW(menu, quotaWarningSoundFlags, Self.quotaWarningSoundCommand, $0)
            }
            "On-screen warning alerts".withCString(encodedAs: UTF16.self) {
                _ = AppendMenuW(menu, quotaWarningOnScreenAlertFlags, Self.quotaWarningOnScreenAlertCommand, $0)
            }
        }
        "Quota threshold settings...".withCString(encodedAs: UTF16.self) {
            _ = AppendMenuW(menu, UINT(MF_STRING), Self.quotaWarningSettingsCommand, $0)
        }
        "Codex web settings...".withCString(encodedAs: UTF16.self) {
            let flags: UINT = { if case .idle = self.codexWebSettingsEditorPhase { return UINT(MF_STRING) }; return UINT(MF_STRING | MF_GRAYED) }()
            _ = AppendMenuW(menu, flags, Self.codexWebSettingsCommand, $0)
        }
        let changelogFlags = UINT(MF_STRING) | (changelogEnabled ? UINT(MF_CHECKED) : 0)
        "Show provider changelog links".withCString(encodedAs: UTF16.self) {
            _ = AppendMenuW(menu, changelogFlags, Self.changelogCommandBase - 1, $0)
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
            self.popupStatusCommands.removeAll(keepingCapacity: true)
            self.popupDashboardCommands.removeAll(keepingCapacity: true)
            self.popupChangelogCommands.removeAll(keepingCapacity: true)
            self.popupProviderQuotaWarningCommands.removeAll(keepingCapacity: true)
            self.popupProviderQuotaWarningNames.removeAll(keepingCapacity: true)
            return
        }
        let command = TrackPopupMenu(menu, UINT(TPM_RIGHTBUTTON | TPM_RETURNCMD), point.x, point.y, 0, hwnd, nil)
        _ = DestroyMenu(menu)
        if command != 0 { self.dispatchCommand(UINT_PTR(command)) }
        self.popupStatusCommands.removeAll(keepingCapacity: true)
        self.popupDashboardCommands.removeAll(keepingCapacity: true)
        self.popupChangelogCommands.removeAll(keepingCapacity: true)
        self.popupProviderQuotaWarningCommands.removeAll(keepingCapacity: true)
        self.popupProviderQuotaWarningNames.removeAll(keepingCapacity: true)
        _ = PostMessageW(hwnd, WM_NULL, 0, 0)
    }

    private func invokeQuit() {
        self.quotaWarningOverlay?.dismiss()
        self.quotaWarningOverlay = nil
        self.quotaWarningOverlayOwner = nil
        self.mailboxLock.lock()
        guard !self.quitInvoked else {
            self.mailboxLock.unlock()
            return
        }
        self.quitInvoked = true
        self.providerEditorPhase = .idle
        self.providerEditorExpectedRequest = nil
        self.providerEditorMailbox = nil
        self.codexWebSettingsEditorPhase = .idle
        self.codexWebSettingsEditorExpectedRequest = nil
        self.codexWebSettingsEditorMailbox = nil
        self.mailboxSessionQuotaNotifications.removeAll(keepingCapacity: false)
        self.mailboxQuotaWarningNotifications.removeAll(keepingCapacity: false)
        self.mailboxPredictivePaceWarningNotifications.removeAll(keepingCapacity: false)
        self.mailboxLock.unlock()
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

    private func toggleSessionQuotaNotificationsSetting() {
        let current = self.presentationDefaults.object(forKey: "sessionQuotaNotificationsEnabled") as? Bool ?? true
        self.presentationDefaults.set(!current, forKey: "sessionQuotaNotificationsEnabled")
        if current {
            self.mailboxLock.lock()
            self.mailboxSessionQuotaNotifications.removeAll(keepingCapacity: false)
            self.mailboxLock.unlock()
        }
        self.onSessionQuotaNotificationSettingsChanged()
    }

    private func toggleQuotaWarningNotificationsSetting() {
        let current = self.presentationDefaults.object(forKey: "quotaWarningNotificationsEnabled") as? Bool ?? false
        self.presentationDefaults.set(!current, forKey: "quotaWarningNotificationsEnabled")
        if current {
            self.mailboxLock.lock()
            self.mailboxQuotaWarningNotifications.removeAll(keepingCapacity: false)
            self.mailboxLock.unlock()
            if self.quotaWarningOverlayOwner == .threshold {
                self.dismissQuotaWarningOverlay()
            }
        }
    }

    private func togglePredictivePaceWarningNotificationsSetting() {
        let current = self.presentationDefaults
            .object(forKey: "predictivePaceWarningNotificationsEnabled") as? Bool ?? false
        let enabled = !current
        self.presentationDefaults.set(enabled, forKey: "predictivePaceWarningNotificationsEnabled")
        if !enabled {
            self.mailboxLock.lock()
            self.mailboxPredictivePaceWarningNotifications.removeAll(keepingCapacity: false)
            self.mailboxLock.unlock()
            if self.quotaWarningOverlayOwner == .predictive {
                self.dismissQuotaWarningOverlay()
            }
        }
        self.onPredictivePaceWarningSettingsChanged(
            WindowsPredictivePaceWarningSettings.load(userDefaults: self.presentationDefaults))
    }

    private func toggleHistoricalTrackingSetting() {
        let current = self.presentationDefaults.object(forKey: "historicalTrackingEnabled") as? Bool ?? false
        self.presentationDefaults.set(!current, forKey: "historicalTrackingEnabled")
        self.onPredictivePaceWarningSettingsChanged(
            WindowsPredictivePaceWarningSettings.load(userDefaults: self.presentationDefaults))
    }

    private static func weeklyProgressWorkDaysCommand(for workDays: Int?) -> UINT_PTR {
        switch workDays {
        case nil: return Self.weeklyProgressWorkDaysCommandBase
        case 4: return Self.weeklyProgressWorkDaysCommandBase + 1
        case 5: return Self.weeklyProgressWorkDaysCommandBase + 2
        case 7: return Self.weeklyProgressWorkDaysCommandBase + 3
        default: return Self.weeklyProgressWorkDaysCommandBase + 4
        }
    }

    private func appendWeeklyProgressWorkDaysMenu(to menu: HMENU) {
        guard let submenu = CreatePopupMenu() else { return }
        let current = self.presentationDefaults.object(forKey: "weeklyProgressWorkDays") as? Int
        for workDays in WindowsPredictivePaceWarningSettings.weeklyProgressWorkDayOptions {
            let label = WindowsPredictivePaceWarningSettings.weeklyProgressWorkDaysLabel(workDays)
            let flags = UINT(MF_STRING) | ((current == workDays) ? UINT(MF_CHECKED) : 0)
            label.withCString(encodedAs: UTF16.self) {
                _ = AppendMenuW(submenu, flags, Self.weeklyProgressWorkDaysCommand(for: workDays), $0)
            }
        }
        let title = Array("Weekly progress work days".utf16) + [0]
        let attached = title.withUnsafeBufferPointer {
            AppendMenuW(menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: submenu)), $0.baseAddress)
        }
        if attached == 0 { _ = DestroyMenu(submenu) }
    }

    private func selectWeeklyProgressWorkDays(_ workDays: Int?) {
        if let workDays {
            self.presentationDefaults.set(workDays, forKey: "weeklyProgressWorkDays")
        } else {
            self.presentationDefaults.removeObject(forKey: "weeklyProgressWorkDays")
        }
        self.onPredictivePaceWarningSettingsChanged(
            WindowsPredictivePaceWarningSettings.load(userDefaults: self.presentationDefaults))
    }

    private func toggleQuotaWarningOnScreenAlertSetting() {
        let current = self.presentationDefaults.object(forKey: "quotaWarningOnScreenAlertEnabled") as? Bool ?? false
        let enabled = !current
        self.presentationDefaults.set(enabled, forKey: "quotaWarningOnScreenAlertEnabled")
        if !enabled {
            self.dismissQuotaWarningOverlay()
        }
    }

    private func toggleQuotaWarningSoundSetting() {
        let current = self.presentationDefaults.object(forKey: "quotaWarningSoundEnabled") as? Bool ?? true
        self.presentationDefaults.set(!current, forKey: "quotaWarningSoundEnabled")
    }

    private func editQuotaWarningSettings() {
        guard let hwnd = self.window else { return }
        let current = WindowsQuotaWarningSettings.load(userDefaults: self.presentationDefaults)
        guard let updated = WindowsQuotaWarningSettingsDialog.show(owner: hwnd, settings: current) else { return }
        self.presentationDefaults.set(updated.sessionThresholds, forKey: "quotaWarningSessionThresholds")
        self.presentationDefaults.set(updated.weeklyThresholds, forKey: "quotaWarningWeeklyThresholds")
        self.presentationDefaults.set(updated.sessionEnabled, forKey: "quotaWarningSessionEnabled")
        self.presentationDefaults.set(updated.weeklyEnabled, forKey: "quotaWarningWeeklyEnabled")
        self.mailboxLock.lock()
        self.mailboxQuotaWarningNotifications.removeAll(keepingCapacity: false)
        self.mailboxLock.unlock()
        self.onQuotaWarningSettingsChanged(updated)
    }

    private func toggleChangelogSetting() {
        let current = self.presentationDefaults.object(forKey: "providerChangelogLinksEnabled") as? Bool ?? false
        self.presentationDefaults.set(!current, forKey: "providerChangelogLinksEnabled")
        self.onPresentationSettingsChanged()
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

    private func dispatchCommand(_ command: UINT_PTR) {
        if let url = self.popupStatusCommands[command] {
            self.openStatusPage(url)
            return
        }
        if let url = self.popupDashboardCommands[command] {
            self.openStatusPage(url)
            return
        }
        if let url = self.popupChangelogCommands[command] {
            self.openStatusPage(url)
            return
        }
        if let providerID = self.popupProviderQuotaWarningCommands[command] {
            self.beginProviderQuotaWarningLoad(providerID)
            return
        }
        switch command {
        case Self.refreshCommand: self.onRefresh()
        case Self.quitCommand: self.invokeQuit()
        case Self.usageBarsShowUsedCommand: self.togglePresentationSetting(forKey: "usageBarsShowUsed")
        case Self.resetTimesShowAbsoluteCommand: self.togglePresentationSetting(forKey: "resetTimesShowAbsolute")
        case Self.hidePersonalInfoCommand: self.togglePresentationSetting(forKey: "hidePersonalInfo")
        case Self.showOptionalCreditsAndExtraUsageCommand: self.toggleOptionalUsageSetting()
        case Self.sessionQuotaNotificationsCommand: self.toggleSessionQuotaNotificationsSetting()
        case Self.quotaWarningNotificationsCommand: self.toggleQuotaWarningNotificationsSetting()
        case Self.predictivePaceWarningNotificationsCommand: self.togglePredictivePaceWarningNotificationsSetting()
        case Self.historicalTrackingCommand: self.toggleHistoricalTrackingSetting()
        case Self.quotaWarningSoundCommand: self.toggleQuotaWarningSoundSetting()
        case Self.quotaWarningOnScreenAlertCommand: self.toggleQuotaWarningOnScreenAlertSetting()
        case Self.quotaWarningSettingsCommand: self.editQuotaWarningSettings()
        case Self.codexWebSettingsCommand: self.beginCodexWebSettingsLoad()
        case Self.changelogCommandBase - 1: self.toggleChangelogSetting()
        case Self.lowPowerModeOffCommand: self.selectLowPowerModePreference(.off)
        case Self.lowPowerModeOnCommand: self.selectLowPowerModePreference(.on)
        case Self.lowPowerModeAutomaticCommand: self.selectLowPowerModePreference(.automatic)
        case Self.weeklyProgressWorkDaysCommandBase: self.selectWeeklyProgressWorkDays(nil)
        case Self.weeklyProgressWorkDaysCommandBase + 1: self.selectWeeklyProgressWorkDays(4)
        case Self.weeklyProgressWorkDaysCommandBase + 2: self.selectWeeklyProgressWorkDays(5)
        case Self.weeklyProgressWorkDaysCommandBase + 3: self.selectWeeklyProgressWorkDays(7)
        case let frequencyCommand
            where frequencyCommand >= Self.refreshFrequencyCommandBase
                && frequencyCommand <= Self.refreshFrequencyCommandBase + 7:
            let index = frequencyCommand - Self.refreshFrequencyCommandBase
            let frequency = WindowsRefreshSettings.Frequency.allCases[Int(index)]
            self.selectRefreshFrequency(frequency)
        default: break
        }
    }

    private func beginProviderQuotaWarningLoad(_ providerID: ProviderInstanceID) {
        guard case .idle = self.providerEditorPhase, !self.quitInvoked else { return }
        let requestID = self.nextProviderEditorRequestID
        self.nextProviderEditorRequestID &+= 1
        self.providerEditorPhase = .loading(
            requestID, providerID, self.popupProviderQuotaWarningNames[providerID] ?? providerID.rawValue)
        self.mailboxLock.lock()
        self.providerEditorExpectedRequest = .init(requestID: requestID, providerID: providerID, kind: .load)
        self.providerEditorMailbox = nil
        self.mailboxLock.unlock()
        self.onProviderQuotaWarningLoad(requestID, providerID)
    }

    private func beginCodexWebSettingsLoad() {
        guard case .idle = self.codexWebSettingsEditorPhase, !self.quitInvoked else { return }
        let requestID = self.nextCodexWebSettingsRequestID
        self.nextCodexWebSettingsRequestID &+= 1
        self.codexWebSettingsEditorPhase = .loading(requestID)
        self.mailboxLock.lock()
        self.codexWebSettingsEditorExpectedRequest = .init(requestID: requestID, kind: .load)
        self.codexWebSettingsEditorMailbox = nil
        self.mailboxLock.unlock()
        self.onCodexWebSettingsLoad(requestID)
    }

    private func beginCodexWebSettingsSave(patch: WindowsCodexWebSettingsPatch) {
        guard !self.quitInvoked else { return }
        let requestID = self.nextCodexWebSettingsRequestID
        self.nextCodexWebSettingsRequestID &+= 1
        self.codexWebSettingsEditorPhase = .saving(requestID)
        self.mailboxLock.lock()
        self.codexWebSettingsEditorExpectedRequest = .init(requestID: requestID, kind: .save)
        self.codexWebSettingsEditorMailbox = nil
        self.mailboxLock.unlock()
        self.onCodexWebSettingsSave(requestID, patch)
    }

    private func drainCodexWebSettingsEditor() {
        self.mailboxLock.lock()
        let mailbox = self.codexWebSettingsEditorMailbox
        if mailbox != nil {
            self.codexWebSettingsEditorMailbox = nil
            self.codexWebSettingsEditorExpectedRequest = nil
        }
        self.mailboxLock.unlock()
        guard let mailbox else { return }
        switch self.codexWebSettingsEditorPhase {
        case let .loading(requestID) where requestID == mailbox.requestID && mailbox.kind == .load:
            guard let result = mailbox.result else { return }
            switch result {
            case let .loaded(snapshot):
                guard !self.quitInvoked, let hwnd = self.window, IsWindow(hwnd) != 0 else { self.codexWebSettingsEditorPhase = .idle; return }
                self.codexWebSettingsEditorPhase = .editing(requestID)
                let patch = WindowsCodexWebSettingsDialog.show(owner: hwnd, settings: snapshot)
                self.codexWebSettingsEditorPhase = .idle
                guard !self.quitInvoked, let patch, !patch.isUnchanged else { return }
                self.beginCodexWebSettingsSave(patch: patch)
            case .providerMissing: self.codexWebSettingsEditorPhase = .idle; self.showProviderEditorNotice("Codex provider is not enabled.")
            case .shuttingDown: self.codexWebSettingsEditorPhase = .idle
            case let .failed(message): self.codexWebSettingsEditorPhase = .idle; self.showProviderEditorNotice("Could not load Codex web settings: \(message)")
            }
        case let .saving(requestID) where requestID == mailbox.requestID && mailbox.kind == .save:
            guard let result = mailbox.saveResult else { return }
            switch result {
            case .saved, .unchanged: self.codexWebSettingsEditorPhase = .idle
            case .providerMissing: self.codexWebSettingsEditorPhase = .idle; self.showProviderEditorNotice("Codex provider is not enabled.")
            case .shuttingDown: self.codexWebSettingsEditorPhase = .idle
            case let .failed(message): self.codexWebSettingsEditorPhase = .idle; self.showProviderEditorNotice("Could not save Codex web settings: \(message)")
            }
        default: break
        }
    }

    /// Consumes provider-editor replies on the tray UI thread only.
    private func drainProviderQuotaWarningEditor() {
        self.mailboxLock.lock()
        let mailbox = self.providerEditorMailbox
        if mailbox != nil {
            self.providerEditorMailbox = nil
            self.providerEditorExpectedRequest = nil
        }
        self.mailboxLock.unlock()
        guard let mailbox else { return }
        switch self.providerEditorPhase {
        case let .loading(requestID, providerID, providerName)
            where requestID == mailbox.requestID
                && providerID == mailbox.providerID
                && mailbox.kind == .load:
            guard let result = mailbox.result else { return }
            switch result {
            case let .loaded(snapshot):
                guard snapshot.providerID == providerID, !self.quitInvoked, let hwnd = self.window, IsWindow(hwnd) != 0 else {
                    self.providerEditorPhase = .idle; return
                }
                self.providerEditorPhase = .editing(requestID, providerID, providerName)
                let patch = WindowsProviderQuotaWarningDialog.show(
                    owner: hwnd, providerName: providerName,
                    session: snapshot.session, weekly: snapshot.weekly)
                self.providerEditorPhase = .idle
                guard !self.quitInvoked else { return }
                guard let patch, !patch.isUnchanged else { return }
                self.beginProviderQuotaWarningSave(providerID, providerName: providerName, patch: patch)
            case .providerMissing: self.providerEditorPhase = .idle; self.showProviderEditorNotice("Provider is no longer enabled.")
            case .shuttingDown: self.providerEditorPhase = .idle
            case let .failed(message): self.providerEditorPhase = .idle; self.showProviderEditorNotice("Could not load provider quota warnings: \(message)")
            }
        case let .saving(requestID, providerID, providerName, patch)
            where requestID == mailbox.requestID
                && providerID == mailbox.providerID
                && mailbox.kind == .save:
            guard let result = mailbox.saveResult else { return }
            switch result {
            case let .saved(snapshot), let .unchanged(snapshot):
                guard snapshot.providerID == providerID else { self.providerEditorPhase = .idle; return }
                self.mailboxLock.lock(); self.mailboxQuotaWarningNotifications.removeAll(keepingCapacity: false); self.mailboxLock.unlock()
                self.providerEditorPhase = .idle
            case .providerMissing: self.providerEditorPhase = .idle; self.showProviderEditorNotice("Provider is no longer enabled.")
            case .shuttingDown: self.providerEditorPhase = .idle
            case let .failed(message):
                guard let hwnd = self.window else { return }
                let retry = "Could not save provider quota warnings: \(message)\n\nRetry?"
                let text = Array(retry.utf16) + [0]; let caption = Array("CodexBar".utf16) + [0]
                let choice = text.withUnsafeBufferPointer { body in
                    caption.withUnsafeBufferPointer { title in MessageBoxW(hwnd, body.baseAddress, title.baseAddress, UINT(MB_RETRYCANCEL | MB_ICONWARNING)) }
                }
                guard !self.quitInvoked else { self.providerEditorPhase = .idle; return }
                if choice == IDRETRY { self.beginProviderQuotaWarningSave(providerID, providerName: providerName, patch: patch) }
                else { self.providerEditorPhase = .idle }
            }
        default: break
        }
    }

    private func beginProviderQuotaWarningSave(
        _ providerID: ProviderInstanceID, providerName: String, patch: WindowsProviderQuotaWarningPatch)
    {
        guard !self.quitInvoked else { return }
        let requestID = self.nextProviderEditorRequestID
        self.nextProviderEditorRequestID &+= 1
        self.providerEditorPhase = .saving(requestID, providerID, providerName, patch)
        self.mailboxLock.lock()
        self.providerEditorExpectedRequest = .init(requestID: requestID, providerID: providerID, kind: .save)
        self.providerEditorMailbox = nil
        self.mailboxQuotaWarningNotifications.removeAll(keepingCapacity: false)
        self.mailboxLock.unlock()
        self.onProviderQuotaWarningSave(requestID, providerID, patch)
    }

    private func showProviderEditorNotice(_ message: String) {
        guard let hwnd = self.window else { return }
        let body = Array(message.utf16) + [0]; let title = Array("CodexBar".utf16) + [0]
        _ = body.withUnsafeBufferPointer { text in title.withUnsafeBufferPointer { caption in MessageBoxW(hwnd, text.baseAddress, caption.baseAddress, UINT(MB_OK | MB_ICONWARNING)) } }
    }

    private func openStatusPage(_ rawURL: String) {
        guard let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              !rawURL.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
        else {
            self.reportStatusOpenFailure(rawURL)
            return
        }
        let target = Array(rawURL.utf16) + [0]
        let result = target.withUnsafeBufferPointer { text in
            ShellExecuteW(nil, nil, text.baseAddress, nil, nil, Int32(SW_SHOWNORMAL))
        }
        if Int(bitPattern: result) <= 32 { self.reportStatusOpenFailure(rawURL) }
    }

    private func reportStatusOpenFailure(_ rawURL: String) {
        FileHandle.standardError.write(Data("CodexBar: could not open provider status page \(rawURL)\n".utf8))
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
        if message == Self.wakeMessage {
            host.drainProviderQuotaWarningEditor()
            host.drainCodexWebSettingsEditor()
            host.drainSessionQuotaNotifications()
            if case .editing = host.providerEditorPhase {} else if case .saving = host.providerEditorPhase {}
            else if case .editing = host.codexWebSettingsEditorPhase {} else if case .saving = host.codexWebSettingsEditorPhase {} else {
                host.drainQuotaWarningNotifications()
                host.drainPredictivePaceWarningNotifications()
            }
            return 0
        }
        if message == Self.taskbarCreated {
            if (try? host.installIcon(hwnd)) == nil { host.invokeQuit() }
            return 0
        }
        // WM_POWERBROADCAST is delivered on this window's UI thread. Keep the
        // callback nonblocking: the application schedules its refresh work.
        // PBT_APMPOWERSTATUSCHANGE covers AC/battery transitions and
        // PBT_APMRESUMEAUTOMATIC covers resume from suspend/hibernate.
        // The registered Battery Saver GUID arrives as PBT_POWERSETTINGCHANGE;
        // the runtime re-reads its current power snapshot in the callback.
        if message == UINT(WM_POWERBROADCAST),
           wParam == WPARAM(PBT_APMPOWERSTATUSCHANGE)
            || wParam == WPARAM(PBT_APMRESUMEAUTOMATIC)
            || wParam == WPARAM(PBT_POWERSETTINGCHANGE)
        {
            host.onPowerChanged()
            return 1
        }
        if message == UINT(WM_CLOSE) { host.invokeQuit(); return 0 }
        if message == UINT(WM_COMMAND) {
            host.dispatchCommand(UINT_PTR(wParam & 0xffff))
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

    private func drainSessionQuotaNotifications() {
        guard self.iconInstalled,
              self.presentationDefaults.object(forKey: "sessionQuotaNotificationsEnabled") as? Bool ?? true
        else {
            self.mailboxLock.lock()
            self.mailboxSessionQuotaNotifications.removeAll(keepingCapacity: false)
            self.mailboxLock.unlock()
            return
        }
        self.mailboxLock.lock()
        let notifications = self.mailboxSessionQuotaNotifications
        self.mailboxSessionQuotaNotifications.removeAll(keepingCapacity: false)
        self.mailboxLock.unlock()
        for notification in notifications {
            self.deliverSessionQuotaNotification(notification)
        }
    }

    private func drainQuotaWarningNotifications() {
        guard case .idle = self.providerEditorPhase else { return }
        guard self.iconInstalled,
              self.presentationDefaults.object(forKey: "quotaWarningNotificationsEnabled") as? Bool ?? false
        else {
            self.mailboxLock.lock()
            self.mailboxQuotaWarningNotifications.removeAll(keepingCapacity: false)
            self.mailboxLock.unlock()
            return
        }
        self.mailboxLock.lock()
        let notifications = self.mailboxQuotaWarningNotifications
        self.mailboxQuotaWarningNotifications.removeAll(keepingCapacity: false)
        self.mailboxLock.unlock()
        for notification in notifications {
            self.deliverQuotaWarningNotification(notification)
        }
    }

    private func drainPredictivePaceWarningNotifications() {
        guard case .idle = self.providerEditorPhase else { return }
        guard self.iconInstalled,
              self.presentationDefaults.object(forKey: "predictivePaceWarningNotificationsEnabled") as? Bool ?? false
        else {
            self.mailboxLock.lock()
            self.mailboxPredictivePaceWarningNotifications.removeAll(keepingCapacity: false)
            self.mailboxLock.unlock()
            return
        }
        self.mailboxLock.lock()
        let notifications = self.mailboxPredictivePaceWarningNotifications
        self.mailboxPredictivePaceWarningNotifications.removeAll(keepingCapacity: false)
        self.mailboxLock.unlock()
        for notification in notifications { self.deliverPredictivePaceWarningNotification(notification) }
    }

    private func deliverSessionQuotaNotification(_ notification: WindowsSessionQuotaNotification) {
        guard self.presentationDefaults.object(forKey: "sessionQuotaNotificationsEnabled") as? Bool ?? true,
              self.iconInstalled,
              let hwnd = self.window
        else { return }
        var data = NOTIFYICONDATAW()
        data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        data.hWnd = hwnd
        data.uID = 1
        data.uFlags = UINT(NIF_INFO)
        data.dwInfoFlags = DWORD(NIIF_INFO)
        Self.copyUTF16(notification.title, into: &data.szInfoTitle)
        Self.copyUTF16(notification.body, into: &data.szInfo)
        guard Shell_NotifyIconW(DWORD(NIM_MODIFY), &data) != 0 else {
            let error = GetLastError()
            FileHandle.standardError.write(
                Data("CodexBar: failed to deliver session quota notification (Win32 error \(error))\n".utf8))
            return
        }
    }

    private func deliverQuotaWarningNotification(_ notification: WindowsQuotaWarningNotification) {
        guard self.presentationDefaults.object(forKey: "quotaWarningNotificationsEnabled") as? Bool ?? false,
              self.iconInstalled,
              let hwnd = self.window
        else { return }
        let overlayEnabled = self.presentationDefaults
            .object(forKey: "quotaWarningOnScreenAlertEnabled") as? Bool ?? false
        let hidePersonalInfo = self.presentationDefaults.object(forKey: "hidePersonalInfo") as? Bool ?? false
        let soundEnabled = self.presentationDefaults.object(forKey: "quotaWarningSoundEnabled") as? Bool ?? true
        let copy = notification.copy(hidePersonalInfo: hidePersonalInfo)
        if overlayEnabled {
            if self.quotaWarningOverlay == nil { self.quotaWarningOverlay = WindowsQuotaWarningOverlay() }
            self.quotaWarningOverlay?.show(title: copy.title, body: copy.body, owner: hwnd)
            self.quotaWarningOverlayOwner = .threshold
        } else {
            if self.quotaWarningOverlayOwner == .threshold {
                self.dismissQuotaWarningOverlay()
            }
        }
        var data = NOTIFYICONDATAW()
        data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        data.hWnd = hwnd
        data.uID = 1
        data.uFlags = UINT(NIF_INFO)
        data.dwInfoFlags = DWORD(soundEnabled ? NIIF_INFO : (NIIF_INFO | NIIF_NOSOUND))
        Self.copyUTF16(copy.title, into: &data.szInfoTitle)
        Self.copyUTF16(copy.body, into: &data.szInfo)
        guard Shell_NotifyIconW(DWORD(NIM_MODIFY), &data) != 0 else {
            let error = GetLastError()
            FileHandle.standardError.write(
                Data("CodexBar: failed to deliver quota warning notification (Win32 error \(error))\n".utf8))
            return
        }
    }

    private func deliverPredictivePaceWarningNotification(_ notification: WindowsPredictivePaceWarningNotification) {
        guard self.presentationDefaults.object(forKey: "predictivePaceWarningNotificationsEnabled") as? Bool ?? false,
              self.iconInstalled,
              let hwnd = self.window else { return }
        let overlayEnabled = self.presentationDefaults
            .object(forKey: "quotaWarningOnScreenAlertEnabled") as? Bool ?? false
        let hidePersonalInfo = self.presentationDefaults.object(forKey: "hidePersonalInfo") as? Bool ?? false
        let soundEnabled = self.presentationDefaults.object(forKey: "quotaWarningSoundEnabled") as? Bool ?? true
        let copy = notification.copy(hidePersonalInfo: hidePersonalInfo)
        if overlayEnabled {
            if self.quotaWarningOverlay == nil { self.quotaWarningOverlay = WindowsQuotaWarningOverlay() }
            self.quotaWarningOverlay?.show(title: copy.title, body: copy.body, owner: hwnd)
            self.quotaWarningOverlayOwner = .predictive
        } else if self.quotaWarningOverlayOwner == .predictive {
            self.dismissQuotaWarningOverlay()
        }
        var data = NOTIFYICONDATAW()
        data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        data.hWnd = hwnd
        data.uID = 1
        data.uFlags = UINT(NIF_INFO)
        data.dwInfoFlags = DWORD(soundEnabled ? NIIF_INFO : (NIIF_INFO | NIIF_NOSOUND))
        Self.copyUTF16(copy.title, into: &data.szInfoTitle)
        Self.copyUTF16(copy.body, into: &data.szInfo)
        guard Shell_NotifyIconW(DWORD(NIM_MODIFY), &data) != 0 else {
            let error = GetLastError()
            FileHandle.standardError.write(Data("CodexBar: failed to deliver predictive warning notification (Win32 error \(error))\n".utf8))
            return
        }
    }

    private func dismissQuotaWarningOverlay() {
        self.quotaWarningOverlay?.dismiss()
        self.quotaWarningOverlay = nil
        self.quotaWarningOverlayOwner = nil
    }

    private static func copyUTF16<T>(_ value: String, into destination: inout T) {
        let capacity = MemoryLayout<T>.size / MemoryLayout<UInt16>.stride
        guard capacity > 0 else { return }
        var units = Array(value.utf16.prefix(max(0, capacity - 1)))
        if let last = units.last, (0xD800...0xDBFF).contains(last) { units.removeLast() }
        units.append(0)
        withUnsafeMutableBytes(of: &destination) { raw in
            let output = raw.bindMemory(to: UInt16.self)
            for (index, unit) in units.prefix(output.count).enumerated() { output[index] = unit }
        }
    }

    public enum TrayError: Error, Sendable { case alreadyRunning; case win32(UInt32) }
}
#endif
