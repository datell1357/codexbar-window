#if os(Windows)
import Foundation

/// Read-only recovery of a closed browser's database. No repair, compaction or file writes.
enum WindowsLevelDBSnapshot {
    struct Snapshot: Sendable {
        let sequence: UInt64
        let entries: [Data: WindowsLevelDBWriteBatch.Mutation]
    }
    enum Failure: Error { case unavailable, missingFile, changed, oversized, invalidTableRange, invalidSequence, timedOut }

    static func read(directory: URL, deadline: Date = Date().addingTimeInterval(15)) throws -> Snapshot {
        try self.check(deadline)
        return try WindowsLevelDBReadLock.withLock(directory: directory) {
            var fileBudget = 256 * 1024 * 1024
            func readFile(_ name: String, maximumBytes: Int = 64 * 1024 * 1024) throws -> Data {
                try self.check(deadline)
                let data = try WindowsLevelDBFileReader.read(directory.appendingPathComponent(name),
                    maximumBytes: min(maximumBytes, fileBudget), deadline: deadline)
                fileBudget -= data.count
                return data
            }
            func inventory() throws -> [WindowsLevelDBFileNames.Numbered: String] {
                try self.check(deadline)
                let names: [String]
                do { names = try FileManager.default.contentsOfDirectory(atPath: directory.path) }
                catch { throw Failure.unavailable }
                return try WindowsLevelDBFileNames.inventory(names)
            }
            let current = try readFile("CURRENT", maximumBytes: 64)
            let manifestName = try WindowsLevelDBFileNames.currentManifest(current)
            let files = try inventory()
            guard let manifestID = WindowsLevelDBFileNames.numbered(manifestName),
                  files[manifestID] == manifestName else { throw Failure.missingFile }
            let manifestData = try readFile(manifestName)
            let manifest = try WindowsLevelDBManifest.decode(manifestData)
            // Levels above zero must have disjoint ordered internal-key ranges.
            for level in 1..<7 {
                let tables = try manifest.tables.filter { $0.id.level == level }.sorted {
                    try WindowsLevelDBTableReader.compare($0.smallest, $1.smallest) < 0
                }
                for index in tables.indices where index > 0 {
                    guard try WindowsLevelDBTableReader.compare(tables[index - 1].largest, tables[index].smallest) < 0 else {
                        throw Failure.invalidTableRange
                    }
                }
            }
            var mutations: [WindowsLevelDBWriteBatch.Mutation] = []
            var mutationBudget = 64 * 1024 * 1024
            func append(_ incoming: [WindowsLevelDBWriteBatch.Mutation]) throws {
                guard incoming.count <= 100_000 - mutations.count else { throw Failure.oversized }
                for mutation in incoming {
                    try self.check(deadline)
                    guard mutation.key.count <= mutationBudget else { throw Failure.oversized }
                    mutationBudget -= mutation.key.count
                    let valueSize = mutation.value?.count ?? 0
                    guard valueSize <= mutationBudget else { throw Failure.oversized }
                    mutationBudget -= valueSize
                    mutations.append(mutation)
                }
            }
            for table in manifest.tables {
                guard let name = files[.init(kind: .table, number: table.id.number)] else { throw Failure.missingFile }
                let decoded = try WindowsLevelDBTableReader.mutations(in: readFile(name), metadata: table)
                guard decoded.allSatisfy({ $0.sequence <= manifest.lastSequence }) else { throw Failure.invalidSequence }
                try append(decoded)
            }
            // Recovery includes newer WALs that may not yet have been registered in the manifest.
            let logs = files.keys.filter {
                $0.kind == .log && ($0.number >= manifest.logNumber || $0.number == manifest.previousLogNumber)
            }.sorted { $0.number < $1.number }
            if manifest.logNumber > 0, files[.init(kind: .log, number: manifest.logNumber)] == nil { throw Failure.missingFile }
            if manifest.previousLogNumber > 0, files[.init(kind: .log, number: manifest.previousLogNumber)] == nil { throw Failure.missingFile }
            var sequence = manifest.lastSequence
            for log in logs {
                guard let name = files[log] else { throw Failure.missingFile }
                let records = try WindowsLevelDBLogReader.records(in: readFile(name))
                for record in records {
                    try self.check(deadline)
                    let batch = try WindowsLevelDBWriteBatch.decode(record)
                    if let last = batch.mutations.last { sequence = max(sequence, last.sequence) }
                    try append(batch.mutations)
                }
            }
            let entries = try WindowsLevelDBVersions.latest(mutations, through: sequence)
            guard try readFile("CURRENT", maximumBytes: 64) == current,
                  try readFile(manifestName) == manifestData,
                  try inventory() == files else { throw Failure.changed }
            try self.check(deadline)
            return Snapshot(sequence: sequence, entries: entries)
        }
    }

    private static func check(_ deadline: Date) throws {
        try Task.checkCancellation()
        guard Date() < deadline else { throw Failure.timedOut }
    }
}
#endif
