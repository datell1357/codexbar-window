#if os(Windows)
import CodexBarCore
import Crypto
import Foundation

/// Preserves the two usage-history stores byte-for-byte; it does not merge accounts or parse away
/// unknown/invalid historical rows. Cost SQLite stores and external session logs are separate data.
enum WindowsUsageHistoryRecovery {
    enum Failure: Error {
        case invalidArchive, unsupportedEntries, tooLarge, changed, invalidDestination
        case destinationOccupied, partialRestore
    }
    enum Kind: String, Codable, Sendable { case planUtilization, historicalPace }
    struct Entry: Codable, Sendable {
        let id: UUID
        let kind: Kind
        let providerID: String?
        let bytes: Int
        let sha256: String
        let encryptedBytes: Int
        let encryptedSHA256: String
        var filename: String { self.id.uuidString.lowercased() + ".cbhist" }
    }
    struct Manifest: Codable, Sendable {
        let version: Int
        let archiveID: UUID
        let createdAt: Date
        let status: String
        let planDirectoryPresent: Bool
        let pacePresent: Bool
        let entries: [Entry]
    }
    private struct FilePayload: Codable {
        let version: Int
        let archiveID: UUID
        let entryID: UUID
        let kind: Kind
        let providerID: String?
        let data: Data
    }
    private struct OperationRecord: Encodable {
        let version = 1
        let operationID: UUID
        let archiveID: UUID
        let status: String
        let recordedAt = Date()
        let plannedFiles: Int
        let writtenEntryIDs: [UUID]
        let runtimeValidation = "NOT_RUN"
    }

    private static let maximumProviders = 1024
    private static let maximumFileBytes = WindowsPlanUtilizationHistoryStore.maximumFileBytes
    private static let maximumTotalBytes = 512 * 1024 * 1024
    private static let maximumEncryptedFileBytes = 48 * 1024 * 1024
    private static let maximumManifestBytes = 2 * 1024 * 1024
    private static let manifestName = "history-manifest.cbhm"
    private static let manifestMagic = Data("CodexBar.Windows.UsageHistoryManifest.v1\0".utf8)
    private static let fileMagic = Data("CodexBar.Windows.UsageHistoryFile.v1\0".utf8)
    private static let archiveStatus = "RAW_HISTORY_BACKUP_NOT_RUNTIME_VALIDATED"

    /// Caller owns exclusive profile access for the whole operation, including the final manifest.
    static func backup(to directory: URL) throws -> Int {
        try self.requireOutsideLiveHistory(directory)
        let providerNames = try self.planProviderNames()
        let archiveID = UUID()
        var entries: [Entry] = []
        var total = 0
        return try WindowsRecoveryFileAccess.withNewDirectory(directory) {
            for providerID in providerNames ?? [] {
                let data = try WindowsRecoveryFileAccess.read(self.planURL(providerID),
                    limit: self.maximumFileBytes, allowEmpty: true)
                total += data.count
                guard total <= self.maximumTotalBytes else { throw Failure.tooLarge }
                entries.append(try self.writeEntry(data, kind: .planUtilization, providerID: providerID,
                    archiveID: archiveID, directory: directory))
            }
            let pace = try WindowsRecoveryFileAccess.readIfPresent(HistoricalUsageHistoryStore.defaultFileURL(),
                limit: self.maximumFileBytes, allowEmpty: true)
            if let pace {
                total += pace.count
                guard total <= self.maximumTotalBytes else { throw Failure.tooLarge }
                entries.append(try self.writeEntry(pace, kind: .historicalPace, providerID: nil,
                    archiveID: archiveID, directory: directory))
            }
            // No final manifest is published if an old app/tool changed the observed input set.
            guard try self.planProviderNames() == providerNames else { throw Failure.changed }
            for entry in entries {
                let data = try WindowsRecoveryFileAccess.read(self.sourceURL(entry),
                    limit: self.maximumFileBytes, allowEmpty: true)
                guard data.count == entry.bytes, self.hash(data) == entry.sha256 else { throw Failure.changed }
            }
            if pace == nil,
               try WindowsRecoveryFileAccess.readIfPresent(HistoricalUsageHistoryStore.defaultFileURL(),
                   limit: self.maximumFileBytes, allowEmpty: true) != nil { throw Failure.changed }
            let manifest = Manifest(version: 1, archiveID: archiveID, createdAt: Date(), status: self.archiveStatus,
                planDirectoryPresent: providerNames != nil, pacePresent: pace != nil, entries: entries)
            try self.validate(manifest)
            try WindowsRecoveryFileAccess.publish(self.sealManifest(manifest),
                to: directory.appendingPathComponent(self.manifestName))
            return entries.count
        }
    }

