#if os(Windows)
import CodexBarCore
import Foundation

/// Versioned, bounded payload for a future authenticated Windows widget transport.
/// A context identifier prevents stale delivery; it does not authenticate the sender.
public enum WindowsWidgetSnapshotCodec {
    public static let maximumBytes = 2 * 1024 * 1024
    public enum Failure: Error, Sendable {
        case oversized, malformed, unsupportedVersion, contextChanged, invalidSnapshot
    }
    private struct Envelope: Codable {
        let version: Int
        let contextID: UUID
        let snapshot: WidgetSnapshot
    }

    public static func encode(_ snapshot: WidgetSnapshot, contextID: UUID, now: Date) throws -> Data {
        try validate(snapshot, now: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do { data = try encoder.encode(Envelope(version: 1, contextID: contextID, snapshot: snapshot)) }
        catch { throw Failure.malformed }
        guard data.count <= maximumBytes else { throw Failure.oversized }
        return data
    }

    public static func decode(_ data: Data, expectedContextID: UUID, now: Date) throws -> WidgetSnapshot {
        guard data.count <= maximumBytes else { throw Failure.oversized }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope: Envelope
        do { envelope = try decoder.decode(Envelope.self, from: data) }
        catch { throw Failure.malformed }
        guard envelope.version == 1 else { throw Failure.unsupportedVersion }
        guard envelope.contextID == expectedContextID else { throw Failure.contextChanged }
        try validate(envelope.snapshot, now: now)
        return envelope.snapshot
    }

    private static func validate(_ snapshot: WidgetSnapshot, now: Date) throws {
        guard now.timeIntervalSince1970.isFinite,
              snapshot.entries.count <= 256, snapshot.enabledProviders.count <= 256 else { throw Failure.invalidSnapshot }
        try timestamp(snapshot.generatedAt, now: now)
        var enabled = Set<String>()
        for id in snapshot.enabledProviders {
            guard let provider = id.firstPartyProvider,
                  WindowsWidgetConfiguration.selectableProviders.contains(provider),
                  enabled.insert(id.rawValue).inserted else { throw Failure.invalidSnapshot }
        }
        var seen = Set<String>()
        for entry in snapshot.entries {
            guard let provider = entry.provider.firstPartyProvider,
                  WindowsWidgetConfiguration.selectableProviders.contains(provider),
                  seen.insert(entry.provider.rawValue).inserted,
                  entry.quotaOwnerKey == nil else { throw Failure.invalidSnapshot }
            try timestamp(entry.updatedAt, now: now)
            for window in [entry.primary, entry.secondary, entry.tertiary].compactMap({ $0 }) {
                try validateWindow(window)
            }
            let rows = entry.usageRows ?? []
            guard rows.count <= 64 else { throw Failure.invalidSnapshot }
            var rowIDs = Set<String>()
            for row in rows {
                try text(row.id, limit: 256); try text(row.title, limit: 1024)
                guard !row.id.isEmpty, rowIDs.insert(row.id).inserted,
                      row.percentLeft?.isFinite ?? true else { throw Failure.invalidSnapshot }
                if let window = row.window { try validateWindow(window) }
            }
            guard entry.creditsRemaining?.isFinite ?? true,
                  entry.codeReviewRemainingPercent?.isFinite ?? true else { throw Failure.invalidSnapshot }
            _ = try WindowsWidgetHistory.validatedDailyUsage(entry.dailyUsage)
            if let token = entry.tokenUsage {
                try text(token.sessionLabel, limit: 256); try text(token.last30DaysLabel, limit: 256)
                try currency(token.currencyCode)
                guard let updatedAt = token.updatedAt else { throw Failure.invalidSnapshot }
                try timestamp(updatedAt, now: now)
                for value in [token.sessionCostUSD, token.last30DaysCostUSD].compactMap({ $0 }) {
                    guard value.isFinite, value >= 0 else { throw Failure.invalidSnapshot }
                }
                for count in [token.sessionTokens, token.last30DaysTokens].compactMap({ $0 }) {
                    guard count >= 0 else { throw Failure.invalidSnapshot }
                }
            }
            if let cost = entry.providerCost {
                guard provider == .devin, cost.period == "Extra usage balance",
                      cost.used.isFinite, cost.limit.isFinite,
                      cost.nextRegenAmount == nil, cost.personalUsed == nil,
                      cost.balance == nil, cost.balanceUpdatedAt == nil else { throw Failure.invalidSnapshot }
                try currency(cost.currencyCode); try timestamp(cost.updatedAt, now: now)
                if let reset = cost.resetsAt, !reset.timeIntervalSince1970.isFinite { throw Failure.invalidSnapshot }
            }
        }
    }

    private static func validateWindow(_ window: RateWindow) throws {
        guard window.usedPercent.isFinite, window.nextRegenPercent?.isFinite ?? true,
              window.resetDescription == nil else { throw Failure.invalidSnapshot }
        if let minutes = window.windowMinutes, minutes <= 0 { throw Failure.invalidSnapshot }
        if let reset = window.resetsAt, !reset.timeIntervalSince1970.isFinite { throw Failure.invalidSnapshot }
    }

    private static func timestamp(_ date: Date, now: Date) throws {
        guard date.timeIntervalSince1970.isFinite, date.timeIntervalSince(now) <= 60 else { throw Failure.invalidSnapshot }
    }

    private static func text(_ value: String, limit: Int) throws {
        guard value.utf8.count <= limit,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw Failure.invalidSnapshot }
    }

    private static func currency(_ value: String) throws {
        guard value.utf8.count == 3, value.utf8.allSatisfy({ (65...90).contains($0) }) else { throw Failure.invalidSnapshot }
    }
}
#endif
