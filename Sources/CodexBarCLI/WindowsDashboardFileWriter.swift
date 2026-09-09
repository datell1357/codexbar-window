#if os(Windows)
import Foundation
import WinSDK

/// Atomically publishes dashboard JSON on Windows while inheriting the
/// destination directory's ACL. The staged file is created with CREATE_NEW,
/// written completely, flushed and closed, then replaced in the same directory.
enum WindowsDashboardFileWriter {
    static func write(_ data: Data, toPath path: String) throws {
        let destination = URL(fileURLWithPath: path)
        let directory = destination.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw NSError(
                domain: "Win32",
                code: Int(ERROR_PATH_NOT_FOUND),
                userInfo: [
                    NSFilePathErrorKey: path,
                    NSLocalizedDescriptionKey:
                        "--output directory does not exist: \(directory.path) (parent directories are not created)",
                ])
        }

        let staged = directory.appendingPathComponent(
            ".\(destination.lastPathComponent).codexbar-dashboard-\(UUID().uuidString)")
        let handle = try openNewFile(staged)
        var closeAttempted = false
        var published = false
        do {
            try writeAll(data, to: handle, path: staged.path)
            guard FlushFileBuffers(handle) != 0 else { throw win32Error(path: staged.path) }
            let closeResult = CloseHandle(handle)
            closeAttempted = true
            guard closeResult != 0 else { throw win32Error(path: staged.path) }
            try replace(staged, with: destination)
            published = true
        } catch {
            if !closeAttempted {
                _ = CloseHandle(handle)
                closeAttempted = true
            }
            if !published { try? FileManager.default.removeItem(at: staged) }
            throw error
        }
    }

    private static func openNewFile(_ url: URL) throws -> HANDLE {
        let path = Array(url.path.utf16) + [0]
        let handle: HANDLE? = path.withUnsafeBufferPointer {
            CreateFileW(
                $0.baseAddress,
                DWORD(GENERIC_WRITE),
                0,
                nil,
                DWORD(CREATE_NEW),
                DWORD(FILE_ATTRIBUTE_NORMAL),
                nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else {
            throw win32Error(path: url.path)
        }
        return handle
    }

    private static func writeAll(_ data: Data, to handle: HANDLE, path: String) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                var written: DWORD = 0
                let remaining = min(data.count - offset, Int(DWORD.max))
                let ok = WriteFile(handle, base.advanced(by: offset), DWORD(remaining), &written, nil)
                guard ok != 0 else { throw win32Error(path: path) }
                guard written > 0 else {
                    throw win32Error(path: path, code: DWORD(ERROR_WRITE_FAULT))
                }
                offset += Int(written)
            }
        }
    }

    private static func replace(_ staged: URL, with destination: URL) throws {
        let source = Array(staged.path.utf16) + [0]
        let target = Array(destination.path.utf16) + [0]
        let ok = source.withUnsafeBufferPointer { sourceBuffer in
            target.withUnsafeBufferPointer { targetBuffer in
                MoveFileExW(
                    sourceBuffer.baseAddress,
                    targetBuffer.baseAddress,
                    DWORD(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
            }
        }
        guard ok != 0 else { throw win32Error(path: destination.path) }
    }

    private static func win32Error(path: String, code: DWORD = GetLastError()) -> NSError {
        NSError(domain: "Win32", code: Int(code), userInfo: [NSFilePathErrorKey: path])
    }
}
#endif
