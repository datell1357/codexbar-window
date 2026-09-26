import Foundation

/// Local report evidence only. References are report-local numbers, never session IDs or paths.
/// CostUsageDailyReport deliberately omits this payload from its public JSON representation.
public struct CodexModelActivityEvidence: Codable, Equatable, Sendable {
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

        public init(day: String, model: String, effort: String?, sessionReference: Int?, tokens: Int,
                    knownCostUSD: Double? = nil, pricedTokens: Int? = nil, unpricedTokens: Int? = nil) {
            self.day = day
            self.model = model
            self.effort = CostUsageCodexEffortContext.normalizedEffort(effort)
            self.sessionReference = sessionReference
            self.tokens = tokens
            self.knownCostUSD = knownCostUSD
            self.pricedTokens = pricedTokens
            self.unpricedTokens = unpricedTokens
        }
    }
    public let version: Int
    public let timeZoneIdentifier: String
    public let sinceDay: String
    public let untilDay: String
    public let rowsComplete: Bool
    public let rows: [Row]

    public init(timeZoneIdentifier: String, sinceDay: String, untilDay: String, rowsComplete: Bool, rows: [Row]) {
        self.version = 1
        self.timeZoneIdentifier = timeZoneIdentifier
        self.sinceDay = sinceDay
        self.untilDay = untilDay
        self.rowsComplete = rowsComplete
        self.rows = rows
    }
}
