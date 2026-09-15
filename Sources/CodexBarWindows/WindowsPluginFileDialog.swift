#if os(Windows)
import Foundation
import WinSDK

enum WindowsPluginFileDialog {
    enum Selection { case selected(URL), cancelled, failed }
    static func show(owner: HWND, titleKey: String = "plugin_installTitle", initialDirectory: URL? = nil) -> Selection {
        var path = [WCHAR](repeating: 0, count: 32768)
        let filter = Array("Plugins (*.js;*.ts)\0*.js;*.ts\0\0".utf16)
        let title = Array(WindowsStatusLocalization.text(titleKey).utf16) + [0]
        let initialPath = initialDirectory.map { Array($0.path.utf16) + [0] } ?? [0]
        var options = OPENFILENAMEW()
        options.lStructSize = DWORD(MemoryLayout<OPENFILENAMEW>.size)
        options.hwndOwner = owner
        options.nFilterIndex = 1
        options.Flags = DWORD(OFN_EXPLORER | OFN_NOCHANGEDIR | OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_DONTADDTORECENT)
        let accepted = path.withUnsafeMutableBufferPointer { buffer in
            filter.withUnsafeBufferPointer { filters in
                title.withUnsafeBufferPointer { caption in
                    options.lpstrFile = buffer.baseAddress
                    options.nMaxFile = DWORD(buffer.count)
                    options.lpstrFilter = filters.baseAddress
                    options.lpstrTitle = caption.baseAddress
                    return initialPath.withUnsafeBufferPointer { directory in
                        options.lpstrInitialDir = initialDirectory == nil ? nil : directory.baseAddress
                        return GetOpenFileNameW(&options)
                    }
                }
            }
        }
        if accepted == 0 { return CommDlgExtendedError() == 0 ? .cancelled : .failed }
        guard let end = path.firstIndex(of: 0), end > 0 else { return .failed }
        return .selected(URL(fileURLWithPath: String(decoding: path.prefix(end), as: UTF16.CodeUnit.self)))
    }
}
#endif
