#if os(Windows)
import Foundation

/// One manifest logical record; applying records to a live-file set is a separate operation.
/// Format: google/leveldb db/version_edit.cc.
enum WindowsLevelDBVersionEdit {
    struct FileID: Hashable, Sendable {
        let level: Int
        let number: UInt64
    }
    struct Table: Sendable, Equatable {
        let id: FileID
        let size: UInt64
        let smallest: Data
        let largest: Data
    }
    struct Edit: Sendable {
        var comparator: Data?
        var logNumber: UInt64?
        var previousLogNumber: UInt64?
        var nextFileNumber: UInt64?
        var lastSequence: UInt64?
        var compactPointers: [(level: Int, key: Data)] = []
        var deletedFiles: Set<FileID> = []
        var newFiles: [Table] = []
    }
    enum Failure: Error { case oversized, truncated, invalidVarint, unknownTag, duplicateField, invalidLevel, invalidSequence }

    static func decode(_ data: Data) throws -> Edit {
        try Task.checkCancellation()
        guard data.count <= 4 * 1024 * 1024 else { throw Failure.oversized }
        var reader = Reader(bytes: Array(data))
        var edit = Edit()
        var singletons = Set<UInt64>()
        var newIDs = Set<FileID>()
        var fieldCount = 0
        while reader.offset < reader.bytes.count {
            try Task.checkCancellation()
            fieldCount += 1
            guard fieldCount <= 100_000 else { throw Failure.oversized }
            let tag = try reader.varint(bits: 32)
            if [UInt64(1), 2, 3, 4, 9].contains(tag) {
                guard singletons.insert(tag).inserted else { throw Failure.duplicateField }
            }
            switch tag {
            case 1: edit.comparator = try reader.string()
            case 2: edit.logNumber = try reader.varint(bits: 64)
            case 3: edit.nextFileNumber = try reader.varint(bits: 64)
            case 4:
                let sequence = try reader.varint(bits: 64)
                guard sequence <= WindowsLevelDBWriteBatch.maximumSequence else { throw Failure.invalidSequence }
                edit.lastSequence = sequence
            case 5:
                let level = try reader.level()
                let key = try reader.internalKey()
                edit.compactPointers.append((level: level, key: key))
            case 6:
                let id = try FileID(level: reader.level(), number: reader.varint(bits: 64))
                edit.deletedFiles.insert(id)
            case 7:
                let id = try FileID(level: reader.level(), number: reader.varint(bits: 64))
                guard newIDs.insert(id).inserted else { throw Failure.duplicateField }
                let size = try reader.varint(bits: 64)
                let smallest = try reader.internalKey()
                let largest = try reader.internalKey()
                edit.newFiles.append(Table(id: id, size: size, smallest: smallest, largest: largest))
            case 9: edit.previousLogNumber = try reader.varint(bits: 64)
            default: throw Failure.unknownTag
            }
        }
        try Task.checkCancellation()
        return edit
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0
        mutating func varint(bits: Int) throws -> UInt64 {
            let limit = bits == 32 ? 5 : 10
            var value: UInt64 = 0
            for index in 0..<limit {
                guard offset < bytes.count else { throw Failure.truncated }
                let byte = bytes[offset]
                offset += 1
                if index == limit - 1, byte > (bits == 32 ? 15 : 1) { throw Failure.invalidVarint }
                value |= UInt64(byte & 0x7F) << (index * 7)
                if byte & 0x80 == 0 { return value }
            }
            throw Failure.invalidVarint
        }
        mutating func level() throws -> Int {
            let value = try self.varint(bits: 32)
            guard value < 7 else { throw Failure.invalidLevel }
            return Int(value)
        }
        mutating func string() throws -> Data {
            let length = try self.varint(bits: 32)
            guard length <= UInt64(bytes.count - offset) else { throw Failure.truncated }
            let end = offset + Int(length)
            defer { offset = end }
            return Data(bytes[offset..<end])
        }
        mutating func internalKey() throws -> Data {
            let key = try self.string()
            _ = try WindowsLevelDBVersions.tableMutation(internalKey: key, value: Data())
            return key
        }
    }
}
#endif
