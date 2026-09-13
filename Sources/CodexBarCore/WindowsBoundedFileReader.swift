#if os(Windows)
import Foundation

/// Reads at most a caller-specified limit plus one overflow byte. Errors never become empty data.
public enum WindowsBoundedFileReader {
    public enum Failure: Error { case invalidLimit, tooLarge }

    public static func readIfPresent(at url: URL, maximumBytes: Int) throws -> Data? {
        guard maximumBytes > 0, maximumBytes <= 64 * 1024 * 1024 else { throw Failure.invalidLimit }
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError) { return nil }
        var closed = false
        defer { if !closed { try? handle.close() } }
        var data = Data()
        while true {
            let remaining = maximumBytes - data.count
            let count = min(65_536, remaining + 1)
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else {
                try handle.close()
                closed = true
                return data
            }
            guard chunk.count <= remaining else { throw Failure.tooLarge }
            data.append(chunk)
        }
    }
}
#endif
