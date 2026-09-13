#if os(Windows)
import Foundation
import WinSDK

enum WindowsSpendJSONSaveDialog {
    /// Nil means the selected file was saved or the user cancelled the save dialog.
    static func saveJSON(_ data: Data, filename: String, owner: HWND, hidePersonalInfo: Bool, isCurrent: @Sendable () -> Bool = { true }) -> String? {
        guard !data.isEmpty, data.count <= 16 * 1024 * 1024 else { return "The cost JSON is unavailable or too large." }
        guard isCurrent() else { return "The captured account or cost settings changed. Reopen cost export before saving." }
        guard hidePersonalInfo == WindowsUsagePresentationSettings.load().hidePersonalInfo else {
            return "Privacy settings changed. Choose Save cost export JSON again."
        }
        var path = [WCHAR](repeating: 0, count: 32768)
        for (index, unit) in filename.utf16.prefix(200).enumerated() { path[index] = unit }
        let filter = Array("JSON image (*.json)\0*.json\0\0".utf16)
        let ext = Array("json".utf16) + [WCHAR(0)]
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
            return CommDlgExtendedError() == 0 ? nil : "Windows could not open the JSON save dialog."
        }
        guard isCurrent() else { return "The captured account or cost settings changed. Reopen cost export before saving." }
        guard hidePersonalInfo == WindowsUsagePresentationSettings.load().hidePersonalInfo else {
            return "Privacy settings changed. The JSON was not saved. Choose Save cost export JSON again."
        }
        let selected = String(decoding: path.prefix { $0 != 0 }, as: UTF16.self)
        let url = URL(fileURLWithPath: selected)
        guard !selected.isEmpty, url.pathExtension.lowercased() == "json" else { return "Choose a filename ending in .json." }
        guard isCurrent() else { return "The captured data changed. The JSON was not saved." }
        do { try data.write(to: url, options: .atomic); return nil }
        catch { return "The cost JSON could not be saved to the selected file." }
    }
}
#endif
