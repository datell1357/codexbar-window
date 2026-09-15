#if os(Windows)
import CodexBarCore
import Foundation
import WinSDK

/// Each mutation merges a fresh provider document under a per-provider process lock.
/// No long-lived cache can republish history removed by another app instance.
struct WindowsPlanUtilizationHistoryStore: Sendable {
    enum Failure: Error, Sendable { case busy, changed, tooLarge, invalidData, unavailable }
    static let maximumFileBytes = 32 * 1024 * 1024
    static var defaultDirectory: URL {
        CodexBarPlatformPaths.codexBarDataDirectory().appendingPathComponent("plan-utilization-history", isDirectory: true)
    }
    let directory: URL

    init(directory: URL = Self.defaultDirectory) { self.directory = directory }

    func fileURL(providerID: ProviderInstanceID) -> URL {
        self.directory.appendingPathComponent(providerID.rawValue + ".json")
    }

    func load(providerID: ProviderInstanceID) throws -> PlanUtilizationHistoryCore.Document {
        try self.withLock(providerID: providerID) {
            try self.decode(self.readRaw(self.fileURL(providerID: providerID)))
        }
    }

    @discardableResult
    func record(providerID: ProviderInstanceID, samples: [PlanUtilizationHistoryCore.Series],
                accountKey: String?, updatePreferred: Bool,
                identityTransition: PlanUtilizationHistoryCore.IdentityTransition = .fixed) throws -> PlanUtilizationHistoryCore.Document {
        try self.withLock(providerID: providerID) {
            let fileURL = self.fileURL(providerID: providerID)
            let previous = try self.readRaw(fileURL)
            var document = try self.decode(previous)
            let before = document
            try document.record(samples, accountKey: accountKey, updatePreferred: updatePreferred,
                identityTransition: identityTransition)
            guard document != before else { return document }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(document)
            guard data.count <= Self.maximumFileBytes else { throw Failure.tooLarge }
            try WindowsCredentialFileWriter.writePrivate(data, to: fileURL, beforePublish: { _ in
                guard try self.readRaw(fileURL) == previous else { throw Failure.changed }
            })
            return document
        }
    }

    private func decode(_ data: Data?) throws -> PlanUtilizationHistoryCore.Document {
        guard let data else { return PlanUtilizationHistoryCore.Document() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode(PlanUtilizationHistoryCore.Document.self, from: data) }
        catch { throw Failure.invalidData }
    }

    private func readRaw(_ url: URL) throws -> Data? {
        let attributes = url.path.withCString(encodedAs: UTF16.self) { GetFileAttributesW($0) }
        if attributes == DWORD(INVALID_FILE_ATTRIBUTES) {
            let code = GetLastError()
            if code == ERROR_FILE_NOT_FOUND || code == ERROR_PATH_NOT_FOUND { return nil }
            throw Failure.unavailable
        }
        guard attributes & DWORD(FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) == 0 else {
            throw Failure.unavailable
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while data.count <= Self.maximumFileBytes {
            let part = try file.read(upToCount: min(65536, Self.maximumFileBytes + 1 - data.count)) ?? Data()
            if part.isEmpty { return data }
            data.append(part)
        }
        throw Failure.tooLarge
    }

    private func withLock<T>(providerID: ProviderInstanceID, operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        let lockURL = self.directory.appendingPathComponent(providerID.rawValue + ".lock")
        let opened = lockURL.path.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, DWORD(GENERIC_READ | GENERIC_WRITE), 0, nil, DWORD(OPEN_ALWAYS),
                DWORD(FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT), nil)
        }
        guard let handle = opened, handle != INVALID_HANDLE_VALUE else {
            let code = GetLastError()
            if code == ERROR_SHARING_VIOLATION || code == ERROR_LOCK_VIOLATION { throw Failure.busy }
            throw Failure.unavailable
        }
        defer { CloseHandle(handle) }
        var info = BY_HANDLE_FILE_INFORMATION()
        guard GetFileType(handle) == DWORD(FILE_TYPE_DISK), GetFileInformationByHandle(handle, &info) != 0,
              info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) == 0 else {
            throw Failure.unavailable
        }
        return try operation()
    }
}
#endif
