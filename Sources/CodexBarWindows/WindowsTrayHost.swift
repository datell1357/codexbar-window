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

    private static let startupRegistrationCommand = UINT_PTR(0x7546)
    private static let providerDetailsCommandBase = UINT_PTR(0x7D00)
    private var popupProviderDetails: [UINT_PTR: (title: String, body: String, links: [WindowsProviderDetailsDialog.Link])] = [:]
    private static let copyUsageCommandBase = UINT_PTR(0x7C00)
    private static let copyErrorCommandBase = UINT_PTR(0x7B00)
    private var popupCopyErrors: [UINT_PTR: String] = [:]
    private static let copySummaryCommand = UINT_PTR(0x754D)
    private var popupCopySummary: String?
    private var popupCopyPrivacy = false
    private static let cliPathAddCommand = UINT_PTR(0x754B)
    private static let cliPathRemoveCommand = UINT_PTR(0x754C)
    private let cliPathOperation = WindowsCLIPathOperation()
    private var cliPathOperationRunning = false // Protected by mailboxLock.
    private static let cliSetupTimer = UINT_PTR(0x754A)
    private var cliSetupDialogOpen = false
    private var cliSetupRunning = false // Protected by mailboxLock.
    private var cliSetupCancelled = false
    private var cliSetupResult: (text: String, hidePaths: Bool, mutation: Bool)?
    private static let cliSetupCommand = UINT_PTR(0x7549)
    private static let startupDetailsCommand = UINT_PTR(0x7548)
    private static let startupSettingsCommand = UINT_PTR(0x7547)
    private var startupRegistrationMessage: String?
    private static let menuHotkeyCommand = UINT_PTR(0x7533)
    private static let menuHotkeyID: Int32 = 0x4342
    private static let shortcutChoiceBase = UINT_PTR(0x7900)
    private var activeHotkeyID: Int32 = 0x4342
    private var ownedHotkeyIDs: Set<Int32> = []
    private var systemSessionEnding = false
    public var isSystemSessionEnding: Bool {
        self.mailboxLock.lock()
        defer { self.mailboxLock.unlock() }
        return self.systemSessionEnding
    }
    private var activeMenuShortcut: WindowsMenuShortcut?
    private static let applySavedShortcutCommand = UINT_PTR(0x7545)
    private var menuHotkeyRegistered = false
    private var menuHotkeyFailed = false
    private var menuHotkeyFailureMessage: String?
    private static let cleanupHotkeyCommand = UINT_PTR(0x7544)
    private var popupIsOpen = false
    private var keyboardInitialMenu: HMENU?
    private var keyboardInitialPosition: UINT?
    private var keyboardPopupAnchor: POINT?
    private var keyboardReturnTarget: (window: HWND, process: DWORD, thread: DWORD)?
    private static let chooseTitleDatabaseCommand = UINT_PTR(0x7530)
    private static let clearTitleDatabaseCommand = UINT_PTR(0x7531)
    private static let disableTitleDatabaseCommand = UINT_PTR(0x7532)
    private static let sessionDetailsCommand = UINT_PTR(0x752F)
    private static let claudeTitlesCommand = UINT_PTR(0x752E)
    private static let codexTitleFolderCommand = UINT_PTR(0x752B)
    private static let clearCodexTitleCommand = UINT_PTR(0x752C)
    private static let disableCodexTitleCommand = UINT_PTR(0x752D)
    private static let inferNewSessionMetadataCommand = UINT_PTR(0x752A)
    private static let sessionMetadataToggleCommand = UINT_PTR(0x7525)
    private static let codexSessionFolderCommand = UINT_PTR(0x7526)
    private static let claudeProjectFolderCommand = UINT_PTR(0x7527)
    private static let clearCodexSessionFolderCommand = UINT_PTR(0x7528)
    private static let clearClaudeProjectFolderCommand = UINT_PTR(0x7529)
    private static let nativeSessionDirectoryCommand = UINT_PTR(0x7524)
    private static let pagePopupMessage = UINT(WM_APP) + 2
    private static let localPreviousPageCommand = UINT_PTR(0x7520)
    private static let localNextPageCommand = UINT_PTR(0x7521)
    private static let remotePreviousPageCommand = UINT_PTR(0x7522)
    private static let remoteNextPageCommand = UINT_PTR(0x7523)
    private static let sessionLabelCommandBase = UINT_PTR(0x7510)
    private static let remoteSettingsCommand = UINT_PTR(0x7502)
    private static let remoteRefreshCommand = UINT_PTR(0x7503)
    private static let remoteSessionCommandBase = UINT_PTR(0x7800)
    private static let agentSessionsToggleCommand = UINT_PTR(0x7500)
    private static let agentSessionsRefreshCommand = UINT_PTR(0x7501)
    private static let agentSessionCommandBase = UINT_PTR(0x7600)
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

    private let onLocalSessionPage: @Sendable (WindowsSessionPageRequest) -> Void
    private let onRemoteSessionPage: @Sendable (WindowsSessionPageRequest) -> Void
    private var popupPageCommands: [UINT_PTR: (request: WindowsSessionPageRequest, remote: Bool)] = [:]
    private let onRemoteSettingsChanged: @Sendable () -> Void
    private let onRemoteRefresh: @Sendable () -> Void
    private let onRemoteFocus: @Sendable (WindowsRemoteFocusRequest) -> Void
    private var mailboxRemoteSessions: WindowsRemoteSessionMenuSnapshot = .disabled
    private var popupRemoteCommands: [UINT_PTR: WindowsRemoteFocusRequest] = [:]
    private var remoteEditorOpen = false
    private let onAgentSessionsSettingsChanged: @Sendable () -> Void
    private let onAgentSessionsRefresh: @Sendable () -> Void
    private let onAgentSessionFocus: @Sendable (WindowsSessionFocusRequest) -> Void
    private var mailboxAgentSessions: WindowsSessionMenuSnapshot = .disabled
    private var popupRemoteDetails: [UINT_PTR: String] = [:]
    private var popupSessionDetails: String?
    private var popupAgentSessionCommands: [UINT_PTR: WindowsSessionFocusRequest] = [:]
    private let onTokenAccountAdd: @Sendable (UUID, WindowsTokenAccountAddRequest) -> Void
    private var popupTokenAccountAdds: [UINT_PTR: (UsageProvider, UUID?)] = [:]
    private var tokenAccountAddResult: WindowsTokenAccountAddResult?
    private let onCredentialEditBegin: @Sendable (UUID, ProviderInstanceID, UUID) -> Void
    private let onCredentialEditSave: @Sendable (UUID, UUID, String) -> Void
    private let onCredentialEditCancel: @Sendable (UUID) -> Void
    private var popupCredentialEdits: [UINT_PTR: (ProviderInstanceID, UUID)] = [:]
    private var credentialLoadResult: WindowsTokenAccountCredentialLoadResult?
    private var credentialSaveResult: WindowsTokenAccountCredentialSaveResult?
    private let onTokenAccountRename: @Sendable (UUID, WindowsTokenAccountRenameRequest) -> Void
    private var popupTokenAccountRenames: [UINT_PTR: (ProviderInstanceID, UUID, String)] = [:]
    private var tokenAccountRenameResult: WindowsTokenAccountRenameResult?
    private let onTokenAccountSelect: @Sendable (WindowsTokenAccountSelectionRequest) -> Void
    private var tokenAccountPage = 0
    private var tokenAccountPageQueued = false
    private var tokenAccountPageIDs: [UUID] = []
    private var popupTokenAccountPages: [UINT_PTR: Int] = [:]
    private var popupTokenAccountCommands: [UINT_PTR: WindowsTokenAccountSelectionRequest] = [:]
    // Pending request and result are protected by mailboxLock.
    private var tokenAccountPendingID: UUID?
    private var tokenAccountResult: WindowsTokenAccountSelectionSaveResult?

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
        onAgentSessionsSettingsChanged: @escaping @Sendable () -> Void = {},
        onAgentSessionsRefresh: @escaping @Sendable () -> Void = {},
        onAgentSessionFocus: @escaping @Sendable (WindowsSessionFocusRequest) -> Void = { _ in },
        onRemoteSettingsChanged: @escaping @Sendable () -> Void = {},
        onRemoteRefresh: @escaping @Sendable () -> Void = {},
        onRemoteFocus: @escaping @Sendable (WindowsRemoteFocusRequest) -> Void = { _ in },
        onLocalSessionPage: @escaping @Sendable (WindowsSessionPageRequest) -> Void = { _ in },
        onRemoteSessionPage: @escaping @Sendable (WindowsSessionPageRequest) -> Void = { _ in },
        onPresentationSettingsChanged: @escaping PresentationSettingsChangedHandler = {},
        onOptionalUsageSettingsChanged: @escaping OptionalUsageSettingsChangedHandler = {},
        onRefreshSettingsChanged: @escaping RefreshSettingsChangedHandler = {},
        onSessionQuotaNotificationSettingsChanged: @escaping SessionQuotaNotificationSettingsChangedHandler = {},
        onQuotaWarningSettingsChanged: @escaping QuotaWarningSettingsChangedHandler = {},
        onTokenAccountAdd: @escaping @Sendable (UUID, WindowsTokenAccountAddRequest) -> Void = { _, _ in },
        onCredentialEditBegin: @escaping @Sendable (UUID, ProviderInstanceID, UUID) -> Void = { _, _, _ in },
        onCredentialEditSave: @escaping @Sendable (UUID, UUID, String) -> Void = { _, _, _ in },
        onCredentialEditCancel: @escaping @Sendable (UUID) -> Void = { _ in },
        onTokenAccountRename: @escaping @Sendable (UUID, WindowsTokenAccountRenameRequest) -> Void = { _, _ in },
        onTokenAccountSelect: @escaping @Sendable (WindowsTokenAccountSelectionRequest) -> Void = { _ in },
        onProviderQuotaWarningLoad: @escaping ProviderQuotaWarningLoadHandler = { _, _ in },
        onProviderQuotaWarningSave: @escaping ProviderQuotaWarningSaveHandler = { _, _, _ in },
        onCodexWebSettingsLoad: @escaping CodexWebSettingsLoadHandler = { _ in },
        onCodexWebSettingsSave: @escaping CodexWebSettingsSaveHandler = { _, _ in },
        onPredictivePaceWarningSettingsChanged: @escaping PredictivePaceWarningSettingsChangedHandler = { _ in })
    {
        self.onLocalSessionPage = onLocalSessionPage
        self.onRemoteSessionPage = onRemoteSessionPage
        self.onRemoteSettingsChanged = onRemoteSettingsChanged
        self.onRemoteRefresh = onRemoteRefresh
        self.onRemoteFocus = onRemoteFocus
        self.onAgentSessionsSettingsChanged = onAgentSessionsSettingsChanged
        self.onAgentSessionsRefresh = onAgentSessionsRefresh
        self.onAgentSessionFocus = onAgentSessionFocus
        self.onRefresh = onRefresh
        self.onQuit = onQuit
        self.onPowerChanged = onPowerChanged
        self.onMenuOpen = onMenuOpen
        self.onPresentationSettingsChanged = onPresentationSettingsChanged
        self.onOptionalUsageSettingsChanged = onOptionalUsageSettingsChanged
        self.onRefreshSettingsChanged = onRefreshSettingsChanged
        self.onSessionQuotaNotificationSettingsChanged = onSessionQuotaNotificationSettingsChanged
        self.onQuotaWarningSettingsChanged = onQuotaWarningSettingsChanged
        self.onTokenAccountAdd = onTokenAccountAdd
        self.onCredentialEditBegin = onCredentialEditBegin
        self.onCredentialEditSave = onCredentialEditSave
        self.onCredentialEditCancel = onCredentialEditCancel
        self.onTokenAccountRename = onTokenAccountRename
        self.onTokenAccountSelect = onTokenAccountSelect
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
            for id in self.ownedHotkeyIDs { _ = UnregisterHotKey(hwnd, id) }
            self.ownedHotkeyIDs.removeAll()
            self.menuHotkeyRegistered = false
            self.activeMenuShortcut = nil
            self.removeIcon(hwnd)
            if let powerNotification {
                if UnregisterPowerSettingNotification(powerNotification) == 0 {
                    let error = GetLastError()
                    FileHandle.standardError.write(
                        Data("CodexBar: failed to unregister Battery Saver notification (Win32 error \(error))\n".utf8))
                }
            }
            _ = KillTimer(hwnd, Self.cliSetupTimer)
            self.mailboxLock.lock()
            self.cliSetupCancelled = true
            self.cliSetupResult = nil
            self.window = nil
            self.mailboxLock.unlock()
            if IsWindow(hwnd) != 0 { DestroyWindow(hwnd) }
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
        if self.presentationDefaults.object(forKey: "windowsMenuHotkeyEnabled") as? Bool ?? false {
            self.registerMenuHotkey(hwnd)
        }
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
    public func showSessionPage() {
        self.mailboxLock.lock()
        let hwnd = self.quitInvoked ? nil : self.window
        self.mailboxLock.unlock()
        if let hwnd { PostMessageW(hwnd, Self.pagePopupMessage, 0, 0) }
    }

    public func postRemoteSessions(_ snapshot: WindowsRemoteSessionMenuSnapshot) {
        self.mailboxLock.lock()
        guard !self.quitInvoked else { self.mailboxLock.unlock(); return }
        self.mailboxRemoteSessions = snapshot
        let hwnd = self.window
        self.mailboxLock.unlock()
        if let hwnd { PostMessageW(hwnd, Self.wakeMessage, 0, 0) }
    }

    public func postAgentSessions(_ snapshot: WindowsSessionMenuSnapshot) {
        self.mailboxLock.lock()
        guard !self.quitInvoked else {
            self.mailboxLock.unlock()
            return
        }
        self.mailboxAgentSessions = snapshot
        let hwnd = self.window
        self.mailboxLock.unlock()
        if let hwnd { PostMessageW(hwnd, Self.wakeMessage, 0, 0) }
    }

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
    public func invalidateQueuedAccountNotifications(providerID: ProviderInstanceID) {
        self.mailboxLock.lock()
        defer { self.mailboxLock.unlock() }
        self.mailboxSessionQuotaNotifications.removeAll { $0.providerID == providerID }
        self.mailboxQuotaWarningNotifications.removeAll { $0.providerID == providerID }
        self.mailboxPredictivePaceWarningNotifications.removeAll { $0.providerID == providerID }
    }

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

    public func postTokenAccountAdd(requestID: UUID, result: WindowsTokenAccountAddResult) {
        self.mailboxLock.lock()
        guard !self.quitInvoked, self.tokenAccountPendingID == requestID,
              self.tokenAccountAddResult == nil else { self.mailboxLock.unlock(); return }
        self.tokenAccountAddResult = result
        let hwnd = self.window
        self.mailboxLock.unlock()
        if let hwnd { PostMessageW(hwnd, Self.wakeMessage, 0, 0) }
    }

    private func drainTokenAccountAdd() {
        guard !self.quitInvoked, !self.remoteEditorOpen,
              case .idle = self.providerEditorPhase, case .idle = self.codexWebSettingsEditorPhase else { return }
        self.mailboxLock.lock()
        let result = self.tokenAccountAddResult
        if result != nil { self.tokenAccountAddResult = nil; self.tokenAccountPendingID = nil }
        self.mailboxLock.unlock()
        guard let result else { return }
        let message: String
        switch result {
        case .saved: message = "Account added and selected. Usage refresh was requested; credentials have not yet been verified."
        case .alreadyAdded: message = "This account was already added. Refresh usage to see the current selection."
        case .invalidInput: message = "Could not add the account. Check the name, credential size and optional fields."
        case .staleSelection: message = "The account selection changed. Refresh usage and reopen Add saved account."
        case .refreshInProgress: message = "Usage is refreshing. Add the account after it finishes."
        case .unavailable: message = "This provider is no longer available for saved accounts."
        case .shuttingDown: return
        case .failed: message = "Could not add or protect the account. Check your Windows profile and configuration access, then try again."
        }
        self.showMessage(message, caption: "Add saved account")
    }

    public func postCredentialEditLoad(requestID: UUID, result: WindowsTokenAccountCredentialLoadResult) {
        self.mailboxLock.lock()
        guard !self.quitInvoked, self.tokenAccountPendingID == requestID,
              self.credentialLoadResult == nil else {
            self.mailboxLock.unlock()
            if case let .loaded(ticketID) = result { self.onCredentialEditCancel(ticketID) }
            return
        }
        self.credentialLoadResult = result
        let window = self.window
        self.mailboxLock.unlock()
        if let window { PostMessageW(window, Self.wakeMessage, 0, 0) }
    }

    public func postCredentialEditSave(requestID: UUID, result: WindowsTokenAccountCredentialSaveResult) {
        self.mailboxLock.lock()
        guard !self.quitInvoked, self.tokenAccountPendingID == requestID,
              self.credentialSaveResult == nil else { self.mailboxLock.unlock(); return }
        self.credentialSaveResult = result
        let window = self.window
        self.mailboxLock.unlock()
        if let window { PostMessageW(window, Self.wakeMessage, 0, 0) }
    }

    private func drainCredentialEdit() {
        guard !self.quitInvoked, !self.remoteEditorOpen, let window = self.window,
              case .idle = self.providerEditorPhase, case .idle = self.codexWebSettingsEditorPhase else { return }
        self.mailboxLock.lock()
        let loaded = self.credentialLoadResult
        let saved = self.credentialSaveResult
        let requestID = self.tokenAccountPendingID
        self.credentialLoadResult = nil
        self.credentialSaveResult = nil
        self.mailboxLock.unlock()
        guard loaded != nil || saved != nil, let requestID else { return }
        var message: String?
        if let loaded {
            switch loaded {
            case let .loaded(ticketID):
                self.remoteEditorOpen = true
                let input = WindowsAccountNameDialog.showCredentialReplacement(owner: window)
                self.remoteEditorOpen = false
                if !self.quitInvoked { PostMessageW(window, Self.wakeMessage, 0, 0) }
                if !self.quitInvoked, case let .saved(secret) = input {
                    self.onCredentialEditSave(requestID, ticketID, secret)
                    return
                }
                self.onCredentialEditCancel(ticketID)
                if case .failed = input { message = "Could not open the credential editor." }
            case .unavailable: message = "The saved account is no longer available. Refresh usage and try again."
            case .refreshInProgress: message = "Usage is refreshing. Try again after it finishes."
            case .shuttingDown: break
            case .failed: message = "Could not load the account. Check configuration access and try again."
            }
        }
        if let saved {
            switch saved {
            case .saved: message = "Credential saved. Usage refresh was requested; authentication has not yet been verified."
            case .unchanged: message = "The credential is unchanged."
            case .invalidInput: message = "The replacement credential is empty or exceeds the size limit. Reopen the editor."
            case .staleAccount: message = "The account changed or the edit expired. Refresh usage and reopen the editor."
            case .refreshInProgress: message = "Usage is refreshing. Reopen the editor after it finishes."
            case .shuttingDown: break
            case .failed: message = "Could not save or protect the credential. Check configuration access and reopen the editor."
            }
        }
        self.mailboxLock.lock()
        if self.tokenAccountPendingID == requestID { self.tokenAccountPendingID = nil }
        self.mailboxLock.unlock()
        if !self.quitInvoked, let message { self.showMessage(message, caption: "Replace account credential") }
    }

    public func postTokenAccountRename(requestID: UUID, result: WindowsTokenAccountRenameResult) {
        self.mailboxLock.lock()
        guard !self.quitInvoked, self.tokenAccountPendingID == requestID,
              self.tokenAccountRenameResult == nil else { self.mailboxLock.unlock(); return }
        self.tokenAccountRenameResult = result
        let hwnd = self.window
        self.mailboxLock.unlock()
        if let hwnd { PostMessageW(hwnd, Self.wakeMessage, 0, 0) }
    }

    private func drainTokenAccountRename() {
        guard !self.quitInvoked, !self.remoteEditorOpen,
              case .idle = self.providerEditorPhase, case .idle = self.codexWebSettingsEditorPhase else { return }
        self.mailboxLock.lock()
        let result = self.tokenAccountRenameResult
        if result != nil { self.tokenAccountRenameResult = nil; self.tokenAccountPendingID = nil }
        self.mailboxLock.unlock()
        guard let result else { return }
        let message: String
        switch result {
        case .saved: message = "Account name saved."
        case .unchanged: message = "The account name is unchanged."
        case .invalidLabel: message = "Enter a nonempty name of at most 160 characters without control characters."
        case .staleAccount: message = "The account changed. Refresh usage, reopen Saved accounts and try again."
        case .refreshInProgress: message = "Usage is refreshing. Try renaming after the refresh finishes."
        case .unavailable: message = "The saved account is no longer available."
        case .shuttingDown: return
        case .failed: message = "Could not save the account name. Check access to the CodexBar configuration and try again."
        }
        self.showMessage(message, caption: "Rename saved account")
    }

    public func postTokenAccountSelection(requestID: UUID, result: WindowsTokenAccountSelectionSaveResult) {
        self.mailboxLock.lock()
        guard !self.quitInvoked, self.tokenAccountPendingID == requestID,
              self.tokenAccountResult == nil else { self.mailboxLock.unlock(); return }
        self.tokenAccountResult = result
        let hwnd = self.window
        self.mailboxLock.unlock()
        if let hwnd { PostMessageW(hwnd, Self.wakeMessage, 0, 0) }
    }

    private func drainTokenAccountSelection() {
        guard !self.quitInvoked, !self.remoteEditorOpen,
              case .idle = self.providerEditorPhase, case .idle = self.codexWebSettingsEditorPhase else { return }
        self.mailboxLock.lock()
        let result = self.tokenAccountResult
        if result != nil { self.tokenAccountResult = nil; self.tokenAccountPendingID = nil }
        self.mailboxLock.unlock()
        guard let result else { return }
        let message: String
        switch result {
        case .saved: message = "Account selection saved. Usage refresh was requested."
        case .unchanged: message = "This account is already selected."
        case .refreshInProgress: message = "Usage is refreshing. Reopen Saved accounts after it finishes and select again."
        case .staleSelection: message = "The saved account selection changed. Refresh usage and reopen Saved accounts."
        case .unavailable: message = "This saved account is no longer available. Refresh usage and reopen Saved accounts."
        case .shuttingDown: return
        case .failed: message = "Could not save the account selection. Check access to the CodexBar configuration and try again."
        }
        self.showMessage(message, caption: "Saved accounts")
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

    @discardableResult
    private func registerMenuHotkey(_ window: HWND) -> Bool {
        if self.menuHotkeyRegistered { return true }
        self.cleanupInactiveHotkeys(window)
        guard self.ownedHotkeyIDs.isEmpty else { return false }
        guard let shortcut = WindowsMenuShortcut.load(self.presentationDefaults) else {
            self.menuHotkeyFailed = true
            self.menuHotkeyFailureMessage = "Saved shortcut is invalid. Choose a combination, then enable it."
            self.presentationDefaults.set(false, forKey: "windowsMenuHotkeyEnabled")
            return false
        }
        let success = RegisterHotKey(window, self.activeHotkeyID, shortcut.modifiers, shortcut.key) != 0
        if success { self.ownedHotkeyIDs.insert(self.activeHotkeyID) }
        self.menuHotkeyRegistered = success
        self.activeMenuShortcut = success ? shortcut : nil
        self.menuHotkeyFailed = !success
        self.menuHotkeyFailureMessage = success ? nil : "Shortcut registration failed (Win32 \(GetLastError())). Choose another combination or retry."
        return success
    }

    private func cleanupInactiveHotkeys(_ window: HWND) {
        let inactive = self.ownedHotkeyIDs.filter { !self.menuHotkeyRegistered || $0 != self.activeHotkeyID }
        var failed = false
        for id in inactive {
            if UnregisterHotKey(window, id) != 0 { self.ownedHotkeyIDs.remove(id) }
            else { failed = true }
        }
        if failed {
            self.menuHotkeyFailed = true
            self.menuHotkeyFailureMessage = "Inactive shortcut registration cleanup failed; retry cleanup or exit the app."
        } else if !inactive.isEmpty {
            self.menuHotkeyFailed = false
            self.menuHotkeyFailureMessage = nil
        }
    }

    private func selectMenuShortcut(_ shortcut: WindowsMenuShortcut) {
        guard let window = self.window, !self.quitInvoked else { return }
        let saved = WindowsMenuShortcut.load(self.presentationDefaults)
        guard shortcut != saved || (self.menuHotkeyRegistered && shortcut != self.activeMenuShortcut) else { return }
        if self.menuHotkeyRegistered, shortcut != self.activeMenuShortcut {
            self.cleanupInactiveHotkeys(window)
            guard let candidate = [Self.menuHotkeyID, Self.menuHotkeyID + 1].first(where: { !self.ownedHotkeyIDs.contains($0) }) else { return }
            guard RegisterHotKey(window, candidate, shortcut.modifiers, shortcut.key) != 0 else {
                self.menuHotkeyFailed = true
                self.menuHotkeyFailureMessage = "New shortcut registration failed (Win32 \(GetLastError())); previous shortcut retained."
                return
            }
            self.ownedHotkeyIDs.insert(candidate)
            guard UnregisterHotKey(window, self.activeHotkeyID) != 0 else {
                let error = GetLastError()
                let cleaned = UnregisterHotKey(window, candidate) != 0
                if cleaned { self.ownedHotkeyIDs.remove(candidate) }
                self.menuHotkeyFailed = true
                self.menuHotkeyFailureMessage = "Previous shortcut release failed (Win32 \(error)); setting retained." +
                    (cleaned ? " Candidate released." : " Candidate cleanup is still needed.")
                return
            }
            self.ownedHotkeyIDs.remove(self.activeHotkeyID)
            self.activeHotkeyID = candidate
            self.activeMenuShortcut = shortcut
        }
        if !self.menuHotkeyRegistered {
            self.cleanupInactiveHotkeys(window)
            guard self.ownedHotkeyIDs.isEmpty else { return }
        }
        if !self.menuHotkeyRegistered, WindowsMenuShortcut.load(self.presentationDefaults) == nil {
            self.presentationDefaults.set(false, forKey: "windowsMenuHotkeyEnabled")
        }
        self.presentationDefaults.set(shortcut.rawValue, forKey: "windowsMenuShortcut")
        self.menuHotkeyFailureMessage = nil
        self.menuHotkeyFailed = false
    }

    private func appendShortcutMenu(to menu: HMENU) {
        guard let child = CreatePopupMenu() else { return }
        let selected = WindowsMenuShortcut.load(self.presentationDefaults)
        let enableFlags = UINT(MF_STRING) | (self.menuHotkeyRegistered ? UINT(MF_CHECKED) : 0) |
            (selected == nil && !self.menuHotkeyRegistered ? UINT(MF_GRAYED) : 0)
        var succeeded = "Enable menu shortcut".withCString(encodedAs: UTF16.self) {
            AppendMenuW(child, enableFlags, Self.menuHotkeyCommand, $0) != 0
        }
        let activeLabel = self.menuHotkeyRegistered ? (self.activeMenuShortcut?.title ?? "Unknown registration") : "Off"
        let savedLabel = selected?.title ?? "Invalid value"
        for label in ["Active now: \(activeLabel)", "Saved selection: \(savedLabel)"] {
            succeeded = succeeded && label.withCString(encodedAs: UTF16.self) {
                AppendMenuW(child, UINT(MF_STRING | MF_GRAYED), 0, $0) != 0
            }
        }
        if self.menuHotkeyRegistered, let selected, selected != self.activeMenuShortcut {
            succeeded = succeeded && "Apply saved selection to active shortcut".withCString(encodedAs: UTF16.self) {
                AppendMenuW(child, UINT(MF_STRING), Self.applySavedShortcutCommand, $0) != 0
            }
        }
        if selected == nil {
            let explanation = self.menuHotkeyRegistered ?
                "Saved shortcut is invalid; the current registration is unchanged. Choose a combination." :
                "Saved shortcut is invalid. Choose a combination below, then enable it."
            succeeded = succeeded && explanation.withCString(encodedAs: UTF16.self) {
                AppendMenuW(child, UINT(MF_STRING | MF_GRAYED), 0, $0) != 0
            }
        }
        if self.menuHotkeyFailed {
            succeeded = succeeded && (self.menuHotkeyFailureMessage ?? "Shortcut operation failed; retry from this menu").withCString(encodedAs: UTF16.self) {
                AppendMenuW(child, UINT(MF_STRING | MF_GRAYED), 0, $0) != 0
            }
        }
        let inactiveCount = self.ownedHotkeyIDs.filter { !self.menuHotkeyRegistered || $0 != self.activeHotkeyID }.count
        if inactiveCount > 0 {
            succeeded = succeeded && "Retry cleanup of \(inactiveCount) inactive shortcut registration(s)".withCString(encodedAs: UTF16.self) {
                AppendMenuW(child, UINT(MF_STRING), Self.cleanupHotkeyCommand, $0) != 0
            }
        }
        let choices = WindowsMenuShortcut.allCases
        let groups: [(String, ClosedRange<UINT>)] = [("A–M", 0x41...0x4D), ("N–Z", 0x4E...0x5A), ("0–9", 0x30...0x39)]
        for modifier in WindowsMenuShortcut.Modifier.allCases {
            for (label, range) in groups {
                guard succeeded, let group = CreatePopupMenu() else { succeeded = false; break }
                var groupSucceeded = true
                for (index, choice) in choices.enumerated() where choice.modifier == modifier && range.contains(choice.key) {
                    groupSucceeded = groupSucceeded && choice.title.withCString(encodedAs: UTF16.self) {
                        AppendMenuW(group, UINT(MF_STRING) | (choice == selected ? UINT(MF_CHECKED) : 0),
                                    Self.shortcutChoiceBase + UINT_PTR(index), $0) != 0
                    }
                }
                let attached = groupSucceeded && "\(modifier.title) + \(label)".withCString(encodedAs: UTF16.self) {
                    AppendMenuW(child, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: group)), $0) != 0
                }
                if !attached { _ = DestroyMenu(group); succeeded = false }
            }
        }
        let attached = succeeded && "Menu short&cut".withCString(encodedAs: UTF16.self) {
            AppendMenuW(menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: child)), $0) != 0
        }
        if !attached { _ = DestroyMenu(child) }
    }

    private func captureKeyboardReturnTarget() {
        self.keyboardReturnTarget = nil
        guard let target = GetForegroundWindow(), target != self.window,
              IsWindow(target) != 0, IsWindowVisible(target) != 0 else { return }
        var process: DWORD = 0
        let thread = GetWindowThreadProcessId(target, &process)
        guard thread != 0, process != 0 else { return }
        self.keyboardReturnTarget = (target, process, thread)
    }

    private func restoreKeyboardReturnTarget(owner: HWND) {
        guard !self.quitInvoked, !self.remoteEditorOpen,
              GetForegroundWindow() == owner, let target = self.keyboardReturnTarget,
              IsWindow(target.window) != 0, IsWindowVisible(target.window) != 0,
              IsWindowEnabled(target.window) != 0, IsIconic(target.window) == 0 else { return }
        var process: DWORD = 0
        let thread = GetWindowThreadProcessId(target.window, &process)
        guard thread == target.thread, process == target.process else { return }
        // Best effort only: never attach input queues, restore minimized windows, or retry
        // after another application has taken foreground ownership.
        _ = SetForegroundWindow(target.window)
    }

    private func keyboardMenuPoint() -> POINT? {
        // Capture the user's foreground monitor before activating the hidden tray owner window.
        let foreground = GetForegroundWindow()
        let monitor = MonitorFromWindow(foreground, UINT(MONITOR_DEFAULTTONEAREST))
        var info = MONITORINFO()
        info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        var area = RECT()
        if let monitor, GetMonitorInfoW(monitor, &info) != 0 { area = info.rcWork }
        else if SystemParametersInfoW(UINT(SPI_GETWORKAREA), 0, &area, 0) == 0 { return nil }
        guard area.right > area.left, area.bottom > area.top else { return nil }
        var point = POINT()
        point.x = max(area.left, area.right - 1 - min(12, (area.right - area.left) / 2))
        point.y = max(area.top, area.bottom - 1 - min(12, (area.bottom - area.top) / 2))
        return point
    }

    private func popup(notifyMenuOpen: Bool = true, keyboardInitiated: Bool = false, preserveAnchor: Bool = false) {
        guard !self.remoteEditorOpen, !self.popupIsOpen, !self.quitInvoked else { return }
        self.popupIsOpen = true
        self.popupCopySummary = nil
        self.popupCopyErrors.removeAll(keepingCapacity: true)
        self.popupProviderDetails.removeAll(keepingCapacity: true)
        self.popupTokenAccountCommands.removeAll(keepingCapacity: true)
        self.popupTokenAccountRenames.removeAll(keepingCapacity: true)
        self.popupCredentialEdits.removeAll(keepingCapacity: true)
        self.popupTokenAccountAdds.removeAll(keepingCapacity: true)
        self.popupTokenAccountPages.removeAll(keepingCapacity: true)
        var continuingPage = false
        let focusSavedAccounts = preserveAnchor && self.tokenAccountPageQueued
        self.tokenAccountPageQueued = false
        var savedAccountsMenuPosition: Int32 = -1
        defer {
            self.popupIsOpen = false
            self.popupCopySummary = nil
            self.popupCopyErrors.removeAll(keepingCapacity: true)
            self.popupProviderDetails.removeAll(keepingCapacity: true)
            self.popupTokenAccountCommands.removeAll(keepingCapacity: true)
        self.popupTokenAccountRenames.removeAll(keepingCapacity: true)
        self.popupCredentialEdits.removeAll(keepingCapacity: true)
        self.popupTokenAccountAdds.removeAll(keepingCapacity: true)
            self.popupTokenAccountPages.removeAll(keepingCapacity: true)
            self.mailboxLock.lock()
            let cliReady = self.cliSetupResult != nil
            self.mailboxLock.unlock()
            if cliReady, !self.quitInvoked, let hwnd = self.window {
                PostMessageW(hwnd, Self.wakeMessage, 0, 0)
            }
            if !continuingPage { self.keyboardReturnTarget = nil }
        }
        if !preserveAnchor {
            if keyboardInitiated { self.captureKeyboardReturnTarget() }
            else { self.keyboardReturnTarget = nil }
            self.keyboardPopupAnchor = keyboardInitiated ? self.keyboardMenuPoint() : nil
        }
        guard let hwnd = self.window, let menu = CreatePopupMenu() else { return }
        if notifyMenuOpen { self.onMenuOpen() }
        self.mailboxLock.lock()
        let rows = self.mailboxRows
        let menuEntries = self.mailboxMenuEntries
        let agentSessions = self.mailboxAgentSessions
        let remoteSessions = self.mailboxRemoteSessions
        self.mailboxLock.unlock()
        self.popupPageCommands.removeAll(keepingCapacity: true)
        self.popupRemoteCommands.removeAll(keepingCapacity: true)
        self.popupRemoteDetails.removeAll(keepingCapacity: true)
        self.popupAgentSessionCommands.removeAll(keepingCapacity: true)
        self.popupSessionDetails = nil
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
        self.popupCopySummary = WindowsClipboard.summary(rows: rows)
        self.popupCopyPrivacy = WindowsUsagePresentationSettings.load().hidePersonalInfo
        if self.popupCopySummary != nil {
            "Copy &redacted summary".withCString(encodedAs: UTF16.self) {
                _ = AppendMenuW(menu, UINT(MF_STRING), Self.copySummaryCommand, $0)
            }
        }
        if let addMenu = CreatePopupMenu() {
            var commands: [UINT_PTR: (UsageProvider, UUID?)] = [:]
            for entry in menuEntries {
                guard commands.count < 128, let provider = UsageProvider(rawValue: entry.providerID),
                      TokenAccountSupportCatalog.support(for: provider) != nil else { continue }
                let command = UINT_PTR(0x8100 + commands.count)
                let title = ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
                    .replacingOccurrences(of: "&", with: "&&")
                if title.withCString(encodedAs: UTF16.self, { AppendMenuW(addMenu, UINT(MF_STRING), command, $0) }) != 0 {
                    commands[command] = (provider, entry.tokenAccountSelection?.selectedID)
                }
            }
            let attached = !commands.isEmpty && "Add saved account…".withCString(encodedAs: UTF16.self) {
                AppendMenuW(menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: addMenu)), $0) != 0
            }
            if attached { self.popupTokenAccountAdds = commands } else { DestroyMenu(addMenu) }
        }
        let accountIDs = menuEntries.flatMap { $0.tokenAccountSelection?.accounts.map(\.id) ?? [] }
        if accountIDs != self.tokenAccountPageIDs {
            self.tokenAccountPageIDs = accountIDs
            self.tokenAccountPage = 0
        }
        let accountPageCount = max(1, (accountIDs.count + 127) / 128)
        self.tokenAccountPage = min(self.tokenAccountPage, accountPageCount - 1)
        let accountStart = self.tokenAccountPage * 128
        let accountEnd = min(accountIDs.count, accountStart + 128)
        if let accountsMenu = CreatePopupMenu() {
            var accountOffset = 0
            var pageCommands: [UINT_PTR: Int] = [:]
            if accountPageCount > 1 {
                let title = "Page \(self.tokenAccountPage + 1) of \(accountPageCount)"
                title.withCString(encodedAs: UTF16.self) {
                    _ = AppendMenuW(accountsMenu, UINT(MF_STRING | MF_GRAYED), 0, $0)
                }
                for (command, page, label) in [(UINT_PTR(0x7F00), self.tokenAccountPage - 1, "Previous accounts…"),
                                                (UINT_PTR(0x7F01), self.tokenAccountPage + 1, "Next accounts…")]
                    where page >= 0 && page < accountPageCount {
                    if label.withCString(encodedAs: UTF16.self, {
                        AppendMenuW(accountsMenu, UINT(MF_STRING), command, $0)
                    }) != 0 { pageCommands[command] = page }
                }
            }
            var commands: [UINT_PTR: WindowsTokenAccountSelectionRequest] = [:]
            var credentialEdits: [UINT_PTR: (ProviderInstanceID, UUID)] = [:]
            var renames: [UINT_PTR: (ProviderInstanceID, UUID, String)] = [:]
            for entry in menuEntries {
                guard let selection = entry.tokenAccountSelection else { continue }
                let providerStart = accountOffset
                accountOffset += selection.accounts.count
                let start = max(0, accountStart - providerStart)
                let end = min(selection.accounts.count, accountEnd - providerStart)
                guard start < end, let providerMenu = CreatePopupMenu() else { continue }
                var providerCommands: [UINT_PTR: WindowsTokenAccountSelectionRequest] = [:]
                var providerCredentialEdits: [UINT_PTR: (ProviderInstanceID, UUID)] = [:]
                var providerRenames: [UINT_PTR: (ProviderInstanceID, UUID, String)] = [:]
                for account in selection.accounts[start..<end] {
                    let command = UINT_PTR(0x7E00 + commands.count + providerCommands.count)
                    let request = WindowsTokenAccountSelectionRequest(id: UUID(), providerID: selection.providerID,
                        accountID: account.id, expectedSelectedID: selection.selectedID)
                    let flags = UINT(MF_STRING) | (selection.selectedID == account.id ? UINT(MF_CHECKED) : 0)
                    let title = account.title.replacingOccurrences(of: "&", with: "&&")
                    if title.withCString(encodedAs: UTF16.self, { AppendMenuW(providerMenu, flags, command, $0) }) != 0 {
                        providerCommands[command] = request
                        let credentialCommand = UINT_PTR(0x8200) + command - UINT_PTR(0x7E00)
                        if ("Replace credential for " + title + "…").withCString(encodedAs: UTF16.self, {
                            AppendMenuW(providerMenu, UINT(MF_STRING), credentialCommand, $0)
                        }) != 0 { providerCredentialEdits[credentialCommand] = (selection.providerID, account.id) }
                        let renameCommand = UINT_PTR(0x8000) + command - UINT_PTR(0x7E00)
                        let renameTitle = "Rename " + title + "…"
                        if renameTitle.withCString(encodedAs: UTF16.self, {
                            AppendMenuW(providerMenu, UINT(MF_STRING), renameCommand, $0)
                        }) != 0 { providerRenames[renameCommand] = (selection.providerID, account.id, account.labelRevision) }
                    }
                }
                let suffix = selection.requiresManualSource ? " (manual source)" : ""
                let title = (entry.title + suffix).replacingOccurrences(of: "&", with: "&&")
                let attached = !providerCommands.isEmpty && title.withCString(encodedAs: UTF16.self) {
                    AppendMenuW(accountsMenu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: providerMenu)), $0) != 0
                }
                if attached {
                    commands.merge(providerCommands) { _, new in new }
                    credentialEdits.merge(providerCredentialEdits) { _, new in new }
                    renames.merge(providerRenames) { _, new in new }
                } else { DestroyMenu(providerMenu) }
            }
            let menuPosition = GetMenuItemCount(menu)
            let attached = (!commands.isEmpty || !pageCommands.isEmpty) && "Saved &accounts".withCString(encodedAs: UTF16.self) {
                AppendMenuW(menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: accountsMenu)), $0) != 0
            }
            if attached {
                self.popupTokenAccountCommands = commands
                self.popupTokenAccountRenames = renames
                self.popupCredentialEdits = credentialEdits
                self.popupTokenAccountPages = pageCommands
                savedAccountsMenuPosition = menuPosition
            } else { DestroyMenu(accountsMenu) }
        }
        let detailEntries = menuEntries.filter { $0.usageCopyText != nil || $0.errorCopyText != nil }
        if !detailEntries.isEmpty, let detailsMenu = CreatePopupMenu() {
            var commands: [UINT_PTR: (title: String, body: String, links: [WindowsProviderDetailsDialog.Link])] = [:]
            for (index, entry) in detailEntries.prefix(128).enumerated() {
                let title = String(LogRedactor.redact(entry.title).replacingOccurrences(of: "\0", with: "").prefix(160))
                var sections: [String] = []
                if let usage = entry.usageCopyText { sections.append("Usage\r\n" + usage) }
                if let error = entry.errorCopyText { sections.append("Fetch error\r\n" + error) }
                let body = sections.joined(separator: "\r\n\r\n")
                var links: [WindowsProviderDetailsDialog.Link] = []
                if entry.dashboardVisible, let url = entry.dashboardURL {
                    links.append(.init(title: "Dashboard", url: url))
                }
                if entry.statusVisible, let url = entry.statusURL {
                    links.append(.init(title: "Status page", url: url))
                }
                if self.presentationDefaults.object(forKey: "providerChangelogLinksEnabled") as? Bool ?? false,
                   entry.changelogVisible, let url = entry.changelogURL {
                    links.append(.init(title: "Release notes", url: url))
                }
                let command = Self.providerDetailsCommandBase + UINT_PTR(index)
                if title.replacingOccurrences(of: "&", with: "&&").withCString(encodedAs: UTF16.self, {
                    AppendMenuW(detailsMenu, UINT(MF_STRING), command, $0)
                }) != 0 { commands[command] = (title, body, links) }
            }
            let attached = !commands.isEmpty && "Provider &details".withCString(encodedAs: UTF16.self) {
                AppendMenuW(menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: detailsMenu)), $0) != 0
            }
            if attached { self.popupProviderDetails = commands } else { _ = DestroyMenu(detailsMenu) }
        }
        let usageEntries = menuEntries.filter { $0.usageCopyText != nil }
        if !usageEntries.isEmpty, let usageMenu = CreatePopupMenu() {
            var commands: [UINT_PTR: String] = [:]
            for (index, entry) in usageEntries.prefix(128).enumerated() {
                guard let text = entry.usageCopyText else { continue }
                let command = Self.copyUsageCommandBase + UINT_PTR(index)
                let title = entry.title.replacingOccurrences(of: "&", with: "&&")
                if title.withCString(encodedAs: UTF16.self, { AppendMenuW(usageMenu, UINT(MF_STRING), command, $0) }) != 0 {
                    commands[command] = text
                }
            }
            let attached = !commands.isEmpty && "Copy provider &usage".withCString(encodedAs: UTF16.self) {
                AppendMenuW(menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: usageMenu)), $0) != 0
            }
            if attached { self.popupCopyErrors.merge(commands) { _, new in new } } else { _ = DestroyMenu(usageMenu) }
        }
        let failures = menuEntries.filter { $0.errorCopyText != nil }
        if !failures.isEmpty, let errorMenu = CreatePopupMenu() {
            var commands: [UINT_PTR: String] = [:]
            for (index, entry) in failures.prefix(128).enumerated() {
                guard let text = entry.errorCopyText else { continue }
                let command = Self.copyErrorCommandBase + UINT_PTR(index)
                let title = entry.title.replacingOccurrences(of: "&", with: "&&")
                if title.withCString(encodedAs: UTF16.self, { AppendMenuW(errorMenu, UINT(MF_STRING), command, $0) }) != 0 {
                    commands[command] = text
                }
            }
            let attached = !commands.isEmpty && "Copy provider &error".withCString(encodedAs: UTF16.self) {
                AppendMenuW(menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: errorMenu)), $0) != 0
            }
            if attached { self.popupCopyErrors.merge(commands) { _, new in new } } else { _ = DestroyMenu(errorMenu) }
        }
        if !rows.isEmpty { _ = AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil) }
        let statusEntries = menuEntries.filter(\.statusVisible)
        if !statusEntries.isEmpty, let statusMenu = CreatePopupMenu() {
            var statusItemsAppended = true
            for (index, entry) in statusEntries.enumerated() {
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
        let localMenuPosition = GetMenuItemCount(menu)
        self.appendAgentSessionsMenu(to: menu, snapshot: agentSessions)
        self.appendRemoteSessionsMenu(to: menu, snapshot: remoteSessions)
        let startupState = WindowsStartupRegistration.state()
        let startupTitle: String
        switch startupState {
        case .absent: startupTitle = "Register this app at Windows sign-in"
        case .registered: startupTitle = "Registered at sign-in (Windows policy may override)"
        case .conflict: startupTitle = "Startup entry belongs to a different command"
        case .unavailable: startupTitle = "Startup registration unavailable for this executable"
        case .packaged: startupTitle = "Packaged startup integration is not implemented yet"
        }
        startupTitle.withCString(encodedAs: UTF16.self) {
            let disabled = startupState == .conflict || startupState == .unavailable || startupState == .packaged
            _ = AppendMenuW(menu, UINT(MF_STRING) | (startupState == .registered ? UINT(MF_CHECKED) : 0) |
                            (disabled ? UINT(MF_GRAYED) : 0), Self.startupRegistrationCommand, $0)
        }
        if let message = self.startupRegistrationMessage {
            message.withCString(encodedAs: UTF16.self) { _ = AppendMenuW(menu, UINT(MF_STRING | MF_GRAYED), 0, $0) }
        }
        "Startup registration details…".withCString(encodedAs: UTF16.self) {
            _ = AppendMenuW(menu, UINT(MF_STRING), Self.startupDetailsCommand, $0)
        }
        "Open Windows startup apps settings…".withCString(encodedAs: UTF16.self) {
            _ = AppendMenuW(menu, UINT(MF_STRING), Self.startupSettingsCommand, $0)
        }
        self.mailboxLock.lock()
        let cliTitle = self.cliPathOperationRunning ? "CLI PATH update running…" : self.cliSetupRunning
            ? (self.cliSetupCancelled ? "CLI discovery cancellation pending…" : "Cancel CLI discovery…")
            : (self.cliSetupResult != nil ? "Show CLI discovery result…" : "Command-line setup…")
        self.mailboxLock.unlock()
        cliTitle.withCString(encodedAs: UTF16.self) {
            _ = AppendMenuW(menu, UINT(MF_STRING), Self.cliSetupCommand, $0)
        }
        for (title, command) in [("Add this CLI folder to user PATH…", Self.cliPathAddCommand),
                                 ("Remove this CLI folder from user PATH…", Self.cliPathRemoveCommand)] {
            title.withCString(encodedAs: UTF16.self) { _ = AppendMenuW(menu, UINT(MF_STRING), command, $0) }
        }
        self.appendShortcutMenu(to: menu)
        self.appendSessionLabelMenu(to: menu)
        self.appendRefreshFrequencyMenu(to: menu)
        self.appendLowPowerModeMenu(to: menu)
        _ = AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil)
        "Re&fresh".withCString(encodedAs: UTF16.self) { _ = AppendMenuW(menu, UINT(MF_STRING), Self.refreshCommand, $0) }
        "&Quit".withCString(encodedAs: UTF16.self) { _ = AppendMenuW(menu, UINT(MF_STRING), Self.quitCommand, $0) }
        _ = SetForegroundWindow(hwnd)
        var point = self.keyboardPopupAnchor ?? POINT()
        let havePoint = self.keyboardPopupAnchor != nil || GetCursorPos(&point) != 0
        guard havePoint else {
            _ = DestroyMenu(menu)
            self.restoreKeyboardReturnTarget(owner: hwnd)
            self.popupPageCommands.removeAll(keepingCapacity: true)
        self.popupRemoteCommands.removeAll(keepingCapacity: true)
        self.popupRemoteDetails.removeAll(keepingCapacity: true)
        self.popupAgentSessionCommands.removeAll(keepingCapacity: true)
        self.popupSessionDetails = nil
        self.popupStatusCommands.removeAll(keepingCapacity: true)
            self.popupDashboardCommands.removeAll(keepingCapacity: true)
            self.popupChangelogCommands.removeAll(keepingCapacity: true)
            self.popupProviderQuotaWarningCommands.removeAll(keepingCapacity: true)
            self.popupProviderQuotaWarningNames.removeAll(keepingCapacity: true)
            return
        }
        var flags = UINT(TPM_RIGHTBUTTON | TPM_RETURNCMD)
        if self.keyboardPopupAnchor != nil {
            // Re-clamp a retained page anchor if the display configuration changed between menus.
            let monitor = MonitorFromPoint(point, UINT(MONITOR_DEFAULTTONEAREST))
            var info = MONITORINFO()
            info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
            if let monitor, GetMonitorInfoW(monitor, &info) != 0,
               info.rcWork.right > info.rcWork.left, info.rcWork.bottom > info.rcWork.top {
                point.x = min(max(point.x, info.rcWork.left), info.rcWork.right - 1)
                point.y = min(max(point.y, info.rcWork.top), info.rcWork.bottom - 1)
            }
            flags |= UINT(TPM_RIGHTALIGN | TPM_BOTTOMALIGN)
        }
        if focusSavedAccounts, savedAccountsMenuPosition >= 0,
           GetSubMenu(menu, savedAccountsMenuPosition) != nil {
            self.keyboardInitialMenu = menu
            self.keyboardInitialPosition = UINT(savedAccountsMenuPosition)
        } else if self.keyboardReturnTarget != nil, localMenuPosition >= 0, GetSubMenu(menu, localMenuPosition) != nil {
            self.keyboardInitialMenu = menu
            self.keyboardInitialPosition = UINT(localMenuPosition)
        }
        let command = TrackPopupMenu(menu, flags, point.x, point.y, 0, hwnd, nil)
        self.keyboardInitialMenu = nil
        self.keyboardInitialPosition = nil
        _ = DestroyMenu(menu)
        continuingPage = command != 0 && self.popupPageCommands[UINT_PTR(command)] != nil
        if command != 0 {
            self.dispatchCommand(UINT_PTR(command))
            continuingPage = continuingPage || self.tokenAccountPageQueued
        } else { self.restoreKeyboardReturnTarget(owner: hwnd) }
        self.popupPageCommands.removeAll(keepingCapacity: true)
        self.popupRemoteCommands.removeAll(keepingCapacity: true)
        self.popupRemoteDetails.removeAll(keepingCapacity: true)
        self.popupAgentSessionCommands.removeAll(keepingCapacity: true)
        self.popupSessionDetails = nil
        self.popupStatusCommands.removeAll(keepingCapacity: true)
        self.popupDashboardCommands.removeAll(keepingCapacity: true)
        self.popupChangelogCommands.removeAll(keepingCapacity: true)
        self.popupProviderQuotaWarningCommands.removeAll(keepingCapacity: true)
        self.popupProviderQuotaWarningNames.removeAll(keepingCapacity: true)
        _ = PostMessageW(hwnd, WM_NULL, 0, 0)
    }

    private func appendAgentSessionsMenu(to menu: HMENU, snapshot: WindowsSessionMenuSnapshot) {
        guard let submenu = CreatePopupMenu() else { return }
        var commands: [UINT_PTR: WindowsSessionFocusRequest] = [:]
        var details: String?
        func append(_ title: String, flags: UINT, command: UINT_PTR) -> Bool {
            title.withCString(encodedAs: UTF16.self) { AppendMenuW(submenu, flags, command, $0) != 0 }
        }
        let enabledFlags = UINT(MF_STRING) | (snapshot.enabled ? UINT(MF_CHECKED) : 0)
        var succeeded = append("Enable local CLI sessions", flags: enabledFlags, command: Self.agentSessionsToggleCommand)
        succeeded = succeeded && self.appendSessionSettingsMenu(to: submenu, localEnabled: snapshot.enabled)
        if snapshot.enabled {
            succeeded = succeeded && append(
                snapshot.isRefreshing ? "Refresh queued / scanning…" : "Refresh sessions (clear title cache)",
                flags: UINT(MF_STRING), command: Self.agentSessionsRefreshCommand)
            if let message = snapshot.message, !message.isEmpty {
                let scalars = message.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
                let summary = scalars.prefix(90).map(String.init).joined() + (scalars.count > 90 ? "…" : "")
                details = scalars.prefix(8192).map(String.init).joined() +
                    (scalars.count > 8192 ? "\n\n[Display truncated]" : "")
                succeeded = succeeded && append(summary.replacingOccurrences(of: "&", with: "&&"),
                                                flags: UINT(MF_STRING | MF_GRAYED), command: 0)
                succeeded = succeeded && append("Session status details…", flags: UINT(MF_STRING),
                                                command: Self.sessionDetailsCommand)
            }
            for (index, item) in snapshot.rows.enumerated() {
                let command = Self.agentSessionCommandBase + UINT_PTR(index)
                let flags = UINT(MF_STRING) | (item.isEnabled ? 0 : UINT(MF_GRAYED))
                succeeded = succeeded && append(item.title, flags: flags, command: command)
                if item.isEnabled { commands[command] = item.request }
            }
        }
        if snapshot.enabled { succeeded = succeeded && self.appendPageControls(to: submenu, page: snapshot.page, remote: false) }
        let title = snapshot.enabled ? "&Local CLI sessions (\(snapshot.page.totalItems))" : "&Local CLI sessions"
        let attached = succeeded && title.withCString(encodedAs: UTF16.self) {
            AppendMenuW(menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: submenu)), $0) != 0
        }
        if attached {
            self.popupAgentSessionCommands = commands
            self.popupSessionDetails = details
        }
        else {
            self.popupPageCommands[Self.localPreviousPageCommand] = nil
            self.popupPageCommands[Self.localNextPageCommand] = nil
            _ = DestroyMenu(submenu)
        }
    }

    private func appendSessionSettingsMenu(to menu: HMENU, localEnabled: Bool) -> Bool {
        guard let settings = CreatePopupMenu() else { return false }
        func append(_ title: String, flags: UINT, command: UINT_PTR) -> Bool {
            title.withCString(encodedAs: UTF16.self) { AppendMenuW(settings, flags, command, $0) != 0 }
        }
        let hidePersonalInfo = self.presentationDefaults.object(forKey: "hidePersonalInfo") as? Bool ?? false
        var succeeded = true
        let nativeDirectories = self.presentationDefaults.object(forKey: "windowsNativeSessionCwdEnabled") as? Bool ?? false
        let nativeFlags = UINT(MF_STRING) | (nativeDirectories ? UINT(MF_CHECKED) : 0)
        succeeded = succeeded && append("Read native directories (experimental, 64-bit)",
                                        flags: nativeFlags, command: Self.nativeSessionDirectoryCommand)
        let correlate = self.presentationDefaults.object(forKey: "windowsSessionMetadataEnabled") as? Bool ?? false
        succeeded = succeeded && append("Match session metadata", flags: UINT(MF_STRING) | (correlate ? UINT(MF_CHECKED) : 0),
                                        command: Self.sessionMetadataToggleCommand)
        let claudeTitles = self.presentationDefaults.object(forKey: "windowsClaudeSessionTitlesEnabled") as? Bool ?? false
        succeeded = succeeded && append("Read Claude transcript titles (experimental)",
                                        flags: UINT(MF_STRING) | (claudeTitles ? UINT(MF_CHECKED) : 0),
                                        command: Self.claudeTitlesCommand)
        let inferNew = self.presentationDefaults.object(forKey: "windowsInferNewSessionMetadataEnabled") as? Bool ?? false
        succeeded = succeeded && append("Infer new-session metadata (experimental)",
                                        flags: UINT(MF_STRING) | (inferNew ? UINT(MF_CHECKED) : 0),
                                        command: Self.inferNewSessionMetadataCommand)
        succeeded = succeeded && append("Choose Codex sessions folder…", flags: UINT(MF_STRING), command: Self.codexSessionFolderCommand)
        succeeded = succeeded && append("Choose Claude projects folder…", flags: UINT(MF_STRING), command: Self.claudeProjectFolderCommand)
        if self.presentationDefaults.string(forKey: "windowsCodexSessionDirectory") != nil {
            succeeded = succeeded && append("Use Codex folder from environment", flags: UINT(MF_STRING), command: Self.clearCodexSessionFolderCommand)
        }
        if self.presentationDefaults.string(forKey: "windowsClaudeProjectDirectory") != nil {
            succeeded = succeeded && append("Use Claude folder from environment", flags: UINT(MF_STRING), command: Self.clearClaudeProjectFolderCommand)
        }
        succeeded = succeeded && append("Choose folder containing Codex session_index.jsonl…",
                                        flags: UINT(MF_STRING), command: Self.codexTitleFolderCommand)
        succeeded = succeeded && append(self.codexTitleSourceLabel(hidePersonalInfo: hidePersonalInfo),
                                        flags: UINT(MF_STRING | MF_GRAYED), command: 0)
        succeeded = succeeded && append("Disable Codex indexed titles",
                                        flags: UINT(MF_STRING), command: Self.disableCodexTitleCommand)
        if self.presentationDefaults.string(forKey: "windowsCodexTitleIndex") != nil {
            succeeded = succeeded && append("Use title source from environment",
                                            flags: UINT(MF_STRING), command: Self.clearCodexTitleCommand)
        }
        succeeded = succeeded && append("Choose Codex SQLite title file…", flags: UINT(MF_STRING), command: Self.chooseTitleDatabaseCommand)
        succeeded = succeeded && append(self.codexTitleSourceLabel(hidePersonalInfo: hidePersonalInfo, database: true),
                                        flags: UINT(MF_STRING | MF_GRAYED), command: 0)
        succeeded = succeeded && append("Disable SQLite title fallback", flags: UINT(MF_STRING), command: Self.disableTitleDatabaseCommand)
        if self.presentationDefaults.string(forKey: "windowsCodexTitleDatabase") != nil {
            succeeded = succeeded && append("Use SQLite source from environment", flags: UINT(MF_STRING), command: Self.clearTitleDatabaseCommand)
        }
        for item in self.sessionSourceGuidance(localEnabled: localEnabled) {
            succeeded = succeeded && append(item.title, flags: UINT(MF_STRING), command: item.command)
        }
        let attached = succeeded && "Session settings and sources".withCString(encodedAs: UTF16.self) {
            AppendMenuW(menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: settings)), $0) != 0
        }
        // Once attached the parent owns the child. On failure only this unattached menu is destroyed.
        if !attached { _ = DestroyMenu(settings) }
        return attached
    }

    private func appendSessionLabelMenu(to menu: HMENU) {
        guard let submenu = CreatePopupMenu() else { return }
        let selected = WindowsSessionLabelStyle.load(self.presentationDefaults)
        var succeeded = true
        for (index, style) in WindowsSessionLabelStyle.allCases.enumerated() {
            let flags = UINT(MF_STRING) | (style == selected ? UINT(MF_CHECKED) : 0)
            let appended = style.title.withCString(encodedAs: UTF16.self) {
                AppendMenuW(submenu, flags, Self.sessionLabelCommandBase + UINT_PTR(index), $0)
            }
            if appended == 0 { succeeded = false; break }
        }
        let attached = succeeded && "Session labels".withCString(encodedAs: UTF16.self) {
            AppendMenuW(menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: submenu)), $0) != 0
        }
        if !attached { _ = DestroyMenu(submenu) }
    }

    private func appendRemoteSessionsMenu(to menu: HMENU, snapshot: WindowsRemoteSessionMenuSnapshot) {
        guard let submenu = CreatePopupMenu() else { return }
        var commands: [UINT_PTR: WindowsRemoteFocusRequest] = [:]
        var details: [UINT_PTR: String] = [:]
        func append(_ title: String, _ flags: UINT, _ command: UINT_PTR) -> Bool {
            title.withCString(encodedAs: UTF16.self) { AppendMenuW(submenu, flags, command, $0) != 0 }
        }
        var succeeded = append("Remote host settings…", UINT(MF_STRING), Self.remoteSettingsCommand)
        if snapshot.enabled {
            succeeded = succeeded && append("Refresh remote sessions", UINT(MF_STRING), Self.remoteRefreshCommand)
        }
        for message in snapshot.messages.prefix(64) {
            let title = message.replacingOccurrences(of: "&", with: "&&")
            succeeded = succeeded && append(title, UINT(MF_STRING | MF_GRAYED), 0)
        }
        for (index, row) in snapshot.rows.enumerated() {
            let command = Self.remoteSessionCommandBase + UINT_PTR(index)
            let hasDetails = row.statusDetails != nil && row.request == nil
            succeeded = succeeded && append(row.title, UINT(MF_STRING) | (row.isEnabled || hasDetails ? 0 : UINT(MF_GRAYED)), command)
            if hasDetails { details[command] = row.statusDetails }
            else if row.isEnabled { commands[command] = row.request }
        }
        if snapshot.enabled { succeeded = succeeded && self.appendPageControls(to: submenu, page: snapshot.page, remote: true) }
        let title = snapshot.enabled ? "&Remote sessions" : "&Remote sessions (off)"
        let attached = succeeded && title.withCString(encodedAs: UTF16.self) {
            AppendMenuW(menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: submenu)), $0) != 0
        }
        if attached {
            self.popupRemoteCommands = commands
            self.popupRemoteDetails = details
        } else {
            self.popupPageCommands[Self.remotePreviousPageCommand] = nil
            self.popupPageCommands[Self.remoteNextPageCommand] = nil
            _ = DestroyMenu(submenu)
        }
    }

    private func appendPageControls(to menu: HMENU, page: WindowsSessionPage, remote: Bool) -> Bool {
        guard page.count > 1 else { return true }
        guard AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil) != 0 else { return false }
        let label = page.title.withCString(encodedAs: UTF16.self) {
            AppendMenuW(menu, UINT(MF_STRING | MF_GRAYED), 0, $0)
        }
        guard label != 0 else { return false }
        let options: [(String, UINT_PTR, WindowsSessionPageRequest?)] = [
            ("Previous page", remote ? Self.remotePreviousPageCommand : Self.localPreviousPageCommand, page.previous),
            ("Next page", remote ? Self.remoteNextPageCommand : Self.localNextPageCommand, page.next),
        ]
        for (title, command, request) in options {
            let flags = UINT(MF_STRING) | (request == nil ? UINT(MF_GRAYED) : 0)
            let result = title.withCString(encodedAs: UTF16.self) { AppendMenuW(menu, flags, command, $0) }
            guard result != 0 else { return false }
            if let request { self.popupPageCommands[command] = (request, remote) }
        }
        return true
    }

    private func sessionMetadataSettingsChanged() {
        self.mailboxLock.lock()
        self.mailboxAgentSessions = .init(
            enabled: self.presentationDefaults.object(forKey: "agentSessionsEnabled") as? Bool ?? false,
            isRefreshing: true, rows: [], message: "Applying session metadata settings…")
        self.mailboxLock.unlock()
        self.onAgentSessionsSettingsChanged()
    }

    /// Configuration guidance only. Do not touch files or probe providers while building a menu.
    /// Each row routes to an existing setting action; nothing is automatically enabled or reset.
    private func showSessionDetails() {
        guard let details = self.popupSessionDetails else { return }
        self.popupSessionDetails = nil
        self.showSessionMessage(details, caption: "Local CLI session status")
    }

    private func showSessionMessage(_ details: String, caption: String) {
        self.showMessage("Status captured when the session menu opened. Refresh sessions to update.\n\n" + details,
                         caption: caption)
    }

    private func showProviderDetails(_ body: String, title: String, links: [WindowsProviderDetailsDialog.Link]) {
        guard !self.remoteEditorOpen, !self.quitInvoked, let window = self.window,
              case .idle = self.providerEditorPhase, case .idle = self.codexWebSettingsEditorPhase else { return }
        self.remoteEditorOpen = true
        let privacy = WindowsUsagePresentationSettings.load().hidePersonalInfo
        let result = WindowsProviderDetailsDialog.show(
            owner: window, title: title,
            text: "Redacted snapshot from the opened menu. Refresh all closes this window and requests usage and session updates. Reopen details after the update.\r\n\r\n" + body,
            links: links)
        self.remoteEditorOpen = false
        if !self.quitInvoked {
            PostMessageW(window, Self.wakeMessage, 0, 0)
            if let result {
                switch result {
                case .closed: break
                case .refreshAll: self.onRefresh()
                case let .openURL(url):
                    guard privacy == WindowsUsagePresentationSettings.load().hidePersonalInfo else {
                        self.showMessage("Privacy settings changed. Reopen provider details before opening a link.",
                                         caption: "Provider details")
                        return
                    }
                    self.openProviderPage(url)
                }
            } else { self.showMessage("Could not open provider details.", caption: "Provider details") }
        }
    }

    private func showMessage(_ body: String, caption: String) {
        guard !self.remoteEditorOpen, !self.quitInvoked, let window = self.window,
              case .idle = self.providerEditorPhase, case .idle = self.codexWebSettingsEditorPhase else { return }
        self.remoteEditorOpen = true
        defer {
            self.remoteEditorOpen = false
            if !self.quitInvoked { PostMessageW(window, Self.wakeMessage, 0, 0) }
        }
        body.withCString(encodedAs: UTF16.self) { text in
            caption.withCString(encodedAs: UTF16.self) { title in
                _ = MessageBoxW(window, text, title, UINT(MB_OK | MB_ICONINFORMATION))
            }
        }
    }

    private func sessionSourceGuidance(localEnabled: Bool) -> [(title: String, command: UINT_PTR)] {
        guard localEnabled else {
            return [("Start here: enable local CLI sessions", Self.agentSessionsToggleCommand)]
        }
        guard self.presentationDefaults.object(forKey: "windowsSessionMetadataEnabled") as? Bool ?? false else {
            return [("To use configured metadata: enable matching", Self.sessionMetadataToggleCommand)]
        }
        func configured(_ key: String, _ variable: String) -> String? {
            let value = self.presentationDefaults.string(forKey: key) ?? CodexBarPlatformPaths.environmentValue(
                variable, environment: ProcessInfo.processInfo.environment)
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        var rows: [(title: String, command: UINT_PTR)] = []
        let codex = configured("windowsCodexSessionDirectory", "CODEXBAR_WINDOWS_CODEX_SESSIONS_ROOT")
        let claude = configured("windowsClaudeProjectDirectory", "CODEXBAR_WINDOWS_CLAUDE_PROJECTS_ROOT")
        if let codex {
            do { _ = try WindowsSessionMetadataRoots(codexSessions: codex, claudeProjects: nil) }
            catch { rows.append(("Fix invalid Codex source: choose sessions folder…", Self.codexSessionFolderCommand)) }
        } else {
            rows.append(("Codex metadata needs a sessions folder…", Self.codexSessionFolderCommand))
        }
        if let claude {
            do { _ = try WindowsSessionMetadataRoots(codexSessions: nil, claudeProjects: claude) }
            catch { rows.append(("Fix invalid Claude source: choose projects folder…", Self.claudeProjectFolderCommand)) }
        } else {
            let titles = self.presentationDefaults.object(forKey: "windowsClaudeSessionTitlesEnabled") as? Bool ?? false
            rows.append((titles ? "Claude titles need a projects folder…" : "Claude metadata needs a projects folder…",
                         Self.claudeProjectFolderCommand))
        }
        if let title = configured("windowsCodexTitleIndex", "CODEXBAR_WINDOWS_CODEX_TITLE_INDEX") {
            do { _ = try WindowsSessionMetadataRoots(codexSessions: nil, claudeProjects: nil, codexTitleIndex: title) }
            catch { rows.append(("Fix invalid title source: choose index folder…", Self.codexTitleFolderCommand)) }
        }
        if let database = configured("windowsCodexTitleDatabase", "CODEXBAR_WINDOWS_CODEX_TITLE_DATABASE") {
            do { _ = try WindowsSessionMetadataRoots(codexSessions: nil, claudeProjects: nil, codexTitleDatabase: database) }
            catch { rows.append(("Fix invalid SQLite source: choose database file…", Self.chooseTitleDatabaseCommand)) }
        }
        return rows
    }

    private func codexTitleSourceLabel(hidePersonalInfo: Bool, database: Bool = false) -> String {
        let override = self.presentationDefaults.string(forKey: database ? "windowsCodexTitleDatabase" : "windowsCodexTitleIndex")
        let environment = CodexBarPlatformPaths.environmentValue(
            database ? "CODEXBAR_WINDOWS_CODEX_TITLE_DATABASE" : "CODEXBAR_WINDOWS_CODEX_TITLE_INDEX", environment: ProcessInfo.processInfo.environment)
        guard let raw = override ?? environment,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (database ? "SQLite titles: " : "Indexed titles: ") + (override != nil ? "disabled" : "no source configured")
        }
        let source = override != nil ? "selected source" : "environment"
        let kind = database ? "SQLite source" : "Title source"
        // Describe configuration only; this does not claim the file exists or was matched.
        guard !hidePersonalInfo else { return "\(kind): \(source) (path hidden)" }
        let clean = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            .prefix(160).map(String.init).joined().replacingOccurrences(of: "&", with: "&&")
        return "\(kind) (\(source)): \(clean)"
    }

    private func chooseCodexTitleDatabase() {
        guard !self.remoteEditorOpen, !self.quitInvoked, let window = self.window,
              case .idle = self.providerEditorPhase, case .idle = self.codexWebSettingsEditorPhase else { return }
        self.remoteEditorOpen = true
        defer {
            self.remoteEditorOpen = false
            if !self.quitInvoked { PostMessageW(window, Self.wakeMessage, 0, 0) }
        }
        guard let path = WindowsSessionMetadataFolderPicker.choose(
            owner: window, title: "Choose a Codex SQLite title file (.sqlite or .db)", includeFiles: true),
              !self.quitInvoked else { return }
        do {
            let roots = try WindowsSessionMetadataRoots(codexSessions: nil, claudeProjects: nil, codexTitleDatabase: path)
            let units = Array(path.utf16) + [0]
            let attributes = units.withUnsafeBufferPointer { GetFileAttributesW($0.baseAddress) }
            guard let normalized = roots.codexTitleDatabase,
                  attributes != INVALID_FILE_ATTRIBUTES,
                  attributes & DWORD(FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) == 0,
                  normalized.lowercased().hasSuffix(".sqlite") || normalized.lowercased().hasSuffix(".db") else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            self.presentationDefaults.set(normalized, forKey: "windowsCodexTitleDatabase")
            self.sessionMetadataSettingsChanged()
        } catch {
            "Choose a local .sqlite or .db file. The previous setting has been retained.".withCString(encodedAs: UTF16.self) { text in
                "Codex SQLite source".withCString(encodedAs: UTF16.self) { title in
                    _ = MessageBoxW(window, text, title, UINT(MB_OK | MB_ICONERROR))
                }
            }
        }
    }

    private func chooseCodexTitleFolder() {
        guard !self.remoteEditorOpen, !self.quitInvoked, let window = self.window,
              case .idle = self.providerEditorPhase, case .idle = self.codexWebSettingsEditorPhase else { return }
        self.remoteEditorOpen = true
        defer {
            self.remoteEditorOpen = false
            if !self.quitInvoked { PostMessageW(window, Self.wakeMessage, 0, 0) }
        }
        guard let folder = WindowsSessionMetadataFolderPicker.choose(
            owner: window, title: "Choose the folder containing Codex session_index.jsonl"),
              !self.quitInvoked else { return }
        let path = folder + (folder.hasSuffix("\\") ? "" : "\\") + "session_index.jsonl"
        do {
            let roots = try WindowsSessionMetadataRoots(codexSessions: nil, claudeProjects: nil, codexTitleIndex: path)
            guard let normalized = roots.codexTitleIndex else { return }
            self.presentationDefaults.set(normalized, forKey: "windowsCodexTitleIndex")
            self.sessionMetadataSettingsChanged()
        } catch {
            "Choose an absolute local Windows drive folder.".withCString(encodedAs: UTF16.self) { text in
                "Codex title source".withCString(encodedAs: UTF16.self) {
                    _ = MessageBoxW(window, text, $0, UINT(MB_OK | MB_ICONERROR))
                }
            }
        }
    }

    private func chooseSessionMetadataFolder(codex: Bool) {
        guard !self.remoteEditorOpen, !self.quitInvoked, let window = self.window,
              case .idle = self.providerEditorPhase, case .idle = self.codexWebSettingsEditorPhase else { return }
        self.remoteEditorOpen = true
        defer {
            self.remoteEditorOpen = false
            if !self.quitInvoked { PostMessageW(window, Self.wakeMessage, 0, 0) }
        }
        guard let path = WindowsSessionMetadataFolderPicker.choose(
            owner: window, title: codex ? "Choose the Codex sessions folder" : "Choose the Claude projects folder"),
              !self.quitInvoked else { return }
        do {
            _ = try WindowsSessionMetadataRoots(codexSessions: codex ? path : nil, claudeProjects: codex ? nil : path)
            self.presentationDefaults.set(path, forKey: codex ? "windowsCodexSessionDirectory" : "windowsClaudeProjectDirectory")
            self.sessionMetadataSettingsChanged()
        } catch {
            "Choose an absolute local Windows drive folder.".withCString(encodedAs: UTF16.self) { text in
                "Session metadata".withCString(encodedAs: UTF16.self) {
                    _ = MessageBoxW(window, text, $0, UINT(MB_OK | MB_ICONERROR))
                }
            }
        }
    }

    private func editRemoteSettings() {
        guard !self.remoteEditorOpen, !self.quitInvoked, let window = self.window else { return }
        guard case .idle = self.providerEditorPhase, case .idle = self.codexWebSettingsEditorPhase else { return }
        self.remoteEditorOpen = true
        defer {
            self.remoteEditorOpen = false
            if !self.quitInvoked { PostMessageW(window, Self.wakeMessage, 0, 0) }
        }
        do {
            let settings = try WindowsRemoteSessionSettings.load(from: self.presentationDefaults)
            guard let updated = WindowsRemoteSessionSettingsDialog.show(owner: window, settings: settings),
                  !self.quitInvoked
            else { return }
            try updated.save(to: self.presentationDefaults)
            self.onRemoteSettingsChanged()
        } catch {
            let message = error.localizedDescription
            message.withCString(encodedAs: UTF16.self) { text in
                "Remote settings could not be saved".withCString(encodedAs: UTF16.self) { title in
                    _ = MessageBoxW(window, text, title, UINT(MB_OK | MB_ICONERROR))
                }
            }
        }
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
        self.cliSetupCancelled = true
        self.cliSetupResult = nil
        self.mailboxAgentSessions = .disabled
        self.mailboxRemoteSessions = .disabled
        self.popupRemoteCommands.removeAll()
        self.popupRemoteDetails.removeAll()
        self.popupPageCommands.removeAll()
        self.popupAgentSessionCommands.removeAll()
        self.popupSessionDetails = nil
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
        self.cliPathOperation.requestStop()
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
        if let (provider, expectedSelectedID) = self.popupTokenAccountAdds[command] {
            guard !self.quitInvoked, !self.remoteEditorOpen, let window = self.window,
                  let support = TokenAccountSupportCatalog.support(for: provider),
                  case .idle = self.providerEditorPhase, case .idle = self.codexWebSettingsEditorPhase else { return }
            self.mailboxLock.lock()
            let busy = self.tokenAccountPendingID != nil
            self.mailboxLock.unlock()
            guard !busy else { self.showMessage("An account change is already being saved. Please wait.", caption: "Saved accounts"); return }
            self.remoteEditorOpen = true
            let result = WindowsAccountAddDialog.show(owner: window,
                providerName: ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName, provider: provider, support: support)
            self.remoteEditorOpen = false
            if !self.quitInvoked { PostMessageW(window, Self.wakeMessage, 0, 0) }
            guard !self.quitInvoked else { return }
            switch result {
            case .cancelled: break
            case .failed: self.showMessage("Could not open the account editor.", caption: "Saved accounts")
            case let .saved(draft):
                let requestID = UUID()
                self.mailboxLock.lock()
                self.tokenAccountPendingID = requestID
                self.mailboxLock.unlock()
                self.onTokenAccountAdd(requestID, .init(providerID: provider.instanceID, accountID: UUID(),
                    label: draft.label, token: draft.token, usageScope: draft.scope,
                    organizationID: draft.organization, workspaceID: draft.workspace,
                    expectedSelectedID: expectedSelectedID))
            }
            return
        }
        if let (providerID, accountID) = self.popupCredentialEdits[command] {
            guard !self.quitInvoked, !self.remoteEditorOpen,
                  case .idle = self.providerEditorPhase, case .idle = self.codexWebSettingsEditorPhase else { return }
            guard self.popupCopyPrivacy == WindowsUsagePresentationSettings.load().hidePersonalInfo else {
                self.showMessage("Privacy settings changed. Reopen Saved accounts.", caption: "Saved accounts")
                return
            }
            self.mailboxLock.lock()
            guard self.tokenAccountPendingID == nil else {
                self.mailboxLock.unlock()
                self.showMessage("An account change is already in progress. Please wait.", caption: "Saved accounts")
                return
            }
            let requestID = UUID()
            self.tokenAccountPendingID = requestID
            self.mailboxLock.unlock()
            self.onCredentialEditBegin(requestID, providerID, accountID)
            return
        }
        if let (providerID, accountID, revision) = self.popupTokenAccountRenames[command] {
            guard !self.quitInvoked, !self.remoteEditorOpen, let window = self.window,
                  case .idle = self.providerEditorPhase, case .idle = self.codexWebSettingsEditorPhase else { return }
            guard self.popupCopyPrivacy == WindowsUsagePresentationSettings.load().hidePersonalInfo else {
                self.showMessage("Privacy settings changed. Reopen Saved accounts before renaming.", caption: "Saved accounts")
                return
            }
            self.mailboxLock.lock()
            let busy = self.tokenAccountPendingID != nil
            self.mailboxLock.unlock()
            guard !busy else { self.showMessage("An account change is already being saved. Please wait.", caption: "Saved accounts"); return }
            self.remoteEditorOpen = true
            let result = WindowsAccountNameDialog.show(owner: window)
            self.remoteEditorOpen = false
            if !self.quitInvoked { PostMessageW(window, Self.wakeMessage, 0, 0) }
            guard !self.quitInvoked else { return }
            switch result {
            case .cancelled: break
            case .failed: self.showMessage("Could not open the name editor.", caption: "Saved accounts")
            case let .saved(label):
                let requestID = UUID()
                self.mailboxLock.lock()
                self.tokenAccountPendingID = requestID
                self.mailboxLock.unlock()
                self.onTokenAccountRename(requestID, .init(providerID: providerID, accountID: accountID,
                    expectedLabelRevision: revision, replacementLabel: label))
            }
            return
        }
        if let page = self.popupTokenAccountPages[command] {
            guard !self.quitInvoked, let window = self.window else { return }
            let previousPage = self.tokenAccountPage
            self.tokenAccountPage = page
            self.tokenAccountPageQueued = PostMessageW(window, Self.pagePopupMessage, 0, 0) != 0
            if !self.tokenAccountPageQueued {
                self.tokenAccountPage = previousPage
                self.showMessage("Could not open the next account page. Reopen Saved accounts and try again.",
                                 caption: "Saved accounts")
            }
            return
        }
        if let request = self.popupTokenAccountCommands[command] {
            guard !self.quitInvoked, !self.remoteEditorOpen,
                  case .idle = self.providerEditorPhase, case .idle = self.codexWebSettingsEditorPhase else { return }
            guard self.popupCopyPrivacy == WindowsUsagePresentationSettings.load().hidePersonalInfo else {
                self.showMessage("Privacy settings changed. Reopen the menu before selecting an account.", caption: "Saved accounts")
                return
            }
            self.mailboxLock.lock()
            let busy = self.tokenAccountPendingID != nil
            if !busy { self.tokenAccountPendingID = request.id }
            self.mailboxLock.unlock()
            if busy { self.showMessage("An account selection is already being saved. Please wait.", caption: "Saved accounts") }
            else { self.onTokenAccountSelect(request) }
            return
        }
        if let details = self.popupProviderDetails[command] {
            guard self.popupCopyPrivacy == WindowsUsagePresentationSettings.load().hidePersonalInfo else {
                self.showMessage("Privacy settings changed. Reopen the menu to view current details.", caption: "Provider details")
                return
            }
            self.showProviderDetails(details.body, title: details.title, links: details.links)
            return
        }
        if let text = self.popupCopyErrors[command], let owner = self.window {
            guard self.popupCopyPrivacy == WindowsUsagePresentationSettings.load().hidePersonalInfo else {
                self.showMessage("Privacy settings changed. Reopen the menu before copying.", caption: "Copy provider details")
                return
            }
            if let error = WindowsClipboard.write(text, owner: owner) {
                self.showMessage(error, caption: "Copy provider details")
            }
            return
        }
        if let page = self.popupPageCommands[command] {
            if page.remote { self.onRemoteSessionPage(page.request) } else { self.onLocalSessionPage(page.request) }
            return
        }
        if let request = self.popupRemoteCommands[command] { self.onRemoteFocus(request); return }
        if let details = self.popupRemoteDetails.removeValue(forKey: command) {
            self.showSessionMessage(details, caption: "Remote host session status")
            return
        }
        if let request = self.popupAgentSessionCommands[command] {
            self.onAgentSessionFocus(request)
            return
        }
        if let url = self.popupStatusCommands[command] {
            self.openProviderPage(url)
            return
        }
        if let url = self.popupDashboardCommands[command] {
            self.openProviderPage(url)
            return
        }
        if let url = self.popupChangelogCommands[command] {
            self.openProviderPage(url)
            return
        }
        if let providerID = self.popupProviderQuotaWarningCommands[command] {
            self.beginProviderQuotaWarningLoad(providerID)
            return
        }
        if command >= Self.shortcutChoiceBase, command < Self.shortcutChoiceBase + UINT_PTR(WindowsMenuShortcut.allCases.count) {
            self.selectMenuShortcut(WindowsMenuShortcut.allCases[Int(command - Self.shortcutChoiceBase)])
            return
        }
        switch command {
        case Self.copySummaryCommand:
            guard let owner = self.window, let text = self.popupCopySummary else { return }
            guard self.popupCopyPrivacy == WindowsUsagePresentationSettings.load().hidePersonalInfo else {
                self.showMessage("Privacy settings changed. Reopen the menu before copying.", caption: "Copy summary")
                return
            }
            if let error = WindowsClipboard.write(text, owner: owner) {
                self.showMessage(error, caption: "Copy summary")
            }
        case Self.cliPathAddCommand: self.beginCLIPathOperation(.add)
        case Self.cliPathRemoveCommand: self.beginCLIPathOperation(.remove)
        case Self.cliSetupCommand:
            self.showCLISetup()
        case Self.startupDetailsCommand:
            self.showStartupDetails()
        case Self.startupSettingsCommand:
            self.openStartupSettings()
        case Self.startupRegistrationCommand:
            do {
                let state = WindowsStartupRegistration.state()
                guard state == .registered || state == .absent else { throw WindowsStartupRegistration.Failure.conflict }
                try WindowsStartupRegistration.setRegistered(state == .absent)
                self.startupRegistrationMessage = nil
            } catch {
                self.startupRegistrationMessage = "Startup change failed; reopen this menu to read the current registration."
            }
        case Self.applySavedShortcutCommand:
            if self.menuHotkeyRegistered, let saved = WindowsMenuShortcut.load(self.presentationDefaults) {
                self.selectMenuShortcut(saved)
            }
        case Self.cleanupHotkeyCommand:
            if let window = self.window, !self.quitInvoked { self.cleanupInactiveHotkeys(window) }
        case Self.menuHotkeyCommand:
            guard let window = self.window else { return }
            if self.menuHotkeyRegistered {
                if UnregisterHotKey(window, self.activeHotkeyID) != 0 {
                    self.ownedHotkeyIDs.remove(self.activeHotkeyID)
                    self.menuHotkeyRegistered = false
                    self.activeMenuShortcut = nil
                    self.menuHotkeyFailed = false
                    self.presentationDefaults.set(false, forKey: "windowsMenuHotkeyEnabled")
                    self.menuHotkeyFailureMessage = nil
                    self.cleanupInactiveHotkeys(window)
                } else {
                    self.menuHotkeyFailed = true
                    self.menuHotkeyFailureMessage = "Shortcut disable failed (Win32 \(GetLastError())); shortcut remains active."
                }
            } else if self.registerMenuHotkey(window) {
                self.presentationDefaults.set(true, forKey: "windowsMenuHotkeyEnabled")
            }
        case Self.sessionDetailsCommand: self.showSessionDetails()
        case Self.sessionLabelCommandBase, Self.sessionLabelCommandBase + 1, Self.sessionLabelCommandBase + 2:
            let index = Int(command - Self.sessionLabelCommandBase)
            let style = WindowsSessionLabelStyle.allCases[index]
            self.presentationDefaults.set(style.rawValue, forKey: "agentSessionLabelStyle")
            self.onPresentationSettingsChanged()
        case Self.remoteSettingsCommand: self.editRemoteSettings()
        case Self.remoteRefreshCommand: self.onRemoteRefresh()
        case Self.inferNewSessionMetadataCommand:
            let value = self.presentationDefaults.object(forKey: "windowsInferNewSessionMetadataEnabled") as? Bool ?? false
            self.presentationDefaults.set(!value, forKey: "windowsInferNewSessionMetadataEnabled")
            self.sessionMetadataSettingsChanged()
        case Self.claudeTitlesCommand:
            let enabled = self.presentationDefaults.object(forKey: "windowsClaudeSessionTitlesEnabled") as? Bool ?? false
            self.presentationDefaults.set(!enabled, forKey: "windowsClaudeSessionTitlesEnabled")
            self.sessionMetadataSettingsChanged()
        case Self.chooseTitleDatabaseCommand: self.chooseCodexTitleDatabase()
        case Self.clearTitleDatabaseCommand:
            self.presentationDefaults.removeObject(forKey: "windowsCodexTitleDatabase")
            self.sessionMetadataSettingsChanged()
        case Self.disableTitleDatabaseCommand:
            self.presentationDefaults.set("", forKey: "windowsCodexTitleDatabase")
            self.sessionMetadataSettingsChanged()
        case Self.codexTitleFolderCommand: self.chooseCodexTitleFolder()
        case Self.clearCodexTitleCommand:
            self.presentationDefaults.removeObject(forKey: "windowsCodexTitleIndex")
            self.sessionMetadataSettingsChanged()
        case Self.disableCodexTitleCommand:
            // Empty explicit override suppresses environment fallback; removeObject restores it.
            self.presentationDefaults.set("", forKey: "windowsCodexTitleIndex")
            self.sessionMetadataSettingsChanged()
        case Self.sessionMetadataToggleCommand:
            let value = self.presentationDefaults.object(forKey: "windowsSessionMetadataEnabled") as? Bool ?? false
            self.presentationDefaults.set(!value, forKey: "windowsSessionMetadataEnabled")
            self.sessionMetadataSettingsChanged()
        case Self.codexSessionFolderCommand: self.chooseSessionMetadataFolder(codex: true)
        case Self.claudeProjectFolderCommand: self.chooseSessionMetadataFolder(codex: false)
        case Self.clearCodexSessionFolderCommand:
            self.presentationDefaults.removeObject(forKey: "windowsCodexSessionDirectory")
            self.sessionMetadataSettingsChanged()
        case Self.clearClaudeProjectFolderCommand:
            self.presentationDefaults.removeObject(forKey: "windowsClaudeProjectDirectory")
            self.sessionMetadataSettingsChanged()
        case Self.nativeSessionDirectoryCommand:
            let current = self.presentationDefaults.object(forKey: "windowsNativeSessionCwdEnabled") as? Bool ?? false
            self.presentationDefaults.set(!current, forKey: "windowsNativeSessionCwdEnabled")
            self.mailboxLock.lock()
            self.mailboxAgentSessions = .init(
                enabled: self.presentationDefaults.object(forKey: "agentSessionsEnabled") as? Bool ?? false,
                isRefreshing: true, rows: [], message: "Applying session directory settings…")
            self.mailboxLock.unlock()
            self.onAgentSessionsSettingsChanged()
        case Self.agentSessionsToggleCommand:
            let enabled = self.presentationDefaults.object(forKey: "agentSessionsEnabled") as? Bool ?? false
            self.presentationDefaults.set(!enabled, forKey: "agentSessionsEnabled")
            self.onAgentSessionsSettingsChanged()
        case Self.agentSessionsRefreshCommand: self.onAgentSessionsRefresh()
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

    public func shutdownCLIPathHelper(timeout: TimeInterval) -> Bool {
        self.cliPathOperation.drain(timeout: timeout)
    }

    private func beginCLIPathOperation(_ action: WindowsCLIPathOperation.Action) {
        guard let hwnd = self.window, !self.quitInvoked else { return }
        self.mailboxLock.lock()
        let busy = self.cliSetupRunning || self.cliPathOperationRunning
        self.mailboxLock.unlock()
        guard !busy else { self.showProviderEditorNotice("A CLI operation is already running."); return }
        let message = action == .add
            ? "Add this app's CLI folder to your user PATH? Existing entries keep their priority."
            : "Remove all literal entries for this app's folder from your user PATH? Files will remain installed."
        let body = Array((message + "\nSign out and sign in again after the change.").utf16) + [0]
        let title = Array("CodexBar user PATH".utf16) + [0]
        let choice = body.withUnsafeBufferPointer { text in
            title.withUnsafeBufferPointer { caption in
                MessageBoxW(hwnd, text.baseAddress, caption.baseAddress,
                            UINT(MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2))
            }
        }
        guard choice == IDYES, !self.quitInvoked else { return }
        self.mailboxLock.lock()
        guard !self.cliSetupRunning, !self.cliPathOperationRunning else { self.mailboxLock.unlock(); return }
        self.cliPathOperationRunning = true
        self.cliSetupResult = nil
        self.mailboxLock.unlock()
        _ = SetTimer(hwnd, Self.cliSetupTimer, 250, nil)
        Thread.detachNewThread { [weak self] in
            guard let self else { return }
            let text = self.cliPathOperation.run(action)
            self.mailboxLock.lock()
            self.cliPathOperationRunning = false
            if !self.quitInvoked, let window = self.window {
                self.cliSetupResult = (text, true, true)
                PostMessageW(window, Self.wakeMessage, 0, 0)
            }
            self.mailboxLock.unlock()
        }
    }

    private func showCLISetup() {
        guard self.window != nil, !self.quitInvoked else { return }
        let hidePaths = self.presentationDefaults.object(forKey: "hidePersonalInfo") as? Bool ?? false
        self.mailboxLock.lock()
        if self.cliPathOperationRunning {
            self.mailboxLock.unlock()
            self.showProviderEditorNotice("PATH update is running. Wait for its result before another CLI operation.")
            return
        }
        if self.cliSetupRunning {
            self.cliSetupCancelled = true
            self.mailboxLock.unlock()
            self.showProviderEditorNotice("CLI discovery cancellation requested. Reopen setup after the current file query returns.")
            return
        }
        if self.cliSetupResult != nil {
            self.mailboxLock.unlock()
            if let hwnd = self.window { PostMessageW(hwnd, Self.wakeMessage, 0, 0) }
            return
        }
        self.cliSetupRunning = true
        self.cliSetupCancelled = false
        self.cliSetupResult = nil
        self.mailboxLock.unlock()
        // Timer retries deferred delivery after nested modal loops; a failed timer
        // still leaves the result available through the menu and wake message.
        if let hwnd = self.window { _ = SetTimer(hwnd, Self.cliSetupTimer, 250, nil) }
        Thread.detachNewThread { [weak self] in
            guard let self else { return }
            let text = WindowsCLISetup.guidance(hidePaths: hidePaths) {
                self.mailboxLock.lock()
                defer { self.mailboxLock.unlock() }
                return self.cliSetupCancelled || self.quitInvoked
            }
            self.mailboxLock.lock()
            self.cliSetupRunning = false
            if !self.cliSetupCancelled, !self.quitInvoked {
                self.cliSetupResult = (text, hidePaths, false)
                // Post while holding the lifetime lock used by window teardown.
                if let hwnd = self.window { PostMessageW(hwnd, Self.wakeMessage, 0, 0) }
            }
            self.mailboxLock.unlock()
        }
    }

    private func drainCLISetup() {
        guard !self.cliSetupDialogOpen, !self.popupIsOpen, !self.remoteEditorOpen, !self.quitInvoked,
              case .idle = self.providerEditorPhase, case .idle = self.codexWebSettingsEditorPhase,
              let hwnd = self.window else { return }
        self.mailboxLock.lock()
        let result = self.cliSetupResult
        let running = self.cliSetupRunning || self.cliPathOperationRunning
        if IsWindowEnabled(hwnd) != 0 { self.cliSetupResult = nil }
        self.mailboxLock.unlock()
        guard IsWindowEnabled(hwnd) != 0 else { return }
        if !running { _ = KillTimer(hwnd, Self.cliSetupTimer) }
        guard let result else { return }
        let hidePaths = self.presentationDefaults.object(forKey: "hidePersonalInfo") as? Bool ?? false
        // Never surface previously collected paths after privacy has been enabled.
        guard result.mutation || hidePaths == result.hidePaths else { self.showCLISetup(); return }
        self.cliSetupDialogOpen = true
        defer { self.cliSetupDialogOpen = false }
        let body = Array(result.text.utf16) + [0]
        let title = Array("CodexBar command-line setup".utf16) + [0]
        _ = body.withUnsafeBufferPointer { text in
            title.withUnsafeBufferPointer { caption in
                MessageBoxW(hwnd, text.baseAddress, caption.baseAddress, UINT(MB_OK | MB_ICONINFORMATION))
            }
        }
    }

    private func showStartupDetails() {
        guard let hwnd = self.window, !self.quitInvoked else { return }
        // Read on selection; the menu's earlier state may already be stale.
        let state = WindowsStartupRegistration.state()
        let message = state.guidance + "\n\nOpen Windows startup apps settings now?"
        let body = Array(message.utf16) + [0]
        let title = Array("CodexBar startup registration".utf16) + [0]
        let choice = body.withUnsafeBufferPointer { text in
            title.withUnsafeBufferPointer { caption in
                MessageBoxW(hwnd, text.baseAddress, caption.baseAddress,
                            UINT(MB_YESNO | MB_ICONINFORMATION | MB_DEFBUTTON2))
            }
        }
        if choice == IDYES { self.openStartupSettings() }
    }

    private func openStartupSettings() {
        guard let hwnd = self.window, !self.quitInvoked else { return }
        // Fixed OS destination only; provider URLs retain their HTTP(S) restriction.
        let target = Array("ms-settings:startupapps".utf16) + [0]
        let result = target.withUnsafeBufferPointer { text in
            ShellExecuteW(hwnd, nil, text.baseAddress, nil, nil, Int32(SW_SHOWNORMAL))
        }
        guard Int(bitPattern: result) > 32 else {
            self.showProviderEditorNotice(
                "Windows startup apps settings could not be opened. " +
                "Open Windows Settings > Apps > Startup manually. " +
                "CodexBar has not changed your startup registration.")
            return
        }
        // Shell acceptance does not establish page visibility or startup policy state.
    }

    private func openProviderPage(_ rawURL: String) {
        guard !self.quitInvoked, let owner = self.window else { return }
        guard rawURL.utf16.count <= 16_384, let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              !rawURL.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
        else {
            self.reportProviderOpenFailure(invalidAddress: true)
            return
        }
        let target = Array(rawURL.utf16) + [0]
        let result = target.withUnsafeBufferPointer { text in
            ShellExecuteW(owner, nil, text.baseAddress, nil, nil, Int32(SW_SHOWNORMAL))
        }
        let code = Int(bitPattern: result)
        if code <= 32 { self.reportProviderOpenFailure(invalidAddress: false, shellCode: code) }
        // Shell acceptance does not prove the destination loaded or authenticated.
    }

    private func reportProviderOpenFailure(invalidAddress: Bool, shellCode: Int? = nil) {
        // Provider dashboard paths, queries and fragments may contain account identifiers.
        // Report the failure category only; never print the attempted URL.
        let category = invalidAddress ? "invalid address" : "Windows shell rejected the request"
        let code = shellCode.map { " (shell result \($0))" } ?? ""
        FileHandle.standardError.write(Data("CodexBar: could not open provider page: \(category)\(code)\n".utf8))
        let guidance = invalidAddress
            ? "The provider page address is unavailable or is not a supported HTTP(S) address. " +
              "Open the provider website manually."
            : "Windows could not open the provider page" + code + ". " +
              "Check your default web browser in Windows Settings > Apps > Default apps, then try again. " +
              "You can also open the provider website manually."
        self.showMessage(guidance, caption: "Could not open provider page")
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
        if message == UINT(WM_INITMENUPOPUP), let menu = host.keyboardInitialMenu,
           wParam == WPARAM(UInt(bitPattern: menu)), let position = host.keyboardInitialPosition {
            host.keyboardInitialMenu = nil
            host.keyboardInitialPosition = nil
            // Highlight a navigation submenu only; do not inject keys or execute a command.
            let state = GetMenuState(menu, position, UINT(MF_BYPOSITION))
            if state != UINT.max, state & UINT(MF_DISABLED | MF_GRAYED | MF_SEPARATOR) == 0,
               GetSubMenu(menu, Int32(position)) != nil {
                _ = HiliteMenuItem(hwnd, menu, position, UINT(MF_BYPOSITION | MF_HILITE))
            }
            return 0
        }
        if message == UINT(WM_HOTKEY), wParam == WPARAM(host.activeHotkeyID) {
            guard host.menuHotkeyRegistered, !host.quitInvoked, !host.remoteEditorOpen,
                  case .idle = host.providerEditorPhase, case .idle = host.codexWebSettingsEditorPhase else { return 0 }
            if host.popupIsOpen { _ = EndMenu() }
            else { host.popup(keyboardInitiated: true) }
            return 0
        }
        if message == Self.pagePopupMessage {
            guard !host.quitInvoked, !host.remoteEditorOpen,
                  case .idle = host.providerEditorPhase, case .idle = host.codexWebSettingsEditorPhase
            else { return 0 }
            host.popup(notifyMenuOpen: false, preserveAnchor: true)
            return 0
        }
        if message == UINT(WM_TIMER), wParam == WPARAM(Self.cliSetupTimer) {
            host.drainCLISetup()
            return 0
        }
        if message == Self.wakeMessage {
            host.drainCLISetup()
            if host.remoteEditorOpen { return 0 }
            host.drainCredentialEdit()
            host.drainTokenAccountAdd()
            host.drainTokenAccountRename()
            host.drainTokenAccountSelection()
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
        if message == UINT(WM_QUERYENDSESSION) {
            // Do not veto logoff/shutdown or start irreversible cleanup during a cancellable query.
            return 1
        }
        if message == UINT(WM_ENDSESSION) {
            if wParam != 0 {
                host.mailboxLock.lock()
                host.systemSessionEnding = true
                host.mailboxLock.unlock()
                host.keyboardReturnTarget = nil
                if host.popupIsOpen { _ = EndMenu() }
                host.invokeQuit()
            }
            // FALSE means another application/user cancelled shutdown. Keep this app running.
            return 0
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
