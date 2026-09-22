import Foundation

extension CostUsageScanner {
    // MARK: - Claude

    private struct ClaudeTokens {
        let input: Int
        let cacheRead: Int
        let cacheCreate: Int
        let cacheCreate1h: Int
        let output: Int
        let costNanos: Int
        let costPriced: Bool
    }

    private struct ClaudeDayModelKey: Hashable {
        let day: String
        let model: String
    }

    private struct ClaudeRepricedCost {
        var total: Double = 0
        var sampleCount: Int = 0
        var unresolved = false
    }

    static func defaultClaudeProjectsRoots(
        options: Options,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        workingDirectory: URL? = nil) -> [URL]
    {
        if let override = options.claudeProjectsRoots {
            return override
        }

        var roots: [URL] = []

        if let configuredRoot = environment[ClaudeConfigPaths.configDirectoryEnvironmentKey],
           !configuredRoot.isEmpty
        {
            let root = ClaudeConfigPaths.configRoot(
                environment: environment,
                workingDirectory: workingDirectory)
            roots.append(root.appendingPathComponent("projects", isDirectory: true))
        } else {
            var pathEnvironment = environment
            if pathEnvironment["HOME"]?.isEmpty ?? true {
                pathEnvironment["HOME"] = homeDirectory.path
            }
            let ownerHome = ClaudeConfigPaths.homeDirectory(
                environment: pathEnvironment,
                workingDirectory: workingDirectory)
            let configRoot = ClaudeConfigPaths.configRoot(
                environment: pathEnvironment,
                workingDirectory: workingDirectory)
            roots.append(ownerHome.appendingPathComponent(".config/claude/projects", isDirectory: true))
            roots.append(configRoot.appendingPathComponent("projects", isDirectory: true))
            roots.append(contentsOf: ClaudeDesktopProjectsLocator.roots(
                homeDirectory: ownerHome,
                fileManager: fileManager))
        }

        return self.deduplicatedClaudeProjectRoots(roots)
    }

    private static func deduplicatedClaudeProjectRoots(_ roots: [URL]) -> [URL] {
        var seen: Set<String> = []
        var out: [URL] = []
        for root in roots {
            let standardized = root.standardizedFileURL
            let path = standardized.path
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            out.append(standardized)
        }
        return out
    }

    static func parseClaudeFile(
        fileURL: URL,
        range: CostUsageDayRange,
        providerFilter: ClaudeLogProviderFilter,
        startOffset: Int64 = 0,
        modelsDevCatalog: ModelsDevCatalog? = nil,
        modelsDevCacheRoot: URL? = nil) -> ClaudeParseResult
    {
        let pricingResolver = modelsDevCatalog.map { CostUsagePricing.ClaudeResolver(catalog: $0) }
            ?? CostUsagePricing.ClaudeResolver(now: Date(), cacheRoot: modelsDevCacheRoot)
        return (
            try? self.parseClaudeFileCancellable(
                fileURL: fileURL,
                range: range,
                providerFilter: providerFilter,
                startOffset: startOffset,
                pricingResolver: pricingResolver,
                checkCancellation: nil)) ?? ClaudeParseResult(rows: [], parsedBytes: startOffset)
    }

