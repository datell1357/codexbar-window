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

    static func make(model: WindowsSpendDashboardModel, hiddenSourceIDs: [String], hidePersonalInfo: Bool = false) -> Self {
        var sourceIndex = 0
        return Self(
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
                        sourceIndex += 1
                        return Provider(
                            id: hidePersonalInfo ? "source-\(sourceIndex)" : $0.id,
                            displayName: hidePersonalInfo
                                ? ProviderDescriptorRegistry.descriptor(for: $0.provider).metadata.displayName
                                : LogRedactor.redact($0.displayName),
                            sourceKind: $0.sourceKind.rawValue,
                            totalTokens: $0.totalTokens,
                            totalCost: $0.totalCost)
                    },
                    models: group.models.enumerated().map { index, row in
                        Model(
                            provider: row.provider.rawValue,
                            modelName: hidePersonalInfo
                                ? WindowsShareStatsSanitizer.modelName(row.modelName) ?? "Model \(index + 1)"
                                : LogRedactor.redact(row.modelName),
                            totalTokens: row.totalTokens,
                            totalCost: row.totalCost)
                    })
            },
            hiddenSourceIDs: hidePersonalInfo
                ? hiddenSourceIDs.indices.map { "hidden-source-\($0 + 1)" } : hiddenSourceIDs)
    }
}

enum WindowsSpendDashboardJSONExporter {
    static func encodedData(model: WindowsSpendDashboardModel, hiddenSourceIDs: [String],
                            hidePersonalInfo: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(
            WindowsSpendDashboardExportPayload.make(model: model, hiddenSourceIDs: hiddenSourceIDs,
                                                     hidePersonalInfo: hidePersonalInfo))
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
