#if os(Windows)
import Foundation
import WinSDK

/// A short-lived, non-activating warning surface for quota threshold crossings.
///
/// The controller is intended to be used from the tray host's UI thread.  It owns
/// the native window and replaces an existing presentation when a newer warning
/// arrives.
public final class WindowsQuotaWarningOverlay {
    private static let lifetimeMilliseconds: UINT = 4_500
    private static let className = "CodexBar.QuotaWarningOverlay"
    private static let width: Int32 = 440
    private static let height: Int32 = 112

    private var context: Context?
    private var nextGeneration: UINT_PTR = 0

    public init() {}

    public func show(title: String, body: String, owner: HWND) {
        self.dismiss()
        let generation = self.nextGeneration &+ 1
        self.nextGeneration = generation == 0 ? 1 : generation
        let context = Context(
            title: String(decoding: title.utf16.prefix(256), as: UTF16.self),
            body: String(decoding: body.utf16.prefix(768), as: UTF16.self),
            owner: owner,
            timerID: self.nextGeneration)
        self.context = context

        guard Self.registerClass() else {
            self.context = nil
            return
        }
        let instance = GetModuleHandleW(nil)
        let exStyle = DWORD(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TRANSPARENT)
        let style = DWORD(WS_POPUP | WS_BORDER)
        let className = Array(Self.className.utf16) + [0]
        let caption = Array("CodexBar quota warning".utf16) + [0]
        let created: HWND? = className.withUnsafeBufferPointer { classBuffer in
            caption.withUnsafeBufferPointer { captionBuffer in
                CreateWindowExW(
                    exStyle, classBuffer.baseAddress, captionBuffer.baseAddress, style,
                    0, 0, Self.width, Self.height, nil, nil, instance,
                    Unmanaged.passUnretained(context).toOpaque())
            }
        }
        guard let created else {
            self.context = nil
            return
        }
        context.window = created
        Self.center(created, owner: owner)
        guard SetLayeredWindowAttributes(created, 0, 255, DWORD(LWA_ALPHA)) != 0,
              SetTimer(created, context.timerID, Self.lifetimeMilliseconds, nil) != 0 else {
            DestroyWindow(created)
            self.context = nil
            return
        }
        SetWindowPos(created, HWND_TOPMOST, 0, 0, 0, 0,
                     UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW))
        ShowWindow(created, Int32(SW_SHOWNOACTIVATE))
        UpdateWindow(created)
    }

    public func dismiss() {
        guard let context, let window = context.window else {
            self.context = nil
            return
        }
        if context.timerID != 0 { KillTimer(window, context.timerID) }
        if IsWindow(window) != 0 { DestroyWindow(window) }
        self.context = nil
    }

    private final class Context {
        let title: String
        let body: String
        let owner: HWND
        let timerID: UINT_PTR
        var window: HWND?

        init(title: String, body: String, owner: HWND, timerID: UINT_PTR) {
            self.title = title
            self.body = body
            self.owner = owner
            self.timerID = timerID
        }
    }

    private static let windowProc: WNDPROC = { hwnd, message, wParam, lParam in
        guard let hwnd else { return 0 }
        if message == UINT(WM_NCCREATE),
           let create = UnsafeMutableRawPointer(bitPattern: UInt(lParam))?.assumingMemoryBound(to: CREATESTRUCTW.self),
           let parameters = create.pointee.lpCreateParams
        {
            SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), LONG_PTR(Int(bitPattern: parameters)))
        }
        let value = GetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA))
        guard value != 0,
              let raw = UnsafeRawPointer(bitPattern: UInt(value)) else {
            return DefWindowProcW(hwnd, message, wParam, lParam)
        }
        let context = Unmanaged<Context>.fromOpaque(raw).takeUnretainedValue()

        switch message {
        case UINT(WM_TIMER):
            guard UINT_PTR(wParam) == context.timerID else { return 0 }
            KillTimer(hwnd, context.timerID)
            DestroyWindow(hwnd)
            return 0
        case UINT(WM_MOUSEACTIVATE):
            return LRESULT(MA_NOACTIVATE)
        case UINT(WM_NCHITTEST):
            // Combined with WS_EX_TRANSPARENT, this prevents activation and forwards
            // hit testing to the underlying application window where possible.
            return LRESULT(HTTRANSPARENT)
        case UINT(WM_ERASEBKGND):
            return 1
        case UINT(WM_PAINT):
            Self.paint(hwnd, context: context)
            return 0
        case UINT(WM_NCDESTROY):
            if context.timerID != 0 { KillTimer(hwnd, context.timerID) }
            SetWindowLongPtrW(hwnd, Int32(GWLP_USERDATA), 0)
            context.window = nil
            return 0
        default:
            return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }

    private static func registerClass() -> Bool {
        var windowClass = WNDCLASSEXW()
        windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        windowClass.hInstance = GetModuleHandleW(nil)
        windowClass.lpfnWndProc = Self.windowProc
        windowClass.hCursor = LoadCursorW(nil, IDC_ARROW)
        windowClass.hbrBackground = nil
        let name = Array(Self.className.utf16) + [0]
        let result = name.withUnsafeBufferPointer { buffer in
            windowClass.lpszClassName = buffer.baseAddress
            return RegisterClassExW(&windowClass)
        }
        return result != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS
    }

    private static func center(_ hwnd: HWND, owner: HWND) {
        var area = RECT()
        let monitor = MonitorFromWindow(owner, UINT(MONITOR_DEFAULTTONEAREST))
        var info = MONITORINFO()
        info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        if monitor == nil || GetMonitorInfoW(monitor, &info) == 0 {
            SystemParametersInfoW(UINT(SPI_GETWORKAREA), 0, &area, 0)
        } else {
            area = info.rcWork
        }
        let x = area.left + max(0, (area.right - area.left - Self.width) / 2)
        let y = area.top + max(0, (area.bottom - area.top - Self.height) / 2)
        SetWindowPos(hwnd, nil, x, y, 0, 0, UINT(SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER))
    }

    private static func paint(_ hwnd: HWND, context: Context) {
        var paint = PAINTSTRUCT()
        guard let dc = BeginPaint(hwnd, &paint) else { return }
        let background = CreateSolidBrush(GetSysColor(COLOR_INFOBK))
        FillRect(dc, &paint.rcPaint, background)
        DeleteObject(background)

        SetBkMode(dc, Int32(TRANSPARENT))
        SetTextColor(dc, GetSysColor(COLOR_INFOTEXT))
        let font = GetStockObject(DEFAULT_GUI_FONT)
        let previous = SelectObject(dc, font)
        var titleRect = RECT(left: 16, top: 12, right: Self.width - 16, bottom: 38)
        drawText(context.title, dc: dc, rect: &titleRect, flags: UINT(DT_SINGLELINE | DT_END_ELLIPSIS))
        var bodyRect = RECT(left: 16, top: 40, right: Self.width - 16, bottom: Self.height - 12)
        drawText(context.body, dc: dc, rect: &bodyRect,
                 flags: UINT(DT_WORDBREAK | DT_END_ELLIPSIS | DT_NOPREFIX))
        SelectObject(dc, previous)
        EndPaint(hwnd, &paint)
    }

    private static func drawText(_ value: String, dc: HDC, rect: inout RECT, flags: UINT) {
        var text = Array(value.utf16) + [0]
        text.withUnsafeMutableBufferPointer { buffer in
            _ = DrawTextW(dc, buffer.baseAddress, -1, &rect, flags)
        }
    }
}
#endif
