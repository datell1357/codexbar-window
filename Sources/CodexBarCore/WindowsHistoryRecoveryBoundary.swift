#if os(Windows)
import Foundation
import WinSDK

/// Persistent import provenance. Existence changes ownership policy; unreadable metadata must never
/// be treated as an ordinary local history file. The original digest is provenance, not a rolling hash.
package enum WindowsHistoryRecoveryBoundary {
    package enum Failure: Error { case unavailable, invalidData }
    package struct Record: Codable, Equatable, Sendable {
        package let version: Int
        package let archiveID: UUID
        package let entryID: UUID
        package let originalSHA256: String
        package let filename: String
        package let ownershipPolicy: String

        package init(archiveID: UUID, entryID: UUID, originalSHA256: String, filename: String) {
            self.version = 1
            self.archiveID = archiveID
            self.entryID = entryID
            self.originalSHA256 = originalSHA256
            self.filename = filename
            self.ownershipPolicy = "EXACT_STORED_ACCOUNT_KEYS_ONLY"
        }

        package func encoded() throws -> Data {
            try WindowsHistoryRecoveryBoundary.validate(self, filename: self.filename)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(self)
        }
    }

    package static let maximumBytes = 8192
    package static let extensionName = "recovery-boundary.json"
    package static func url(for file: URL) -> URL { file.appendingPathExtension(self.extensionName) }

    package static func read(for file: URL) throws -> Record? {
        let url = self.url(for: file)
        guard url.isFileURL, !url.path.contains("\0") else { throw Failure.invalidData }
        let opened = url.path.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ), nil, DWORD(OPEN_EXISTING),
                DWORD(FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT), nil)
        }
        guard let handle = opened, handle != INVALID_HANDLE_VALUE else {
            let code = GetLastError()
            if code == ERROR_FILE_NOT_FOUND || code == ERROR_PATH_NOT_FOUND { return nil }
            throw Failure.unavailable
        }
        defer { CloseHandle(handle) }
        var info = BY_HANDLE_FILE_INFORMATION()
        guard GetFileType(handle) == DWORD(FILE_TYPE_DISK), GetFileInformationByHandle(handle, &info) != 0,
              info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY) == 0,
              info.nNumberOfLinks == 1, info.nFileSizeHigh == 0,
              info.nFileSizeLow > 0, info.nFileSizeLow <= DWORD(self.maximumBytes) else { throw Failure.invalidData }
        var buffer = [UInt8](repeating: 0, count: self.maximumBytes + 1)
        var count: DWORD = 0
        let succeeded = buffer.withUnsafeMutableBytes { ReadFile(handle, $0.baseAddress, DWORD($0.count), &count, nil) }
        guard succeeded != 0, count == info.nFileSizeLow else { throw Failure.unavailable }
        let data = Data(buffer.prefix(Int(count)))
        let record: Record
        do { record = try JSONDecoder().decode(Record.self, from: data) }
        catch { throw Failure.invalidData }
        try self.validate(record, filename: file.lastPathComponent)
        return record
    }

    private static func validate(_ record: Record, filename: String) throws {
        guard record.version == 1, record.ownershipPolicy == "EXACT_STORED_ACCOUNT_KEYS_ONLY",
              record.filename.lowercased() == filename.lowercased(), !record.filename.isEmpty,
              record.filename.utf8.count <= 128, !record.filename.contains("\0"),
              !record.filename.contains("/"), !record.filename.contains("\\"), !record.filename.contains(":"),
              record.originalSHA256.utf8.count == 64,
              record.originalSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw Failure.invalidData
        }
    }
}
#endif
