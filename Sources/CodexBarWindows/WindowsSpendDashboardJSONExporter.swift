#if os(Windows)
import Foundation
import CodexBarCore

// Original spend export schema; intentionally excludes project paths and session records.
struct WindowsSpendDashboardExportPayload: Encodable, Sendable {
    let requestedDays: Int
    let selectedDay: Date?
    let groups: [Group]
    let hiddenSourceIDs: [String]

    struct Group: Encodable, Sendable {
        let currencyCode: String
        let totalTokens: Int?
        let totalCost: Double?
        let meteredCost: Double?
        let provenance: String
        let coverage: CostUsageCoverageCounts
        let tokenMix: CostUsageTokenMix
        let providers: [Provider]
        let models: [Model]
    }

    struct Provider: Encodable, Sendable {
        let id: String
        let displayName: String
        let sourceKind: String
        let totalTokens: Int?
        let totalCost: Double?
    }

    struct Model: Encodable, Sendable {
        let provider: String
        let modelName: String
        let totalTokens: Int?
        let totalCost: Double?
    }

    static func make(model: WindowsSpendDashboardModel, hiddenSourceIDs: [String]) -> Self {
        Self(
            requestedDays: model.requestedDays,
            selectedDay: model.selectedDay,
            groups: model.groups.map { group in
                Group(
                    currencyCode: group.currencyCode,
                    totalTokens: group.totalTokens,
                    totalCost: group.totalCost,
                    meteredCost: group.meteredCost,
                    provenance: group.provenance.rawValue,
                    coverage: group.coverage,
                    tokenMix: group.tokenMix,
                    providers: group.providers.map {
                        Provider(
                            id: $0.id,
                            displayName: $0.displayName,
                            sourceKind: $0.sourceKind.rawValue,
                            totalTokens: $0.totalTokens,
                            totalCost: $0.totalCost)
                    },
                    models: group.models.map {
                        Model(
                            provider: $0.provider.rawValue,
                            modelName: $0.modelName,
                            totalTokens: $0.totalTokens,
                            totalCost: $0.totalCost)
                    })
            },
            hiddenSourceIDs: hiddenSourceIDs)
    }
}

enum WindowsSpendDashboardJSONExporter {
    static func encodedData(model: WindowsSpendDashboardModel, hiddenSourceIDs: [String]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(
            WindowsSpendDashboardExportPayload.make(model: model, hiddenSourceIDs: hiddenSourceIDs))
    }

    static func defaultFilename(days: Int) -> String {
        if days >= WindowsSpendHistoryPolicy.scanDays {
            return "codexbar-spend-all-time.json"
        }
        return "codexbar-spend-last-\(days)-days.json"
    }

    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

}
#endif
