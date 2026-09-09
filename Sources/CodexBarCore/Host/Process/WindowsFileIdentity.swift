#if os(Windows)
import Foundation
import WinSDK

/// Native identity and metadata for a Windows file, collected from one open handle.
///
/// The volume serial number and file index form the stable identity used by callers;
/// size and last-write time are read from that same handle so a replacement cannot
/// produce a mixed metadata snapshot.
package struct WindowsFileIdentitySnapshot: Hashable, Sendable {
    package let volumeSerialNumber: UInt32
    package let fileIndex: UInt64
    package let fileSize: UInt64
    package let lastWriteTime: Date

    package init(
        volumeSerialNumber: UInt32,
        fileIndex: UInt64,
        fileSize: UInt64,
        lastWriteTime: Date)
    {
        self.volumeSerialNumber = volumeSerialNumber
        self.fileIndex = fileIndex
        self.fileSize = fileSize
        self.lastWriteTime = lastWriteTime
    }
}

package enum WindowsFileIdentity {
    /// Reads the file identity and metadata using `CreateFileW` and
    /// `GetFileInformationByHandle`. Returns `nil` when the path cannot be opened
    /// or the handle query fails.
    package static func snapshot(atPath path: String) -> WindowsFileIdentitySnapshot? {
        guard !path.contains("\0") else { return nil }

        let utf16Path = Array(path.utf16) + [0]
        let handle: HANDLE? = utf16Path.withUnsafeBufferPointer { buffer in
            CreateFileW(
                buffer.baseAddress,
                DWORD(FILE_READ_ATTRIBUTES),
                DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE),
                nil,
                DWORD(OPEN_EXISTING),
                DWORD(FILE_ATTRIBUTE_NORMAL),
                nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { return nil }
        defer { CloseHandle(handle) }

        var information = BY_HANDLE_FILE_INFORMATION()
        guard GetFileInformationByHandle(handle, &information) != 0 else { return nil }

        let fileIndex = (UInt64(information.nFileIndexHigh) << 32) | UInt64(information.nFileIndexLow)
        let fileSize = (UInt64(information.nFileSizeHigh) << 32) | UInt64(information.nFileSizeLow)
        let lastWriteTicks = (UInt64(information.ftLastWriteTime.dwHighDateTime) << 32)
            | UInt64(information.ftLastWriteTime.dwLowDateTime)
        let lastWriteTime = Date(
            timeIntervalSince1970: (Double(lastWriteTicks) / 10_000_000) - 11_644_473_600)

        return WindowsFileIdentitySnapshot(
            volumeSerialNumber: information.dwVolumeSerialNumber,
            fileIndex: fileIndex,
            fileSize: fileSize,
            lastWriteTime: lastWriteTime)
    }
}
#endif
