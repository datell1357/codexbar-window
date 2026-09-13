#if os(Windows)
import Foundation

/// A bounded immutable SSTable image. Block entries and index traversal are decoded separately.
struct WindowsLevelDBTableContainer: Sendable {
    struct Handle: Sendable, Equatable {
        let offset: UInt64
        let size: UInt64
    }
    enum Failure: Error { case oversized, invalidFooter, invalidHandle, checksumMismatch, unsupportedCompression }
    let metaindex: Handle
    let index: Handle
    private let bytes: [UInt8]

    init(data: Data) throws {
        try Task.checkCancellation()
        guard data.count <= 64 * 1024 * 1024 else { throw Failure.oversized }
        guard data.count >= 48 else { throw Failure.invalidFooter }
        let bytes = Array(data)
        let footerStart = bytes.count - 48
        var magic: UInt64 = 0
        for i in 0..<8 { magic |= UInt64(bytes[bytes.count - 8 + i]) << (8 * i) }
        guard magic == 0xDB4775248B80FB57 else { throw Failure.invalidFooter }
        let handles = Array(bytes[footerStart..<(bytes.count - 8)])
        var position = 0
        self.metaindex = try Self.readHandle(handles, position: &position)
        self.index = try Self.readHandle(handles, position: &position)
        guard handles[position...].allSatisfy({ $0 == 0 }) else { throw Failure.invalidFooter }
        self.bytes = bytes
        try self.check(self.metaindex)
        try self.check(self.index)
        try Task.checkCancellation()
    }

    static func decodeHandle(_ data: Data) throws -> Handle {
        guard data.count <= 20 else { throw Failure.invalidHandle }
        let bytes = Array(data)
        var position = 0
        let result = try self.readHandle(bytes, position: &position)
        guard position == bytes.count else { throw Failure.invalidHandle }
        return result
    }

    func block(_ handle: Handle) throws -> Data {
        try Task.checkCancellation()
        try self.check(handle)
        let start = Int(handle.offset)
        let end = start + Int(handle.size)
        let compression = self.bytes[end]
        var stored: UInt32 = 0
        for i in 0..<4 { stored |= UInt32(self.bytes[end + 1 + i]) << (8 * i) }
        guard WindowsLevelDBChecksum.maskedCRC(self.bytes[start...end]) == stored else { throw Failure.checksumMismatch }
        let payload = Data(self.bytes[start..<end])
        let result: Data
        switch compression {
        case 0:
            guard payload.count <= 4 * 1024 * 1024 else { throw Failure.oversized }
            result = payload
        case 1: result = try WindowsLevelDBSnappy.decode(payload)
        default: throw Failure.unsupportedCompression
        }
        try Task.checkCancellation()
        return result
    }

    private func check(_ handle: Handle) throws {
        let limit = UInt64(self.bytes.count - 48)
        guard handle.offset <= limit, handle.size <= limit - handle.offset,
              limit - handle.offset - handle.size >= 5 else { throw Failure.invalidHandle }
        guard handle.size <= 8 * 1024 * 1024 else { throw Failure.oversized }
    }

    private static func readHandle(_ bytes: [UInt8], position: inout Int) throws -> Handle {
        func number() throws -> UInt64 {
            var result: UInt64 = 0
            for i in 0..<10 {
                guard position < bytes.count else { throw Failure.invalidHandle }
                let byte = bytes[position]
                position += 1
                guard i != 9 || byte <= 1 else { throw Failure.invalidHandle }
                result |= UInt64(byte & 0x7F) << (i * 7)
                if byte & 0x80 == 0 { return result }
            }
            throw Failure.invalidHandle
        }
        let offset = try number()
        let size = try number()
        return Handle(offset: offset, size: size)
    }
}
#endif
