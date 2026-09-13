#if os(Windows)
import Foundation

/// Replays one complete manifest byte stream. File acquisition and CURRENT consistency are separate.
enum WindowsLevelDBManifest {
    struct State: Sendable {
        let logNumber: UInt64
        let previousLogNumber: UInt64
        let nextFileNumber: UInt64
        let lastSequence: UInt64
        let tables: [WindowsLevelDBVersionEdit.Table]
    }
    enum Failure: Error { case unsupportedComparator, missingMetadata, regressingMetadata, conflictingFile, oversized }

    static func decode(_ data: Data) throws -> State {
        let records = try WindowsLevelDBLogReader.records(in: data)
        var tables: [WindowsLevelDBVersionEdit.FileID: WindowsLevelDBVersionEdit.Table] = [:]
        var log: UInt64?
        var previous: UInt64 = 0
        var next: UInt64?
        var sequence: UInt64?
        var hasComparator = false
        var metadataBudget = 64 * 1024 * 1024
        for record in records {
            try Task.checkCancellation()
            let edit = try WindowsLevelDBVersionEdit.decode(record)
            if let comparator = edit.comparator {
                guard comparator == Data("leveldb.BytewiseComparator".utf8) else { throw Failure.unsupportedComparator }
                hasComparator = true
            }
            if let value = edit.logNumber {
                guard log.map({ value >= $0 }) ?? true else { throw Failure.regressingMetadata }
                log = value
            }
            if let value = edit.previousLogNumber { previous = value }
            if let value = edit.nextFileNumber {
                guard next.map({ value >= $0 }) ?? true else { throw Failure.regressingMetadata }
                next = value
            }
            if let value = edit.lastSequence {
                guard sequence.map({ value >= $0 }) ?? true else { throw Failure.regressingMetadata }
                sequence = value
            }
            // VersionEdit semantics apply removals before additions, including level moves.
            for id in edit.deletedFiles { tables.removeValue(forKey: id) }
            for table in edit.newFiles {
                guard table.id.number > 0, table.size > 0 else { throw Failure.conflictingFile }
                guard table.smallest.count <= metadataBudget else { throw Failure.oversized }
                metadataBudget -= table.smallest.count
                guard table.largest.count <= metadataBudget else { throw Failure.oversized }
                metadataBudget -= table.largest.count
                if let existing = tables[table.id], existing != table { throw Failure.conflictingFile }
                tables[table.id] = table
                guard tables.count <= 100_000 else { throw Failure.oversized }
            }
        }
        guard hasComparator, let log, let next, let sequence else { throw Failure.missingMetadata }
        // The same physical file cannot be active in two levels in the final version.
        var fileNumbers = Set<UInt64>()
        for table in tables.values {
            try Task.checkCancellation()
            guard fileNumbers.insert(table.id.number).inserted else { throw Failure.conflictingFile }
        }
        let ordered = tables.values.sorted {
            $0.id.level == $1.id.level ? $0.id.number < $1.id.number : $0.id.level < $1.id.level
        }
        return State(logNumber: log, previousLogNumber: previous, nextFileNumber: next,
            lastSequence: sequence, tables: ordered)
    }
}
#endif
