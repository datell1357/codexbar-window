#if os(Windows)
import Foundation
import WinSDK
import ucrt

/// Use the same Windows volume/file-index identity for path checks and the parser's open handle.
/// Path absence is distinct from failure; an unreadable log must not become an empty snapshot.
enum OpenCodexWindowsLogIdentity {
    struct Snapshot {
        let fileIdentity: String
        let size: Int64
    }

    static func atURL(_ url: URL) throws -> Snapshot? {
        guard url.isFileURL, !url.path.contains("\0") else { throw CocoaError(.fileReadInvalidFileName) }
        let path = Array(url.path.utf16) + [UInt16(0)]
        let opened = path.withUnsafeBufferPointer {
            CreateFileW($0.baseAddress, DWORD(FILE_READ_ATTRIBUTES),
                        DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE), nil,
                        DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let opened, opened != INVALID_HANDLE_VALUE else {
            let code = GetLastError()
            if code == DWORD(ERROR_FILE_NOT_FOUND) || code == DWORD(ERROR_PATH_NOT_FOUND) { return nil }
            throw self.failure(code)
        }
        defer { CloseHandle(opened) }
        return try self.read(opened)
    }

    static func opened(_ file: FileHandle) throws -> Snapshot {
        guard file.fileDescriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
        let raw = _get_osfhandle(file.fileDescriptor)
        guard raw != -1, let handle = HANDLE(bitPattern: UInt(truncatingIfNeeded: raw)), handle != INVALID_HANDLE_VALUE else {
            throw CocoaError(.fileReadUnknown)
        }
        // FileHandle owns this handle; do not close it here.
        return try self.read(handle)
    }

    private static func read(_ handle: HANDLE) throws -> Snapshot {
        guard GetFileType(handle) == DWORD(FILE_TYPE_DISK) else { throw CocoaError(.fileReadUnsupportedScheme) }
        var information = BY_HANDLE_FILE_INFORMATION()
        guard GetFileInformationByHandle(handle, &information) != 0 else { throw self.failure(GetLastError()) }
        guard information.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) == 0 else { throw CocoaError(.fileReadUnknown) }
        let size = (UInt64(information.nFileSizeHigh) << 32) | UInt64(information.nFileSizeLow)
        guard let signedSize = Int64(exactly: size) else { throw CocoaError(.fileReadTooLarge) }
        let index = (UInt64(information.nFileIndexHigh) << 32) | UInt64(information.nFileIndexLow)
        return Snapshot(fileIdentity: "\(information.dwVolumeSerialNumber):\(index)", size: signedSize)
    }

    private static func failure(_ code: DWORD) -> NSError {
        NSError(domain: "NSWin32ErrorDomain", code: Int(code), userInfo: nil)
    }
}
#endif
