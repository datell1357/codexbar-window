#if os(Windows)
import CodexBarCore
import Foundation
import WinSDK

/// Local recovery I/O shared by config-only and multi-store settings operations.
enum WindowsRecoveryFileAccess {
    enum Failure: Error { case invalidPath, missingInput, unavailableInput, invalidInput, unavailableOutput }

    static func explicitPath(_ text: String) throws -> URL {
        _ = try self.pathComponents(text)
        return URL(fileURLWithPath: text)
    }

    /// Reject UNC/device paths, streams, common DOS aliases, reserved names and traversal components.
    private static func pathComponents(_ path: String) throws -> (root: String, components: [String]) {
        let text = path.replacingOccurrences(of: "/", with: "\\")
        let units = Array(text.utf16)
        guard units.count >= 4, units.count < 32700,
              (65...90).contains(Int(units[0])) || (97...122).contains(Int(units[0])),
              units[1] == 58, units[2] == 92 else { throw Failure.invalidPath }
        let parts = text.dropFirst(3).split(separator: "\\", omittingEmptySubsequences: false).map(String.init)
        let reserved = Set(["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"] +
                           (1...9).flatMap { ["COM\($0)", "LPT\($0)"] } +
                           ["COM¹", "COM²", "COM³", "LPT¹", "LPT²", "LPT³"])
        for part in parts {
            guard !part.isEmpty, part != ".", part != "..", !part.hasSuffix("."), !part.hasSuffix(" "),
                  !part.unicodeScalars.contains(where: { $0.value < 32 || "<>:\"|?*".unicodeScalars.contains($0) }),
                  !reserved.contains(String(part.split(separator: ".").first ?? "").uppercased()) else {
                throw Failure.invalidPath
            }
        }
        return (String(text.prefix(3)), parts)
    }

    private static func withPinnedParents<T>(_ url: URL, body: () throws -> T) throws -> T {
        guard url.isFileURL else { throw Failure.invalidPath }
        let (root, components) = try self.pathComponents(url.path)
        let drive = root.withCString(encodedAs: UTF16.self) { GetDriveTypeW($0) }
        guard drive == UINT(DRIVE_FIXED) || drive == UINT(DRIVE_REMOVABLE) else { throw Failure.invalidPath }
        var handles: [HANDLE] = []
        defer { for handle in handles.reversed() { CloseHandle(handle) } }
        var path = root
        for component in [""] + Array(components.dropLast()) {
            if !component.isEmpty { path += (path.hasSuffix("\\") ? "" : "\\") + component }
            let opened = path.withCString(encodedAs: UTF16.self) {
                CreateFileW($0, DWORD(FILE_READ_ATTRIBUTES), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE), nil,
                            DWORD(OPEN_EXISTING), DWORD(FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT), nil)
            }
            guard let handle = opened, handle != INVALID_HANDLE_VALUE else {
                let code = GetLastError()
                if code == ERROR_FILE_NOT_FOUND || code == ERROR_PATH_NOT_FOUND { throw Failure.missingInput }
                throw Failure.invalidPath
            }
            handles.append(handle)
            var info = BY_HANDLE_FILE_INFORMATION()
            guard GetFileType(handle) == DWORD(FILE_TYPE_DISK), GetFileInformationByHandle(handle, &info) != 0,
                  info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0,
                  info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) == 0 else {
                throw Failure.invalidPath
            }
        }
        return try body()
    }

    static func read(_ url: URL, limit: Int, allowEmpty: Bool = false) throws -> Data {
        guard limit > 0, limit <= 64 * 1024 * 1024 else { throw Failure.invalidInput }
        return try self.withPinnedParents(url) {
            let opened = url.path.withCString(encodedAs: UTF16.self) {
                CreateFileW($0, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ), nil, DWORD(OPEN_EXISTING),
                            DWORD(FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT), nil)
            }
            guard let handle = opened, handle != INVALID_HANDLE_VALUE else {
                let code = GetLastError()
                if code == ERROR_FILE_NOT_FOUND || code == ERROR_PATH_NOT_FOUND { throw Failure.missingInput }
                throw Failure.unavailableInput
            }
            defer { CloseHandle(handle) }
            var info = BY_HANDLE_FILE_INFORMATION()
            guard GetFileType(handle) == DWORD(FILE_TYPE_DISK), GetFileInformationByHandle(handle, &info) != 0,
                  info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) == 0,
                  info.nNumberOfLinks == 1, info.nFileSizeHigh == 0,
                  (allowEmpty || info.nFileSizeLow > 0),
                  UInt64(info.nFileSizeLow) <= UInt64(limit) else { throw Failure.invalidInput }
            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                var count: DWORD = 0
                let requested = min(buffer.count, limit - result.count + 1)
                let succeeded = buffer.withUnsafeMutableBytes {
                    ReadFile(handle, $0.baseAddress, DWORD(requested), &count, nil)
                }
                guard succeeded != 0 else { throw Failure.unavailableInput }
                if count == 0 { break }
                guard Int(count) <= requested, Int(count) <= limit - result.count else { throw Failure.invalidInput }
                result.append(contentsOf: buffer.prefix(Int(count)))
            }
            guard result.count == Int(info.nFileSizeLow) else { throw Failure.invalidInput }
            return result
        }
    }

    static func publish(_ bytes: Data, to destination: URL) throws {
        try self.withPinnedParents(destination) {
            do { try WindowsCredentialFileWriter.writePrivate(bytes, to: destination, publication: .createNew) }
            catch { throw Failure.unavailableOutput }
        }
    }

    static func readIfPresent(_ url: URL, limit: Int, allowEmpty: Bool = false) throws -> Data? {
        do { return try self.read(url, limit: limit, allowEmpty: allowEmpty) }
        catch Failure.missingInput { return nil }
    }

    static func directoryNamesIfPresent(_ directory: URL, maximumEntries: Int) throws -> [String]? {
        do {
            return try self.withDirectory(directory) {
                try WindowsBoundedDirectoryNames.read(directory, maximumEntries: maximumEntries,
                    deadline: Date().addingTimeInterval(15))
            }
        } catch Failure.missingInput { return nil }
    }

    static func withDirectory<T>(_ directory: URL, body: () throws -> T) throws -> T {
        try self.withPinnedParents(directory.appendingPathComponent("recovery-root"), body: body)
    }

    /// Existing directories are pinned and checked; files/reparse points are not accepted as stores.
    static func withDirectoryCreatingIfMissing<T>(_ directory: URL, body: () throws -> T) throws -> T {
        try self.withPinnedParents(directory) {
            let created = directory.path.withCString(encodedAs: UTF16.self) { CreateDirectoryW($0, nil) }
            if created == 0, GetLastError() != DWORD(ERROR_ALREADY_EXISTS) { throw Failure.unavailableOutput }
            return try self.withDirectory(directory, body: body)
        }
    }

    /// All children are fixed by the caller, never interpreted as paths supplied by an archive.
    /// A failed operation preserves the new directory and any files already published inside it.
    static func withNewDirectory<T>(_ destination: URL, body: () throws -> T) throws -> T {
        try self.withPinnedParents(destination) {
            let created = destination.path.withCString(encodedAs: UTF16.self) { CreateDirectoryW($0, nil) }
            guard created != 0 else { throw Failure.unavailableOutput }
            return try self.withPinnedParents(destination.appendingPathComponent("recovery-root"), body: body)
        }
    }

}
#endif
