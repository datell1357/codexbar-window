#if os(Windows)
import Foundation
import CodexBarCore

/// Report-local evidence is reconciled with the same captured daily model totals before display.
enum WindowsCodexActivityAnalysis {
    struct Reference: Hashable, Sendable {
        let source: Int
        let number: Int
    }
    struct Model: Sendable {
        var effortTokens: [String: Int] = [:] // Empty key means unrecorded/invalid effort, never "none".
        var effortPricing: [String: WindowsCodexEffortPricing.Value] = [:]
        var sessions: Set<Reference> = []
        var sessionsComplete = true
        var rawAliases: Set<String> = []
        var aliasesComplete = true
        mutating func addAliases(_ values: [String], complete: Bool) {
            self.aliasesComplete = self.aliasesComplete && complete
            for value in values {
                if self.rawAliases.contains(value) { continue }
                if self.rawAliases.count < 256 { self.rawAliases.insert(value) }
                else { self.aliasesComplete = false }
            }
        }
    }
    struct Period: Sendable {
        var models: [String: Model] = [:]
        var complete = false
        var byDay: [String: [String: Model]] = [:]
        var sessions: [Reference: Session] = [:]
    }
    struct Session: Sendable {
        var models: [String: Model] = [:]
        var byDay: [String: [String: Model]] = [:]
        var sessionID: String? = nil
    }
    private struct Key: Hashable {
        let day: String
        let model: String
    }
    static func build(inputs: [WindowsSpendDashboardModel.ProviderInput],
                      interval: DateInterval, calendar: Calendar, costMultipliers: [Double]? = nil) -> Period {
        var result = Period(complete: !inputs.isEmpty)
        guard calendar.startOfDay(for: interval.start) == interval.start,
              calendar.startOfDay(for: interval.end) == interval.end else { return Period() }
        let start = Self.dayKey(interval.start, calendar: calendar)
        let end = Self.dayKey(interval.end.addingTimeInterval(-1), calendar: calendar)
        for (source, input) in inputs.enumerated() {
            guard input.provider == .codex, input.sourceKind == .native,
                  let evidence = input.snapshot.codexActivity, evidence.version == 1,
                  evidence.rows.count <= 8192, evidence.timeZoneIdentifier == calendar.timeZone.identifier,
                  Self.day(evidence.sinceDay, calendar: calendar) != nil,
                  Self.day(evidence.untilDay, calendar: calendar) != nil,
                  evidence.sinceDay <= start, evidence.untilDay >= end,
                  input.snapshot.daily.count <= 400
            else { result.complete = false; continue }
            var expected: [Key: Int] = [:]
            var actual: [Key: Int] = [:]
            var sourceModels: [String: Model] = [:]
            var sourceDays: [String: [String: Model]] = [:]
            var seenDays: Set<String> = []
            var valid = true
            var modelVisits = 0
            var aliasVisits = 0
            for entry in input.snapshot.daily {
                guard Self.day(entry.date, calendar: calendar) != nil else { valid = false; break }
                guard entry.date >= start, entry.date <= end else { continue }
                guard seenDays.insert(entry.date).inserted else { valid = false; break }
                var total = 0
                for row in entry.modelBreakdowns ?? [] {
                    modelVisits += 1
                    guard modelVisits <= 8192, row.modelName.utf8.count <= 256,
                          let tokens = row.totalTokens, tokens >= 0 else { valid = false; break }
                    let model = CodexModelsAnalyticsBuilder().canonicalID(row.modelName)
                    guard !model.isEmpty else { valid = false; break }
                    let key = Key(day: entry.date, model: model)
                    guard Self.add(tokens, to: &total), Self.add(tokens, key: key, to: &expected)
                    else { valid = false; break }
                }
                if !valid || entry.totalTokens != total { valid = false; break }
            }
            if !valid { result.complete = false; continue }
            for row in evidence.rows {
                guard Self.day(row.day, calendar: calendar) != nil,
                      row.day >= evidence.sinceDay, row.day <= evidence.untilDay,
                      row.model.utf8.count <= 256, row.tokens >= 0,
                      row.sessionReference.map({ (0..<4096).contains($0) }) ?? true else { valid = false; break }
                guard row.day >= start, row.day <= end, row.tokens > 0 else { continue }
                let model = CodexModelsAnalyticsBuilder().canonicalID(row.model)
                guard !model.isEmpty else { valid = false; break }
                let key = Key(day: row.day, model: model)
                guard Self.add(row.tokens, key: key, to: &actual) else { valid = false; break }
                var value = sourceModels[model] ?? Model()
                let aliasCount = row.rawAliases?.count ?? 0
                let aliases: (values: [String], complete: Bool)
                if aliasCount <= 8192 - aliasVisits {
                    aliasVisits += aliasCount
                    aliases = row.validatedAliases
                } else { aliases = ([], false) }
                value.addAliases(aliases.values, complete: aliases.complete)
                let effort = Self.effort(row.effort)
                guard Self.add(row.tokens, key: effort, to: &value.effortTokens) else { valid = false; break }
                if let reference = row.sessionReference { value.sessions.insert(.init(source: source, number: reference)) }
                else { value.sessionsComplete = false }
                sourceModels[model] = value
                var dayValue = sourceDays[row.day]?[model] ?? Model()
                guard Self.add(row.tokens, key: effort, to: &dayValue.effortTokens) else { valid = false; break }
                if let reference = row.sessionReference { dayValue.sessions.insert(.init(source: source, number: reference)) }
                else { dayValue.sessionsComplete = false }
                sourceDays[row.day, default: [:]][model] = dayValue
            }
            // No partial allocation to effort or sessions when event totals contradict the day/model report.
            guard valid, actual == expected else { result.complete = false; continue }
            result.complete = result.complete && evidence.rowsComplete
            let prices = WindowsCodexEffortPricing.build(daily: input.snapshot.daily, evidence: evidence,
                since: start, until: end, multiplier: costMultipliers.map { $0.indices.contains(source) ? $0[source] : .nan } ?? 1)
            for (day, models) in prices.byDay {
                for (model, efforts) in models {
                    for (effort, price) in efforts {
                        sourceModels[model, default: .init()].effortPricing[effort, default: .init()].merge(price)
                        sourceDays[day, default: [:]][model, default: .init()].effortPricing[effort, default: .init()].merge(price)
                    }
                }
            }
            for (model, sourceValue) in sourceModels {
                var value = result.models[model] ?? Model()
                for (effort, tokens) in sourceValue.effortTokens {
                    if !Self.add(tokens, key: effort, to: &value.effortTokens) { valid = false; break }
                }
                guard valid else { break }
                for (effort, price) in sourceValue.effortPricing {
                    value.effortPricing[effort, default: .init()].merge(price)
                }
                value.sessions.formUnion(sourceValue.sessions)
                value.sessionsComplete = value.sessionsComplete && sourceValue.sessionsComplete
                value.addAliases(sourceValue.rawAliases.sorted(), complete: sourceValue.aliasesComplete)
                result.models[model] = value
            }
            if !valid { return Period() } // Cross-source overflow invalidates the whole aggregation.
            let identities = evidence.resolvedSessionIdentities
            for (index, row) in evidence.rows.enumerated() where row.day >= start && row.day <= end && row.tokens > 0 {
                guard let reference = row.sessionReference else { continue }
                let key = Reference(source: source, number: reference)
                let model = CodexModelsAnalyticsBuilder().canonicalID(row.model)
                let effort = Self.effort(row.effort)
                var session = result.sessions[key] ?? Session()
                session.sessionID = identities[reference]
                var totals = session.models[model] ?? Model()
                var daily = session.byDay[row.day]?[model] ?? Model()
                guard Self.add(row.tokens, key: effort, to: &totals.effortTokens),
                      Self.add(row.tokens, key: effort, to: &daily.effortTokens) else { return Period() }
                if let pricing = prices.rows[index] {
                    totals.effortPricing[effort, default: .init()].merge(pricing)
                    daily.effortPricing[effort, default: .init()].merge(pricing)
                }
                totals.sessions.insert(key); daily.sessions.insert(key)
                session.models[model] = totals
                session.byDay[row.day, default: [:]][model] = daily
                result.sessions[key] = session
            }
            for (day, models) in sourceDays {
                for (model, incoming) in models {
                    var value = result.byDay[day]?[model] ?? Model()
                    for (effort, tokens) in incoming.effortTokens {
                        if !Self.add(tokens, key: effort, to: &value.effortTokens) { return Period() }
                    }
                    for (effort, price) in incoming.effortPricing {
                        value.effortPricing[effort, default: .init()].merge(price)
                    }
                    value.sessions.formUnion(incoming.sessions)
                    value.sessionsComplete = value.sessionsComplete && incoming.sessionsComplete
                    result.byDay[day, default: [:]][model] = value
                }
            }
        }
        return result
    }

    static func effort(_ raw: String?) -> String {
        guard let raw, raw.utf8.count <= 128 else { return "" }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (1...64).contains(value.utf8.count),
              value.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 })
        else { return "" }
        return value
    }

    private static func add(_ value: Int, to total: inout Int) -> Bool {
        let sum = total.addingReportingOverflow(value)
        guard !sum.overflow else { return false }
        total = sum.partialValue
        return true
    }
    private static func add<Key: Hashable>(_ value: Int, key: Key, to values: inout [Key: Int]) -> Bool {
        guard value > 0 else { return true }
        var total = values[key] ?? 0
        guard Self.add(value, to: &total) else { return false }
        values[key] = total
        return true
    }
    private static func dayKey(_ value: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: value)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    private static func day(_ key: String, calendar: Calendar) -> Date? {
        guard key.utf8.count == 10 else { return nil }
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let value = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              Self.dayKey(value, calendar: calendar) == key else { return nil }
        return value
    }
}
#endif
