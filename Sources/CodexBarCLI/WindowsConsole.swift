#if os(Windows)
import Foundation
import WinSDK

/// Small Windows console boundary used by the CLI without probing redirected streams.
enum WindowsConsole {
    private static let outputHandle = DWORD(bitPattern: Int32(-11))
    private static let inputHandle = DWORD(bitPattern: Int32(-10))
    private static let errorHandle = DWORD(bitPattern: Int32(-12))
    private static let enableProcessedOutput: DWORD = 0x0001
    private static let enableVirtualTerminalProcessing: DWORD = 0x0004

    static func supportsANSIOutput() -> Bool {
        guard let handle = standardHandle(outputHandle) else { return false }
        var mode: DWORD = 0
        guard GetConsoleMode(handle, &mode) != 0 else { return false }
        if (mode & (enableProcessedOutput | enableVirtualTerminalProcessing))
            == (enableProcessedOutput | enableVirtualTerminalProcessing)
        {
            return true
        }
        return SetConsoleMode(handle, mode | enableProcessedOutput | enableVirtualTerminalProcessing) != 0
    }

    static func isInteractiveTerminal() -> Bool {
        consoleMode(for: inputHandle) && consoleMode(for: errorHandle)
    }

    static func visibleWidth() -> Int? {
        guard let handle = standardHandle(outputHandle) else { return nil }
        var info = CONSOLE_SCREEN_BUFFER_INFO()
        guard GetConsoleScreenBufferInfo(handle, &info) != 0 else { return nil }
        let width = Int(info.srWindow.Right) - Int(info.srWindow.Left) + 1
        return width > 0 ? width : nil
    }

    private static func consoleMode(for handleID: DWORD) -> Bool {
        guard let handle = standardHandle(handleID) else { return false }
        var mode: DWORD = 0
        return GetConsoleMode(handle, &mode) != 0
    }

    private static func standardHandle(_ id: DWORD) -> HANDLE? {
        let handle = GetStdHandle(id)
        guard let handle, handle != INVALID_HANDLE_VALUE else { return nil }
        return handle
    }
}
#endif
