#if os(Windows)
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Process-keyed view binding. Raw ownership IDs stay inside the MAC input, never in native UI JSON.
enum WindowsAppSpendSelection {
    static func revision(snapshot: WindowsSpendDashboardController.Snapshot, query: WindowsAppSpendProjection.Query,
                         context: String, hidePersonalInfo: Bool, key: SymmetricKey) -> String {
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
        return mac.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
#endif