    static func restoreNew(from archive: URL, to destination: URL) throws -> Int {
        try self.requireOutsideLiveHistory(destination)
        guard !self.contains(archive, destination) else { throw Failure.invalidDestination }
        let manifest = try self.readManifest(archive)
        // Detect incomplete/tampered chunks before creating output; re-read and bind again on write.
        try self.preflight(manifest, archive: archive)
        return try WindowsRecoveryFileAccess.withNewDirectory(destination) {
            let planDirectory = destination.appendingPathComponent("plan-utilization-history", isDirectory: true)
            if manifest.planDirectoryPresent {
                try WindowsRecoveryFileAccess.withNewDirectory(planDirectory) {}
            }
            for entry in manifest.entries {
                let target = self.destinationURL(entry, root: destination)
                try WindowsRecoveryFileAccess.publish(self.readEntry(entry, manifest: manifest, directory: archive), to: target)
            }
            let record = OperationRecord(operationID: UUID(), archiveID: manifest.archiveID,
                status: "HISTORY_FILES_MATERIALIZED_NOT_ACTIVATED", plannedFiles: manifest.entries.count,
                writtenEntryIDs: manifest.entries.map(\.id))
            try WindowsRecoveryFileAccess.publish(JSONEncoder().encode(record),
                to: destination.appendingPathComponent("history-materialization.json"))
            return manifest.entries.count
        }
    }

    /// Explicitly restores only when every target file in the archive is absent. Existing provider
    /// files outside the archive are preserved. No file is overwritten or merged, even if identical.
    static func restoreMissing(from archive: URL, operationDirectory: URL) throws -> Int {
        try self.requireOutsideLiveHistory(archive)
        try self.requireOutsideLiveHistory(operationDirectory)
        guard !self.contains(archive, operationDirectory) else { throw Failure.invalidDestination }
        let manifest = try self.readManifest(archive)
        try self.preflight(manifest, archive: archive)
        for entry in manifest.entries { try self.requireAbsent(self.sourceURL(entry)) }
        let operationID = UUID()
        var written: [UUID] = []
        var publicationStarted = false
        return try WindowsRecoveryFileAccess.withNewDirectory(operationDirectory) {
            // Preserve the planned identities/hashes privately before any live history publication.
            try WindowsRecoveryFileAccess.publish(self.sealManifest(manifest),
                to: operationDirectory.appendingPathComponent("history-restore-plan.cbhm"))
            let prepared = OperationRecord(operationID: operationID, archiveID: manifest.archiveID,
                status: "HISTORY_RESTORE_PREPARED", plannedFiles: manifest.entries.count, writtenEntryIDs: [])
            try WindowsRecoveryFileAccess.publish(JSONEncoder().encode(prepared),
                to: operationDirectory.appendingPathComponent("history-restore-prepared.json"))
            do {
                let root = HistoricalUsageHistoryStore.defaultFileURL().deletingLastPathComponent()
                try WindowsRecoveryFileAccess.withDirectoryCreatingIfMissing(root) {
                    if manifest.planDirectoryPresent {
                        try WindowsRecoveryFileAccess.withDirectoryCreatingIfMissing(
                            WindowsPlanUtilizationHistoryStore.defaultDirectory) {}
                    }
                    for entry in manifest.entries {
                        let data = try self.readEntry(entry, manifest: manifest, directory: archive)
                        let target = self.sourceURL(entry)
                        let publish = {
                            try self.requireAbsent(target)
                            publicationStarted = true
                            try WindowsRecoveryFileAccess.publish(data, to: target)
                            written.append(entry.id)
                        }
                        if let rawID = entry.providerID, let providerID = ProviderInstanceID(rawValue: rawID) {
                            // Cooperate with older per-provider writers as well as the profile lease.
                            try WindowsPlanUtilizationHistoryStore().withExclusiveAccess(providerID: providerID, operation: publish)
                        } else {
                            try publish()
                        }
                    }
                }
                let completed = OperationRecord(operationID: operationID, archiveID: manifest.archiveID,
                    status: "MISSING_HISTORY_FILES_PUBLISHED", plannedFiles: manifest.entries.count,
                    writtenEntryIDs: written)
                try WindowsRecoveryFileAccess.publish(JSONEncoder().encode(completed),
                    to: operationDirectory.appendingPathComponent("history-restore-completed.json"))
                return written.count
            } catch {
                let failed = OperationRecord(operationID: operationID, archiveID: manifest.archiveID,
                    status: publicationStarted ? "PARTIAL_OR_INDETERMINATE" : "NOT_PUBLISHED",
                    plannedFiles: manifest.entries.count, writtenEntryIDs: written)
                try? WindowsRecoveryFileAccess.publish(JSONEncoder().encode(failed),
                    to: operationDirectory.appendingPathComponent("history-restore-failed.json"))
                if publicationStarted { throw Failure.partialRestore }
                throw error
            }
        }
    }

