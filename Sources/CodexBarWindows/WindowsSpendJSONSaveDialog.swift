#if os(Windows)
import Foundation
import WinSDK

enum WindowsSpendJSONSaveDialog {
    /// Nil means the selected file was saved or the user cancelled the save dialog.
    static func saveJSON(_ data: Data, filename: String, owner: HWND, hidePersonalInfo: Bool, isCurrent: @Sendable () -> Bool = { true }) -> String? {
        Self.save(data, filename: filename, owner: owner, hidePersonalInfo: hidePersonalInfo, fileExtension: "json", isCurrent: isCurrent)
    }
    static func saveCSV(_ data: Data, filename: String, owner: HWND, hidePersonalInfo: Bool, isCurrent: @Sendable () -> Bool) -> String? {
        Self.save(data, filename: filename, owner: owner, hidePersonalInfo: hidePersonalInfo, fileExtension: "csv", isCurrent: isCurrent)
    }
    private static func save(_ data: Data, filename: String, owner: HWND, hidePersonalInfo: Bool,
                             fileExtension: String, isCurrent: @Sendable () -> Bool) -> String? {
        guard !data.isEmpty, data.count <= 16 * 1024 * 1024 else { return "The export is unavailable or too large." }
        guard isCurrent() else { return "The captured account or cost settings changed. Reopen cost export before saving." }
        guard hidePersonalInfo == WindowsUsagePresentationSettings.load().hidePersonalInfo else {
            return "Privacy settings changed. Choose the export action again."
        }
        var path = [WCHAR](repeating: 0, count: 32768)
        for (index, unit) in filename.utf16.prefix(200).enumerated() { path[index] = unit }
        let filter = Array("\(fileExtension.uppercased()) file (*.\(fileExtension))\0*.\(fileExtension)\0\0".utf16)
        let ext = Array(fileExtension.utf16) + [WCHAR(0)]
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
            return CommDlgExtendedError() == 0 ? nil : "Windows could not open the export save dialog."
        }
        guard isCurrent() else { return "The captured account or cost settings changed. Reopen cost export before saving." }
        guard hidePersonalInfo == WindowsUsagePresentationSettings.load().hidePersonalInfo else {
            return "Privacy settings changed. The file was not saved. Choose the export action again."
        }
        let selected = String(decoding: path.prefix { $0 != 0 }, as: UTF16.self)
        let url = URL(fileURLWithPath: selected)
        guard !selected.isEmpty, url.pathExtension.lowercased() == fileExtension else { return "Choose a filename ending in .\(fileExtension)." }
        guard isCurrent() else { return "The captured data changed. The file was not saved." }
        do { try data.write(to: url, options: .atomic); return nil }
        catch { return "The export could not be saved to the selected file." }
    }
}
#endif
