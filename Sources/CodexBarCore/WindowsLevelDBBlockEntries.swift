#if os(Windows)
import Foundation

/// Decodes prefix-compressed entries from an already checksummed and decompressed block.
/// Comparator ordering is the responsibility of the index/data caller.
enum WindowsLevelDBBlockEntries {
    struct Entry: Sendable {
        let key: Data
        let value: Data
    }
    enum Failure: Error { case oversized, truncated, invalidRestart, invalidPrefix, invalidVarint }

    static func decode(_ data: Data) throws -> [Entry] {
        try Task.checkCancellation()
        guard data.count <= 4 * 1024 * 1024 else { throw Failure.oversized }
        guard data.count >= 8 else { throw Failure.truncated }
        let bytes = Array(data)
        func fixed32(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 |
                Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        let count = fixed32(bytes.count - 4)
        guard count > 0, count <= (bytes.count - 4) / 4 else { throw Failure.invalidRestart }
        let end = bytes.count - 4 - count * 4
        var restarts: [Int] = []
        for index in 0..<count {
            if index & 1023 == 0 { try Task.checkCancellation() }
            let restart = fixed32(end + index * 4)
            guard index == 0 ? restart == 0 : restart > restarts[index - 1] else { throw Failure.invalidRestart }
            guard restart < end || (end == 0 && count == 1 && restart == 0) else { throw Failure.invalidRestart }
            restarts.append(restart)
        }
        if end == 0 { return [] }
        var offset = 0
        func varint() throws -> Int {
            var result: UInt32 = 0
            for index in 0..<5 {
                guard offset < end else { throw Failure.truncated }
                let byte = bytes[offset]
                offset += 1
                guard index != 4 || byte <= 15 else { throw Failure.invalidVarint }
                result |= UInt32(byte & 0x7F) << (7 * index)
                if byte & 0x80 == 0 { return Int(result) }
            }
            throw Failure.invalidVarint
        }
        var previous = Data()
        var result: [Entry] = []
        var restartIndex = 0
        var budget = 64 * 1024 * 1024
        while offset < end {
            try Task.checkCancellation()
            guard result.count < 100_000 else { throw Failure.oversized }
            let start = offset
            let shared = try varint()
            let unshared = try varint()
            let valueLength = try varint()
            guard shared <= previous.count else { throw Failure.invalidPrefix }
            if restartIndex < restarts.count {
                guard start <= restarts[restartIndex] else { throw Failure.invalidRestart }
                if start == restarts[restartIndex] {
                    guard shared == 0 else { throw Failure.invalidRestart }
                    restartIndex += 1
                }
            }
            guard unshared <= end - offset else { throw Failure.truncated }
            guard valueLength <= end - offset - unshared else { throw Failure.truncated }
            guard shared <= 4 * 1024 * 1024, unshared <= 4 * 1024 * 1024 - shared else { throw Failure.oversized }
            let keyLength = shared + unshared
            guard keyLength <= budget else { throw Failure.oversized }
            budget -= keyLength
            guard valueLength <= budget else { throw Failure.oversized }
            budget -= valueLength
            var key = Data(previous.prefix(shared))
            key.append(contentsOf: bytes[offset..<(offset + unshared)])
            offset += unshared
            let value = Data(bytes[offset..<(offset + valueLength)])
            offset += valueLength
            result.append(Entry(key: key, value: value))
            previous = key
        }
        guard restartIndex == restarts.count else { throw Failure.invalidRestart }
        try Task.checkCancellation()
        return result
    }
}
#endif
