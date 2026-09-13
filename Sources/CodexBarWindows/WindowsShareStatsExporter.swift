#if os(Windows)
import Foundation
import WinSDK

enum WindowsShareStatsExporter {
    /// Nil means the selected file was saved or the user cancelled the save dialog.
    static func savePNG(_ data: Data, filename: String, owner: HWND, hidePersonalInfo: Bool) -> String? {
        guard !data.isEmpty, data.count <= 16 * 1024 * 1024 else { return "The share image is unavailable or too large." }
        guard hidePersonalInfo == WindowsUsagePresentationSettings.load().hidePersonalInfo else {
            return "Privacy settings changed. Choose Save Share Stats PNG again."
        }
        var path = [WCHAR](repeating: 0, count: 32768)
        for (index, unit) in filename.utf16.prefix(200).enumerated() { path[index] = unit }
        let filter = Array("PNG image (*.png)\0*.png\0\0".utf16)
        let ext = Array("png".utf16) + [WCHAR(0)]
        var options = OPENFILENAMEW()
        options.lStructSize = DWORD(MemoryLayout<OPENFILENAMEW>.size)
        options.hwndOwner = owner
        options.nFilterIndex = 1
        options.Flags = DWORD(OFN_EXPLORER | OFN_NOCHANGEDIR | OFN_PATHMUSTEXIST | OFN_OVERWRITEPROMPT | OFN_NOREADONLYRETURN)
        let accepted = path.withUnsafeMutableBufferPointer { buffer in
            filter.withUnsafeBufferPointer { filterBuffer in
                ext.withUnsafeBufferPointer { extensionBuffer in
                    options.lpstrFile = buffer.baseAddress
                    options.nMaxFile = DWORD(buffer.count)
                    options.lpstrFilter = filterBuffer.baseAddress
                    options.lpstrDefExt = extensionBuffer.baseAddress
                    return GetSaveFileNameW(&options)
                }
            }
        }
        guard accepted != 0 else {
            return CommDlgExtendedError() == 0 ? nil : "Windows could not open the image save dialog."
        }
        guard hidePersonalInfo == WindowsUsagePresentationSettings.load().hidePersonalInfo else {
            return "Privacy settings changed. The image was not saved. Choose Save Share Stats PNG again."
        }
        let selected = String(decoding: path.prefix { $0 != 0 }, as: UTF16.self)
        let url = URL(fileURLWithPath: selected)
        guard !selected.isEmpty, url.pathExtension.lowercased() == "png" else { return "Choose a filename ending in .png." }
        do { try data.write(to: url, options: .atomic); return nil }
        catch { return "The share image could not be saved to the selected file." }
    }
}
#endif
