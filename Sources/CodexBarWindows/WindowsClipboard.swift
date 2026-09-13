#if os(Windows)
import CodexBarCore
import Foundation
import WinSDK

/// Writes only an explicitly selected, redacted menu snapshot. Never reads the clipboard.
enum WindowsClipboard {
    static func summary(rows: [String]) -> String? {
        guard !rows.isEmpty, rows.count <= 512 else { return nil }
        let text = rows.joined(separator: "\r\n")
        guard text.utf16.count <= 65_536 else { return nil }
        let redacted = LogRedactor.redact(text).replacingOccurrences(of: "\0", with: "")
        return redacted.isEmpty ? nil : redacted
    }

    /// A nil result means ownership was transferred to Windows. Errors are suitable for a dialog.
    static func write(_ text: String, owner: HWND) -> String? {
        guard !text.isEmpty, text.utf16.count <= 65_536 else { return "The summary is empty or too large to copy." }
        let units = Array(text.utf16) + [UInt16(0)]
        let byteCount = units.count * MemoryLayout<UInt16>.size
        guard let memory = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(byteCount)) else {
            return "Windows could not allocate clipboard memory."
        }
        var transferred = false
        defer { if !transferred { _ = GlobalFree(memory) } }
        guard let bytes = GlobalLock(memory) else { return "Windows could not prepare clipboard memory." }
        units.withUnsafeBytes { source in
            if let base = source.baseAddress { bytes.copyMemory(from: base, byteCount: byteCount) }
        }
        _ = GlobalUnlock(memory)
        guard OpenClipboard(owner) != 0 else { return "The clipboard is busy. Try copying again." }
        defer { _ = CloseClipboard() }
        guard EmptyClipboard() != 0 else { return "Windows could not replace the clipboard contents." }
        guard SetClipboardData(UINT(CF_UNICODETEXT), memory) != nil else {
            return "Windows could not publish the summary. The previous clipboard contents may have been cleared."
        }
        transferred = true
        return nil
    }
}
#endif
