#if os(Windows)
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Process-keyed view binding. Raw ownership IDs stay inside the MAC input, never in native UI JSON.
enum WindowsAppSpendSelection {
    static func codexExportRevision(modelsRevision: String, query: WindowsAppSpendProjection.Query,
                                    key: SymmetricKey) -> String {
        var mac = HMAC<SHA256>(key: key)
        let values = ["codex-model-csv-v1", modelsRevision, query.codexModel?.mode ?? "all",
                      query.codexGranularity ?? "daily", query.codexMetric ?? "tokens"]
            + (query.codexModel?.indices.map(String.init) ?? [])
        for value in values {
            let bytes = Data(value.utf8)
            mac.update(data: Data("\(bytes.count):".utf8))
            mac.update(data: bytes)
        }
        return mac.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func codexModelsRevision(analysis: WindowsCodexModelAnalysis.Snapshot, viewRevision: String,
                                    key: SymmetricKey) -> String {
        var mac = HMAC<SHA256>(key: key)
        for value in ["codex-model-selection-v2", viewRevision, String(analysis.modelKeys.count)] + analysis.modelKeys {
            let bytes = Data(value.utf8)
            mac.update(data: Data("\(bytes.count):".utf8))
            mac.update(data: bytes)
        }
        // Session navigation uses report-local numbers. Bind their ordering and model membership to this capture too.
        for (name, period) in [("current", analysis.current), ("previous", analysis.previous)] {
            for reference in period.activity.sessions.keys.sorted(by: {
                $0.source == $1.source ? $0.number < $1.number : $0.source < $1.source
            }) {
                let models = period.activity.sessions[reference]?.models.keys.sorted() ?? []
                let values = ["session", name, String(reference.source), String(reference.number), String(models.count)] + models
                for value in values {
                    let bytes = Data(value.utf8)
                    mac.update(data: Data("\(bytes.count):".utf8))
                    mac.update(data: bytes)
                }
            }
        }
        return mac.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func revision(snapshot: WindowsSpendDashboardController.Snapshot, query: WindowsAppSpendProjection.Query,
                         context: String, hidePersonalInfo: Bool, key: SymmetricKey,
                         conversionRates: [String: Double]? = nil) -> String {
        let group = query.currency.flatMap { code in snapshot.model.groups.first { $0.currencyCode == code } }
            ?? (query.currency == nil ? snapshot.model.groups.first : nil)
        let values = [context, String(query.days), group?.currencyCode ?? "", String(hidePersonalInfo),
                      String(snapshot.stale), group?.timeZone.identifier ?? "",
                      group.map { String($0.chartDomain.lowerBound.timeIntervalSince1970) } ?? "",
                      group.map { String($0.chartDomain.upperBound.timeIntervalSince1970) } ?? ""]
            + (group?.projects.map { "project:" + $0.id } ?? [])
            + (group?.sessions.map { "session:" + $0.id } ?? [])
        // Length prefixes keep adjacent IDs unambiguous without constructing another serialized copy.
        var mac = HMAC<SHA256>(key: key)
        for value in values {
            let bytes = Data(value.utf8)
            mac.update(data: Data("\(bytes.count):".utf8))
            mac.update(data: bytes)
        }
        // A share/export action must match the rates used to display the selected totals.
        let rates = conversionRates ?? [:]
        for code in rates.keys.sorted() {
            guard let rate = rates[code] else { continue }
            let value = code + ":" + String(rate)
            let bytes = Data(value.utf8)
            mac.update(data: Data("\(bytes.count):".utf8))
            mac.update(data: bytes)
        }
        return mac.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
#endif