    private static func planProviderNames() throws -> [String]? {
        let directory = WindowsPlanUtilizationHistoryStore.defaultDirectory
        guard let names = try WindowsRecoveryFileAccess.directoryNamesIfPresent(directory,
            maximumEntries: self.maximumProviders * 2) else { return nil }
        var providers: [String] = []
        var seen = Set<String>()
        for name in names {
            let canonical = name.lowercased()
            if canonical.hasSuffix(".lock"), ProviderInstanceID(rawValue: String(canonical.dropLast(5))) != nil {
                let lock = try WindowsRecoveryFileAccess.read(directory.appendingPathComponent(name), limit: 1, allowEmpty: true)
                guard lock.isEmpty else { throw Failure.unsupportedEntries }
                continue
            }
            guard canonical.hasSuffix(".json"), ProviderInstanceID(rawValue: String(canonical.dropLast(5))) != nil,
                  seen.insert(String(canonical.dropLast(5))).inserted else {
                throw Failure.unsupportedEntries
            }
            providers.append(String(canonical.dropLast(5)))
            guard providers.count <= self.maximumProviders else { throw Failure.tooLarge }
        }
        return providers.sorted()
    }

    private static func writeEntry(_ data: Data, kind: Kind, providerID: String?, archiveID: UUID,
                                   directory: URL) throws -> Entry {
        let id = UUID()
        let payload = FilePayload(version: 1, archiveID: archiveID, entryID: id, kind: kind, providerID: providerID, data: data)
        let bytes = try self.seal(JSONEncoder().encode(payload), magic: self.fileMagic, purpose: .historyFile,
            limit: self.maximumEncryptedFileBytes)
        let entry = Entry(id: id, kind: kind, providerID: providerID, bytes: data.count, sha256: self.hash(data),
            encryptedBytes: bytes.count, encryptedSHA256: self.hash(bytes))
        try WindowsRecoveryFileAccess.publish(bytes, to: directory.appendingPathComponent(entry.filename))
        return entry
    }

    private static func readManifest(_ directory: URL) throws -> Manifest {
        let bytes = try WindowsRecoveryFileAccess.read(directory.appendingPathComponent(self.manifestName),
            limit: self.maximumManifestBytes)
        let data = try self.open(bytes, magic: self.manifestMagic, purpose: .historyManifest, limit: self.maximumManifestBytes)
        let manifest: Manifest
        do { manifest = try JSONDecoder().decode(Manifest.self, from: data) }
        catch { throw Failure.invalidArchive }
        try self.validate(manifest)
        return manifest
    }

    private static func sealManifest(_ manifest: Manifest) throws -> Data {
        try self.seal(JSONEncoder().encode(manifest), magic: self.manifestMagic,
            purpose: .historyManifest, limit: self.maximumManifestBytes)
    }

    private static func readEntry(_ entry: Entry, manifest: Manifest, directory: URL) throws -> Data {
        let bytes = try WindowsRecoveryFileAccess.read(directory.appendingPathComponent(entry.filename),
            limit: self.maximumEncryptedFileBytes)
        guard bytes.count == entry.encryptedBytes, self.hash(bytes) == entry.encryptedSHA256 else { throw Failure.changed }
        let data = try self.open(bytes, magic: self.fileMagic, purpose: .historyFile, limit: self.maximumEncryptedFileBytes)
        let payload: FilePayload
        do { payload = try JSONDecoder().decode(FilePayload.self, from: data) }
        catch { throw Failure.invalidArchive }
        guard payload.version == 1, payload.archiveID == manifest.archiveID, payload.entryID == entry.id,
              payload.kind == entry.kind, payload.providerID == entry.providerID,
              payload.data.count == entry.bytes, self.hash(payload.data) == entry.sha256 else { throw Failure.changed }
        return payload.data
    }

