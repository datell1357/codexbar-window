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

    /// Publishes both registered PNG and the standard DIB representation from one render.
    /// Allocate and fill both buffers before touching the existing clipboard contents.
    static func writeImage(png: Data, dib: Data, owner: HWND) -> String? {
        guard !png.isEmpty, !dib.isEmpty, png.count <= 16 * 1024 * 1024, dib.count <= 16 * 1024 * 1024 else {
            return "The share image is empty or too large to copy."
        }
        let format = "PNG".withCString(encodedAs: UTF16.self) { RegisterClipboardFormatW($0) }
        guard format != 0 else { return "Windows could not register the PNG clipboard format." }
        func allocate(_ data: Data) -> HGLOBAL? {
            guard let handle = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(data.count)) else { return nil }
            guard let bytes = GlobalLock(handle) else { _ = GlobalFree(handle); return nil }
            data.withUnsafeBytes { source in
                if let base = source.baseAddress { bytes.copyMemory(from: base, byteCount: data.count) }
            }
            _ = GlobalUnlock(handle)
            return handle
        }
        guard let pngMemory = allocate(png) else { return "Windows could not prepare the PNG clipboard image." }
        var pngTransferred = false
        defer { if !pngTransferred { _ = GlobalFree(pngMemory) } }
        guard let dibMemory = allocate(dib) else { return "Windows could not prepare the bitmap clipboard image." }
        var dibTransferred = false
        defer { if !dibTransferred { _ = GlobalFree(dibMemory) } }
        guard OpenClipboard(owner) != 0 else { return "The clipboard is busy. Try copying the image again." }
        defer { _ = CloseClipboard() }
        guard EmptyClipboard() != 0 else { return "Windows could not replace the clipboard contents." }
        guard SetClipboardData(format, pngMemory) != nil else {
            return "Windows could not copy the image. The previous clipboard contents may have been cleared."
        }
        pngTransferred = true
        guard SetClipboardData(UINT(CF_DIB), dibMemory) != nil else {
            return "Only the PNG image was copied. Bitmap-only applications may not be able to paste it."
        }
        dibTransferred = true
        return nil
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
