#if os(Windows)
import Foundation
import WinSDK

/// Read an existing regular file through one retained handle. Call inside WindowsLevelDBReadLock
/// when multiple files must describe the same database version.
enum WindowsLevelDBFileReader {
    enum Failure: Error { case unavailable, invalidFile, oversized, changed, timedOut }

    static func read(_ url: URL, maximumBytes: Int, deadline: Date) throws -> Data {
        try self.check(deadline)
        guard maximumBytes >= 0, maximumBytes <= 64 * 1024 * 1024,
              url.isFileURL, NSString(string: url.path).isAbsolutePath, !url.path.contains("\0") else {
            throw Failure.invalidFile
        }
        let path = Array(url.path.utf16) + [0]
        let opened = path.withUnsafeBufferPointer {
            CreateFileW($0.baseAddress, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ), nil,
                DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT), nil)
        }
        guard let handle = opened, handle != INVALID_HANDLE_VALUE else { throw Failure.unavailable }
        defer { CloseHandle(handle) }
        let before = try self.info(handle)
        let length = (UInt64(before.nFileSizeHigh) << 32) | UInt64(before.nFileSizeLow)
        guard length <= UInt64(maximumBytes) else { throw Failure.oversized }
        var data = Data()
        data.reserveCapacity(Int(length))
        while data.count < Int(length) {
            try self.check(deadline)
            var chunk = [UInt8](repeating: 0, count: min(65_536, Int(length) - data.count))
            var count: DWORD = 0
            let success = chunk.withUnsafeMutableBytes {
                ReadFile(handle, $0.baseAddress, DWORD($0.count), &count, nil)
            }
            guard success != 0, count > 0, Int(count) <= chunk.count else { throw Failure.changed }
            data.append(contentsOf: chunk.prefix(Int(count)))
        }
        // Confirm exact EOF, including for an empty file; never accept a prefix as a complete image.
        var extra: UInt8 = 0
        var extraCount: DWORD = 0
        guard ReadFile(handle, &extra, 1, &extraCount, nil) != 0, extraCount == 0 else { throw Failure.changed }
        let after = try self.info(handle)
        guard before.dwVolumeSerialNumber == after.dwVolumeSerialNumber,
              before.nFileIndexHigh == after.nFileIndexHigh, before.nFileIndexLow == after.nFileIndexLow,
              before.nFileSizeHigh == after.nFileSizeHigh, before.nFileSizeLow == after.nFileSizeLow,
              before.ftLastWriteTime.dwHighDateTime == after.ftLastWriteTime.dwHighDateTime,
              before.ftLastWriteTime.dwLowDateTime == after.ftLastWriteTime.dwLowDateTime else { throw Failure.changed }
        try self.check(deadline)
        return data
    }

    private static func info(_ handle: HANDLE) throws -> BY_HANDLE_FILE_INFORMATION {
        var result = BY_HANDLE_FILE_INFORMATION()
        guard GetFileType(handle) == DWORD(FILE_TYPE_DISK), GetFileInformationByHandle(handle, &result) != 0,
              result.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) == 0 else {
            throw Failure.invalidFile
        }
        return result
    }

    private static func check(_ deadline: Date) throws {
        try Task.checkCancellation()
        guard Date() < deadline else { throw Failure.timedOut }
    }
}
#endif
