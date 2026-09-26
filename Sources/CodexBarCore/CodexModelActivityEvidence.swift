import Foundation

/// Local report evidence only. Rows use report-local numbers; the optional identity table stays internal.
/// CostUsageDailyReport deliberately omits this payload from its public JSON representation.
public struct CodexModelActivityEvidence: Codable, Equatable, Sendable {
    public struct SessionIdentity: Codable, Equatable, Sendable {
        public let reference: Int
        public let sessionID: String
        public init(reference: Int, sessionID: String) {
            self.reference = reference; self.sessionID = sessionID
        }
    }
    public struct Row: Codable, Equatable, Sendable {
        public let day: String
        public let model: String
        public let effort: String?
        public let sessionReference: Int?
        public let tokens: Int
        /// Optional for old reports. Counts partition tokens; known cost can cover only the priced portion.
        public let knownCostUSD: Double?
        public let pricedTokens: Int?
        public let unpricedTokens: Int?
        /// Raw event labels, not reconstructed from canonical model IDs. Optional for legacy reports.
        public let rawAliases: [String]?
        public let aliasesComplete: Bool?

        public init(day: String, model: String, effort: String?, sessionReference: Int?, tokens: Int,
                    knownCostUSD: Double? = nil, pricedTokens: Int? = nil, unpricedTokens: Int? = nil,
                    rawAliases: [String]? = nil, aliasesComplete: Bool? = nil) {
            self.day = day
            self.model = model
            self.effort = CostUsageCodexEffortContext.normalizedEffort(effort)
            self.sessionReference = sessionReference
            self.tokens = tokens
            self.knownCostUSD = knownCostUSD
            self.pricedTokens = pricedTokens
            self.unpricedTokens = unpricedTokens
            self.rawAliases = rawAliases
            self.aliasesComplete = aliasesComplete
        }
        public var validatedAliases: (values: [String], complete: Bool) {
            guard let rawAliases, rawAliases.count <= 32 else { return ([], false) }
            var result: Set<String> = []
            for alias in rawAliases {
                guard let valid = CodexModelActivityEvidence.rawAlias(alias, model: self.model),
                      result.insert(valid).inserted else { return ([], false) }
            }
            return (result.sorted(), self.aliasesComplete == true && !result.isEmpty)
        }
    }
    public let version: Int
    public let timeZoneIdentifier: String
    public let sinceDay: String
    public let untilDay: String
    public let rowsComplete: Bool
    public let rows: [Row]
    /// Missing in legacy reports. Never included in the public daily-report JSON.
    public let sessionIdentities: [SessionIdentity]?

    public init(timeZoneIdentifier: String, sinceDay: String, untilDay: String, rowsComplete: Bool, rows: [Row],
                sessionIdentities: [SessionIdentity]? = nil) {
        self.version = 1
        self.timeZoneIdentifier = timeZoneIdentifier
        self.sinceDay = sinceDay
        self.untilDay = untilDay
        self.rowsComplete = rowsComplete
        self.rows = rows
        self.sessionIdentities = sessionIdentities
    }

    public static func normalizedSessionID(_ raw: String?) -> String? {
        guard let raw, raw.utf8.count <= 512 else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.illegalCharacters.contains($0)
        }) else { return nil }
        return UUID(uuidString: value)?.uuidString.lowercased() ?? value
    }

    public static func rawAlias(_ raw: String?, model: String) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              raw.utf8.count <= 256, !raw.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              CodexModelsAnalyticsBuilder().canonicalID(raw) == CodexModelsAnalyticsBuilder().canonicalID(model)
        else { return nil }
        return raw
    }

    /// Ambiguous or malformed identity metadata must not affect valid token/cost evidence.
    public var resolvedSessionIdentities: [Int: String] {
        guard let entries = self.sessionIdentities, entries.count <= 4096 else { return [:] }
        var result: [Int: String] = [:]
        var seen: Set<String> = []
        for entry in entries {
            guard (0..<4096).contains(entry.reference),
                  let id = Self.normalizedSessionID(entry.sessionID),
                  result[entry.reference] == nil, seen.insert(id).inserted else { return [:] }
            result[entry.reference] = id
        }
        return result
    }
}