    static func parseClaudeFileCancellable(
        fileURL: URL,
        range: CostUsageDayRange,
        providerFilter: ClaudeLogProviderFilter,
        startOffset: Int64 = 0,
        pricingResolver: CostUsagePricing.ClaudeResolver,
        expectedFile: CostUsageFileReadSnapshot? = nil,
        expectedPrefixAnchor: CostUsageCodexTokenIndexAnchor? = nil,
        maxBytesToRead: Int64? = nil,
        resumeState: CostUsageJsonl.ResumeState? = nil,
        expectedCommittedAnchor: CostUsageCodexTokenIndexAnchor? = nil,
        windowsContentContinuation: UUID? = nil,
        checkCancellation: CancellationCheck? = nil) throws -> ClaudeParseResult
    {
        let readSnapshot = try expectedFile ?? CostUsageFileReadSnapshot.capture(at: fileURL)
        func toInt(_ v: Any?) -> Int {
            if let n = v as? NSNumber {
                return n.intValue
            }
            return 0
        }

        func toBool(_ value: Any?) -> Bool {
            if let bool = value as? Bool {
                return bool
            }
            if let number = value as? NSNumber {
                return number.boolValue
            }
            return false
        }

        let pathRole = Self.claudePathRole(fileURL: fileURL)
        var keyedRows: [String: ClaudeUsageRow] = [:]
        var unkeyedRows: [ClaudeUsageRow] = []

        let maxLineBytes = 512 * 1024
        // Keep the full line so usage at the tail isn't dropped on large tool outputs.
        let prefixBytes = maxLineBytes
        let costScale = 1_000_000_000.0

        let parsedBytes: Int64
        var windowsReadProof: CostUsageClaudeReadProof?
        var scanProgress: CostUsageJsonl.ScanProgress?
        do {
            let progress = try CostUsageJsonl.scanBounded(
                fileURL: fileURL,
                offset: startOffset,
                maxLineBytes: maxLineBytes,
                prefixBytes: prefixBytes,
                maxBytesToRead: maxBytesToRead,
                resumeState: resumeState,
                expectedFile: readSnapshot,
                captureWindowsContent: true,
                expectedPrefixAnchor: expectedPrefixAnchor,
                expectedCommittedAnchor: expectedCommittedAnchor,
                windowsContentContinuation: windowsContentContinuation,
                retainWindowsContent: maxBytesToRead != nil,
                checkCancellation: checkCancellation,
                onLine: { line in
                    guard !line.bytes.isEmpty else { return }
                    guard !line.wasTruncated else { return }
                    guard line.bytes.containsAscii(#""type":"assistant""#) else { return }
                    guard line.bytes.containsAscii(#""usage""#) else { return }

                    autoreleasepool {
                        guard
                            let obj = try? ClaudeJSONObject.decode(line.bytes),
                            let type = obj["type"] as? String,
                            type == "assistant"
                        else { return }
                        let message = obj.dictionary("message")
                        guard Self.matchesClaudeProviderFilter(obj: obj, message: message, filter: providerFilter)
                        else { return }

                        guard let tsText = obj["timestamp"] as? String,
                              let parsedTimestamp = Self.claudeTimestampAndDayKey(tsText, calendar: range.calendar)
                        else { return }
                        let timestamp = parsedTimestamp.date
                        let dayKey = parsedTimestamp.dayKey

                        guard let message else { return }
                        guard let model = message["model"] as? String else { return }
                        guard let usage = message.dictionary("usage") else { return }

                        let input = max(0, toInt(usage["input_tokens"]))
                        let cacheCreate = max(0, toInt(usage["cache_creation_input_tokens"]))
                        let cacheCreate1h = Self.claudeOneHourCacheCreationTokens(
                            usage: usage,
                            total: cacheCreate)
                        let cacheRead = max(0, toInt(usage["cache_read_input_tokens"]))
                        let output = max(0, toInt(usage["output_tokens"]))
                        if input == 0, cacheCreate == 0, cacheRead == 0, output == 0 {
                            return
                        }

                        let cost = pricingResolver.costUSD(
                            model: model,
                            inputTokens: input,
                            cacheReadInputTokens: cacheRead,
                            cacheCreationInputTokens: cacheCreate,
                            cacheCreationInputTokens1h: cacheCreate1h,
                            outputTokens: output,
                            pricingDate: timestamp)
                        let costNanos = cost.map { Int(($0 * costScale).rounded()) } ?? 0
                        let tokens = ClaudeTokens(
                            input: input,
                            cacheRead: cacheRead,
                            cacheCreate: cacheCreate,
                            cacheCreate1h: cacheCreate1h,
                            output: output,
                            costNanos: costNanos,
                            costPriced: cost != nil)

                        guard CostUsageDayRange.isInRange(
                            dayKey: dayKey,
                            since: range.scanSinceKey,
                            until: range.scanUntilKey)
                        else { return }

                        let messageId = message["id"] as? String
                        let requestId = obj["requestId"] as? String
                        let sessionId = obj["sessionId"] as? String
                            ?? obj["session_id"] as? String
                            ?? obj.dictionary("metadata")?["sessionId"] as? String
                            ?? message.dictionary("metadata")?["sessionId"] as? String
                        let normalizedModel = pricingResolver.normalize(model)
                        let row = ClaudeUsageRow(
                            dayKey: dayKey,
                            model: normalizedModel,
                            sessionId: sessionId,
                            messageId: messageId,
                            requestId: requestId,
                            timestampUnixMs: Int64((timestamp.timeIntervalSince1970 * 1000).rounded()),
                            isSidechain: toBool(obj["isSidechain"]),
                            pathRole: pathRole,
                            input: tokens.input,
                            cacheRead: tokens.cacheRead,
                            cacheCreate: tokens.cacheCreate,
                            cacheCreate1h: tokens.cacheCreate1h,
                            output: tokens.output,
                            costNanos: tokens.costNanos,
                            costPriced: tokens.costPriced)

                        // Streaming chunks share message.id + requestId inside a file.
                        // Keep overwriting so the final cumulative chunk wins.
                        if let messageId, let requestId {
                            let key = "\(messageId):\(requestId)"
                            keyedRows[key] = row
                        } else {
                            // Older logs omit IDs; treat each line as distinct to avoid dropping usage.
                            unkeyedRows.append(row)
                        }
                    }
                })
            parsedBytes = progress.committedOffset
            scanProgress = progress
            #if os(Windows)
            guard let readSnapshot, progress.readOffset <= readSnapshot.size else {
                throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
            }
            if progress.readOffset == readSnapshot.size {
                windowsReadProof = CostUsageClaudeReadProof(
                    source: readSnapshot, parsedBytes: parsedBytes,
                    readAnchor: progress.windowsReadAnchor, committedAnchor: progress.windowsCommittedAnchor)
            }
            #endif
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            #if os(Windows)
            // A failed stream (including a custom cancellation callback) is not a completed
            // parse. Do not publish partial rows with the source's full size/mtime stamp.
            throw error
            #else
            parsedBytes = startOffset
            #endif
        }

        let rows = keyedRows.keys.sorted().compactMap { keyedRows[$0] } + unkeyedRows
        return ClaudeParseResult(
            rows: rows, parsedBytes: parsedBytes, windowsReadProof: windowsReadProof, progress: scanProgress)
    }

    private static func claudeOneHourCacheCreationTokens(usage: ClaudeJSONObject, total: Int) -> Int {
        guard let cacheCreation = usage.dictionary("cache_creation") else { return 0 }
        let tokens = (cacheCreation["ephemeral_1h_input_tokens"] as? NSNumber)?.intValue ?? 0
        return min(total, max(0, tokens))
    }

    private static func claudePathRole(fileURL: URL) -> ClaudePathRole {
        fileURL.path.contains("/subagents/") ? .subagent : .parent
    }

    private static func claudeCanonicalRowKey(_ row: ClaudeUsageRow) -> String? {
        guard let messageId = row.messageId, let requestId = row.requestId else {
            return nil
        }
        return "\(messageId):\(requestId)"
    }

    private static func mergeClaudeRows(existing: [ClaudeUsageRow], delta: [ClaudeUsageRow]) -> [ClaudeUsageRow] {
        var keyedRows: [String: ClaudeUsageRow] = [:]
        var unkeyedRows: [ClaudeUsageRow] = []

        for row in existing {
            if let key = Self.claudeInFileKey(row) {
                keyedRows[key] = row
            } else {
                unkeyedRows.append(row)
            }
        }
        for row in delta {
            if let key = Self.claudeInFileKey(row) {
                keyedRows[key] = row
            } else {
                unkeyedRows.append(row)
            }
        }

        return keyedRows.keys.sorted().compactMap { keyedRows[$0] } + unkeyedRows
    }

    private static func claudeInFileKey(_ row: ClaudeUsageRow) -> String? {
        guard let messageId = row.messageId, let requestId = row.requestId else { return nil }
        return "\(messageId):\(requestId)"
    }

    private static func claudeRowWins(
        lhs: (path: String, row: ClaudeUsageRow),
        rhs: (path: String, row: ClaudeUsageRow)) -> Bool
    {
        if lhs.row.isSidechain != rhs.row.isSidechain {
            return rhs.row.isSidechain
        }
        if lhs.row.pathRole != rhs.row.pathRole {
            return rhs.row.pathRole == .subagent
        }
        return lhs.path < rhs.path
    }

    private static func reconciledClaudeRows(cache: CostUsageCache) -> [ClaudeUsageRow] {
        #if DEBUG
        recordClaudeScanWork(.reconcile)
        #endif
        var rows: [ClaudeUsageRow] = []
        var winners: [String: (path: String, row: ClaudeUsageRow)] = [:]

        for path in cache.files.keys.sorted() {
            guard let fileRows = cache.files[path]?.claudeRows else { continue }
            for row in fileRows {
                guard let canonicalKey = Self.claudeCanonicalRowKey(row) else {
                    rows.append(row)
                    continue
                }
                let candidate = (path: path, row: row)
                if let existing = winners[canonicalKey] {
                    if Self.claudeRowWins(lhs: candidate, rhs: existing) {
                        winners[canonicalKey] = candidate
                    }
                } else {
                    winners[canonicalKey] = candidate
                }
            }
        }

        rows.append(contentsOf: winners.keys.sorted().compactMap { winners[$0]?.row })
        return rows
    }

    private static func rebuildClaudeDays(cache: inout CostUsageCache) {
        var days: [String: [String: [Int]]] = [:]

        for row in Self.reconciledClaudeRows(cache: cache) {
            var dayModels = days[row.dayKey] ?? [:]
            var packed = dayModels[row.model] ?? [0, 0, 0, 0, 0, 0, 0, 0]
            packed[0] = (packed[safe: 0] ?? 0) + row.input
            packed[1] = (packed[safe: 1] ?? 0) + row.cacheRead
            packed[2] = (packed[safe: 2] ?? 0) + row.cacheCreate
            packed[3] = (packed[safe: 3] ?? 0) + row.output
            packed[4] = (packed[safe: 4] ?? 0) + row.costNanos
            packed[5] = (packed[safe: 5] ?? 0) + 1
            packed[6] = (packed[safe: 6] ?? 0) + ((row.costPriced ?? (row.costNanos > 0)) ? 1 : 0)
            packed[7] = (packed[safe: 7] ?? 0) + (row.cacheCreate1h ?? 0)
            dayModels[row.model] = packed
            days[row.dayKey] = dayModels
        }

        cache.days = days
    }

    private static let vertexProviderKeys: Set<String> = [
        "provider",
        "platform",
        "backend",
        "api_provider",
        "apiprovider",
        "api_type",
        "apitype",
        "source",
        "vendor",
        "client",
    ]

    private static func matchesClaudeProviderFilter(
        obj: ClaudeJSONObject,
        message: ClaudeJSONObject?,
        filter: ClaudeLogProviderFilter) -> Bool
    {
        switch filter {
        case .all:
            true
        case .vertexAIOnly:
            self.isVertexAIUsageEntry(obj: obj, message: message)
        case .excludeVertexAI:
            !self.isVertexAIUsageEntry(obj: obj, message: message)
        }
    }

    static func isVertexAIUsageEntry(obj: Any) -> Bool {
        guard let obj = ClaudeJSONObject(obj) else { return false }
        return self.isVertexAIUsageEntry(obj: obj)
    }

    static func isVertexAIUsageEntry(obj: ClaudeJSONObject) -> Bool {
        self.isVertexAIUsageEntry(obj: obj, message: obj.dictionary("message"))
    }

    private static func isVertexAIUsageEntry(obj: ClaudeJSONObject, message: ClaudeJSONObject?) -> Bool {
        // Primary detection: Vertex AI message IDs and request IDs have "vrtx" prefix
        // e.g., "msg_vrtx_0154LUXjFVzQGUca3yK2RUeo", "req_vrtx_011CWjK86SWeFuXqZKUtgB1H"
        if let messageId = message?["id"] as? String,
           messageId.contains("_vrtx_")
        {
            return true
        }
        if let requestId = obj["requestId"] as? String,
           requestId.contains("_vrtx_")
        {
            return true
        }

        // Secondary detection: model name with @ version separator (Vertex AI format)
        // e.g., "claude-opus-4-5@20251101" vs "claude-opus-4-5-20251101"
        if let model = message?["model"] as? String,
           Self.modelNameLooksVertex(model)
        {
            return true
        }

        // The recursive walk already includes root and message metadata, requests, context, and client.
        return Self.containsVertexAIMetadata(in: obj)
    }

    /// Detects Vertex AI model names by format.
    /// Vertex AI uses @ for version separator: claude-opus-4-5@20251101
    /// Anthropic API uses -: claude-opus-4-5-20251101
    private static func modelNameLooksVertex(_ model: String) -> Bool {
        // Vertex AI model format: claude-{variant}@{version}
        // Examples: claude-opus-4-5@20251101, claude-sonnet-4-5@20250514
        guard model.hasPrefix("claude-") else { return false }
        return model.contains("@")
    }

    private static func containsVertexAIMetadata(in dict: ClaudeJSONObject) -> Bool {
        dict.contains { key, value in
            if self.containsClaudeVertexMarker(key, includeGCP: true) {
                return true
            }
            if self.vertexProviderKeys.contains(key.lowercased()),
               let text = value.string,
               self.containsClaudeVertexMarker(text)
            {
                return true
            }
            if let nested = value.dictionary {
                return self.containsVertexAIMetadata(in: nested)
            }
            // Array elements descend into dictionaries only, never into another array.
            return value.arrayContainsDictionary { self.containsVertexAIMetadata(in: $0) }
        }
    }

    private static func containsClaudeVertexMarker(_ value: String, includeGCP: Bool = false) -> Bool {
        let asciiMatch = value.utf8.withContiguousStorageIfAvailable { bytes -> Bool? in
            // Validate the entire decoded string before matching: a later combining scalar can
            // change Foundation's substring semantics even when the marker itself is ASCII.
            guard bytes.allSatisfy({ $0 < 0x80 }) else { return nil }
            for index in bytes.indices {
                let first = bytes[index] | 0x20
                if first == 0x76, index + 5 < bytes.count, // vertex
                   bytes[index + 1] | 0x20 == 0x65,
                   bytes[index + 2] | 0x20 == 0x72,
                   bytes[index + 3] | 0x20 == 0x74,
                   bytes[index + 4] | 0x20 == 0x65,
                   bytes[index + 5] | 0x20 == 0x78
                {
                    return true
                }
                if includeGCP, first == 0x67, index + 2 < bytes.count, // gcp
                   bytes[index + 1] | 0x20 == 0x63,
                   bytes[index + 2] | 0x20 == 0x70
                {
                    return true
                }
            }
            return false
        }.flatMap(\.self)
        if let asciiMatch {
            return asciiMatch
        }

        let lower = value.lowercased()
        return lower.contains("vertex") || (includeGCP && lower.contains("gcp"))
    }

    private static func claudeRootCandidates(for rootPath: String) -> [String] {
        if rootPath.hasPrefix("/var/") {
            return ["/private" + rootPath, rootPath]
        }
        if rootPath.hasPrefix("/private/var/") {
            let trimmed = String(rootPath.dropFirst("/private".count))
            return [rootPath, trimmed]
        }
        return [rootPath]
    }

    private struct ClaudeSourceFile {
        let url: URL
        let stamp: CostUsageClaudeFileStamp
    }

    private struct ClaudeSourceInventory {
        let publicationObservations = CostUsagePublicationObservations.forCurrentPlatform()
        var files: [String: ClaudeSourceFile] = [:]

        var stamps: [String: CostUsageClaudeFileStamp] {
            self.files.mapValues(\.stamp)
        }
    }

    private final class ClaudeScanState {
        var cache: CostUsageCache
        var sourceFileIDs: [String: String]
        var windowsReadProofs: [String: CostUsageClaudeReadProof]
        var partial: CostUsageClaudeContentCheckpoint.File?
        var completedPublication: CostUsageSourcePublication?
        let publicationObservations: CostUsagePublicationObservations?
        let range: CostUsageDayRange
        let providerFilter: ClaudeLogProviderFilter
        let forceFullScan: Bool
        let changedPaths: Set<String>
        let pricingResolver: CostUsagePricing.ClaudeResolver
        let checkCancellation: CancellationCheck?

        init(
            cache: CostUsageCache,
            sourceFileIDs: [String: String],
            windowsReadProofs: [String: CostUsageClaudeReadProof],
            publicationObservations: CostUsagePublicationObservations?,
            range: CostUsageDayRange,
            providerFilter: ClaudeLogProviderFilter,
            forceFullScan: Bool,
            changedPaths: Set<String>,
            pricingResolver: CostUsagePricing.ClaudeResolver,
            checkCancellation: CancellationCheck?)
        {
            self.cache = cache
            self.sourceFileIDs = sourceFileIDs
            self.windowsReadProofs = windowsReadProofs
            self.publicationObservations = publicationObservations
            self.range = range
            self.providerFilter = providerFilter
            self.forceFullScan = forceFullScan
            self.changedPaths = changedPaths
            self.pricingResolver = pricingResolver
            self.checkCancellation = checkCancellation
        }
    }

    @discardableResult
    private static func processClaudeFile(
        source: ClaudeSourceFile,
        state: ClaudeScanState,
        maxBytesToRead: Int64? = nil) throws -> Int64
    {
        try state.checkCancellation?()
        let path = source.url.path
        let stamp = source.stamp
        #if os(Windows)
        // Discovery may span refreshes. Parse only the observed prefix while allowing a log
        // to grow; the parser and publication ledger still bind rows to actual consumed bytes.
        try WindowsCostSourceInventory.requireCompatibleFileAfterRead(at: source.url, stamp: stamp)
        let readSnapshot: CostUsageFileReadSnapshot? = CostUsageFileReadSnapshot(claude: stamp)
        let partial = state.partial
        if let partial, !partial.isUsable(path: path, stamp: stamp) {
            throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
        }
        #else
        let readSnapshot: CostUsageFileReadSnapshot? = nil
        let partial: CostUsageClaudeContentCheckpoint.File? = nil
        #endif
        let cached = state.cache.files[path]
        let sameFile = state.sourceFileIDs[path] == stamp.fileID
        #if os(Windows)
        let previousProof = state.windowsReadProofs[path]
        let canReuse: Bool
        if partial == nil, let cached, cached.claudeRows != nil, sameFile, !state.forceFullScan,
           let previousProof, previousProof.parsedBytes == cached.parsedBytes,
           previousProof.source.size == cached.size,
           previousProof.isUsable(for: stamp, allowAppend: true)
        {
            // Bounded work is staged only. The full publication check still validates every
            // reused proof; append seed verification consumes the same budget as parser bytes.
            canReuse = if maxBytesToRead != nil {
                true
            } else {
                try previousProof.matchesContent(
                    at: source.url, stamp: stamp, checkCancellation: state.checkCancellation)
            }
        } else {
            canReuse = false
        }
        #else
        let canReuse = sameFile
        #endif

        if let cached, canReuse,
           cached.mtimeUnixMs == stamp.mtimeUnixMs,
           cached.size == stamp.size,
           !state.forceFullScan,
           !state.changedPaths.contains(path)
        {
            #if os(Windows)
            try previousProof?.observe(at: source.url, stamp: stamp, in: state.publicationObservations)
            #endif
            return 0
        }

        let startOffset: Int64 = if let partial {
            partial.readBytes
        } else if let cached, canReuse, !state.forceFullScan,
                                    stamp.size > cached.size,
                                    cached.claudeRows != nil,
                                    let parsedBytes = cached.parsedBytes, parsedBytes > 0, parsedBytes <= stamp.size
        {
            parsedBytes
        } else {
            0
        }
        let prefixAnchor: CostUsageCodexTokenIndexAnchor?
        #if os(Windows)
        prefixAnchor = partial?.readAnchor ?? (startOffset > 0 ? previousProof?.committedAnchor : nil)
        if startOffset > 0, partial == nil {
            try previousProof?.observe(at: source.url, stamp: stamp, in: state.publicationObservations)
        }
        #else
        prefixAnchor = nil
        #endif

        state.pricingResolver.prepareCatalog()
        #if DEBUG
        Self.recordClaudeScanWork(.transcriptParse(startOffset: startOffset))
        #endif
        let parsed = try Self.parseClaudeFileCancellable(
            fileURL: source.url,
            range: state.range,
            providerFilter: state.providerFilter,
            startOffset: startOffset,
            pricingResolver: state.pricingResolver,
            expectedFile: readSnapshot,
            expectedPrefixAnchor: prefixAnchor,
            maxBytesToRead: maxBytesToRead,
            resumeState: partial?.resume,
            expectedCommittedAnchor: partial == nil ? prefixAnchor : partial?.committedAnchor,
            windowsContentContinuation: partial?.contentContinuation,
            checkCancellation: state.checkCancellation)
        let rows = if let partial {
            Self.mergeClaudeRows(existing: partial.rows, delta: parsed.rows)
        } else if startOffset > 0 {
            Self.mergeClaudeRows(existing: cached?.claudeRows ?? [], delta: parsed.rows)
        } else {
            parsed.rows
        }
        let bytesRead = parsed.progress?.windowsContentBytesRead
            ?? max(0, (parsed.progress?.readOffset ?? parsed.parsedBytes) - startOffset)
        #if os(Windows)
        try WindowsCostSourceInventory.requireCompatibleFileAfterRead(at: source.url, stamp: stamp)
        guard let progress = parsed.progress else {
            throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
        }
        if progress.readOffset < stamp.size {
            let pending = CostUsageClaudeContentCheckpoint.File(
                path: path, source: stamp, rows: rows, parsedBytes: parsed.parsedBytes,
                readBytes: progress.readOffset, resume: progress.resumeState,
                readAnchor: progress.windowsReadAnchor, committedAnchor: progress.windowsCommittedAnchor,
                contentContinuation: progress.windowsContentContinuation)
            guard bytesRead > 0, pending.isUsable(path: path, stamp: stamp) else {
                throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
            }
            try pending.observe(in: state.publicationObservations)
            state.partial = pending
            return bytesRead
        }
        guard let proof = parsed.windowsReadProof, proof.parsedBytes == parsed.parsedBytes,
              proof.isUsable(for: stamp, allowAppend: false)
        else { throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable }
        try proof.observe(at: source.url, stamp: stamp, in: state.publicationObservations)
        state.windowsReadProofs[path] = proof
        state.partial = nil
        #endif
        let usage = Self.makeFileUsage(
            mtimeUnixMs: stamp.mtimeUnixMs,
            size: stamp.size,
            days: [:],
            parsedBytes: parsed.parsedBytes,
            claudeRows: rows)
        state.cache.files[path] = usage
        state.sourceFileIDs[path] = stamp.fileID
        return bytesRead
    }

    private static func inventoryClaudeRoots(
        _ roots: [URL],
        checkCancellation: CancellationCheck?) throws -> ClaudeSourceInventory
    {
        var inventory = ClaudeSourceInventory()
        #if os(Windows)
        var owners: [String: CostUsageClaudeFileStamp] = [:]
        #endif

        for root in roots {
            try checkCancellation?()
            #if os(Windows)
            guard let files = try WindowsCostSourceInventory.jsonlFiles(
                in: root, checkCancellation: checkCancellation,
                publicationObservations: inventory.publicationObservations)
            else { continue }
            for url in files.keys.sorted(by: { $0.path < $1.path }) {
                guard let stamp = files[url], stamp.size > 0 else { continue }
                if let previous = owners[stamp.fileID] {
                    guard previous == stamp else { throw WindowsCostSourceInventory.Failure.sourceChanged }
                    continue
                }
                owners[stamp.fileID] = stamp
                inventory.files[url.path] = ClaudeSourceFile(url: url, stamp: stamp)
            }
            #else
            let rootPath = root.path
            let rootCandidates = Self.claudeRootCandidates(for: rootPath)
            guard let existingRootPath = rootCandidates.first(where: { FileManager.default.fileExists(atPath: $0) })
            else { continue }
            let existingRoot = existingRootPath == rootPath ? root : URL(fileURLWithPath: existingRootPath)
            guard let enumerator = FileManager.default.enumerator(
                at: existingRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }

            for case let url as URL in enumerator {
                try checkCancellation?()
                guard url.pathExtension.lowercased() == "jsonl" else { continue }
                guard let stamp = CostUsageClaudeFileStamp.read(at: url), stamp.size > 0 else { continue }
                inventory.files[url.path] = ClaudeSourceFile(url: url, stamp: stamp)
            }
            #endif
        }
        return inventory
    }

    #if os(Windows)
    private static func inventoryWindowsClaudeRoots(
        _ roots: [URL], provider: UsageProvider, options: Options, range: CostUsageDayRange,
        artifact: inout CostUsageClaudeCache,
        checkCancellation: CancellationCheck?) throws -> ClaudeSourceInventory
    {
        let fresh = CostUsageWindowsTreeInventory(roots: roots)
        var state: CostUsageWindowsTreeInventory
        if let previous = artifact.windowsInventory, previous.version == fresh.version,
           previous.roots == fresh.roots, previous.policy == fresh.policy,
           previous.phase != .complete || artifact.windowsContent != nil {
            state = previous
        } else {
            WindowsCostDirectoryPages.shared.discard(artifact.windowsInventory?.page)
            WindowsCostContentContinuations.shared.discard(artifact.windowsContent?.partial?.contentContinuation)
            WindowsCostPublicationVerifications.shared.discard(artifact.windowsContent?.verificationToken)
            artifact.windowsContent = nil
            state = fresh
        }
        do {
            let progress = try WindowsCostTreeInventory.advance(
                &state, maxWork: max(1, options.maxWindowsClaudeInventoryWorkPerRefresh),
                checkCancellation: checkCancellation)
            if progress.isComplete {
                var inventory = ClaudeSourceInventory()
                guard let observations = inventory.publicationObservations else {
                    throw WindowsCostSourceInventory.Failure.sourceChanged
                }
                try WindowsCostTreeInventory.observe(state, in: observations, checkCancellation: checkCancellation)
                // Re-validate the frozen tree in bounded slices that rotate through the canonical
                // entry order across refreshes, instead of one unbounded metadata sweep. The
                // durable cursor rides the checkpointed inventory state; per-file read guards
                // and the final publication check still cover every entry before rows publish.
                let publication = observations.freeze()
                let checked = try publication.checkSlice(
                    start: state.publicationCheckedCount ?? 0,
                    maxEntries: max(1, options.maxWindowsClaudeInventoryWorkPerRefresh),
                    checkCancellation: checkCancellation)
                state.publicationCheckedCount = checked < publication.entries.count ? checked : nil
                for (url, stamp) in try WindowsCostTreeInventory.representatives(
                    state, checkCancellation: checkCancellation) where stamp.size > 0 {
                    inventory.files[url.path] = ClaudeSourceFile(url: url, stamp: stamp)
                }
                // Keep the fixed inventory while body parsing spans subsequent collections.
                artifact.windowsInventory = state
                return inventory
            }
        } catch WindowsCostSourceInventory.Failure.sourceChanged {
            WindowsCostDirectoryPages.shared.discard(state.page)
            WindowsCostContentContinuations.shared.discard(artifact.windowsContent?.partial?.contentContinuation)
            WindowsCostPublicationVerifications.shared.discard(artifact.windowsContent?.verificationToken)
            artifact.windowsContent = nil
            state = fresh
        } catch CostUsageSourcePublication.Failure.sourceChangedOrUnavailable {
            WindowsCostDirectoryPages.shared.discard(state.page)
            WindowsCostContentContinuations.shared.discard(artifact.windowsContent?.partial?.contentContinuation)
            WindowsCostPublicationVerifications.shared.discard(artifact.windowsContent?.verificationToken)
            artifact.windowsContent = nil
            state = fresh
        }
        // Checkpoint only: preserve rows/proofs/configuration/lastScan verbatim. This is not a
        // report publication, and an incomplete inventory may never prune absent cached paths.
        artifact.windowsInventory = state
        guard try CostUsageClaudeCacheIO.save(
            provider: provider, cache: artifact, cacheRoot: options.cacheRoot,
            calendar: range.calendar, preserveUsageCalendar: true, checkCancellation: checkCancellation) != nil else {
            throw CostUsageError.localInventoryCheckpointUnavailable
        }
        throw CostUsageError.localInventoryPending(discoveredFiles: state.files.count)
    }

    private static func processWindowsClaudeCollection(
        inventory: ClaudeSourceInventory, artifact: inout CostUsageClaudeCache,
        baseCache: CostUsageCache, reportKey: CostUsageClaudeReportMemoKey,
        options: Options, range: CostUsageDayRange, forceFullScan: Bool, changedPaths: Set<String>,
        pricingResolver: CostUsagePricing.ClaudeResolver,
        checkCancellation: CancellationCheck?) throws -> ClaudeScanState
    {
        let key = CostUsageClaudeContentCheckpoint.Key(report: reportKey, forceRescan: options.forceRescan)
        let paths = inventory.files.keys.sorted()
        let stamps = inventory.stamps
        var checkpoint = CostUsageClaudeContentCheckpoint(
            key: key, sourceInventory: stamps, cache: baseCache,
            sourceFileIDs: options.forceRescan ? [:] : artifact.sourceFileIDs,
            proofs: options.forceRescan ? [:] : artifact.windowsReadProofs)
        if let previous = artifact.windowsContent, previous.version == checkpoint.version,
           previous.key == key, previous.sourceInventory == stamps,
           previous.nextFile >= 0, previous.nextFile <= paths.count,
           previous.partial == nil || previous.nextFile < paths.count {
            checkpoint = previous
        } else {
            WindowsCostContentContinuations.shared.discard(artifact.windowsContent?.partial?.contentContinuation)
            WindowsCostPublicationVerifications.shared.discard(artifact.windowsContent?.verificationToken)
        }
        let state = ClaudeScanState(
            cache: checkpoint.cache, sourceFileIDs: checkpoint.sourceFileIDs,
            windowsReadProofs: checkpoint.proofs, publicationObservations: inventory.publicationObservations,
            range: range, providerFilter: options.claudeLogProviderFilter, forceFullScan: forceFullScan,
            changedPaths: changedPaths, pricingResolver: pricingResolver, checkCancellation: checkCancellation)
        state.partial = checkpoint.partial
        do {
            // Reconstitute evidence for files completed by earlier slices. Checkpoints keep
            // these rows staged; final verification covers every prefix before report publication.
            for path in paths.prefix(checkpoint.nextFile) {
                try checkCancellation?()
                guard let source = inventory.files[path], let usage = state.cache.files[path],
                      usage.claudeRows != nil, state.sourceFileIDs[path] == source.stamp.fileID,
                      let proof = state.windowsReadProofs[path], proof.parsedBytes == usage.parsedBytes,
                      usage.size == source.stamp.size, proof.isUsable(for: source.stamp, allowAppend: false)
                else { throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable }
                try proof.observe(at: source.url, stamp: source.stamp, in: inventory.publicationObservations)
            }
            var remainingBytes = max(1, options.maxWindowsClaudeContentBytesPerRefresh)
            var remainingFiles = max(1, options.maxWindowsClaudeFilesPerRefresh)
            while checkpoint.nextFile < paths.count, remainingBytes > 0, remainingFiles > 0 {
                try checkCancellation?()
                guard let source = inventory.files[paths[checkpoint.nextFile]] else {
                    throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
                }
                let consumed = try Self.processClaudeFile(
                    source: source, state: state, maxBytesToRead: remainingBytes)
                remainingBytes -= min(remainingBytes, consumed)
                remainingFiles -= 1
                if state.partial != nil { break }
                checkpoint.nextFile += 1
            }
            try checkCancellation?()
            let pricingURL = ModelsDevCache.cacheFileURL(cacheRoot: options.cacheRoot)
            guard CostUsageClaudeFileStamp.read(at: pricingURL) == key.pricing else {
                throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
            }
            if checkpoint.nextFile == paths.count {
                let publication = try Self.completedClaudePublication(inventory: inventory, state: state)
                let verifier = WindowsCostPublicationVerifications.shared.take(
                    checkpoint.verificationToken, entries: publication.entries)
                switch try verifier.advance(
                    maxBytes: remainingBytes, maxEntries: max(1, options.maxWindowsClaudeVerificationEntriesPerRefresh),
                    checkCancellation: checkCancellation) {
                case .pending:
                    checkpoint.verificationToken = WindowsCostPublicationVerifications.shared.put(verifier)
                case .complete:
                    // The boundary re-stat uses the same entry budget as the advance. A
                    // partial pass parks the verifier (leases + metadataChecked cursor)
                    // under the checkpoint token so the next refresh resumes in place.
                    if let checked = try verifier.canReuseSlice(
                        entries: publication.entries,
                        maxEntries: max(1, options.maxWindowsClaudeVerificationEntriesPerRefresh),
                        checkCancellation: checkCancellation)
                    {
                        if checked == publication.entries.count {
                            state.completedPublication = CostUsageSourcePublication(
                                entries: publication.entries, windowsVerifier: verifier)
                        } else {
                            checkpoint.verificationToken = WindowsCostPublicationVerifications.shared.put(verifier)
                        }
                    } else if try Self.checkClaudeCheckpointLedgerSlice(
                        publication, checkpoint: &checkpoint,
                        options: options, checkCancellation: checkCancellation)
                    {
                        state.completedPublication = publication
                    }
                case .requiresFullCheck:
                    // Remote/unsupported/busy streams and capacity limits keep the per-entry
                    // check, sliced by a durable checkpoint cursor instead of one unbounded pass.
                    // An incomplete slice falls through to the checkpoint save below, which
                    // persists fallbackCheckedCount and rethrows the pending error.
                    if try Self.checkClaudeCheckpointLedgerSlice(
                        publication, checkpoint: &checkpoint,
                        options: options, checkCancellation: checkCancellation)
                    {
                        state.completedPublication = publication
                    }
                }
                if state.completedPublication != nil {
                    artifact.windowsContent = nil
                    artifact.windowsInventory = nil
                    artifact.windowsForceContentRescan = false
                    return state
                }
            }
            checkpoint.cache = state.cache
            checkpoint.sourceFileIDs = state.sourceFileIDs
            checkpoint.proofs = state.windowsReadProofs
            checkpoint.partial = state.partial
            artifact.windowsContent = checkpoint
            guard try CostUsageClaudeCacheIO.save(
                provider: reportKey.provider, cache: artifact, cacheRoot: options.cacheRoot,
                calendar: range.calendar, preserveUsageCalendar: true, checkCancellation: checkCancellation,
                sourcePublication: inventory.publicationObservations?.freeze().metadataOnly()) != nil else {
                throw CostUsageError.localInventoryCheckpointUnavailable
            }
        } catch CostUsageSourcePublication.Failure.sourceChangedOrUnavailable {
            try Self.restartWindowsClaudeCollection(
                artifact: &artifact, provider: reportKey.provider, options: options,
                range: range, checkCancellation: checkCancellation)
        } catch WindowsCostSourceInventory.Failure.sourceChanged {
            try Self.restartWindowsClaudeCollection(
                artifact: &artifact, provider: reportKey.provider, options: options,
                range: range, checkCancellation: checkCancellation)
        } catch WindowsCostFileReadGuard.Failure.sourceChanged {
            try Self.restartWindowsClaudeCollection(
                artifact: &artifact, provider: reportKey.provider, options: options,
                range: range, checkCancellation: checkCancellation)
        }
        if checkpoint.nextFile == paths.count {
            throw CostUsageError.localContentVerificationPending(totalFiles: paths.count)
        }
        throw CostUsageError.localContentPending(completedFiles: checkpoint.nextFile, totalFiles: paths.count)
    }

    private static func completedClaudePublication(
        inventory: ClaudeSourceInventory, state: ClaudeScanState) throws -> CostUsageSourcePublication
    {
        guard let observations = inventory.publicationObservations else {
            throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
        }
        // Canonical final proofs make the binding independent of which slice completed the
        // final file. Intermediate/old prefix anchors must not change it between continuations.
        var entries = observations.freeze().metadataOnly().entries
        var bound: Set<String> = []
        for index in entries.indices {
            let path = entries[index].url.path
            guard let source = inventory.files[path] else { continue }
            guard case .file = entries[index].expectation, let proof = state.windowsReadProofs[path],
                  proof.isUsable(for: source.stamp, allowAppend: false) else {
                throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
            }
            var anchors: [CostUsageCodexTokenIndexAnchor] = []
            for anchor in [proof.committedAnchor, proof.readAnchor].compactMap({ $0 }) {
                if !anchors.contains(anchor) { anchors.append(anchor) }
            }
            entries[index].contentAnchors = anchors
            bound.insert(path)
        }
        guard bound == Set(inventory.files.keys) else {
            throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
        }
        return CostUsageSourcePublication(entries: entries)
    }

    private static func restartWindowsClaudeCollection(
        artifact: inout CostUsageClaudeCache, provider: UsageProvider, options: Options,
        range: CostUsageDayRange, checkCancellation: CancellationCheck?) throws -> Never
    {
        WindowsCostContentContinuations.shared.discard(artifact.windowsContent?.partial?.contentContinuation)
        WindowsCostPublicationVerifications.shared.discard(artifact.windowsContent?.verificationToken)
        artifact.windowsContent = nil
        artifact.windowsInventory = nil
        artifact.windowsForceContentRescan = true
        guard try CostUsageClaudeCacheIO.save(
            provider: provider, cache: artifact, cacheRoot: options.cacheRoot,
            calendar: range.calendar, preserveUsageCalendar: true, checkCancellation: checkCancellation) != nil else {
            throw CostUsageError.localInventoryCheckpointUnavailable
        }
        throw CostUsageError.localInventoryPending(discoveredFiles: 0)
    }

    /// Per-entry ledger slice for the checkpoint boundary's lease-less and lease-lost paths.
    /// Returns true when the whole publication passed; a partial pass persists its
    /// leading-entry cursor on the checkpoint and returns false so the caller saves+rethrows.
    private static func checkClaudeCheckpointLedgerSlice(
        _ publication: CostUsageSourcePublication,
        checkpoint: inout CostUsageClaudeContentCheckpoint,
        options: Options,
        checkCancellation: CancellationCheck?) throws -> Bool
    {
        let checked = try publication.checkSlice(
            start: checkpoint.fallbackCheckedCount ?? 0,
            maxEntries: max(1, options.maxWindowsClaudeVerificationEntriesPerRefresh),
            checkCancellation: checkCancellation)
        if checked < publication.entries.count {
            checkpoint.fallbackCheckedCount = checked
            return false
        }
        checkpoint.fallbackCheckedCount = nil
        return true
    }
    #endif

    static func loadClaudeDaily(
        provider: UsageProvider,
        range: CostUsageDayRange,
        now: Date,
        options: Options,
        checkCancellation: CancellationCheck?) throws -> CostUsageDailyReport
    {
        let roots = self.defaultClaudeProjectsRoots(options: options)
        #if os(Windows)
        // Discovery may span a calendar change; retain the last completed cache until the
        // replacement inventory and full content pass are ready to publish together.
        var artifact = CostUsageClaudeCacheIO.load(provider: provider, cacheRoot: options.cacheRoot)
        let inventory = try Self.inventoryWindowsClaudeRoots(
            roots, provider: provider, options: options, range: range,
            artifact: &artifact, checkCancellation: checkCancellation)
        #else
        let inventory = try Self.inventoryClaudeRoots(roots, checkCancellation: checkCancellation)
        #endif
        try checkCancellation?()

        let cacheURL = CostUsageClaudeCacheIO.cacheFileURL(provider: provider, cacheRoot: options.cacheRoot)
        let canonicalCachePath = cacheURL.standardizedFileURL.resolvingSymlinksInPath().path
        let cacheArtifactStamp = CostUsageClaudeFileStamp.read(at: cacheURL)
        let pricingURL = ModelsDevCache.cacheFileURL(cacheRoot: options.cacheRoot)
        let pricingArtifactStamp = CostUsageClaudeFileStamp.read(at: pricingURL)
        let reportKey = Self.claudeReportMemoKey(
            provider: provider,
            providerFilter: options.claudeLogProviderFilter,
            range: range,
            roots: roots,
            artifactStamps: (cache: cacheArtifactStamp, pricing: pricingArtifactStamp))
        let memo = CostUsageClaudeReportMemo.shared
        let priorMemo = memo.entry(provider: provider, canonicalCachePath: canonicalCachePath)
        let sourceInventory = inventory.stamps
        #if os(Windows)
        let forcedContentRescan = artifact.windowsForceContentRescan
        #else
        let forcedContentRescan = false
        #endif

        if !options.forceRescan, !forcedContentRescan,
           let priorMemo,
           priorMemo.sourceInventory == sourceInventory,
           priorMemo.reportKey == reportKey
        {
            // The memo-hit content pass shares the leased, budgeted verifier so a large inventory
            // cannot monopolize a refresh. A pending pass persists its token and resumes next slice.
            #if os(Windows)
            if let verification = try Self.claudeMemoContentMatches(priorMemo, inventory: inventory,
                provider: provider, canonicalCachePath: canonicalCachePath,
                options: options, checkCancellation: checkCancellation)
            {
                try checkCancellation?()
                try Self.checkClaudeMemoReportBoundary(
                    verification, observations: inventory.publicationObservations,
                    provider: provider, canonicalCachePath: canonicalCachePath,
                    options: options, checkCancellation: checkCancellation)
                return priorMemo.report
            }
            #else
            if try Self.claudeMemoContentMatches(priorMemo, inventory: inventory,
                provider: provider, canonicalCachePath: canonicalCachePath,
                options: options, checkCancellation: checkCancellation)
            {
                try checkCancellation?()
                try inventory.publicationObservations?.freeze().check(checkCancellation: checkCancellation)
                return priorMemo.report
            }
            #endif
        }

        #if !os(Windows)
        var artifact = CostUsageClaudeCacheIO.load(
            provider: provider,
            cacheRoot: options.cacheRoot,
            calendar: range.calendar)
        #endif
        var cache = artifact.usage
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let refreshMs = Int64(max(0, options.refreshMinIntervalSeconds) * 1000)
        let windowExpanded = Self.requestedWindowExpandsCache(range: range, cache: cache)
        let sourceInventoryChanged = priorMemo.map { $0.sourceInventory != sourceInventory } ?? false
        let cacheArtifactChanged = priorMemo.map {
            $0.reportKey.cacheArtifactStamp != cacheArtifactStamp
        } ?? false
        #if os(Windows)
        let cachedConfigurationChanged = artifact.windowsScanConfiguration != reportKey.scanConfiguration
            || artifact.usage.timeZoneIdentifier != range.calendar.timeZone.identifier
        #else
        let cachedConfigurationChanged = false
        #endif
        let scanConfigurationChanged = cachedConfigurationChanged || (priorMemo.map {
            $0.reportKey.scanConfiguration != reportKey.scanConfiguration
        } ?? false)
        let sourceIdentitiesChanged = artifact.sourceFileIDs != sourceInventory.mapValues(\.fileID)
        let shouldRefresh = options.forceRescan
            || sourceIdentitiesChanged
            || windowExpanded
            || sourceInventoryChanged
            || cacheArtifactChanged
            || scanConfigurationChanged
            || refreshMs == 0
            || cache.lastScanUnixMs == 0
            || nowMs - cache.lastScanUnixMs > refreshMs
        let providerFilter = options.claudeLogProviderFilter
        let hasStableProcessBaseline = priorMemo != nil
            && !sourceIdentitiesChanged
            && !sourceInventoryChanged
            && !cacheArtifactChanged
            && !scanConfigurationChanged
        // A Windows memo miss must visit every row source even during the refresh interval.
        // Metadata and a recent lastScan cannot authorize legacy or changed content proofs.
        #if os(Windows)
        let requiresContentPass = true
        #else
        let requiresContentPass = false
        #endif
        let shouldMutateCache = requiresContentPass
            || (shouldRefresh && (!hasStableProcessBaseline || options.forceRescan || windowExpanded))
        let pricingResolver = CostUsagePricing.ClaudeResolver(now: now, cacheRoot: options.cacheRoot)
        var completedPublication: CostUsageSourcePublication?

        if shouldMutateCache {
            try checkCancellation?()
            if options.forceRescan {
                cache = CostUsageCache()
                #if !os(Windows)
                artifact.sourceFileIDs = [:]
                artifact.windowsReadProofs = [:]
                #endif
            }
            let changedPaths: Set<String> = if let priorMemo {
                Set(inventory.files.keys.filter { path in
                    priorMemo.sourceInventory[path] != sourceInventory[path]
                })
            } else {
                []
            }
            #if os(Windows)
            let scanState = try Self.processWindowsClaudeCollection(
                inventory: inventory, artifact: &artifact, baseCache: cache, reportKey: reportKey,
                options: options, range: range,
                forceFullScan: options.forceRescan || windowExpanded || scanConfigurationChanged || forcedContentRescan,
                changedPaths: changedPaths, pricingResolver: pricingResolver, checkCancellation: checkCancellation)
            #else
            let scanState = ClaudeScanState(
                cache: cache,
                sourceFileIDs: artifact.sourceFileIDs,
                windowsReadProofs: artifact.windowsReadProofs,
                publicationObservations: inventory.publicationObservations,
                range: range,
                providerFilter: providerFilter,
                forceFullScan: options.forceRescan || windowExpanded || scanConfigurationChanged,
                changedPaths: changedPaths,
                pricingResolver: pricingResolver,
                checkCancellation: checkCancellation)

            for path in inventory.files.keys.sorted() {
                guard let source = inventory.files[path] else { continue }
                try Self.processClaudeFile(source: source, state: scanState)
            }
            #endif
            try checkCancellation?()

            cache = scanState.cache
            completedPublication = scanState.completedPublication
            artifact.sourceFileIDs = scanState.sourceFileIDs.filter { sourceInventory[$0.key] != nil }
            artifact.windowsReadProofs = scanState.windowsReadProofs.filter { sourceInventory[$0.key] != nil }
            #if os(Windows)
            artifact.windowsScanConfiguration = reportKey.scanConfiguration
            #endif
            cache.roots = nil

            for key in cache.files.keys where sourceInventory[key] == nil {
                cache.files.removeValue(forKey: key)
            }

            Self.rebuildClaudeDays(cache: &cache)
            Self.pruneDays(cache: &cache, sinceKey: range.scanSinceKey, untilKey: range.scanUntilKey)
            cache.scanSinceKey = range.scanSinceKey
            cache.scanUntilKey = range.scanUntilKey
            cache.lastScanUnixMs = nowMs
        }

        let report = Self.buildClaudeReportFromCache(
            cache: cache,
            range: range,
            pricingResolver: pricingResolver)
        try checkCancellation?()

        // Parsing and retained-row reuse add consumed-byte proofs after directory inventory.
        let sourcePublication = completedPublication ?? inventory.publicationObservations?.freeze()
        artifact.usage = cache
        let committedCacheStamp: CostUsageClaudeFileStamp? = if shouldMutateCache {
            try CostUsageClaudeCacheIO.save(
                provider: provider,
                cache: artifact,
                cacheRoot: options.cacheRoot,
                calendar: range.calendar,
                checkCancellation: checkCancellation,
                sourcePublication: sourcePublication)
        } else {
            nil
        }

        let finalCacheArtifactStamp = CostUsageClaudeFileStamp.read(at: cacheURL)
        let finalPricingArtifactStamp = CostUsageClaudeFileStamp.read(at: pricingURL)
        let finalReportKey = Self.claudeReportMemoKey(
            provider: provider,
            providerFilter: providerFilter,
            range: range,
            roots: roots,
            artifactStamps: (cache: finalCacheArtifactStamp, pricing: finalPricingArtifactStamp))
        let cacheArtifactIsCurrent = if shouldMutateCache {
            committedCacheStamp != nil && finalCacheArtifactStamp == committedCacheStamp
        } else {
            finalCacheArtifactStamp == cacheArtifactStamp
        }
        if cacheArtifactIsCurrent, finalPricingArtifactStamp == pricingArtifactStamp {
            try memo.store(
                provider: provider,
                canonicalCachePath: canonicalCachePath,
                sourceInventory: sourceInventory,
                reportKey: finalReportKey,
                report: report,
                windowsReadProofs: artifact.windowsReadProofs,
                sourcePublication: sourcePublication,
                checkCancellation: checkCancellation)
        }
        try sourcePublication?.check(checkCancellation: checkCancellation)
        return report
    }

    #if os(Windows)
    /// Result of a memo-hit content pass. `.leased` carries the publication verified under
    /// read leases so the report boundary can re-check it through the same leases; `.leaseLess`
    /// means the per-file content check passed without a verifier and the boundary needs its own pass.
    private enum ClaudeMemoVerification {
        case leased(WindowsCostPublicationVerifier)
        case leaseLess
    }

    /// Memo-hit verification shares the leased, budgeted publication verifier. A pass that cannot
    /// finish inside one refresh persists a resume token and throws `localContentVerificationPending`
    /// instead of falling through to a full rescan. Sources whose streams cannot hold a read lease
    /// (remote/unsupported/busy or over-capacity sets) keep the per-file content check, sliced by
    /// entry count with a process-local cursor on the memo.
    private static func claudeMemoContentMatches(
        _ memo: CostUsageClaudeReportMemo.Entry,
        inventory: ClaudeSourceInventory,
        provider: UsageProvider,
        canonicalCachePath: String,
        options: Options,
        checkCancellation: CancellationCheck?) throws -> ClaudeMemoVerification?
    {
        guard let proofs = memo.windowsReadProofs, Set(proofs.keys) == Set(inventory.files.keys)
        else { return nil }
        // The resume token and fallback cursor live on the memo, not the cache artifact:
        // persisting them would rewrite the cache file, change its stamp, and break the
        // reportKey match the resume state depends on.
        let memoStore = CostUsageClaudeReportMemo.shared
        // A completed lease-less content pass survives pending boundary slices: the flag lets
        // later refreshes skip the digest pass while the ledger's recorded anchors still let
        // the boundary re-verify content per entry. It clears on completion, failure or store.
        let contentDone = memoStore.hasContentPassCompleted(
            provider: provider, canonicalCachePath: canonicalCachePath)
        func fullCheck() throws -> Bool {
            // Streams that cannot hold a read lease keep the per-file content check, sliced by
            // entry count. Every file is still observed each refresh so the final publication
            // check covers the whole inventory; only the expensive digest pass is deferred.
            let sorted = inventory.files.keys.sorted()
            var checked = memoStore.fallbackCheckedCount(
                provider: provider, canonicalCachePath: canonicalCachePath) ?? 0
            if checked > sorted.count { checked = 0 }
            var visits = max(1, options.maxWindowsClaudeVerificationEntriesPerRefresh)
            for (index, path) in sorted.enumerated() {
                try checkCancellation?()
                guard let source = inventory.files[path], let proof = proofs[path],
                      proof.isUsable(for: source.stamp, allowAppend: false) else { return false }
                try proof.observe(at: source.url, stamp: source.stamp, in: inventory.publicationObservations)
                if index < checked { continue }
                guard visits > 0 else {
                    memoStore.setFallbackCheckedCount(
                        index, provider: provider, canonicalCachePath: canonicalCachePath)
                    throw CostUsageError.localContentVerificationPending(totalFiles: sorted.count)
                }
                visits -= 1
                guard try proof.matchesContent(
                    at: source.url, stamp: source.stamp, checkCancellation: checkCancellation)
                else { return false }
            }
            memoStore.setFallbackCheckedCount(nil, provider: provider, canonicalCachePath: canonicalCachePath)
            memoStore.setContentPassCompleted(true, provider: provider, canonicalCachePath: canonicalCachePath)
            return true
        }
        guard let observations = inventory.publicationObservations else {
            if contentDone { return .leaseLess }
            return try fullCheck() ? .leaseLess : nil
        }
        // Record every usable proof first so the verifier's entry set covers the whole inventory.
        for path in inventory.files.keys.sorted() {
            try checkCancellation?()
            guard let source = inventory.files[path], let proof = proofs[path],
                  proof.isUsable(for: source.stamp, allowAppend: false) else { return nil }
            try proof.observe(at: source.url, stamp: source.stamp, in: observations)
        }
        if contentDone {
            // The digest pass finished on an earlier refresh; pending boundary slices resume
            // without re-running it. Any stale leased token is discarded with the pass it served.
            WindowsCostPublicationVerifications.shared.discard(
                memoStore.verificationToken(provider: provider, canonicalCachePath: canonicalCachePath))
            memoStore.setVerificationToken(nil, provider: provider, canonicalCachePath: canonicalCachePath)
            return .leaseLess
        }
        // Canonical final proofs keep the token binding independent of observation order.
        var entries = observations.freeze().metadataOnly().entries
        var bound: Set<String> = []
        for index in entries.indices {
            let path = entries[index].url.path
            guard let source = inventory.files[path], let proof = proofs[path],
                  case .file = entries[index].expectation,
                  proof.isUsable(for: source.stamp, allowAppend: false) else { continue }
            var anchors: [CostUsageCodexTokenIndexAnchor] = []
            for anchor in [proof.committedAnchor, proof.readAnchor].compactMap({ $0 }) {
                if !anchors.contains(anchor) { anchors.append(anchor) }
            }
            entries[index].contentAnchors = anchors
            bound.insert(path)
        }
        guard bound == Set(inventory.files.keys) else { return nil }
        let verifier = WindowsCostPublicationVerifications.shared.take(
            memoStore.verificationToken(provider: provider, canonicalCachePath: canonicalCachePath),
            entries: entries)
        do {
            switch try verifier.advance(
                maxBytes: max(1, options.maxWindowsClaudeContentBytesPerRefresh),
                maxEntries: max(1, options.maxWindowsClaudeVerificationEntriesPerRefresh),
                checkCancellation: checkCancellation) {
            case .pending:
                memoStore.setVerificationToken(
                    WindowsCostPublicationVerifications.shared.put(verifier),
                    provider: provider, canonicalCachePath: canonicalCachePath)
                throw CostUsageError.localContentVerificationPending(totalFiles: inventory.files.count)
            case .complete:
                memoStore.setVerificationToken(nil, provider: provider, canonicalCachePath: canonicalCachePath)
                // The completed verifier is the boundary's evidence: its resumable metadata
                // pass re-checks names and leases per entry without re-reading anchored bytes.
                return .leased(verifier)
            case .requiresFullCheck:
                memoStore.setVerificationToken(nil, provider: provider, canonicalCachePath: canonicalCachePath)
                return try fullCheck() ? .leaseLess : nil
            }
        } catch CostUsageSourcePublication.Failure.sourceChangedOrUnavailable {
            // A memo whose content no longer matches is a miss, not a failed refresh: the caller
            // falls through to the scan path, which rebuilds proofs under the same inventory.
            memoStore.setVerificationToken(nil, provider: provider, canonicalCachePath: canonicalCachePath)
            return nil
        } catch WindowsCostFileReadGuard.Failure.sourceChanged {
            memoStore.setVerificationToken(nil, provider: provider, canonicalCachePath: canonicalCachePath)
            return nil
        }
    }

    /// Boundary re-check before a memo report is returned. Leased publications re-verify
    /// metadata through their intact verifier in resumable slices instead of re-reading every
    /// anchored byte; lease-less passes keep the per-entry check, sliced under the same entry
    /// cap with a process-local cursor so a missed cursor simply restarts the pass.
    private static func checkClaudeMemoReportBoundary(
        _ verification: ClaudeMemoVerification,
        observations: CostUsagePublicationObservations?,
        provider: UsageProvider,
        canonicalCachePath: String,
        options: Options,
        checkCancellation: CancellationCheck?) throws
    {
        let key = "claude-memo-boundary|" + canonicalCachePath
        let resume = WindowsCostPublicationResumeKeys.shared
        let memoStore = CostUsageClaudeReportMemo.shared
        if case let .leased(verifier) = verification {
            // A pending boundary pass parks the completed verifier under the memo's resume
            // token, so the next refresh resumes the same leases and the same cursor instead
            // of reopening streams or re-reading anchored bytes.
            if let checked = try verifier.canReuseSlice(
                entries: verifier.entries,
                maxEntries: max(1, options.maxWindowsClaudeVerificationEntriesPerRefresh),
                checkCancellation: checkCancellation)
            {
                guard checked < verifier.entries.count else {
                    resume.clear(for: key)
                    memoStore.setContentPassCompleted(
                        false, provider: provider, canonicalCachePath: canonicalCachePath)
                    return
                }
                memoStore.setVerificationToken(
                    WindowsCostPublicationVerifications.shared.put(verifier),
                    provider: provider, canonicalCachePath: canonicalCachePath)
                throw CostUsageError.localContentVerificationPending(
                    totalFiles: verifier.entries.count)
            }
            // Leases could not back a reuse: continue through the per-entry ledger check.
        }
        guard let publication = observations?.freeze() else { return }
        do {
            let checked = try publication.checkSlice(
                start: resume.checkedCount(for: key) ?? 0,
                maxEntries: max(1, options.maxWindowsClaudeVerificationEntriesPerRefresh),
                checkCancellation: checkCancellation)
            guard checked < publication.entries.count else {
                resume.clear(for: key)
                memoStore.setContentPassCompleted(
                    false, provider: provider, canonicalCachePath: canonicalCachePath)
                return
            }
            resume.setCheckedCount(checked, for: key)
            throw CostUsageError.localContentVerificationPending(
                totalFiles: publication.entries.count)
        } catch CostUsageSourcePublication.Failure.sourceChangedOrUnavailable {
            resume.clear(for: key)
            memoStore.setContentPassCompleted(
                false, provider: provider, canonicalCachePath: canonicalCachePath)
            throw CostUsageSourcePublication.Failure.sourceChangedOrUnavailable
        } catch WindowsCostFileReadGuard.Failure.sourceChanged {
            resume.clear(for: key)
            memoStore.setContentPassCompleted(
                false, provider: provider, canonicalCachePath: canonicalCachePath)
            throw WindowsCostFileReadGuard.Failure.sourceChanged
        }
    }

    #else
    private static func claudeMemoContentMatches(
        _ memo: CostUsageClaudeReportMemo.Entry,
        inventory: ClaudeSourceInventory,
        provider: UsageProvider,
        canonicalCachePath: String,
        options: Options,
        checkCancellation: CancellationCheck?) throws -> Bool
    {
        true
    }
    #endif

    private static func claudeReportMemoKey(
        provider: UsageProvider,
        providerFilter: ClaudeLogProviderFilter,
        range: CostUsageDayRange,
        roots: [URL],
        artifactStamps: (cache: CostUsageClaudeFileStamp?, pricing: CostUsageClaudeFileStamp?))
        -> CostUsageClaudeReportMemoKey
    {
        let providerFilterKey = switch providerFilter {
        case .all: "all"
        case .vertexAIOnly: "vertex-ai-only"
        case .excludeVertexAI: "exclude-vertex-ai"
        }
        return CostUsageClaudeReportMemoKey(
            provider: provider,
            providerFilter: providerFilterKey,
            sinceKey: range.sinceKey,
            untilKey: range.untilKey,
            scanSinceKey: range.scanSinceKey,
            scanUntilKey: range.scanUntilKey,
            timeZoneIdentifier: range.calendar.timeZone.identifier,
            roots: roots.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }.sorted(),
            cacheArtifactStamp: artifactStamps.cache,
            pricingArtifactStamp: artifactStamps.pricing)
    }

    private static func buildClaudeReportFromCache(
        cache: CostUsageCache,
        range: CostUsageDayRange,
        pricingResolver: CostUsagePricing.ClaudeResolver) -> CostUsageDailyReport
    {
        var entries: [CostUsageDailyReport.Entry] = []
        var totalInput = 0
        var totalOutput = 0
        var totalCacheRead = 0
        var totalCacheCreate = 0
        var totalTokens = 0
        var totalCost: Double = 0
        var costSeen = false
        let costScale = 1_000_000_000.0
        var repricedCosts: [ClaudeDayModelKey: ClaudeRepricedCost] = [:]
        let rows = Self.reconciledClaudeRows(cache: cache)
        if !rows.isEmpty {
            pricingResolver.prepareCatalog()
        }

        for row in rows {
            #if DEBUG
            Self.recordClaudeScanWork(.reprice)
            #endif
            let key = ClaudeDayModelKey(day: row.dayKey, model: row.model)
            var aggregate = repricedCosts[key] ?? ClaudeRepricedCost()
            aggregate.sampleCount += 1
            let isPriced = row.costPriced ?? (row.costNanos > 0)
            let currentPricingCost = pricingResolver.costUSD(
                model: row.model,
                inputTokens: row.input,
                cacheReadInputTokens: row.cacheRead,
                cacheCreationInputTokens: row.cacheCreate,
                cacheCreationInputTokens1h: row.cacheCreate1h ?? 0,
                outputTokens: row.output,
                pricingDate: row.timestampUnixMs.map {
                    Date(timeIntervalSince1970: Double($0) / 1000)
                })
            let cost: Double? = if isPriced, row.costNanos == 0 {
                0
            } else if let currentPricingCost {
                currentPricingCost
            } else if isPriced {
                Double(row.costNanos) / costScale
            } else {
                nil
            }
            if let cost {
                aggregate.total += cost
            } else {
                aggregate.unresolved = true
            }
            repricedCosts[key] = aggregate
        }

        let dayKeys = cache.days.keys.sorted().filter {
            CostUsageDayRange.isInRange(dayKey: $0, since: range.sinceKey, until: range.untilKey)
        }

        for day in dayKeys {
            guard let models = cache.days[day] else { continue }
            let modelNames = models.keys.sorted()

            var dayInput = 0
            var dayOutput = 0
            var dayCacheRead = 0
            var dayCacheCreate = 0

            var breakdown: [CostUsageDailyReport.ModelBreakdown] = []
            var dayCost: Double = 0
            var dayCostSeen = false

            for model in modelNames {
                let packed = models[model] ?? [0, 0, 0, 0]
                let input = packed[safe: 0] ?? 0
                let cacheRead = packed[safe: 1] ?? 0
                let cacheCreate = packed[safe: 2] ?? 0
                let output = packed[safe: 3] ?? 0
                let sampleCount = packed[safe: 5] ?? 0
                let totalTokens = input + cacheRead + cacheCreate + output

                // Cache tokens are tracked separately; totalTokens includes input + cache.
                dayInput += input
                dayCacheRead += cacheRead
                dayCacheCreate += cacheCreate
                dayOutput += output

                let repricedCost = repricedCosts[ClaudeDayModelKey(day: day, model: model)]
                let currentPricingCost: Double? = if let repricedCost,
                                                     repricedCost.sampleCount == sampleCount,
                                                     !repricedCost.unresolved
                {
                    repricedCost.total
                } else {
                    nil
                }
                let cost = currentPricingCost
                breakdown.append(
                    CostUsageDailyReport.ModelBreakdown(
                        modelName: model,
                        costUSD: cost,
                        totalTokens: totalTokens))
                if let cost {
                    dayCost += cost
                    dayCostSeen = true
                }
            }

            let sortedBreakdown = Self.sortedModelBreakdowns(breakdown)

            let dayTotal = dayInput + dayCacheRead + dayCacheCreate + dayOutput
            let entryCost = dayCostSeen ? dayCost : nil
            entries.append(CostUsageDailyReport.Entry(
                date: day,
                inputTokens: dayInput,
                outputTokens: dayOutput,
                cacheReadTokens: dayCacheRead,
                cacheCreationTokens: dayCacheCreate,
                totalTokens: dayTotal,
                costUSD: entryCost,
                modelsUsed: modelNames,
                modelBreakdowns: sortedBreakdown))

            totalInput += dayInput
            totalOutput += dayOutput
            totalCacheRead += dayCacheRead
            totalCacheCreate += dayCacheCreate
            totalTokens += dayTotal
            if let entryCost {
                totalCost += entryCost
                costSeen = true
            }
        }

        let summary: CostUsageDailyReport.Summary? = entries.isEmpty
            ? nil
            : CostUsageDailyReport.Summary(
                totalInputTokens: totalInput,
                totalOutputTokens: totalOutput,
                cacheReadTokens: totalCacheRead,
                cacheCreationTokens: totalCacheCreate,
                totalTokens: totalTokens,
                totalCostUSD: costSeen ? totalCost : nil)

        return CostUsageDailyReport(data: entries, summary: summary)
    }
}
