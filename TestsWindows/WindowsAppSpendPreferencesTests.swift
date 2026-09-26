#if os(Windows)
import Foundation
import Testing
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
@testable import CodexBarWindows

/// Pure settings/catalog captures. No defaults, credentials, rates, provider calls or UI are opened.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsAppSpendPreferencesTests {
    private typealias Preferences = WindowsAppSpendPreferences
    private typealias Entry = WindowsSpendSourceSelection.Entry

    private static func sources(count: Int = 85, hidden: Set<String> = []) -> [Entry] {
        (0..<count).map {
            .init(id: "private-source-\($0)", title: "Account alias \($0) · private-account-\($0)@example.invalid",
                  included: !hidden.contains("private-source-\($0)"))
        }
    }
    private static func capture(settings: WindowsSpendSettings = .init(), sources: [Entry]? = Self.sources(),
                                privacy: Bool = true, context: String = "collection:1:9", keyByte: UInt8 = 1)
        -> Preferences.Capture {
        .init(settings: settings, sources: sources, hidePersonalInfo: privacy, context: context,
              key: SymmetricKey(data: Data(repeating: keyByte, count: 32)))
    }
    private static func mutation(_ key: String, _ capture: Preferences.Capture,
                                 value: Bool? = nil, currency: String? = nil, index: Int? = nil) -> Preferences.Mutation {
        .init(key: key, expectedRevision: capture.revision, value: value, currency: currency, sourceIndex: index)
    }

    @Test
    func `source pages retain global indices without transmitting private keys`() throws {
        let capture = Self.capture()
        let first = capture.page(.init())
        let second = capture.page(.init(page: 1))
        let last = capture.page(.init(page: 100000))
        #expect(first.sources.count == 40)
        #expect(second.sources.first?.index == 40)
        #expect(second.sources.first?.title == "Source 41")
        #expect(last.sources.count == 5)
        #expect(last.page == 2)
        #expect(last.pageCount == 3)
        #expect(last.totalSources == 85)
        #expect(last.sources.last?.index == 84)
        #expect(last.revision == first.revision)
        let wire = String(decoding: try JSONEncoder().encode(second), as: UTF8.self)
        #expect(!wire.contains("private-source"))
        #expect(!wire.contains("private-account"))
        #expect(!wire.contains("Account alias"))
        #expect(!wire.contains("example.invalid"))
        let visible = Self.capture(privacy: false).page(.init()).sources.first?.title
        #expect(visible?.contains("Account alias 0") == true)
        #expect(visible?.contains("<redacted-email>") == true)
    }

    @Test
    func `general preferences remain available without a completed source collection`() throws {
        let capture = Self.capture(sources: nil)
        let page = capture.page(.init())
        #expect(!page.sourcesAvailable)
        #expect(page.sources.isEmpty)
        #expect(page.pageCount == 1)
        let enabled = try #require(capture.applying(Self.mutation("collectionEnabled", capture, value: true)))
        #expect(enabled.collectionEnabled)
        #expect(!enabled.codexLocalLedgerEnabled)
        #expect(capture.applying(Self.mutation("allSourcesIncluded", capture, value: false)) == nil)
        #expect(capture.applying(Self.mutation("sourceIncluded", capture, value: false, index: 0)) == nil)
    }

    @Test
    func `catalog ambiguity and index drift never acquire source write authority`() {
        let duplicate = Entry(id: "duplicate", title: "Source", included: true)
        for catalog in [
            [Entry](), [duplicate, duplicate],
            [Entry(id: "", title: "Source", included: true)],
            [Entry(id: "bad\nkey", title: "Source", included: true)],
            [Entry(id: String(repeating: "x", count: 513), title: "Source", included: true)],
            [Entry(id: "source", title: "Source", included: false)],
            Self.sources(count: 4097)
        ] {
            let capture = Self.capture(sources: catalog)
            #expect(!capture.page(.init()).sourcesAvailable)
            #expect(capture.applying(Self.mutation("sourceIncluded", capture, value: true, index: 0)) == nil)
        }
        let capture = Self.capture()
        #expect(capture.applying(Self.mutation("sourceIncluded", capture, value: false, index: 85)) == nil)
        #expect(!Preferences.Query(page: -1).isValid)
        #expect(!Preferences.Query(page: 100001).isValid)
    }

    @Test
    func `settings catalog privacy and process changes invalidate the previous revision`() {
        let capture = Self.capture()
        let mutation = Self.mutation("sourceIncluded", capture, value: false, index: 40)
        #expect(Self.capture().applying(mutation) != nil)
        let reordered = Array(Self.sources().reversed())
        let renamed = [Entry(id: "private-source-0", title: "Renamed source", included: true)] + Array(Self.sources().dropFirst())
        var settings = WindowsSpendSettings()
        settings.hiddenSourceIDs = ["unavailable-source"]
        for changed in [
            Self.capture(context: "collection:2:10"), Self.capture(privacy: false), Self.capture(keyByte: 2),
            Self.capture(sources: reordered), Self.capture(sources: renamed), Self.capture(settings: settings),
            Self.capture(sources: nil)
        ] {
            #expect(changed.revision != capture.revision)
            #expect(changed.applying(mutation) == nil)
        }
    }

    @Test
    func `include exclude operations preserve preferences of unavailable sources`() throws {
        var settings = WindowsSpendSettings()
        settings.hiddenSourceIDs = ["private-source-1", "unavailable-source"]
        let capture = Self.capture(settings: settings, sources: Self.sources(hidden: settings.hiddenSourceIDs))
        let excluded = try #require(capture.applying(Self.mutation("sourceIncluded", capture, value: false, index: 40)))
        #expect(excluded.hiddenSourceIDs == ["private-source-1", "private-source-40", "unavailable-source"])
        #expect(excluded.collectionEnabled == settings.collectionEnabled)
        #expect(excluded.preferredCurrencyCode == settings.preferredCurrencyCode)
        let allShown = try #require(capture.applying(Self.mutation("allSourcesIncluded", capture, value: true)))
        #expect(allShown.hiddenSourceIDs == ["unavailable-source"])
        let allHidden = try #require(capture.applying(Self.mutation("allSourcesIncluded", capture, value: false)))
        #expect(allHidden.hiddenSourceIDs.count == 86)
        #expect(allHidden.hiddenSourceIDs.contains("unavailable-source"))
    }

    @Test
    func `allowlisted preference shapes reject extra arguments and unsupported currencies`() throws {
        let capture = Self.capture()
        for invalid in [
            Self.mutation("apiKey", capture, value: true),
            Self.mutation("collectionEnabled", capture),
            Self.mutation("collectionEnabled", capture, value: true, currency: "USD"),
            Self.mutation("allSourcesIncluded", capture, value: false, index: 0),
            Self.mutation("sourceIncluded", capture, value: false, index: -1),
            Self.mutation("preferredCurrencyCode", capture, value: true, currency: "USD"),
            Self.mutation("preferredCurrencyCode", capture, currency: "usd"),
            Self.mutation("preferredCurrencyCode", capture, currency: "ZZZ"),
            Self.mutation("preferredCurrencyCode", capture, currency: "https://example.invalid")
        ] {
            #expect(!invalid.isValid)
            #expect(capture.applying(invalid) == nil)
        }
        for code in Preferences.currencies {
            let changed = try #require(capture.applying(Self.mutation("preferredCurrencyCode", capture, currency: code)))
            #expect(changed.preferredCurrencyCode == code)
            #expect(changed.collectionEnabled == capture.settings.collectionEnabled)
        }
        for key in ["collectionEnabled", "codexLocalLedgerEnabled", "openCodexUsageLogsEnabled", "hideNativeCodexWhenOpenCodexPresent"] {
            let changed = try #require(capture.applying(Self.mutation(key, capture, value: true)))
            let switches = [changed.collectionEnabled, changed.codexLocalLedgerEnabled,
                            changed.openCodexUsageLogsEnabled, changed.hideNativeCodexWhenOpenCodexPresent]
            #expect(switches.filter { $0 }.count == 1)
            #expect(changed.hiddenSourceIDs.isEmpty)
            #expect(changed.historyDays == capture.settings.historyDays)
        }
    }

    @Test
    func `large source names stay within the native response frame`() throws {
        let title = "Name" + String(repeating: "한\u{0301}", count: 10000)
        let sources: [Entry] = (0..<85).map { .init(id: "private-source-\($0)", title: title, included: true) }
        let page = Self.capture(sources: sources, privacy: false).page(.init())
        #expect(page.truncated)
        #expect(page.sources.allSatisfy { $0.title.utf8.count <= 512 })
        var response = WindowsAppProtocol.Response(protocolVersion: 1, requestID: UUID(),
                                                   generation: UUID(), status: "ok", snapshot: nil)
        response.spendPreferences = page
        let data = try WindowsAppProtocol.response(response)
        #expect(data.count < WindowsAppProtocol.maximumResponseBytes)
        let decoded = try JSONDecoder().decode(WindowsAppProtocol.Response.self, from: data)
        #expect(decoded.spendPreferences?.sources.count == 40)
        #expect(decoded.spend == nil)
        #expect(decoded.snapshot == nil)
    }

    @Test
    func `preference wire uses bounded page and mutation fields independently of spend queries`() throws {
        let capture = Self.capture()
        var request = WindowsAppProtocol.Request(protocolVersion: 1, requestID: UUID(),
                                                generation: UUID(), method: "setSpendPreference", mutation: nil)
        request.spendPreferencesQuery = .init(page: 1)
        request.spendPreferencesMutation = Self.mutation("sourceIncluded", capture, value: false, index: 40)
        let wire = try JSONEncoder().encode(request)
        #expect(wire.count < WindowsAppProtocol.maximumRequestBytes)
        let decoded = try WindowsAppProtocol.request(wire)
        #expect(decoded.spendPreferencesQuery?.page == 1)
        #expect(decoded.spendPreferencesMutation?.sourceIndex == 40)
        #expect(decoded.spendPreferencesMutation?.value == false)
        #expect(decoded.spendPreferencesMutation?.isValid == true)
        #expect(decoded.spendQuery == nil)
        #expect(decoded.mutation == nil)
    }
}
#endif
