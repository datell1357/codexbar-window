import CodexBarCore

// Compatibility aliases keep existing CodexBar call sites and @testable-import surfaces stable
// while the implementation is shared by every platform through CodexBarCore.
typealias HistoricalUsageWindowKind = CodexBarCore.HistoricalUsageWindowKind
typealias HistoricalUsageRecordSource = CodexBarCore.HistoricalUsageRecordSource
typealias HistoricalUsageRecord = CodexBarCore.HistoricalUsageRecord
typealias HistoricalWeekProfile = CodexBarCore.HistoricalWeekProfile
typealias CodexHistoricalDataset = CodexBarCore.CodexHistoricalDataset
typealias HistoricalUsageHistoryStore = CodexBarCore.HistoricalUsageHistoryStore
typealias CodexHistoricalPaceEvaluator = CodexBarCore.CodexHistoricalPaceEvaluator
