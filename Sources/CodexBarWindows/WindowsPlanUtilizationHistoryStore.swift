#if os(Windows)
import CodexBarCore
import Crypto
import Foundation
import WinSDK

/// Each mutation merges a fresh provider document under a per-provider process lock.
/// No long-lived cache can republish history removed by another app instance.
struct WindowsPlanUtilizationHistoryStore: Sendable {
    enum Failure: Error, Sendable { case busy, changed, tooLarge, invalidData, unavailable, ownershipReviewRequired }
    static let maximumFileBytes = 32 * 1024 * 1024
    static var defaultDirectory: URL {
        CodexBarPlatformPaths.codexBarDataDirectory().appendingPathComponent("plan-utilization-history", isDirectory: true)
    }
    let directory: URL

    /// Read-only cache for one owner. It is never accepted by record() as a document to publish.
    struct Selection: Sendable {
        let providerID: ProviderInstanceID
        let accountKey: String?
        let revision: Data?
        let histories: [PlanUtilizationHistoryCore.Series]
        let pairIdentity: String?
        let codexMigrationOwnership: CodexHistoricalOwnershipContext?
        let accountMigration: PlanUtilizationAccountMigration?
        let recoveryBoundary: WindowsHistoryRecoveryBoundary.Record?
    }

    init(directory: URL = Self.defaultDirectory) { self.directory = directory }

    func fileURL(providerID: ProviderInstanceID) -> URL {
        self.directory.appendingPathComponent(providerID.rawValue + ".json")
    }

    func load(providerID: ProviderInstanceID) throws -> PlanUtilizationHistoryCore.Document {
        try self.withLock(providerID: providerID) {
            _ = try WindowsHistoryRecoveryBoundary.read(for: self.fileURL(providerID: providerID))
            return try self.decode(self.readRaw(self.fileURL(providerID: providerID)))
        }
    }

    /// Materializes existing history only; it neither creates a missing history file nor adds observations.
    func loadSelection(providerID: ProviderInstanceID, accountKey: String?, previous: Selection?,
                       codexMigrationOwnership: CodexHistoricalOwnershipContext? = nil,
                       accountMigration: PlanUtilizationAccountMigration? = nil,
                       beforePublish: (() throws -> Void)? = nil) throws -> Selection {
        try self.withLock(providerID: providerID) {
            let fileURL = self.fileURL(providerID: providerID)
            let boundary = try WindowsHistoryRecoveryBoundary.read(for: fileURL)
            guard boundary == nil || accountKey != nil else { throw Failure.ownershipReviewRequired }
            let raw = try self.readRaw(fileURL)
            var revision = try self.revision(raw, boundary: boundary)
            if let previous, previous.providerID == providerID, previous.accountKey == accountKey,
               previous.revision == revision, previous.codexMigrationOwnership == codexMigrationOwnership,
               previous.accountMigration == accountMigration, previous.recoveryBoundary == boundary { return previous }
            var document = try self.decode(raw)
            if raw != nil {
                let before = document
                document = try self.materialize(document, providerID: providerID, accountKey: accountKey,
                    codexOwnership: codexMigrationOwnership, accountMigration: accountMigration, boundary: boundary)
                if document != before {
                    let data = try self.publish(document, to: fileURL, previous: raw, boundary: boundary, beforePublish: beforePublish)
                    revision = try self.revision(data, boundary: boundary)
                }
            }
            return Selection(providerID: providerID, accountKey: accountKey, revision: revision,
                histories: document.histories(accountKey: accountKey),
                pairIdentity: document.sessionEquivalentWindowPairIdentities[accountKey ?? "__codexbar_unscoped__"],
                codexMigrationOwnership: codexMigrationOwnership, accountMigration: accountMigration, recoveryBoundary: boundary)
        }
    }

    @discardableResult
    func record(providerID: ProviderInstanceID, samples: [PlanUtilizationHistoryCore.Series],
                accountKey: String?, updatePreferred: Bool,
                identityTransition: PlanUtilizationHistoryCore.IdentityTransition = .fixed,
                codexMigrationOwnership: CodexHistoricalOwnershipContext? = nil,
                accountMigration: PlanUtilizationAccountMigration? = nil,
                beforePublish: (() throws -> Void)? = nil) throws -> PlanUtilizationHistoryCore.Document {
        try self.withLock(providerID: providerID) {
            let fileURL = self.fileURL(providerID: providerID)
            let boundary = try WindowsHistoryRecoveryBoundary.read(for: fileURL)
            guard boundary == nil || accountKey != nil else { throw Failure.ownershipReviewRequired }
            let previous = try self.readRaw(fileURL)
            var document = try self.decode(previous)
            let before = document
            document = try self.materialize(document, providerID: providerID, accountKey: accountKey,
                codexOwnership: codexMigrationOwnership, accountMigration: accountMigration, boundary: boundary)
            try document.record(samples, accountKey: accountKey, updatePreferred: updatePreferred,
                identityTransition: identityTransition)
            guard document != before else { return document }
            _ = try self.publish(document, to: fileURL, previous: previous, boundary: boundary, beforePublish: beforePublish)
            return document
        }
    }

    private func materialize(_ document: PlanUtilizationHistoryCore.Document,
                             providerID: ProviderInstanceID, accountKey: String?,
                             codexOwnership: CodexHistoricalOwnershipContext?,
                             accountMigration: PlanUtilizationAccountMigration?,
                             boundary: WindowsHistoryRecoveryBoundary.Record?) throws
        -> PlanUtilizationHistoryCore.Document
    {
        if let ownership = codexOwnership {
            guard accountMigration == nil, providerID == .codex,
                  let accountKey, accountKey == ownership.canonicalKey else { throw Failure.changed }
            if boundary != nil { return document }
            return try CodexPlanUtilizationHistoryMigration.materialize(document, ownership: ownership)
        }
        if let migration = accountMigration {
            guard providerID.firstPartyProvider == migration.provider else { throw Failure.changed }
            if boundary != nil { return document }
            return try migration.materialize(document, accountKey: accountKey)
        }
        return document
    }

    private func publish(_ document: PlanUtilizationHistoryCore.Document, to fileURL: URL,
                         previous: Data?, boundary: WindowsHistoryRecoveryBoundary.Record?,
                         beforePublish: (() throws -> Void)?) throws -> Data {
        try document.validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= Self.maximumFileBytes else { throw Failure.tooLarge }
        try WindowsCredentialFileWriter.writePrivate(data, to: fileURL, beforePublish: { _ in
            guard try self.readRaw(fileURL) == previous else { throw Failure.changed }
            guard try WindowsHistoryRecoveryBoundary.read(for: fileURL) == boundary else { throw Failure.changed }
            try beforePublish?()
        })
        return data
    }

    private func revision(_ raw: Data?, boundary: WindowsHistoryRecoveryBoundary.Record?) throws -> Data? {
        guard let raw else { return nil }
        let digest = Data(SHA256.hash(data: raw))
        guard let boundary else { return digest }
        return Data(SHA256.hash(data: digest + (try boundary.encoded())))
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

    /// Allows a reviewed provider removal to coordinate with ordinary history reads and writes.
    /// The caller owns its exact-file checks and must keep deletion inside this scope.
    func withExclusiveAccess<T>(providerID: ProviderInstanceID, operation: () throws -> T) throws -> T {
        try self.withLock(providerID: providerID, operation: operation)
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
