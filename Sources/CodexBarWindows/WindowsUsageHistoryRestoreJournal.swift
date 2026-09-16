#if os(Windows)
import CodexBarCore
import Crypto
import Foundation

/// Immutable operation records. These describe observed publication, not account ownership or
/// filesystem identity. Every resume must separately compare the current raw files and boundaries.
enum WindowsUsageHistoryRestoreJournal {
    struct Record: Codable {
        let version: Int
        let operationID: UUID
        let archiveID: UUID
        let targetLocationSHA256: String
        let status: String
        let recordedAt: Date
        let plannedFiles: Int
        let writtenEntryIDs: [UUID]
        let attemptID: UUID?
        let runtimeValidation: String
    }

    struct Context {
        let operationID: UUID
        let archiveID: UUID
        let targetLocationSHA256: String
        let entryIDs: Set<UUID>

        init(operationID: UUID, manifest: WindowsUsageHistoryRecovery.Manifest,
             planDirectory: URL = WindowsPlanUtilizationHistoryStore.defaultDirectory,
             paceFile: URL = HistoricalUsageHistoryStore.defaultFileURL()) throws {
            self.operationID = operationID
            self.archiveID = manifest.archiveID
            self.entryIDs = Set(manifest.entries.map(\.id))
            func key(_ url: URL) -> String {
                url.standardizedFileURL.path.replacingOccurrences(of: "\\", with: "/")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            }
            let encoded = try JSONEncoder().encode([key(planDirectory), key(paceFile)])
            self.targetLocationSHA256 = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
        }

        func record(status: String, written: [UUID], attemptID: UUID? = nil) -> Record {
            Record(version: 2, operationID: self.operationID, archiveID: self.archiveID,
                targetLocationSHA256: self.targetLocationSHA256, status: status, recordedAt: Date(),
                plannedFiles: self.entryIDs.count, writtenEntryIDs: written, attemptID: attemptID,
                runtimeValidation: "NOT_RUN")
        }
    }

    struct Evidence {
        let knownPublished: Set<UUID>
        let completed: Bool
    }

    private static let maximumRecordBytes = 256 * 1024
    private static let maximumAttempts = 256

    static func publish(_ record: Record, to directory: URL, name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(record)
        guard bytes.count <= self.maximumRecordBytes else { throw WindowsUsageHistoryRecovery.Failure.invalidOperation }
        try WindowsRecoveryFileAccess.publish(bytes, to: directory.appendingPathComponent(name))
    }

    static func publishEntry(_ id: UUID, context: Context, directory: URL) throws {
        let name = self.entryName(id)
        if let existing = try self.read(directory, name: name, context: context,
            statuses: ["HISTORY_ENTRY_PUBLISHED"], attemptID: nil) {
            guard existing.writtenEntryIDs == [id] else { throw WindowsUsageHistoryRecovery.Failure.invalidOperation }
            return
        }
        try self.publish(context.record(status: "HISTORY_ENTRY_PUBLISHED", written: [id]), to: directory, name: name)
    }

