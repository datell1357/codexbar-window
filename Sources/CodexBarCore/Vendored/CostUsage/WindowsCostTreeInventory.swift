import Foundation

/// Durable tree candidates and observations. Only the active directory needs a live handle;
/// completed directories survive process restart. An interrupted directory is replayed in full.
struct CostUsageWindowsTreeInventory: Codable, Equatable, Sendable {
    struct Directory: Codable, Equatable, Sendable {
        let path: String
        var snapshot: CostUsageFileReadSnapshot?
    }
    enum Phase: String, Codable, Sendable { case enumerating, directories, files, complete }

    var version = 1
    let roots: [String]
    let policy: String
    var pending: [Directory]
    var nextDirectory = 0
    var page: CostUsageWindowsDirectoryPageState?
    var activeChildrenStart: Int?
    var directories: [String: CostUsageFileReadSnapshot] = [:]
    var missingRoots: Set<String> = []
    var visited: [String: CostUsageFileReadSnapshot] = [:]
    // Keep all aliases for publication, not just the representative used for aggregation.
    var files: [String: CostUsageClaudeFileStamp] = [:]
    var phase: Phase = .enumerating
    var validationDirectories: [String] = []
    var validationFiles: [String] = []
    var validationIndex = 0
    /// Durable cursor for the bounded post-completion revalidation pass, counted in leading
    /// entries of the canonical frozen publication. nil means no pass is mid-flight; a pass
    /// that reaches the end wraps to nil so the next refresh starts a fresh cycle.
    var publicationCheckedCount: Int? = nil

    init(roots: [URL], policy: String = "all-jsonl-v1") {
        self.roots = Array(Set(roots.map(\.standardizedFileURL.path))).sorted()
        self.policy = policy
        self.pending = self.roots.map { Directory(path: $0, snapshot: nil) }
    }
}

#if os(Windows)
enum WindowsCostTreeInventory {
    struct Progress {
        let work: Int
        let isComplete: Bool
    }

