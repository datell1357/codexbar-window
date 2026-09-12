#if os(Windows)
import Foundation
import WinSDK

/// The picker selects a folder only; selecting it does not enable metadata correlation.
enum WindowsSessionMetadataFolderPicker {
    static func choose(owner: HWND, title: String) -> String? {
        let initialized = CoInitializeEx(nil, DWORD(0x2) /* COINIT_APARTMENTTHREADED */)
        guard initialized >= 0 else { return nil }
        defer { CoUninitialize() }
        var display = [UInt16](repeating: 0, count: 260)
        var info = BROWSEINFOW()
        info.hwndOwner = owner
        info.ulFlags = UINT(BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE | BIF_NONEWFOLDERBUTTON)
        let item = title.withCString(encodedAs: UTF16.self) { caption in
            display.withUnsafeMutableBufferPointer { name in
                info.lpszTitle = caption; info.pszDisplayName = name.baseAddress
                return SHBrowseForFolderW(&info)
            }
        }
        guard let item else { return nil }
        defer { CoTaskMemFree(UnsafeMutableRawPointer(item)) }
        var path = [UInt16](repeating: 0, count: 260)
        guard SHGetPathFromIDListW(item, &path) != 0 else { return nil }
        return String(decoding: path.prefix(while: { $0 != 0 }), as: UTF16.self)
    }
}
#endif
