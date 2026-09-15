#if os(Windows)
import Foundation
import WinSDK

/// A read-only snapshot of the user's high-contrast colors. Never changes system settings.
struct WindowsWidgetChartAccessibility: Sendable {
    enum Failure: Error, Sendable { case windows(UInt32) }
    let background: [UInt8]
    let foreground: [UInt8]

    static func capture() throws -> Self? {
        var setting = HIGHCONTRASTW()
        setting.cbSize = UINT(MemoryLayout<HIGHCONTRASTW>.size)
        let succeeded = SystemParametersInfoW(UINT(SPI_GETHIGHCONTRAST), setting.cbSize, &setting, 0)
        let error = succeeded ? DWORD(0) : GetLastError()
        defer {
            if let scheme = setting.lpszDefaultScheme { _ = LocalFree(UnsafeMutableRawPointer(scheme)) }
        }
        guard succeeded else { throw Failure.windows(error) }
        guard setting.dwFlags & DWORD(HCF_HIGHCONTRASTON) != 0 else { return nil }
        func rgb(_ color: DWORD) -> [UInt8] {
            [UInt8(truncatingIfNeeded: color), UInt8(truncatingIfNeeded: color >> 8),
             UInt8(truncatingIfNeeded: color >> 16)]
        }
        return Self(background: rgb(GetSysColor(Int32(COLOR_WINDOW))),
            foreground: rgb(GetSysColor(Int32(COLOR_WINDOWTEXT))))
    }
}
#endif
