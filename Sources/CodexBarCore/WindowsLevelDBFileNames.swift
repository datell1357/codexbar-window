#if os(Windows)
import Foundation

/// Resolves only LevelDB basenames. Never interprets CURRENT as a filesystem path.
enum WindowsLevelDBFileNames {
    enum Kind: Hashable, Sendable { case manifest, table, log }
    struct Numbered: Hashable, Sendable {
        let kind: Kind
        let number: UInt64
    }
    enum Failure: Error { case invalidCurrent, invalidName, ambiguousNumber, oversized }

    static func currentManifest(_ data: Data) throws -> String {
        guard data.count <= 64, data.last == 10,
              let name = String(data: data.dropLast(), encoding: .ascii),
              let file = self.numbered(name), file.kind == .manifest else { throw Failure.invalidCurrent }
        return name
    }

    static func inventory(_ names: [String]) throws -> [Numbered: String] {
        guard names.count <= 100_000 else { throw Failure.oversized }
        var files: [Numbered: String] = [:]
        for name in names {
            try Task.checkCancellation()
            guard !name.isEmpty, name.utf16.count <= 255,
                  !name.contains("/"), !name.contains("\\"), !name.contains(":"),
                  !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { throw Failure.invalidName }
            guard let file = self.numbered(name) else { continue }
            // .ldb/.sst aliases and zero-padded aliases must not silently select different bytes.
            guard files[file] == nil else { throw Failure.ambiguousNumber }
            files[file] = name
        }
        return files
    }

    static func numbered(_ name: String) -> Numbered? {
        let kind: Kind
        let digits: Substring
        if name.hasPrefix("MANIFEST-") {
            kind = .manifest
            digits = name.dropFirst(9)
        } else if name.hasSuffix(".ldb") || name.hasSuffix(".sst") {
            kind = .table
            digits = name.dropLast(4)
        } else if name.hasSuffix(".log") {
            kind = .log
            digits = name.dropLast(4)
        } else { return nil }
        guard !digits.isEmpty, digits.utf8.count <= 20,
              digits.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = UInt64(digits), number > 0 else { return nil }
        return Numbered(kind: kind, number: number)
    }
}
#endif
