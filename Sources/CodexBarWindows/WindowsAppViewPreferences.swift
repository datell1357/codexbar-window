#if os(Windows)
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Window navigation and spend display choices. Collection, accounts and sharing authority live elsewhere.
enum WindowsAppViewPreferences {
    static let storageKey = "windowsNativeAppViewV1"
    static let maximumStoredBytes = 4096

    struct Values: Codable, Sendable, Equatable {
        var schemaVersion = 1
        var navigation = "overview"
        var days = 30
        var currency: String?
        var section = "providers"
        var chart = "cost"
        var comparePeriods = false
        var selectedDay: String?

        var isValid: Bool {
            guard self.schemaVersion == 1,
                  ["overview", "spend", "costSettings", "settings"].contains(self.navigation),
                  [7, 30, 90, 365].contains(self.days),
                  ["providers", "models", "projects", "sessions"].contains(self.section),
                  ["cost", "tokens"].contains(self.chart) else { return false }
            if let code = self.currency {
                guard code.utf8.count == 3, code.utf8.allSatisfy({ (65...90).contains($0) }) else { return false }
            }
            if let day = self.selectedDay {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                guard day.utf8.count == 10,
                      WindowsAppSpendProjection.selectedDay(day, calendar: calendar) != nil else { return false }
            }
            return true
        }
    }
    struct Mutation: Codable, Sendable {
        let expectedRevision: String
        let values: Values
        var isValid: Bool {
            self.values.isValid && self.expectedRevision.utf8.count == 64
                && self.expectedRevision.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
    }
    struct Page: Codable, Sendable {
        let status: String
        let revision: String
        let values: Values
    }
    struct Result: Sendable {
        let status: String
        let page: Page
    }

    static func page(data: Data?) -> Page {
        guard let data else { return Page(status: "ready", revision: Self.revision(Data("missing".utf8)), values: Values()) }
        guard !data.isEmpty, data.count <= Self.maximumStoredBytes else { return Self.unavailable("invalid") }
        struct Header: Decodable { let schemaVersion: Int }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { return Self.unavailable("invalid") }
        guard header.schemaVersion == 1 else { return Self.unavailable("unsupported") }
        guard let values = try? JSONDecoder().decode(Values.self, from: data), values.isValid else {
            return Self.unavailable("invalid")
        }
        return Page(status: "ready", revision: Self.revision(data), values: values)
    }

    private static func revision(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func unavailable(_ status: String) -> Page {
        Page(status: status, revision: String(repeating: "0", count: 64), values: Values())
    }

    /// Serialize in-process read/compare/write. External editing is not a cross-process transaction.
    /// Invalid or newer stored data remains untouched. Injectable I/O keeps fixtures off real defaults.
    final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private let read: @Sendable () throws -> Data?
        private let write: @Sendable (Data) throws -> Void

        init(read: @escaping @Sendable () throws -> Data?, write: @escaping @Sendable (Data) throws -> Void) {
            self.read = read
            self.write = write
        }
        convenience init() {
            self.init(read: {
                guard let defaults = UserDefaults(suiteName: WindowsRefreshSettings.suiteName) else {
                    throw CocoaError(.fileReadUnknown)
                }
                guard let value = defaults.object(forKey: WindowsAppViewPreferences.storageKey) else { return nil }
                guard let data = value as? Data else { throw CocoaError(.coderReadCorrupt) }
                return data
            }, write: { data in
                guard let defaults = UserDefaults(suiteName: WindowsRefreshSettings.suiteName) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                defaults.set(data, forKey: WindowsAppViewPreferences.storageKey)
                guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
            })
        }
        func page() -> Page {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.readPage()
        }
        func save(_ mutation: Mutation) -> Result {
            self.lock.lock()
            defer { self.lock.unlock() }
            let current = self.readPage()
            guard mutation.isValid else { return .init(status: "invalidRequest", page: current) }
            guard current.status == "ready" else { return .init(status: "viewPreferencesUnavailable", page: current) }
            guard current.revision == mutation.expectedRevision else {
                return .init(status: "settingsChanged", page: current)
            }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(mutation.values)
                guard data.count <= WindowsAppViewPreferences.maximumStoredBytes else {
                    return .init(status: "invalidRequest", page: current)
                }
                try self.write(data)
                let saved = self.readPage()
                guard saved.status == "ready", saved.values == mutation.values else {
                    return .init(status: "settingsSaveFailed", page: saved)
                }
                return .init(status: "ok", page: saved)
            } catch {
                // synchronize can fail after an in-memory write. Return observed state, never success.
                return .init(status: "settingsSaveFailed", page: self.readPage())
            }
        }
        private func readPage() -> Page {
            do { return WindowsAppViewPreferences.page(data: try self.read()) }
            catch { return WindowsAppViewPreferences.unavailable("readFailed") }
        }
    }
}
#endif
