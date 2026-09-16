#if os(Windows)
import Foundation
import WinSDK

/// A live, unsorted Win32 enumeration. Its logical offset is valid only while this object lives.
/// The caller serializes access, bounds visits per page and rechecks the directory snapshot.
final class WindowsCostDirectoryCursor {
    struct Entry {
        let name: String
        let isDirectory: Bool
    }

    let snapshot: WindowsCostFileMetadata.Snapshot
    private var handle: HANDLE?
    private var first: WIN32_FIND_DATAW?
    var logicalOffset: Int64 = 0

    init(directoryURL: URL, snapshot: WindowsCostFileMetadata.Snapshot) throws {
        guard snapshot.isDirectory else { throw CocoaError(.fileReadUnknown) }
        self.snapshot = snapshot
        let path = try WindowsCostFileMetadata.path(directoryURL)
        let separator = path.hasSuffix("/") || path.hasSuffix("\\") ? "" : "\\"
        let pattern = Array((path + separator + "*").utf16) + [UInt16(0)]
        var data = WIN32_FIND_DATAW()
        let opened = pattern.withUnsafeBufferPointer { FindFirstFileW($0.baseAddress, &data) }
        guard let opened, opened != INVALID_HANDLE_VALUE else {
            let code = GetLastError()
            // The caller has observed an existing directory and must re-observe it after this page.
            if code == DWORD(ERROR_FILE_NOT_FOUND) { return }
            throw WindowsCostFileMetadata.failure(code)
        }
        self.handle = opened
        self.first = data
    }

    deinit { if let handle { FindClose(handle) } }

    func next() throws -> Entry? {
        try Task.checkCancellation()
        let data: WIN32_FIND_DATAW
        if let first = self.first {
            data = first
            self.first = nil
        } else {
            guard let handle = self.handle else { return nil }
            var found = WIN32_FIND_DATAW()
            guard FindNextFileW(handle, &found) != 0 else {
                let code = GetLastError()
                FindClose(handle)
                self.handle = nil
                if code == DWORD(ERROR_NO_MORE_FILES) { return nil }
                throw WindowsCostFileMetadata.failure(code)
            }
            data = found
        }
        let name = withUnsafeBytes(of: data.cFileName) { raw in
            String(decoding: raw.bindMemory(to: UInt16.self).prefix(while: { $0 != 0 }), as: UTF16.self)
        }
        return Entry(name: name, isDirectory: data.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0)
    }
}
#endif