    /// Work counts raw native enumeration attempts and final metadata rechecks, including
    /// ignored entries and empty/missing/aliased directories. It is not a byte/time I/O budget.
    static func advance(
        _ state: inout CostUsageWindowsTreeInventory,
        maxWork: Int,
        pages: WindowsCostDirectoryPages = .shared,
        descendIntoDirectory: ((URL) -> Bool)? = nil,
        checkCancellation: (() throws -> Void)? = nil) throws -> Progress
    {
        guard state.version == 1, (0...state.pending.count).contains(state.nextDirectory),
              state.validationIndex >= 0,
              state.validationIndex <= (state.phase == .files ? state.validationFiles.count
                  : state.phase == .directories ? state.validationDirectories.count : 0)
        else { throw WindowsCostSourceInventory.Failure.sourceChanged }
        if let start = state.activeChildrenStart {
            guard state.phase == .enumerating, start > state.nextDirectory, start <= state.pending.count else {
                throw WindowsCostSourceInventory.Failure.sourceChanged
            }
        } else if state.page != nil {
            throw WindowsCostSourceInventory.Failure.sourceChanged
        }
        let knownPaths = state.pending.map(\.path)
        var known = Set(knownPaths)
        guard known.count == knownPaths.count,
              Set(state.roots).isSubset(of: known),
              state.missingRoots.isSubset(of: Set(state.roots)),
              known.allSatisfy({ self.isWithinRoots($0, roots: state.roots) }),
              state.files.keys.allSatisfy({ self.isWithinRoots($0, roots: state.roots) }),
              state.directories.keys.allSatisfy(known.contains),
              state.pending.allSatisfy({ $0.snapshot?.isValidWindowsObservation != false }),
              state.directories.values.allSatisfy(\.isValidWindowsObservation),
              state.visited.values.allSatisfy(\.isValidWindowsObservation),
              state.files.values.allSatisfy({ CostUsageFileReadSnapshot(claude: $0).isValidWindowsObservation })
        else { throw WindowsCostSourceInventory.Failure.sourceChanged }
        var work = 0
        while true {
            try self.check(checkCancellation)
            switch state.phase {
            case .enumerating:
                if state.nextDirectory == state.pending.count {
                    state.validationDirectories = (Array(state.directories.keys) + Array(state.missingRoots)).sorted()
                    state.validationFiles = state.files.keys.sorted()
                    state.validationIndex = 0
                    state.phase = .directories
                    continue
                }
                guard work < maxWork else { return Progress(work: work, isComplete: false) }
                let index = state.nextDirectory
                let candidate = state.pending[index]
                let directory = URL(fileURLWithPath: candidate.path, isDirectory: true)
                // Preflight and the first raw visit share one unit, so maxWork == 1 progresses.
                work += 1
                guard let native = try WindowsCostFileMetadata.atURL(directory) else {
                    guard candidate.snapshot == nil, state.roots.contains(candidate.path) else {
                        throw WindowsCostSourceInventory.Failure.sourceChanged
                    }
                    pages.discard(state.page)
                    state.page = nil
                    state.activeChildrenStart = nil
                    state.missingRoots.insert(candidate.path)
                    state.nextDirectory += 1
                    continue
                }
                guard native.isDirectory else { throw WindowsCostSourceInventory.Failure.unreadableDirectory }
                let snapshot = CostUsageFileReadSnapshot(native: native)
                if let expected = candidate.snapshot, snapshot != expected {
                    throw WindowsCostSourceInventory.Failure.sourceChanged
                }
                state.pending[index].snapshot = snapshot
                state.directories[candidate.path] = snapshot
                if let prior = state.visited[snapshot.fileID] {
                    guard prior == snapshot else { throw WindowsCostSourceInventory.Failure.sourceChanged }
                    pages.discard(state.page)
                    state.page = nil
                    state.activeChildrenStart = nil
                    state.nextDirectory += 1
                    continue
                }
                if !state.roots.contains(candidate.path), descendIntoDirectory?(directory) == false {
                    state.nextDirectory += 1
                    continue
                }
                if state.activeChildrenStart == nil { state.activeChildrenStart = state.pending.count }
                let page = try pages.read(
                    in: directory, continuation: state.page, visitLimit: min(256, maxWork - work + 1),
                    checkCancellation: checkCancellation)
                guard page.directorySnapshot == native else { throw WindowsCostSourceInventory.Failure.sourceChanged }
                work += max(0, page.visits - 1)
                state.page = page.continuation
                for entry in page.entries {
                    try self.check(checkCancellation)
                    let path = entry.url.standardizedFileURL.path
                    if entry.snapshot.isDirectory {
                        let observed = CostUsageFileReadSnapshot(native: entry.snapshot)
                        if let previous = state.directories[path], previous != observed {
                            throw WindowsCostSourceInventory.Failure.sourceChanged
                        }
                        state.directories[path] = observed
                        if known.insert(path).inserted {
                            state.pending.append(.init(path: path, snapshot: observed))
                        }
                    } else {
                        let observed = CostUsageClaudeFileStamp(
                            fileID: entry.snapshot.fileID, size: entry.snapshot.size,
                            modifiedSeconds: entry.snapshot.modifiedSeconds,
                            modifiedNanoseconds: entry.snapshot.modifiedNanoseconds)
                        if let previous = state.files[path],
                           !CostUsageSourcePublication.allowsAppend(
                               .init(claude: observed), from: .init(claude: previous)) {
                            throw WindowsCostSourceInventory.Failure.sourceChanged
                        }
                        state.files[path] = observed
                    }
                }
                if page.continuation == nil {
                    state.visited[snapshot.fileID] = snapshot
                    state.nextDirectory += 1
                    // Choose directory aliases only after the whole parent has been listed.
                    // Sorting a page alone would make traversal depend on native page boundaries.
                    if let start = state.activeChildrenStart {
                        state.pending[start...].sort { $0.path < $1.path }
                    }
                    state.activeChildrenStart = nil
                }
            case .directories:
                if state.validationIndex == state.validationDirectories.count {
                    state.phase = .files
                    state.validationIndex = 0
                    continue
                }
                guard work < maxWork else { return Progress(work: work, isComplete: false) }
                work += 1
                let path = state.validationDirectories[state.validationIndex]
                let observed = try WindowsCostFileMetadata.atURL(URL(fileURLWithPath: path, isDirectory: true))
                if state.missingRoots.contains(path) {
                    guard observed == nil else { throw WindowsCostSourceInventory.Failure.sourceChanged }
                } else {
                    guard let observed, observed.isDirectory,
                          CostUsageFileReadSnapshot(native: observed) == state.directories[path]
                    else { throw WindowsCostSourceInventory.Failure.sourceChanged }
                }
                state.validationIndex += 1
            case .files:
                if state.validationIndex == state.validationFiles.count {
                    state.phase = .complete
                    state.validationIndex = 0
                    continue
                }
                guard work < maxWork else { return Progress(work: work, isComplete: false) }
                work += 1
                let path = state.validationFiles[state.validationIndex]
                guard let stamp = state.files[path] else { throw WindowsCostSourceInventory.Failure.sourceChanged }
                guard let current = try WindowsCostFileMetadata.atURL(URL(fileURLWithPath: path)),
                      !current.isDirectory,
                      CostUsageSourcePublication.allowsAppend(.init(native: current), from: .init(claude: stamp))
                else { throw WindowsCostSourceInventory.Failure.sourceChanged }
                state.files[path] = CostUsageClaudeFileStamp(
                    fileID: current.fileID, size: current.size,
                    modifiedSeconds: current.modifiedSeconds, modifiedNanoseconds: current.modifiedNanoseconds)
                state.validationIndex += 1
            case .complete:
                return Progress(work: work, isComplete: true)
            }
        }
    }

