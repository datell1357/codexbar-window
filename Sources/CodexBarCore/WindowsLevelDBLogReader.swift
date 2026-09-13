#if os(Windows)
import Foundation

/// Strict in-memory physical-log decoder. Never returns a partial view of a corrupt log.
/// Format: google/leveldb doc/log_format.md and util/crc32c.h.
enum WindowsLevelDBLogReader {
    enum Failure: Error {
        case oversized, truncated, invalidPadding, unknownRecordType, checksumMismatch, invalidFragmentSequence
    }

    static func records(in data: Data) throws -> [Data] {
        guard data.count <= 64 * 1024 * 1024 else { throw Failure.oversized }
        let bytes = Array(data)
        let blockSize = 32_768
        let maximumRecordBytes = 4 * 1024 * 1024
        var result: [Data] = []
        var fragment: Data?
        var offset = 0
        while offset < bytes.count {
            try Task.checkCancellation()
            let blockRemaining = blockSize - offset % blockSize
            let available = min(blockRemaining, bytes.count - offset)
            if blockRemaining < 7 {
                guard bytes[offset..<(offset + available)].allSatisfy({ $0 == 0 }) else { throw Failure.invalidPadding }
                offset += available
                continue
            }
            guard available >= 7 else { throw Failure.truncated }
            let checksum = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
                UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
            let length = Int(bytes[offset + 4]) | Int(bytes[offset + 5]) << 8
            let type = bytes[offset + 6]
            if type == 0, length == 0, checksum == 0 {
                guard bytes[offset..<(offset + available)].allSatisfy({ $0 == 0 }) else { throw Failure.invalidPadding }
                offset += available
                continue
            }
            guard (1...4).contains(type) else { throw Failure.unknownRecordType }
            guard length <= blockRemaining - 7, length <= available - 7 else { throw Failure.truncated }
            let payloadStart = offset + 7
            let payloadEnd = payloadStart + length
            guard WindowsLevelDBChecksum.maskedCRC(bytes[(offset + 6)..<payloadEnd]) == checksum else { throw Failure.checksumMismatch }
            switch type {
            case 1:
                guard fragment == nil else { throw Failure.invalidFragmentSequence }
                guard result.count < 100_000 else { throw Failure.oversized }
                result.append(Data(bytes[payloadStart..<payloadEnd]))
            case 2:
                guard fragment == nil else { throw Failure.invalidFragmentSequence }
                fragment = Data(bytes[payloadStart..<payloadEnd])
            case 3, 4:
                guard var pending = fragment else { throw Failure.invalidFragmentSequence }
                guard length <= maximumRecordBytes - pending.count else { throw Failure.oversized }
                pending.append(contentsOf: bytes[payloadStart..<payloadEnd])
                if type == 4 {
                    guard result.count < 100_000 else { throw Failure.oversized }
                    result.append(pending)
                    fragment = nil
                } else { fragment = pending }
            default: throw Failure.unknownRecordType
            }
            offset = payloadEnd
        }
        guard fragment == nil else { throw Failure.truncated }
        try Task.checkCancellation()
        return result
    }

}
#endif
