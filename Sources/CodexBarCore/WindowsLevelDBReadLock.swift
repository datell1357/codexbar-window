#if os(Windows)
import Foundation
import WinSDK

/// Holds an existing database LOCK for a synchronous read operation. Does not create or write files.
enum WindowsLevelDBReadLock {
    enum Failure: LocalizedError {
        case busy, unavailable, invalidFile, unlockFailed
        var errorDescription: String? {
            switch self {
            case .busy: "The browser storage is in use. Close the browser normally and retry importing."
            case .unavailable: "The browser storage lock could not be opened. Check profile access and retry."
            case .invalidFile: "The browser storage lock is not a supported regular file."
            case .unlockFailed: "The browser storage read could not release its lock normally. Retry the import."
            }
        }
    }

    static func withLock<T>(directory: URL, operation: () throws -> T) throws -> T {
        try Task.checkCancellation()
        guard directory.isFileURL, NSString(string: directory.path).isAbsolutePath,
              !directory.path.contains("\0") else { throw Failure.invalidFile }
        let path = Array(directory.appendingPathComponent("LOCK").path.utf16) + [0]
        let opened = path.withUnsafeBufferPointer {
            CreateFileW($0.baseAddress, DWORD(GENERIC_READ), 0, nil, DWORD(OPEN_EXISTING),
                DWORD(FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT), nil)
        }
        guard let handle = opened, handle != INVALID_HANDLE_VALUE else {
            let code = GetLastError()
            if code == DWORD(ERROR_SHARING_VIOLATION) || code == DWORD(ERROR_LOCK_VIOLATION) { throw Failure.busy }
            throw Failure.unavailable
        }
        var locked = false
        defer {
            if locked { _ = UnlockFile(handle, 0, 0, DWORD.max, DWORD.max) }
            CloseHandle(handle)
        }
        var info = BY_HANDLE_FILE_INFORMATION()
        guard GetFileType(handle) == DWORD(FILE_TYPE_DISK), GetFileInformationByHandle(handle, &info) != 0,
              info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) == 0 else {
            throw Failure.invalidFile
        }
        guard LockFile(handle, 0, 0, DWORD.max, DWORD.max) != 0 else {
            let code = GetLastError()
            if code == DWORD(ERROR_LOCK_VIOLATION) || code == DWORD(ERROR_SHARING_VIOLATION) { throw Failure.busy }
            throw Failure.unavailable
        }
        locked = true
        try Task.checkCancellation()
        let result = try operation()
        try Task.checkCancellation()
        guard UnlockFile(handle, 0, 0, DWORD.max, DWORD.max) != 0 else { throw Failure.unlockFailed }
        locked = false
        return result
    }
}
#endif
