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

    /// Empty encrypted JSON is a durable revocation record understood by the normal reader.
    /// If replacement fails, successful removal can still complete logout.
    static func revoke(at url: URL) throws {
        var replaced = false
        do {
            try self.write(Data("[]".utf8), to: url)
            replaced = true
        } catch {
            // Continue to removal: failure to encrypt does not imply failure to delete.
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
            return
        } catch {
            // A retained, encrypted empty session cannot restore the previous cookie values.
            guard replaced else { throw error }
        }
    }

    static func read(from url: URL) throws -> Data? {
        guard let stored = try WindowsBoundedFileReader.readIfPresent(at: url, maximumBytes: 16 * 1024 * 1024) else { return nil }
        guard stored.starts(with: self.header), stored.count > self.header.count else { throw Failure.unsupportedFormat }
        return try WindowsTokenAccountProtection.cursorSession(Data(stored.dropFirst(self.header.count)), protect: false)
    }
}
#endif
