#if os(Windows)
import Foundation

/// Raw Snappy block decoding (not the framed stream format), for LevelDB table blocks.
/// Format reference: google/snappy format_description.txt.
enum WindowsLevelDBSnappy {
    enum Failure: Error { case oversized, truncated, invalidLength, invalidCopy, trailingData }

    static func decode(_ data: Data) throws -> Data {
        try Task.checkCancellation()
        guard data.count <= 8 * 1024 * 1024 else { throw Failure.oversized }
        let bytes = Array(data)
        var offset = 0
        func takeByte() throws -> UInt8 {
            guard offset < bytes.count else { throw Failure.truncated }
            defer { offset += 1 }
            return bytes[offset]
        }
        func fixed(_ count: Int) throws -> UInt64 {
            var value: UInt64 = 0
            for index in 0..<count { value |= UInt64(try takeByte()) << (index * 8) }
            return value
        }
        var declared: UInt32 = 0
        var lengthComplete = false
        for index in 0..<5 {
            let byte = try takeByte()
            guard index != 4 || byte <= 15 else { throw Failure.invalidLength }
            declared |= UInt32(byte & 0x7F) << (index * 7)
            if byte & 0x80 == 0 { lengthComplete = true; break }
        }
        guard lengthComplete else { throw Failure.invalidLength }
        guard declared <= 4 * 1024 * 1024 else { throw Failure.oversized }
        let expected = Int(declared)
        var output: [UInt8] = []
        output.reserveCapacity(expected)
        while output.count < expected {
            try Task.checkCancellation()
            let tag = try takeByte()
            let kind = tag & 3
            if kind == 0 {
                let encoded = Int(tag >> 2)
                let length: Int
                if encoded < 60 { length = encoded + 1 }
                else {
                    let extended = try fixed(encoded - 59)
                    guard extended < UInt64(expected - output.count) else { throw Failure.invalidLength }
                    length = Int(extended) + 1
                }
                guard length <= expected - output.count else { throw Failure.invalidLength }
                guard length <= bytes.count - offset else { throw Failure.truncated }
                output.append(contentsOf: bytes[offset..<(offset + length)])
                offset += length
            } else {
                let length: Int
                let distance: UInt64
                if kind == 1 {
                    length = 4 + Int((tag >> 2) & 7)
                    distance = (UInt64(tag & 0xE0) << 3) | UInt64(try takeByte())
                } else {
                    length = 1 + Int(tag >> 2)
                    distance = try fixed(kind == 2 ? 2 : 4)
                }
                guard distance > 0, distance <= UInt64(output.count) else { throw Failure.invalidCopy }
                guard length <= expected - output.count else { throw Failure.invalidLength }
                // Recompute the source as output grows: overlapping copies implement Snappy RLE.
                for _ in 0..<length { output.append(output[output.count - Int(distance)]) }
            }
        }
        guard offset == bytes.count else { throw Failure.trailingData }
        try Task.checkCancellation()
        return Data(output)
    }
}
#endif
