#if os(Windows)
import CodexBarCore
import Crypto
import Foundation

/// Preserves the two usage-history stores byte-for-byte; it does not merge accounts or parse away
/// unknown/invalid historical rows. Cost SQLite stores and external session logs are separate data.
enum WindowsUsageHistoryRecovery {
    enum Failure: Error {
        case invalidArchive, unsupportedEntries, tooLarge, changed, invalidDestination
        case destinationOccupied, partialRestore, invalidOperation, restoredFileChanged
    }
    enum Kind: String, Codable, Sendable { case planUtilization, historicalPace }
    struct Entry: Codable, Equatable, Sendable {
        let id: UUID
        let kind: Kind
        let providerID: String?
        let bytes: Int
        let sha256: String
        let encryptedBytes: Int
        let encryptedSHA256: String
        var filename: String { self.id.uuidString.lowercased() + ".cbhist" }
    }
    struct Manifest: Codable, Equatable, Sendable {
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
    struct RestoreResult {
        let operationID: UUID
        let publishedFiles: Int
        let reconciledFiles: Int
        let alreadyCompleted: Bool
    }

    private typealias Journal = WindowsUsageHistoryRestoreJournal

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
                _ = try WindowsHistoryRecoveryBoundary.read(for: self.planURL(providerID))
                let data = try WindowsRecoveryFileAccess.read(self.planURL(providerID),
                    limit: self.maximumFileBytes, allowEmpty: true)
                total += data.count
                guard total <= self.maximumTotalBytes else { throw Failure.tooLarge }
                entries.append(try self.writeEntry(data, kind: .planUtilization, providerID: providerID,
                    archiveID: archiveID, directory: directory))
            }
            let pace = try WindowsRecoveryFileAccess.readIfPresent(HistoricalUsageHistoryStore.defaultFileURL(),
                limit: self.maximumFileBytes, allowEmpty: true)
            _ = try WindowsHistoryRecoveryBoundary.read(for: HistoricalUsageHistoryStore.defaultFileURL())
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
                try self.publishBoundary(entry, manifest: manifest, target: target)
                try WindowsRecoveryFileAccess.publish(self.readEntry(entry, manifest: manifest, directory: archive), to: target)
            }
            let context = try Journal.Context(operationID: UUID(), manifest: manifest,
                planDirectory: planDirectory, paceFile: destination.appendingPathComponent("usage-history.jsonl"))
            try Journal.publish(context.record(status: "HISTORY_FILES_MATERIALIZED_NOT_ACTIVATED",
                written: manifest.entries.map(\.id)), to: destination, name: "history-materialization.json")
            return manifest.entries.count
        }
    }

    /// Explicitly restores only when every target file in the archive is absent. Existing provider
    /// files outside the archive are preserved. No file is overwritten or merged, even if identical.
    static func restoreMissing(from archive: URL, operationDirectory: URL) throws -> RestoreResult {
        try self.requireOutsideLiveHistory(archive)
        try self.requireOutsideLiveHistory(operationDirectory)
        guard !self.contains(archive, operationDirectory) else { throw Failure.invalidDestination }
        let manifest = try self.readManifest(archive)
        try self.preflight(manifest, archive: archive)
        for entry in manifest.entries {
            try self.requireAbsent(self.sourceURL(entry))
            try self.requireAbsent(WindowsHistoryRecoveryBoundary.url(for: self.sourceURL(entry)))
        }
        let operationID = UUID()
        let context = try Journal.Context(operationID: operationID, manifest: manifest)
        var written: [UUID] = []
        var publicationStarted = false
        return try WindowsRecoveryFileAccess.withNewDirectory(operationDirectory) {
            // Preserve the planned identities/hashes privately before any live history publication.
            try WindowsRecoveryFileAccess.publish(self.sealManifest(manifest),
                to: operationDirectory.appendingPathComponent("history-restore-plan.cbhm"))
            try Journal.publish(context.record(status: "HISTORY_RESTORE_PREPARED", written: []),
                to: operationDirectory, name: "history-restore-prepared.json")
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
                            try self.publishBoundary(entry, manifest: manifest, target: target)
                            try WindowsRecoveryFileAccess.publish(data, to: target)
                            written.append(entry.id)
                            try Journal.publishEntry(entry.id, context: context, directory: operationDirectory)
                        }
                        if let rawID = entry.providerID, let providerID = ProviderInstanceID(rawValue: rawID) {
                            // Cooperate with older per-provider writers as well as the profile lease.
                            try WindowsPlanUtilizationHistoryStore().withExclusiveAccess(providerID: providerID, operation: publish)
                        } else {
                            try publish()
                        }
                    }
                }
                try self.requirePublished(manifest)
                try Journal.publish(context.record(status: "MISSING_HISTORY_FILES_PUBLISHED", written: written),
                    to: operationDirectory, name: "history-restore-completed.json")
                return RestoreResult(operationID: operationID, publishedFiles: written.count,
                    reconciledFiles: 0, alreadyCompleted: false)
            } catch {
                try? Journal.publish(context.record(status: publicationStarted ? "PARTIAL_OR_INDETERMINATE" : "NOT_PUBLISHED",
                    written: written), to: operationDirectory, name: "history-restore-failed.json")
                if publicationStarted { throw Failure.partialRestore }
                throw error
            }
        }
    }

    /// Caller explicitly selects the original operation. Existing files must match both the archive
    /// bytes and recovery provenance; publication receipts never substitute for current observations.
    static func resumeMissing(from archive: URL, operationDirectory: URL, operationID: UUID) throws -> RestoreResult {
        try self.requireOutsideLiveHistory(archive)
        try self.requireOutsideLiveHistory(operationDirectory)
        guard !self.contains(archive, operationDirectory), !self.contains(operationDirectory, archive) else {
            throw Failure.invalidDestination
        }
        return try WindowsRecoveryFileAccess.withDirectory(operationDirectory) {
            try WindowsRecoveryFileAccess.withDirectory(archive) {
                let manifest = try self.readManifest(archive)
                let plan = try self.readManifest(operationDirectory, filename: "history-restore-plan.cbhm")
                guard plan == manifest else { throw Failure.invalidOperation }
                let context = try Journal.Context(operationID: operationID, manifest: manifest)
                let evidence = try Journal.evidence(in: operationDirectory, context: context)
                try self.preflight(manifest, archive: archive)
                var observed: [UUID: TargetState] = [:]
                for entry in manifest.entries {
                    observed[entry.id] = try self.observe(entry, manifest: manifest,
                        knownPublished: evidence.knownPublished.contains(entry.id))
                }
                if evidence.completed {
                    return RestoreResult(operationID: operationID, publishedFiles: 0,
                        reconciledFiles: manifest.entries.count, alreadyCompleted: true)
                }
                // Persist exact files already observed before any new live publication. Later deletion
                // cannot be mistaken for an entry that the interrupted operation never reached.
                var confirmed = manifest.entries.filter { observed[$0.id] == .present }.map(\.id)
                let attemptID = UUID()
                try Journal.publish(context.record(status: "HISTORY_RECONCILIATION_PREPARED", written: confirmed,
                    attemptID: attemptID), to: operationDirectory, name: Journal.attemptName(attemptID, failed: false))
                var publicationStarted = false
                var publishedFiles = 0
                do {
                    let root = HistoricalUsageHistoryStore.defaultFileURL().deletingLastPathComponent()
                    try WindowsRecoveryFileAccess.withDirectoryCreatingIfMissing(root) {
                        if manifest.planDirectoryPresent {
                            try WindowsRecoveryFileAccess.withDirectoryCreatingIfMissing(
                                WindowsPlanUtilizationHistoryStore.defaultDirectory) {}
                        }
                        for entry in manifest.entries {
                            let data = try self.readEntry(entry, manifest: manifest, directory: archive)
                            let publish = {
                                let current = try self.observe(entry, manifest: manifest,
                                    knownPublished: confirmed.contains(entry.id))
                                guard current == observed[entry.id] else { throw Failure.restoredFileChanged }
                                if case let .absent(boundaryPublished) = current {
                                    publicationStarted = true
                                    let target = self.sourceURL(entry)
                                    if !boundaryPublished { try self.publishBoundary(entry, manifest: manifest, target: target) }
                                    try WindowsRecoveryFileAccess.publish(data, to: target)
                                    confirmed.append(entry.id)
                                    publishedFiles += 1
                                }
                                try Journal.publishEntry(entry.id, context: context, directory: operationDirectory)
                            }
                            if let rawID = entry.providerID, let providerID = ProviderInstanceID(rawValue: rawID) {
                                try WindowsPlanUtilizationHistoryStore().withExclusiveAccess(providerID: providerID, operation: publish)
                            } else {
                                try publish()
                            }
                        }
                    }
                    try self.requirePublished(manifest)
                    try Journal.publish(context.record(status: "MISSING_HISTORY_FILES_PUBLISHED",
                        written: manifest.entries.map(\.id)), to: operationDirectory, name: "history-restore-completed.json")
                    return RestoreResult(operationID: operationID, publishedFiles: publishedFiles,
                        reconciledFiles: manifest.entries.count - publishedFiles, alreadyCompleted: false)
                } catch {
                    try? Journal.publish(context.record(
                        status: publicationStarted ? "PARTIAL_OR_INDETERMINATE" : "RECONCILIATION_INCOMPLETE",
                        written: confirmed, attemptID: attemptID), to: operationDirectory,
                        name: Journal.attemptName(attemptID, failed: true))
                    if publicationStarted { throw Failure.partialRestore }
                    throw error
                }
            }
        }
    }

    private enum TargetState: Equatable { case absent(boundaryPublished: Bool), present }

    private static func observe(_ entry: Entry, manifest: Manifest, knownPublished: Bool) throws -> TargetState {
        let target = self.sourceURL(entry)
        let boundary = try WindowsHistoryRecoveryBoundary.read(for: target)
        let expected = self.boundary(entry, manifest: manifest, target: target)
        guard boundary == nil || boundary == expected else { throw Failure.restoredFileChanged }
        if let data = try WindowsRecoveryFileAccess.readIfPresent(target, limit: self.maximumFileBytes, allowEmpty: true) {
            guard boundary == expected, data.count == entry.bytes, self.hash(data) == entry.sha256 else {
                throw Failure.restoredFileChanged
            }
            return .present
        }
        guard !knownPublished else { throw Failure.restoredFileChanged }
        return .absent(boundaryPublished: boundary != nil)
    }

    private static func requirePublished(_ manifest: Manifest) throws {
        for entry in manifest.entries {
            guard try self.observe(entry, manifest: manifest, knownPublished: true) == .present else {
                throw Failure.restoredFileChanged
            }
        }
    }

    private static func planProviderNames() throws -> [String]? {
        let directory = WindowsPlanUtilizationHistoryStore.defaultDirectory
        guard let names = try WindowsRecoveryFileAccess.directoryNamesIfPresent(directory,
            maximumEntries: self.maximumProviders * 3) else { return nil }
        var providers: [String] = []
        var seen = Set<String>()
        for name in names {
            let canonical = name.lowercased()
            let boundarySuffix = ".json." + WindowsHistoryRecoveryBoundary.extensionName
            if canonical.hasSuffix(boundarySuffix) {
                let id = String(canonical.dropLast(boundarySuffix.count))
                guard ProviderInstanceID(rawValue: id) != nil,
                      try WindowsHistoryRecoveryBoundary.read(for: self.planURL(id)) != nil else {
                    throw Failure.unsupportedEntries
                }
                // Every new restore recreates this restrictive policy; it carries no history rows or grants.
                continue
            }
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

    private static func readManifest(_ directory: URL, filename: String = "history-manifest.cbhm") throws -> Manifest {
        let bytes = try WindowsRecoveryFileAccess.read(directory.appendingPathComponent(filename),
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

    private static func publishBoundary(_ entry: Entry, manifest: Manifest, target: URL) throws {
        let record = self.boundary(entry, manifest: manifest, target: target)
        try WindowsRecoveryFileAccess.publish(record.encoded(), to: WindowsHistoryRecoveryBoundary.url(for: target))
    }

    private static func boundary(_ entry: Entry, manifest: Manifest, target: URL) -> WindowsHistoryRecoveryBoundary.Record {
        WindowsHistoryRecoveryBoundary.Record(archiveID: manifest.archiveID, entryID: entry.id,
            originalSHA256: entry.sha256, filename: target.lastPathComponent)
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
