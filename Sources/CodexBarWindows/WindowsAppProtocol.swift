#if os(Windows)
import Foundation
import CodexBarCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Versioned UI contract. Only display values and an allowlist of non-secret settings cross this boundary.
enum WindowsAppProtocol {
    static let version = 1
    static let maximumRequestBytes = 4096
    static let maximumResponseBytes = 1024 * 1024
    enum Failure: Error { case invalidFrame, oversized }

    struct Request: Codable, Sendable {
        let protocolVersion: Int
        let requestID: UUID
        let generation: UUID?
        let method: String
        let mutation: Mutation?
        var spendQuery: WindowsAppSpendProjection.Query? = nil
        var spendPreferencesQuery: WindowsAppSpendPreferences.Query? = nil
        var spendPreferencesMutation: WindowsAppSpendPreferences.Mutation? = nil
        var spendAction: WindowsAppSpendExport.Action? = nil
    }
    struct Mutation: Codable, Sendable {
        let key: String
        let value: Bool
        let expectedSettingsRevision: String
    }
    struct Response: Codable, Sendable {
        let protocolVersion: Int
        let requestID: UUID
        let generation: UUID
        let status: String
        var snapshot: Snapshot?
        var activation: UInt64 = 0
        var spend: WindowsAppSpendProjection.Page? = nil
        var spendPreferences: WindowsAppSpendPreferences.Page? = nil
    }
    struct Settings: Codable, Sendable, Equatable {
        var hidePersonalInfo: Bool
        var showOptionalCreditsAndExtraUsage: Bool
        var usageBarsShowUsed: Bool
        var resetTimesShowAbsolute: Bool

        init(_ settings: WindowsUsagePresentationSettings) {
            self.hidePersonalInfo = settings.hidePersonalInfo
            self.showOptionalCreditsAndExtraUsage = settings.showOptionalCreditsAndExtraUsage
            self.usageBarsShowUsed = settings.usageBarsShowUsed
            self.resetTimesShowAbsolute = settings.resetTimesShowAbsolute
        }

        var revision: String {
            // Fixed order and boolean bytes make this independent of JSON encoder implementation.
            let bytes: [UInt8] = [self.hidePersonalInfo, self.showOptionalCreditsAndExtraUsage,
                self.usageBarsShowUsed, self.resetTimesShowAbsolute].map { $0 ? 1 : 0 }
            return SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
        }

        static let keys: Set<String> = ["hidePersonalInfo", "showOptionalCreditsAndExtraUsage",
            "usageBarsShowUsed", "resetTimesShowAbsolute"]
    }
    struct Card: Codable, Sendable {
        let id: String
        let title: String
        let rows: [String]
    }
    struct Snapshot: Codable, Sendable {
        let providers: [Card]
        let notices: [String]
        let spendSummary: String
        let refreshing: Bool
        let truncated: Bool
        let settings: Settings
        let settingsRevision: String
    }

    static func request(_ data: Data) throws -> Request {
        guard !data.isEmpty, data.count <= self.maximumRequestBytes else { throw Failure.oversized }
        return try JSONDecoder().decode(Request.self, from: data)
    }

    static func response(_ value: Response) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard !data.isEmpty, data.count <= self.maximumResponseBytes else { throw Failure.oversized }
        return data
    }

    /// Bound bytes, not grapheme count: one displayed character can contain arbitrarily many scalars.
    static func boundedText(_ value: String, maximumUTF8Bytes: Int) -> (text: String, truncated: Bool) {
        var result = ""
        var remaining = max(0, maximumUTF8Bytes)
        for scalar in value.unicodeScalars {
            let bytes = String(scalar).utf8.count
            guard bytes <= remaining else { return (result, true) }
            result.unicodeScalars.append(scalar)
            remaining -= bytes
        }
        return (result, false)
    }

    static func length(_ bytes: Data, limit: Int) throws -> Int {
        guard bytes.count == 4 else { throw Failure.invalidFrame }
        let length = bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
        guard length > 0, length <= limit else { throw Failure.oversized }
        return Int(length)
    }

    static func header(length: Int) throws -> Data {
        guard length > 0, length <= self.maximumResponseBytes else { throw Failure.oversized }
        return Data((0..<4).map { UInt8(truncatingIfNeeded: UInt32(length) >> ($0 * 8)) })
    }
}
#endif
