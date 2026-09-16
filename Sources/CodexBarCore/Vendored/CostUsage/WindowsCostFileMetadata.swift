#if os(Windows)
import Foundation
import WinSDK
import ucrt

/// Cost-log identity is scoped to its actual volume, including files reached through junctions.
/// Missing paths are distinct from unreadable paths; callers choose whether absence is acceptable.
enum WindowsCostFileMetadata {
    struct Snapshot: Equatable, Sendable {
        let fileID: String
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let isDirectory: Bool

        var mtimeUnixMs: Int64 { self.modifiedSeconds * 1000 + self.modifiedNanoseconds / 1_000_000 }
    }

    static func path(_ url: URL) throws -> String {
        let path = url.path
        guard url.isFileURL, NSString(string: path).isAbsolutePath,
              !path.contains("\0"), !path.contains("*"), !path.contains("?"),
              path.utf16.count <= 32700
        else { throw CocoaError(.fileReadInvalidFileName) }
        return path
    }

    static func atURL(_ url: URL) throws -> Snapshot? {
        let path = Array(try self.path(url).utf16) + [UInt16(0)]
        let opened = path.withUnsafeBufferPointer {
            CreateFileW($0.baseAddress, DWORD(FILE_READ_ATTRIBUTES),
                        DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE), nil,
                        DWORD(OPEN_EXISTING), DWORD(FILE_FLAG_BACKUP_SEMANTICS), nil)
        }
        guard let opened, opened != INVALID_HANDLE_VALUE else {
            let code = GetLastError()
            if code == DWORD(ERROR_FILE_NOT_FOUND) || code == DWORD(ERROR_PATH_NOT_FOUND) { return nil }
            throw self.failure(code)
        }
        defer { CloseHandle(opened) }
        return try self.read(opened)
    }

    static func requiredFile(at url: URL) throws -> Snapshot {
        guard let snapshot = try self.atURL(url) else { throw CocoaError(.fileReadNoSuchFile) }
        guard !snapshot.isDirectory else { throw CocoaError(.fileReadUnknown) }
        return snapshot
    }

    static func opened(_ file: FileHandle) throws -> Snapshot {
        guard file.fileDescriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
        let raw = _get_osfhandle(file.fileDescriptor)
        guard raw != -1, let handle = HANDLE(bitPattern: UInt(truncatingIfNeeded: raw)),
              handle != INVALID_HANDLE_VALUE else { throw CocoaError(.fileReadUnknown) }
        // FileHandle owns the handle. Metadata reads must not close it or seek the stream.
        let snapshot = try self.read(handle)
        guard !snapshot.isDirectory else { throw CocoaError(.fileReadUnknown) }
        return snapshot
    }

    static func openedNativeFile(_ handle: HANDLE) throws -> Snapshot {
        let snapshot = try self.read(handle)
        guard !snapshot.isDirectory else { throw CocoaError(.fileReadUnknown) }
        return snapshot
    }

    private static func read(_ handle: HANDLE) throws -> Snapshot {
        guard GetFileType(handle) == DWORD(FILE_TYPE_DISK) else { throw CocoaError(.fileReadUnsupportedScheme) }
        var information = BY_HANDLE_FILE_INFORMATION()
        guard GetFileInformationByHandle(handle, &information) != 0 else { throw self.failure(GetLastError()) }
        let unsignedSize = (UInt64(information.nFileSizeHigh) << 32) | UInt64(information.nFileSizeLow)
        guard let size = Int64(exactly: unsignedSize) else { throw CocoaError(.fileReadTooLarge) }
        let ticks = (UInt64(information.ftLastWriteTime.dwHighDateTime) << 32)
            | UInt64(information.ftLastWriteTime.dwLowDateTime)
        return try Snapshot(
            fileID: self.identity(handle, information: information),
            size: size,
            modifiedSeconds: Int64(ticks / 10_000_000) - 11_644_473_600,
            modifiedNanoseconds: Int64(ticks % 10_000_000) * 100,
            isDirectory: information.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0)
    }

    private static func identity(_ handle: HANDLE, information: BY_HANDLE_FILE_INFORMATION) throws -> String {
        var identity = FILE_ID_INFO()
        if GetFileInformationByHandleEx(
            handle, FILE_INFO_BY_HANDLE_CLASS.FileIdInfo, &identity, DWORD(MemoryLayout<FILE_ID_INFO>.size)) != 0
        {
            let bytes = withUnsafeBytes(of: identity.FileId.Identifier) { Array($0) }
            guard bytes.contains(where: { $0 != 0 }) else { throw self.failure(DWORD(ERROR_NOT_SUPPORTED)) }
            let hex = bytes.map { String(format: "%02x", $0) }.joined()
            return "win128:\(identity.VolumeSerialNumber):\(hex)"
        }
        let code = GetLastError()
        // Older file-system drivers can expose only the legacy volume/index pair. Never fall
        // back for an access/I/O error, and never conflate the two identity representations.
        guard code == DWORD(ERROR_INVALID_PARAMETER) || code == DWORD(ERROR_NOT_SUPPORTED)
            || code == DWORD(ERROR_INVALID_FUNCTION) else { throw self.failure(code) }
        let index = (UInt64(information.nFileIndexHigh) << 32) | UInt64(information.nFileIndexLow)
        guard index != 0 else { throw self.failure(DWORD(ERROR_NOT_SUPPORTED)) }
        return "win64:\(information.dwVolumeSerialNumber):\(index)"
    }

    static func failure(_ code: DWORD) -> NSError {
        // Paths can contain account/project names; keep them out of propagated native errors.
        NSError(domain: "NSWin32ErrorDomain", code: Int(code), userInfo: nil)
    }
}
#endif