    static func evidence(in directory: URL, context: Context) throws -> Evidence {
        guard let prepared = try self.read(directory, name: "history-restore-prepared.json", context: context,
            statuses: ["HISTORY_RESTORE_PREPARED"], attemptID: nil), prepared.writtenEntryIDs.isEmpty else {
            throw WindowsUsageHistoryRecovery.Failure.invalidOperation
        }
        var known = Set<UUID>()
        let completed = try self.read(directory, name: "history-restore-completed.json", context: context,
            statuses: ["MISSING_HISTORY_FILES_PUBLISHED"], attemptID: nil)
        if let completed {
            guard Set(completed.writtenEntryIDs) == context.entryIDs else { throw WindowsUsageHistoryRecovery.Failure.invalidOperation }
            known.formUnion(completed.writtenEntryIDs)
        }
        if let failed = try self.read(directory, name: "history-restore-failed.json", context: context,
            statuses: ["PARTIAL_OR_INDETERMINATE", "NOT_PUBLISHED"], attemptID: nil) {
            guard failed.status != "NOT_PUBLISHED" || failed.writtenEntryIDs.isEmpty else {
                throw WindowsUsageHistoryRecovery.Failure.invalidOperation
            }
            known.formUnion(failed.writtenEntryIDs)
        }
        for id in context.entryIDs {
            if let entry = try self.read(directory, name: self.entryName(id), context: context,
                statuses: ["HISTORY_ENTRY_PUBLISHED"], attemptID: nil) {
                guard entry.writtenEntryIDs == [id] else { throw WindowsUsageHistoryRecovery.Failure.invalidOperation }
                known.insert(id)
            }
        }
        guard let names = try WindowsRecoveryFileAccess.directoryNamesIfPresent(directory, maximumEntries: 4096) else {
            throw WindowsUsageHistoryRecovery.Failure.invalidOperation
        }
        var attempts = Set<UUID>()
        for name in names {
            let canonical = name.lowercased()
            guard canonical.hasPrefix("history-resume-") else { continue }
            let suffix: String
            let statuses: Set<String>
            if canonical.hasSuffix("-prepared.json") {
                suffix = "-prepared.json"
                statuses = ["HISTORY_RECONCILIATION_PREPARED"]
            } else if canonical.hasSuffix("-failed.json") {
                suffix = "-failed.json"
                statuses = ["PARTIAL_OR_INDETERMINATE", "RECONCILIATION_INCOMPLETE"]
            } else { throw WindowsUsageHistoryRecovery.Failure.invalidOperation }
            let rawID = String(canonical.dropFirst("history-resume-".count).dropLast(suffix.count))
            guard let attemptID = UUID(uuidString: rawID), rawID == attemptID.uuidString.lowercased() else {
                throw WindowsUsageHistoryRecovery.Failure.invalidOperation
            }
            attempts.insert(attemptID)
            guard attempts.count <= self.maximumAttempts,
                  let record = try self.read(directory, name: name, context: context, statuses: statuses, attemptID: attemptID) else {
                throw WindowsUsageHistoryRecovery.Failure.invalidOperation
            }
            // A previous attempt's observed files must not silently be recreated after later deletion.
            known.formUnion(record.writtenEntryIDs)
        }
        // Reserve room for the next immutable prepared/failed pair. Completed reads need no new pair.
        guard completed != nil || attempts.count < self.maximumAttempts else { throw WindowsUsageHistoryRecovery.Failure.invalidOperation }
        return Evidence(knownPublished: known, completed: completed != nil)
    }

    static func attemptName(_ id: UUID, failed: Bool) -> String {
        "history-resume-" + id.uuidString.lowercased() + (failed ? "-failed.json" : "-prepared.json")
    }

    private static func entryName(_ id: UUID) -> String { "history-entry-" + id.uuidString.lowercased() + ".json" }

    private static func read(_ directory: URL, name: String, context: Context, statuses: Set<String>,
                             attemptID: UUID?) throws -> Record? {
        guard let bytes = try WindowsRecoveryFileAccess.readIfPresent(directory.appendingPathComponent(name),
            limit: self.maximumRecordBytes) else { return nil }
        let record: Record
        do { record = try JSONDecoder().decode(Record.self, from: bytes) }
        catch { throw WindowsUsageHistoryRecovery.Failure.invalidOperation }
        let written = Set(record.writtenEntryIDs)
        guard record.version == 2, record.operationID == context.operationID, record.archiveID == context.archiveID,
              record.targetLocationSHA256 == context.targetLocationSHA256,
              record.plannedFiles == context.entryIDs.count, record.runtimeValidation == "NOT_RUN",
              record.recordedAt.timeIntervalSince1970.isFinite, record.attemptID == attemptID,
              statuses.contains(record.status), written.count == record.writtenEntryIDs.count,
              written.isSubset(of: context.entryIDs) else { throw WindowsUsageHistoryRecovery.Failure.invalidOperation }
        return record
    }
}
#endif
