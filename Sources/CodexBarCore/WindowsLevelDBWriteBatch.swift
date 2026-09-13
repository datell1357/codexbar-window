#if os(Windows)
import Foundation

/// Decodes logical WAL records, preserving deletions and per-operation sequence numbers.
/// Source format: google/leveldb db/write_batch.cc and db/dbformat.h.
enum WindowsLevelDBWriteBatch {
    struct Mutation: Sendable, Equatable {
        let sequence: UInt64
        let key: Data
        /// nil is deletion; empty Data is a present, empty value.
        let value: Data?
    }

    struct Batch: Sendable {
        let sequence: UInt64
        let mutations: [Mutation]
    }

    enum Failure: Error { case oversized, truncated, invalidVarint, unknownTag, invalidSequence, countMismatch }
    static let maximumSequence: UInt64 = (UInt64(1) << 56) - 1

    static func decode(_ data: Data) throws -> Batch {
        try Task.checkCancellation()
        guard data.count <= 4 * 1024 * 1024 else { throw Failure.oversized }
        var cursor = Cursor(bytes: Array(data))
        let sequence = try cursor.fixed(width: 8)
        let count = try cursor.fixed(width: 4)
        guard count <= 100_000 else { throw Failure.oversized }
        guard sequence <= self.maximumSequence,
              count == 0 || count - 1 <= self.maximumSequence - sequence else { throw Failure.invalidSequence }
        var mutations: [Mutation] = []
        mutations.reserveCapacity(Int(count))
        for index in 0..<Int(count) {
            try Task.checkCancellation()
            let tag = try cursor.byte()
            guard tag == 0 || tag == 1 else { throw Failure.unknownTag }
            let key = try cursor.lengthPrefixed()
            let value = tag == 1 ? try cursor.lengthPrefixed() : nil
            mutations.append(Mutation(sequence: sequence + UInt64(index), key: key, value: value))
        }
        guard cursor.offset == cursor.bytes.count else { throw Failure.countMismatch }
        try Task.checkCancellation()
        return Batch(sequence: sequence, mutations: mutations)
    }

    private struct Cursor {
        let bytes: [UInt8]
        var offset = 0

        mutating func byte() throws -> UInt8 {
            guard offset < bytes.count else { throw Failure.truncated }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func fixed(width: Int) throws -> UInt64 {
            guard width <= bytes.count - offset else { throw Failure.truncated }
            var result: UInt64 = 0
            for shift in 0..<width { result |= UInt64(try self.byte()) << (shift * 8) }
            return result
        }

        mutating func lengthPrefixed() throws -> Data {
            var length: UInt32 = 0
            for index in 0..<5 {
                let next = try self.byte()
                if index == 4, next > 15 { throw Failure.invalidVarint }
                length |= UInt32(next & 0x7F) << (index * 7)
                if next & 0x80 == 0 {
                    guard Int(length) <= bytes.count - offset else { throw Failure.truncated }
                    let end = offset + Int(length)
                    defer { offset = end }
                    return Data(bytes[offset..<end])
                }
            }
            throw Failure.invalidVarint
        }
    }
}
#endif
