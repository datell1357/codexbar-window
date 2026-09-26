#if os(Windows)
import Foundation
import CodexBarCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Display-only source indices are bound to this capture; raw account/source IDs stay in the runtime.
enum WindowsAppSpendPreferences {
    static let currencies = ["auto"] + CurrencyExchange.supportedCurrencies
    struct Query: Codable, Sendable {
        var page = 0
        var isValid: Bool { (0...100000).contains(self.page) }
    }
    struct Mutation: Codable, Sendable {
        let key: String
        let expectedRevision: String
        var value: Bool?
        var currency: String?
        var sourceIndex: Int?

        var isValid: Bool {
            guard self.expectedRevision.utf8.count == 64,
                  self.expectedRevision.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return false }
            switch self.key {
            case "collectionEnabled", "codexLocalLedgerEnabled", "openCodexUsageLogsEnabled",
                 "hideNativeCodexWhenOpenCodexPresent", "allSourcesIncluded":
                return self.value != nil && self.currency == nil && self.sourceIndex == nil
            case "preferredCurrencyCode":
                return self.value == nil && self.sourceIndex == nil
                    && self.currency.map { WindowsAppSpendPreferences.currencies.contains($0) } == true
            case "sourceIncluded":
                return self.value != nil && self.currency == nil && self.sourceIndex.map { (0..<4096).contains($0) } == true
            default: return false
            }
        }
    }
    struct Source: Codable, Sendable {
        let index: Int
        let title: String
        let included: Bool
    }
    struct Page: Codable, Sendable {
        let revision: String
        let collectionEnabled: Bool
        let codexLocalLedgerEnabled: Bool
        let openCodexUsageLogsEnabled: Bool
        let hideNativeCodexWhenOpenCodexPresent: Bool
        let preferredCurrencyCode: String
        let currencies: [String]
        let sourcesAvailable: Bool
        let page: Int
        let pageCount: Int
        let totalSources: Int
        let sources: [Source]
        let truncated: Bool
    }

    struct Capture: Sendable {
        let settings: WindowsSpendSettings
        let sources: [WindowsSpendSourceSelection.Entry]?
        let hidePersonalInfo: Bool
        let revision: String

        init(settings: WindowsSpendSettings, sources: [WindowsSpendSourceSelection.Entry]?,
             hidePersonalInfo: Bool, context: String, key: SymmetricKey) {
            self.settings = settings
            // Reject malformed catalogs as a whole so indices can never drift around filtered-out rows.
            let accepted = sources.flatMap { rows -> [WindowsSpendSourceSelection.Entry]? in
                guard !rows.isEmpty, rows.count <= 4096, Set(rows.map(\.id)).count == rows.count,
                      rows.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 512
                          && !$0.id.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
                          && $0.included == !settings.hiddenSourceIDs.contains($0.id) }) else { return nil }
                return rows
            }
            self.sources = accepted
            self.hidePersonalInfo = hidePersonalInfo
            var mac = HMAC<SHA256>(key: key)
            func add(_ value: String) {
                let data = Data(value.utf8)
                mac.update(data: Data("\(data.count):".utf8))
                mac.update(data: data)
            }
            for field in ["native-spend-preferences-v1", context, String(hidePersonalInfo),
                          String(settings.collectionEnabled), String(settings.codexLocalLedgerEnabled),
                          String(settings.openCodexUsageLogsEnabled), String(settings.hideNativeCodexWhenOpenCodexPresent),
                          String(settings.historyDays), settings.bucketTimeZoneIdentifier, settings.preferredCurrencyCode] {
                add(field)
            }
            add(String(settings.hiddenSourceIDs.count))
            for id in settings.hiddenSourceIDs.sorted() { add(id) }
            add(accepted == nil ? "unavailable" : "available")
            for source in accepted ?? [] {
                add(source.id); add(source.title); add(String(source.included))
            }
            self.revision = mac.finalize().map { String(format: "%02x", $0) }.joined()
        }

        func page(_ query: Query) -> Page {
            let sources = self.sources ?? []
            let pageCount = max(1, (sources.count + 39) / 40)
            let page = min(max(0, query.page), pageCount - 1)
            var truncated = false
            let rows = (page * 40..<min(sources.count, page * 40 + 40)).map { index in
                let raw = self.hidePersonalInfo ? "Source \(index + 1)" : sources[index].title
                let sanitized = LogRedactor.redact(raw).unicodeScalars
                    .filter { $0.value >= 0x20 && $0.value != 0x7F }.map(String.init).joined()
                let title = WindowsAppProtocol.boundedText(sanitized, maximumUTF8Bytes: 512)
                truncated = truncated || title.truncated
                return Source(index: index, title: title.text.isEmpty ? "Source \(index + 1)" : title.text,
                              included: sources[index].included)
            }
            return .init(revision: self.revision, collectionEnabled: self.settings.collectionEnabled,
                codexLocalLedgerEnabled: self.settings.codexLocalLedgerEnabled,
                openCodexUsageLogsEnabled: self.settings.openCodexUsageLogsEnabled,
                hideNativeCodexWhenOpenCodexPresent: self.settings.hideNativeCodexWhenOpenCodexPresent,
                preferredCurrencyCode: self.settings.preferredCurrencyCode, currencies: WindowsAppSpendPreferences.currencies,
                sourcesAvailable: self.sources != nil, page: page, pageCount: pageCount, totalSources: sources.count,
                sources: rows, truncated: truncated)
        }

        /// Return a settings delta only for the precise settings/catalog the user saw.
        func applying(_ mutation: Mutation) -> WindowsSpendSettings? {
            guard mutation.isValid, mutation.expectedRevision == self.revision else { return nil }
            var updated = self.settings
            switch mutation.key {
            case "collectionEnabled": updated.collectionEnabled = mutation.value!
            case "codexLocalLedgerEnabled": updated.codexLocalLedgerEnabled = mutation.value!
            case "openCodexUsageLogsEnabled": updated.openCodexUsageLogsEnabled = mutation.value!
            case "hideNativeCodexWhenOpenCodexPresent": updated.hideNativeCodexWhenOpenCodexPresent = mutation.value!
            case "preferredCurrencyCode": updated.preferredCurrencyCode = mutation.currency!
            case "sourceIncluded":
                guard let sources = self.sources, let index = mutation.sourceIndex, sources.indices.contains(index) else { return nil }
                let id = sources[index].id
                if mutation.value! { updated.hiddenSourceIDs.remove(id) } else { updated.hiddenSourceIDs.insert(id) }
            case "allSourcesIncluded":
                guard let sources = self.sources else { return nil }
                let ids = Set(sources.map(\.id))
                if mutation.value! { updated.hiddenSourceIDs.subtract(ids) } else { updated.hiddenSourceIDs.formUnion(ids) }
            default: return nil
            }
            return updated
        }
    }
}
#endif
