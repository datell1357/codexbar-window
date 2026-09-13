#if os(Windows)
import Foundation

/// Schema-1 localStorage extraction for explicitly requested first-party origins and ASCII keys.
/// Partitioned storage keys are deliberately not folded into their embedded origin.
enum WindowsChromiumLocalStorageDecoder {
    enum Failure: Error { case unsupportedSchema, invalidRequest, invalidString, duplicateKey, oversized }

    static func values(
        in snapshot: WindowsLevelDBSnapshot.Snapshot,
        origin: String,
        keys: Set<String>) throws -> [String: String]
    {
        try Task.checkCancellation()
        guard snapshot.entries[Data("VERSION".utf8)]?.value == Data("1".utf8) else {
            throw Failure.unsupportedSchema
        }
        // Callers provide canonical serialized origins, never arbitrary storage-key prefixes.
        guard origin.utf8.count <= 2048,
              origin.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7E }),
              let components = URLComponents(string: origin), components.scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.path.isEmpty, components.query == nil, components.fragment == nil,
              !origin.contains("^"), !origin.contains("\\"),
              keys.count <= 64,
              keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 &&
                  $0.utf8.allSatisfy { $0 >= 0x21 && $0 <= 0x7E } }) else { throw Failure.invalidRequest }
        let prefix = Data(("_" + origin + "\0").utf8)
        var result: [String: String] = [:]
        var budget = 1024 * 1024
        for (rawKey, mutation) in snapshot.entries {
            try Task.checkCancellation()
            guard rawKey.starts(with: prefix), let rawValue = mutation.value else { continue }
            let key = try self.string(Data(rawKey.dropFirst(prefix.count)))
            // Compare exact code units, not Swift's canonically equivalent String equality.
            guard let requestedKey = keys.first(where: { $0.utf16.elementsEqual(key.utf16) }) else { continue }
            guard result[requestedKey] == nil else { throw Failure.duplicateKey }
            let value = try self.string(rawValue)
            guard value.utf8.count <= budget else { throw Failure.oversized }
            budget -= value.utf8.count
            result[requestedKey] = value
        }
        return result
    }

    static func string(_ data: Data) throws -> String {
        guard data.count <= 4 * 1024 * 1024 else { throw Failure.oversized }
        try Task.checkCancellation()
        // Chromium treats a zero-length encoded vector as the empty string.
        guard let format = data.first else { return "" }
        let payload = Array(data.dropFirst())
        switch format {
        case 1:
            var output = String.UnicodeScalarView()
            for (index, byte) in payload.enumerated() {
                if index % 4096 == 0 { try Task.checkCancellation() }
                output.append(Unicode.Scalar(UInt32(byte))!)
            }
            return String(output)
        case 0:
            guard payload.count % 2 == 0 else { throw Failure.invalidString }
            var units: [UInt16] = []
            units.reserveCapacity(payload.count / 2)
            for index in stride(from: 0, to: payload.count, by: 2) {
                if index % 4096 == 0 { try Task.checkCancellation() }
                units.append(UInt16(payload[index]) | UInt16(payload[index + 1]) << 8)
            }
            // Windows uses little-endian UTF-16. Reject unpaired surrogates instead of
            // replacing bytes in a credential with U+FFFD and silently changing it.
            var index = 0
            while index < units.count {
                if index % 4096 == 0 { try Task.checkCancellation() }
                let unit = units[index]
                if (0xD800...0xDBFF).contains(unit) {
                    guard index + 1 < units.count, (0xDC00...0xDFFF).contains(units[index + 1]) else {
                        throw Failure.invalidString
                    }
                    index += 2
                } else {
                    guard !(0xDC00...0xDFFF).contains(unit) else { throw Failure.invalidString }
                    index += 1
                }
            }
            return String(decoding: units, as: UTF16.self)
        default:
            throw Failure.invalidString
        }
    }
}
#endif
