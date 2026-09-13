#if os(Windows)
import Foundation

/// Full index traversal for the bytewise-comparator table named by manifest metadata.
enum WindowsLevelDBTableReader {
    enum Failure: Error { case metadataMismatch, invalidOrder, invalidIndex, overlappingBlocks, oversized }

    static func mutations(in data: Data, metadata: WindowsLevelDBVersionEdit.Table) throws -> [WindowsLevelDBWriteBatch.Mutation] {
        try Task.checkCancellation()
        guard UInt64(data.count) == metadata.size else { throw Failure.metadataMismatch }
        let table = try WindowsLevelDBTableContainer(data: data)
        guard table.metaindex.offset + table.metaindex.size + 5 <= table.index.offset else { throw Failure.overlappingBlocks }
        // Read and validate metadata even though filter blocks are unnecessary for a full scan.
        _ = try WindowsLevelDBBlockEntries.decode(table.block(table.metaindex))
        let index = try WindowsLevelDBBlockEntries.decode(table.block(table.index))
        var result: [WindowsLevelDBWriteBatch.Mutation] = []
        var firstKey: Data?
        var previousKey: Data?
        var previousSeparator: Data?
        var previousBlockEnd: UInt64 = 0
        var budget = 64 * 1024 * 1024
        for item in index {
            try Task.checkCancellation()
            _ = try self.compare(item.key, item.key)
            if let previousSeparator, try self.compare(previousSeparator, item.key) >= 0 { throw Failure.invalidIndex }
            let handle = try WindowsLevelDBTableContainer.decodeHandle(item.value)
            guard handle.offset >= previousBlockEnd, handle.offset <= table.metaindex.offset,
                  handle.size <= table.metaindex.offset - handle.offset,
                  table.metaindex.offset - handle.offset - handle.size >= 5 else { throw Failure.overlappingBlocks }
            let entries = try WindowsLevelDBBlockEntries.decode(table.block(handle))
            guard let first = entries.first, let last = entries.last else { throw Failure.invalidIndex }
            if let previousSeparator, try self.compare(previousSeparator, first.key) >= 0 { throw Failure.invalidIndex }
            guard try self.compare(last.key, item.key) <= 0 else { throw Failure.invalidIndex }
            for entry in entries {
                try Task.checkCancellation()
                guard result.count < 100_000, entry.key.count <= budget else { throw Failure.oversized }
                budget -= entry.key.count
                guard entry.value.count <= budget else { throw Failure.oversized }
                budget -= entry.value.count
                let mutation = try WindowsLevelDBVersions.tableMutation(internalKey: entry.key, value: entry.value)
                if let previousKey, try self.compare(previousKey, entry.key) >= 0 { throw Failure.invalidOrder }
                if firstKey == nil { firstKey = entry.key }
                previousKey = entry.key
                result.append(mutation)
            }
            previousBlockEnd = handle.offset + handle.size + 5
            previousSeparator = item.key
        }
        guard let firstKey, let previousKey,
              firstKey == metadata.smallest, previousKey == metadata.largest else { throw Failure.metadataMismatch }
        try Task.checkCancellation()
        return result
    }

    /// Internal comparator: user bytes ascending, packed sequence/type descending.
    static func compare(_ lhs: Data, _ rhs: Data) throws -> Int {
        guard lhs.count >= 8, rhs.count >= 8 else { throw Failure.invalidOrder }
        func trailer(_ data: Data) throws -> UInt64 {
            let bytes = Array(data.suffix(8))
            guard bytes[0] <= 1 else { throw Failure.invalidOrder }
            var value: UInt64 = 0
            for index in 0..<8 { value |= UInt64(bytes[index]) << (index * 8) }
            return value
        }
        let leftVersion = try trailer(lhs), rightVersion = try trailer(rhs)
        let left = lhs.dropLast(8), right = rhs.dropLast(8)
        if left.lexicographicallyPrecedes(right) { return -1 }
        if right.lexicographicallyPrecedes(left) { return 1 }
        if leftVersion == rightVersion { return 0 }
        return leftVersion > rightVersion ? -1 : 1
    }
}
#endif