    static func observe(
        _ state: CostUsageWindowsTreeInventory,
        in observations: CostUsagePublicationObservations,
        checkCancellation: (() throws -> Void)? = nil) throws
    {
        guard state.phase == .complete, state.page == nil, state.nextDirectory == state.pending.count else {
            throw WindowsCostSourceInventory.Failure.sourceChanged
        }
        for (path, snapshot) in state.directories {
            try self.check(checkCancellation)
            try observations.directory(URL(fileURLWithPath: path, isDirectory: true), snapshot: snapshot)
        }
        for path in state.missingRoots {
            try self.check(checkCancellation)
            try observations.missing(URL(fileURLWithPath: path, isDirectory: true))
        }
        for (path, stamp) in state.files {
            try self.check(checkCancellation)
            try observations.file(URL(fileURLWithPath: path), snapshot: .init(claude: stamp))
        }
    }

    static func representatives(
        _ state: CostUsageWindowsTreeInventory,
        checkCancellation: (() throws -> Void)? = nil) throws -> [URL: CostUsageClaudeFileStamp]
    {
        guard state.phase == .complete else { throw WindowsCostSourceInventory.Failure.sourceChanged }
        var owners: [String: CostUsageClaudeFileStamp] = [:]
        var files: [URL: CostUsageClaudeFileStamp] = [:]
        for path in state.files.keys.sorted() {
            try self.check(checkCancellation)
            guard let stamp = state.files[path] else { continue }
            if let previous = owners[stamp.fileID] {
                // Aliases can be observed on separate pages while the same log grows.
                let lhs = CostUsageFileReadSnapshot(claude: previous)
                let rhs = CostUsageFileReadSnapshot(claude: stamp)
                guard CostUsageSourcePublication.allowsAppend(lhs, from: rhs)
                    || CostUsageSourcePublication.allowsAppend(rhs, from: lhs)
                else { throw WindowsCostSourceInventory.Failure.sourceChanged }
            } else {
                owners[stamp.fileID] = stamp
                files[URL(fileURLWithPath: path)] = stamp
            }
        }
        return files
    }

    private static func isWithinRoots(_ path: String, roots: [String]) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard url.standardizedFileURL.path == path else { return false }
        return roots.contains { root in
            path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
        }
    }

    private static func check(_ callback: (() throws -> Void)?) throws {
        try Task.checkCancellation()
        try callback?()
    }
}
#endif
