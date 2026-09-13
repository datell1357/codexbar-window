#if os(Windows)
import Foundation

/// Internal-key interpretation and version reduction only. The caller must first establish a
/// complete manifest-selected table/log view; this reducer cannot prove database completeness.
enum WindowsLevelDBVersions {
    enum Failure: Error { case invalidInternalKey, oversized, conflictingVersion, invalidSequence }

    static func tableMutation(internalKey: Data, value: Data) throws -> WindowsLevelDBWriteBatch.Mutation {
        try Task.checkCancellation()
        guard internalKey.count >= 8 else { throw Failure.invalidInternalKey }
        guard internalKey.count <= 4 * 1024 * 1024, value.count <= 4 * 1024 * 1024 else { throw Failure.oversized }
        let suffix = Array(internalKey.suffix(8))
        var packed: UInt64 = 0
        for index in 0..<8 { packed |= UInt64(suffix[index]) << (index * 8) }
        let kind = UInt8(packed & 0xFF)
        guard kind == 0 || kind == 1 else { throw Failure.invalidInternalKey }
        // A tombstone has no value. Reject nonempty payloads rather than interpreting them as a put.
        guard kind != 0 || value.isEmpty else { throw Failure.invalidInternalKey }
        return .init(sequence: packed >> 8, key: Data(internalKey.dropLast(8)), value: kind == 0 ? nil : value)
    }

    private struct Version: Hashable {
        let key: Data
        let sequence: UInt64
    }

    /// Retains tombstones in the result so callers cannot accidentally resurrect an older table value.
    static func latest(
        _ mutations: [WindowsLevelDBWriteBatch.Mutation],
        through maximumSequence: UInt64) throws -> [Data: WindowsLevelDBWriteBatch.Mutation]
    {
        guard maximumSequence <= WindowsLevelDBWriteBatch.maximumSequence else { throw Failure.invalidSequence }
        guard mutations.count <= 100_000 else { throw Failure.oversized }
        var latest: [Data: WindowsLevelDBWriteBatch.Mutation] = [:]
        var observed: [Version: WindowsLevelDBWriteBatch.Mutation] = [:]
        var byteBudget = 64 * 1024 * 1024
        for mutation in mutations {
            try Task.checkCancellation()
            guard mutation.sequence <= WindowsLevelDBWriteBatch.maximumSequence else { throw Failure.invalidSequence }
            let valueBytes = mutation.value?.count ?? 0
            guard mutation.key.count <= byteBudget else { throw Failure.oversized }
            byteBudget -= mutation.key.count
            guard valueBytes <= byteBudget else { throw Failure.oversized }
            byteBudget -= valueBytes
            guard mutation.sequence <= maximumSequence else { continue }
            let version = Version(key: mutation.key, sequence: mutation.sequence)
            if let previous = observed[version] {
                guard previous == mutation else { throw Failure.conflictingVersion }
                continue
            }
            observed[version] = mutation
            if let current = latest[mutation.key], current.sequence > mutation.sequence { continue }
            latest[mutation.key] = mutation
        }
        try Task.checkCancellation()
        return latest
    }
}
#endif
