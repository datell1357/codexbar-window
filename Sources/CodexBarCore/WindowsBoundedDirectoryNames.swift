#if os(Windows)
import Foundation
import WinSDK

/// Enumerates one directory without recursion; failures never return a partial listing.
enum WindowsBoundedDirectoryNames {
    enum Failure: Error { case unavailable, oversized, invalidPath, timedOut }

    static func read(_ directory: URL, maximumEntries: Int = 100_000, deadline: Date) throws -> [String] {
        try self.check(deadline)
        let path = directory.path
        guard directory.isFileURL, NSString(string: path).isAbsolutePath,
              path.utf16.count <= 32700, !path.contains("\0"),
              !path.contains("*"), !path.contains("?"),
              maximumEntries > 0, maximumEntries <= 100_000 else { throw Failure.invalidPath }
        let pattern = Array((path + (path.hasSuffix("\\") || path.hasSuffix("/") ? "" : "\\") + "*").utf16) + [0]
        var data = WIN32_FIND_DATAW()
        let opened = pattern.withUnsafeBufferPointer { FindFirstFileW($0.baseAddress, &data) }
        guard let handle = opened, handle != INVALID_HANDLE_VALUE else {
            if GetLastError() == DWORD(ERROR_FILE_NOT_FOUND) { return [] }
            throw Failure.unavailable
        }
        defer { FindClose(handle) }
        var names: [String] = []
        var bytesRemaining = 16 * 1024 * 1024
        while true {
            try self.check(deadline)
            let name = withUnsafeBytes(of: data.cFileName) { raw in
                String(decoding: raw.bindMemory(to: UInt16.self).prefix(while: { $0 != 0 }), as: UTF16.self)
            }
            if name != ".", name != ".." {
                guard names.count < maximumEntries, name.utf8.count <= bytesRemaining else { throw Failure.oversized }
                bytesRemaining -= name.utf8.count
                names.append(name)
            }
            if FindNextFileW(handle, &data) == 0 {
                guard GetLastError() == DWORD(ERROR_NO_MORE_FILES) else { throw Failure.unavailable }
                break
            }
        }
        try self.check(deadline)
        return names
    }

    private static func check(_ deadline: Date) throws {
        try Task.checkCancellation()
        guard Date() < deadline else { throw Failure.timedOut }
    }
}
#endif
