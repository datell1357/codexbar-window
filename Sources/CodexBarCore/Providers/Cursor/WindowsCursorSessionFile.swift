#if os(Windows)
import Foundation

/// Only encrypted Windows sessions are accepted; plaintext imports require a separate explicit flow.
enum WindowsCursorSessionFile {
    enum Failure: Error { case unsupportedFormat }
    private static let header = Data("CodexBar.Cursor.DPAPI.v1\n".utf8)

    static func write(_ plaintext: Data, to url: URL) throws {
        let encrypted = try WindowsTokenAccountProtection.cursorSession(plaintext, protect: true)
        try CredentialFileWriter.writePrivate(self.header + encrypted, to: url)
    }

    static func read(from url: URL) throws -> Data? {
        guard let stored = try WindowsBoundedFileReader.readIfPresent(at: url, maximumBytes: 16 * 1024 * 1024) else { return nil }
        guard stored.starts(with: self.header), stored.count > self.header.count else { throw Failure.unsupportedFormat }
        return try WindowsTokenAccountProtection.cursorSession(Data(stored.dropFirst(self.header.count)), protect: false)
    }
}
#endif
