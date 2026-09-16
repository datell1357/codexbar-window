#if os(Windows)
import Foundation

/// One complete directory listing for callers that require inventory proof rather than a page.
/// An existing directory's failure/change never becomes an empty successful listing.
enum WindowsCostDirectoryInventory {
    struct Entry {
        let url: URL
        let snapshot: WindowsCostFileMetadata.Snapshot
    }

    struct Listing {
        let directorySnapshot: WindowsCostFileMetadata.Snapshot
        let entries: [Entry]
    }

    static func read(
        in directory: URL,
        includeDirectories: Bool = true,
        checkCancellation: (() throws -> Void)? = nil,
        publicationObservations: CostUsagePublicationObservations? = nil) throws -> Listing?
    {
        try self.check(checkCancellation)
        guard let snapshot = try WindowsCostFileMetadata.atURL(directory) else {
            try publicationObservations?.missing(directory)
            return nil
        }
        guard snapshot.isDirectory else { throw WindowsCostSourceInventory.Failure.unreadableDirectory }
        let cursor = try WindowsCostDirectoryCursor(directoryURL: directory, snapshot: snapshot)
        var entries: [Entry] = []
        while let entry = try cursor.next() {
            try self.check(checkCancellation)
            guard !entry.isHidden, !entry.name.hasPrefix(".") else { continue }
            if entry.isDirectory {
                guard includeDirectories else { continue }
            } else {
                guard entry.name.lowercased().hasSuffix(".jsonl") else { continue }
            }
            let url = directory.appendingPathComponent(entry.name, isDirectory: entry.isDirectory)
            guard let observed = try WindowsCostFileMetadata.atURL(url),
                  observed.isDirectory == entry.isDirectory
            else { throw WindowsCostSourceInventory.Failure.sourceChanged }
            entries.append(Entry(url: url, snapshot: observed))
        }
        for entry in entries {
            try self.check(checkCancellation)
            guard try WindowsCostFileMetadata.atURL(entry.url) == entry.snapshot else {
                throw WindowsCostSourceInventory.Failure.sourceChanged
            }
        }
        try self.check(checkCancellation)
        guard try WindowsCostFileMetadata.atURL(directory) == snapshot else {
            throw WindowsCostSourceInventory.Failure.sourceChanged
        }
        try publicationObservations?.directory(directory, snapshot: .init(native: snapshot))
        for entry in entries {
            if entry.snapshot.isDirectory {
                try publicationObservations?.directory(entry.url, snapshot: .init(native: entry.snapshot))
            } else {
                try publicationObservations?.file(entry.url, snapshot: .init(native: entry.snapshot))
            }
        }
        return Listing(directorySnapshot: snapshot, entries: entries)
    }

    private static func check(_ checkCancellation: (() throws -> Void)?) throws {
        try Task.checkCancellation()
        try checkCancellation?()
    }
}
#endif