    private static func preflight(_ manifest: Manifest, archive: URL) throws {
        for entry in manifest.entries { _ = try self.readEntry(entry, manifest: manifest, directory: archive) }
    }

    private static func validate(_ manifest: Manifest) throws {
        guard manifest.version == 1, manifest.status == self.archiveStatus,
              manifest.createdAt.timeIntervalSince1970.isFinite,
              manifest.entries.count <= self.maximumProviders + 1 else { throw Failure.invalidArchive }
        var ids = Set<UUID>()
        var providers = Set<String>()
        var pace = false
        var total = 0
        for entry in manifest.entries {
            guard ids.insert(entry.id).inserted, entry.bytes >= 0, entry.bytes <= self.maximumFileBytes,
                  entry.encryptedBytes > self.fileMagic.count, entry.encryptedBytes <= self.maximumEncryptedFileBytes,
                  self.validHash(entry.sha256), self.validHash(entry.encryptedSHA256) else { throw Failure.invalidArchive }
            total += entry.bytes
            guard total <= self.maximumTotalBytes else { throw Failure.tooLarge }
            switch entry.kind {
            case .planUtilization:
                guard manifest.planDirectoryPresent, let id = entry.providerID,
                      ProviderInstanceID(rawValue: id) != nil, providers.insert(id).inserted,
                      providers.count <= self.maximumProviders else { throw Failure.invalidArchive }
                // Ensure a provider ID cannot become a DOS device or another path namespace.
                _ = try WindowsRecoveryFileAccess.explicitPath(self.planURL(id).path)
            case .historicalPace:
                guard !pace, entry.providerID == nil else { throw Failure.invalidArchive }
                pace = true
            }
        }
        guard pace == manifest.pacePresent else { throw Failure.invalidArchive }
    }

    private static func sourceURL(_ entry: Entry) -> URL {
        switch entry.kind {
        case .planUtilization: self.planURL(entry.providerID!) // Validated manifest / locally constructed entry.
        case .historicalPace: HistoricalUsageHistoryStore.defaultFileURL()
        }
    }

    private static func planURL(_ providerID: String) -> URL {
        WindowsPlanUtilizationHistoryStore.defaultDirectory.appendingPathComponent(providerID + ".json")
    }

    private static func destinationURL(_ entry: Entry, root: URL) -> URL {
        switch entry.kind {
        case .planUtilization:
            root.appendingPathComponent("plan-utilization-history", isDirectory: true)
                .appendingPathComponent(entry.providerID! + ".json")
        case .historicalPace: root.appendingPathComponent("usage-history.jsonl")
        }
    }

    private static func requireAbsent(_ url: URL) throws {
        guard try WindowsRecoveryFileAccess.readIfPresent(url, limit: self.maximumFileBytes, allowEmpty: true) == nil else {
            throw Failure.destinationOccupied
        }
    }

    private static func requireOutsideLiveHistory(_ url: URL) throws {
        let root = HistoricalUsageHistoryStore.defaultFileURL().deletingLastPathComponent()
        guard !self.contains(root, url), !self.contains(WindowsPlanUtilizationHistoryStore.defaultDirectory, url) else {
            throw Failure.invalidDestination
        }
    }

    /// Inputs have already passed the local absolute path checks; no archive-supplied relative paths.
    private static func contains(_ parent: URL, _ child: URL) -> Bool {
        func key(_ url: URL) -> String {
            url.standardizedFileURL.path.replacingOccurrences(of: "\\", with: "/")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        }
        let root = key(parent)
        let path = key(child)
        return path == root || path.hasPrefix(root + "/")
    }

    private static func seal(_ data: Data, magic: Data, purpose: WindowsRecoveryProtection.Purpose,
                             limit: Int) throws -> Data {
        let bytes = try WindowsRecoveryProtection.transform(data, protect: true, purpose: purpose,
            maximumBytes: limit - magic.count)
        return magic + bytes
    }

    private static func open(_ bytes: Data, magic: Data, purpose: WindowsRecoveryProtection.Purpose,
                             limit: Int) throws -> Data {
        guard bytes.count > magic.count, bytes.count <= limit, bytes.starts(with: magic) else { throw Failure.invalidArchive }
        return try WindowsRecoveryProtection.transform(Data(bytes.dropFirst(magic.count)), protect: false,
            purpose: purpose, maximumBytes: limit - magic.count)
    }

    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func validHash(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
#endif
