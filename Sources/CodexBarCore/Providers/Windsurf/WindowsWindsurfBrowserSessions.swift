#if os(Windows)
import Foundation

/// Builds structural candidates only. A candidate must pass a provider request before it can be saved.
enum WindowsWindsurfBrowserSessions {
    struct Candidate: Sendable {
        let id: UUID
        let sourceLabel: String
        let origin: String
        let sessionBundle: String
    }

    struct Result: Sendable {
        let candidates: [Candidate]
        let incompleteOrigins: Int
        let invalidOrigins: Int
    }

    enum Failure: Error { case timedOut }

    static func load(
        profile: WindowsChromiumLocalStorageProfiles.Profile,
        deadline: Date = Date().addingTimeInterval(15)) throws -> Result
    {
        try self.check(deadline)
        let snapshot = try WindowsLevelDBSnapshot.read(directory: profile.directory, deadline: deadline)
        return try self.candidates(in: snapshot, sourceLabel: profile.label, deadline: deadline)
    }

    static func candidates(
        in snapshot: WindowsLevelDBSnapshot.Snapshot,
        sourceLabel: String,
        deadline: Date) throws -> Result
    {
        let keys: Set<String> = [
            "devin_session_token", "devin_auth1_token", "devin_account_id", "devin_primary_org_id",
        ]
        var candidates: [Candidate] = []
        var incomplete = 0
        var invalid = 0
        // Keep each origin independent even when a browser has sessions for both services.
        for origin in ["https://app.devin.ai", "https://windsurf.com"] {
            try self.check(deadline)
            let values: [String: String]
            do {
                values = try WindowsChromiumLocalStorageDecoder.values(in: snapshot, origin: origin, keys: keys)
            } catch is CancellationError {
                throw CancellationError()
            } catch WindowsChromiumLocalStorageDecoder.Failure.unsupportedSchema {
                throw WindowsChromiumLocalStorageDecoder.Failure.unsupportedSchema
            } catch {
                invalid += 1
                continue
            }
            guard !values.isEmpty else { continue }
            guard values.count == keys.count else { incomplete += 1; continue }
            // Serialize once; the existing parser handles a single JSON.stringify storage layer.
            let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
            guard let bundle = String(data: data, encoding: .utf8) else { invalid += 1; continue }
            do {
                try WindsurfWebFetcher.validateManualSessionInput(bundle)
            } catch {
                invalid += 1
                continue
            }
            try self.check(deadline)
            candidates.append(Candidate(id: UUID(), sourceLabel: sourceLabel, origin: origin, sessionBundle: bundle))
        }
        try self.check(deadline)
        return Result(candidates: candidates, incompleteOrigins: incomplete, invalidOrigins: invalid)
    }

    private static func check(_ deadline: Date) throws {
        try Task.checkCancellation()
        guard Date() < deadline else { throw Failure.timedOut }
    }
}
#endif
