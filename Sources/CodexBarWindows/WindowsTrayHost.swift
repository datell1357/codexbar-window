#if os(Windows)
import Foundation
import WinSDK

/// Minimal Win32 tray host.  The host owns every HWND/HMENU on the thread running
/// `run`; callers may publish rows from any thread through `postRows`.
public final class WindowsTrayHost: @unchecked Sendable {
    /// Callbacks run on the tray UI thread and must only enqueue work; provider
    /// fetches or other blocking operations should be scheduled asynchronously.
    public typealias RefreshHandler = @Sendable () -> Void
    public typealias QuitHandler = @Sendable () -> Void

    private static let wakeMessage = UINT(WM_APP) + 1
    private static let refreshCommand = UINT_PTR(0x7001)
    private static let quitCommand = UINT_PTR(0x7002)
    private static let className = Array("CodexBar.WindowsTrayHost".utf16) + [0]
    private static let taskbarCreated: UINT = {
        "TaskbarCreated".withCString(encodedAs: UTF16.self) { RegisterWindowMessageW($0) }
    }()

    private let onRefresh: RefreshHandler
    private let onQuit: QuitHandler
    private let mailboxLock = NSLock()
    private var mailboxRows: [String] = []
    private var window: HWND?
    private var runReserved = false
    private var iconInstalled = false
    private var quitInvoked = false

    public init(onRefresh: @escaping RefreshHandler, onQuit: @escaping QuitHandler) {
        self.onRefresh = onRefresh
        self.onQuit = onQuit
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
        if message == UINT(WM_CLOSE) { host.invokeQuit(); DestroyWindow(hwnd); return 0 }
        if message == UINT(WM_COMMAND) {
            switch UINT_PTR(wParam & 0xffff) {
            case Self.refreshCommand: host.onRefresh()
            case Self.quitCommand: host.invokeQuit()
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
