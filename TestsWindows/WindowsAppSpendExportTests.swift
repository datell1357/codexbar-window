#if os(Windows)
import Foundation
import Testing
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
@testable import CodexBarCore
@testable import CodexBarWindows

/// Synthetic values and an injected byte renderer only. No GDI, clipboard, defaults, files or dialogs.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsAppSpendExportTests {
    private typealias Model = WindowsSpendDashboardModel
    private typealias Snapshot = WindowsSpendDashboardController.Snapshot
    private typealias Export = WindowsAppSpendExport
    private static let revision = String(repeating: "a", count: 64)
    private static let day = Date(timeIntervalSince1970: 1788912000)
    private static var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private static func group(_ code: String, cost: Double = 2, alias: String = "Private Account") -> Model.CurrencyGroup {
        let start = Self.calendar.date(byAdding: .day, value: -6, to: Self.day)!
        let end = Self.calendar.date(byAdding: .day, value: 1, to: Self.day)!
        let models: [Model.ModelRow] = [
            .init(rank: 1, provider: .codex, providerName: alias, modelName: "gpt-example",
                  totalTokens: 10, totalCost: cost),
            .init(rank: 2, provider: .codex, providerName: alias, modelName: "C:\\private\\model",
                  totalTokens: 0, totalCost: 0)
        ]
        return .init(currencyCode: code,
            providers: [.init(id: "private-owner-\(code)", rank: 1, provider: .codex, displayName: alias,
                              totalTokens: 10, totalCost: cost, coveredDayCount: 7)],
            models: models,
            projects: [.init(rank: 1, provider: .codex, providerName: alias, sourceID: "private-owner-\(code)",
                projectName: "Private Repository", path: "C:\\private\\repository", totalTokens: 10, totalCost: cost)],
            dailyPoints: [], totalTokens: 10, totalCost: cost, coveredDayCount: 7,
            chartDomain: start...end,
            modelHistoryCompleteness: .complete,
            sessions: [.init(id: "private-session", sourceID: "private-owner-\(code)", provider: .codex,
                displayName: alias, lastActivity: Self.day, totalTokens: 10, totalCost: cost, modelName: nil)],
            timeZone: Self.calendar.timeZone)
    }
    private static func snapshot(stale: Bool = false, partial: Bool = false, openCodeUnavailable: Bool = false,
                                 selectedDay: Date? = nil, alias: String = "Private Account") -> Snapshot {
        let model = Model(requestedDays: 7, groups: [Self.group("EUR", cost: 99), Self.group("USD", alias: alias)],
                          selectedDay: selectedDay)
        return .init(generation: 1, phase: partial ? .partial : .ready, model: model,
            sharePayload: WindowsShareStatsBuilder.make(model: model), loadedAt: Self.day, stale: stale, failure: nil,
            openCodexObservation: openCodeUnavailable ? .unavailable : .disabled,
            sourceFailures: partial ? [.init(sourceID: "private-owner-USD", provider: .codex,
                                             accountIdentityUnconfirmed: true)] : [])
    }
    private static func make(_ kind: String, snapshot: Snapshot = Self.snapshot(), currency: String = "USD",
                             privacy: Bool = true) -> WindowsUsageRuntime.ShareStatsCopyResult {
        Export.make(snapshot: snapshot, currency: currency, action: kind, hidePersonalInfo: privacy,
            hiddenSourceIDs: ["hidden-private-owner"], calendar: Self.calendar, renderer: { _, _ in nil })
    }
    private static func isUnavailable(_ result: WindowsUsageRuntime.ShareStatsCopyResult) -> Bool {
        if case .unavailable = result { return true }
        return false
    }

    @Test
    func `action wire carries an allowlisted operation and revision without artifact bytes`() throws {
        for kind in ["preview", "copyText", "copyImage", "saveImage", "copyJSON", "saveJSON"] {
            let action = Export.Action(kind: kind, expectedRevision: Self.revision)
            #expect(action.isValid)
            let request = WindowsAppProtocol.Request(protocolVersion: 1, requestID: UUID(), generation: UUID(),
                method: "spendAction", mutation: nil, spendQuery: .init(days: 7, currency: "USD"), spendAction: action)
            let data = try JSONEncoder().encode(request)
            #expect(data.count < WindowsAppProtocol.maximumRequestBytes)
            let decoded = try WindowsAppProtocol.request(data)
            #expect(decoded.spendAction?.kind == kind)
            #expect(decoded.spendAction?.expectedRevision == Self.revision)
        }
        for action in [
            Export.Action(kind: "execute", expectedRevision: Self.revision),
            .init(kind: "saveJSON", expectedRevision: "old"),
            .init(kind: "copyText", expectedRevision: String(repeating: "G", count: 64))
        ] { #expect(!action.isValid) }
    }

    @Test
    func `JSON selects the displayed period and currency instead of all groups`() throws {
        guard case let .json(data, filename, copy, notice) = Self.make("copyJSON") else {
            Issue.record("Expected selected JSON"); return
        }
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try #require(object["groups"] as? [[String: Any]])
        #expect(object["requestedDays"] as? Int == 7)
        #expect(groups.count == 1)
        #expect(groups.first?["currencyCode"] as? String == "USD")
        #expect(groups.first?["totalCost"] as? Double == 2)
        #expect(filename == "codexbar-spend-last-7-days-USD.json")
        #expect(copy && notice == nil)
    }

    @Test
    func `privacy JSON removes identifiers aliases and private models while local detail stays explicit`() throws {
        let model = Self.snapshot().model
        let hidden = WindowsSpendDashboardExportPayload.make(model: model,
            hiddenSourceIDs: ["hidden-private-owner"], hidePersonalInfo: true)
        #expect(hidden.groups[0].providers[0].id == "source-1")
        #expect(hidden.groups[1].providers[0].id == "source-2")
        #expect(hidden.hiddenSourceIDs == ["hidden-source-1"])
        #expect(hidden.groups.allSatisfy { $0.models.map(\.modelName) == ["GPT", "Model 2"] })
        let wire = String(decoding: try WindowsSpendDashboardJSONExporter.encodedData(model: model,
            hiddenSourceIDs: ["hidden-private-owner"], hidePersonalInfo: true), as: UTF8.self)
        for privateValue in ["private", "Private Account", "Repository", "session"] {
            #expect(!wire.contains(privateValue))
        }
        let local = WindowsSpendDashboardExportPayload.make(model: model, hiddenSourceIDs: ["hidden-private-owner"])
        #expect(local.groups[1].providers[0].id == "private-owner-USD")
        #expect(local.groups[1].providers[0].displayName == "Private Account")
        #expect(local.hiddenSourceIDs == ["hidden-private-owner"])
        let localWire = String(decoding: try JSONEncoder().encode(local), as: UTF8.self)
        #expect(!localWire.contains("Private Repository"))
        #expect(!localWire.contains("private-session"))
    }

    @Test
    func `share text uses public labels and skips image rendering`() {
        let snapshot = Self.snapshot()
        let canonical = ProviderDescriptorRegistry.descriptor(for: .codex).metadata.displayName
        #expect(snapshot.sharePayload?.providers.allSatisfy { $0.providerName == canonical } == true)
        #expect(snapshot.sharePayload?.topModels.allSatisfy { $0.providerName == canonical && $0.modelName == "GPT" } == true)
        var renders = 0
        let result = Export.make(snapshot: snapshot, currency: "USD", action: "copyText", hidePersonalInfo: false,
            hiddenSourceIDs: [], calendar: Self.calendar, renderer: { _, _ in renders += 1; return nil })
        guard case let .ready(text) = result else { Issue.record("Expected text"); return }
        #expect(renders == 0)
        #expect(text.contains(canonical))
        #expect(!text.contains("EUR"))
        #expect(!text.contains("Private Account"))
        #expect(!text.contains("private-owner"))
    }

    @Test
    func `preview copy and save use the scoped renderer output without rerendering`() {
        let png = Data([1, 2, 3]), dib = Data([4, 5, 6]) // Opaque injected bytes, not an encoded-image validity fixture.
        for action in ["preview", "copyImage", "saveImage"] {
            var renders = 0
            let result = Export.make(snapshot: Self.snapshot(), currency: "USD", action: action,
                hidePersonalInfo: true, hiddenSourceIDs: [], calendar: Self.calendar, renderer: { payload, calendar in
                    renders += 1
                    #expect(payload.days == 7 && payload.totalTokens == 10)
                    #expect(payload.currencies.map(\.currencyCode) == ["USD"])
                    #expect(payload.currencies.first?.estimatedCost == 2)
                    #expect(payload.providers.allSatisfy { $0.currencyCode == "USD" })
                    #expect(payload.topModels.allSatisfy { $0.currencyCode == "USD" })
                    #expect(calendar.timeZone == Self.calendar.timeZone)
                    return .init(png: png, dib: dib)
                })
            #expect(renders == 1)
            switch result {
            case let .preview(actualPNG, actualDIB, filename, text):
                #expect(action == "preview" && actualPNG == png && actualDIB == dib)
                #expect(filename == "codexbar-subscriptions-last-7-days-USD.png" && !text.contains("EUR"))
            case let .clipboardImage(actualPNG, actualDIB):
                #expect(action == "copyImage" && actualPNG == png && actualDIB == dib)
            case let .image(actualPNG, filename):
                #expect(action == "saveImage" && actualPNG == png && filename.hasSuffix("-USD.png"))
            default: Issue.record("Expected the requested image operation")
            }
        }
    }

    @Test
    func `incomplete collections block share cards and retain a JSON collection notice`() {
        for snapshot in [
            Self.snapshot(stale: true), Self.snapshot(partial: true), Self.snapshot(openCodeUnavailable: true)
        ] {
            #expect(Self.isUnavailable(Self.make("copyText", snapshot: snapshot)))
            guard case let .json(_, _, _, notice) = Self.make("saveJSON", snapshot: snapshot) else {
                Issue.record("Expected partial JSON with a notice"); continue
            }
            #expect(notice != nil)
        }
        #expect(Export.collectionNotice(Self.snapshot(partial: true))?.contains("account identity") == true)
        #expect(Export.collectionNotice(Self.snapshot()) == nil)
    }

    @Test
    func `missing currency day scope and failed rendering do not produce artifacts`() {
        #expect(Self.isUnavailable(Self.make("saveJSON", currency: "KRW")))
        #expect(Self.isUnavailable(Self.make("saveJSON", snapshot: Self.snapshot(selectedDay: Self.day))))
        #expect(Self.isUnavailable(Self.make("execute")))
        #expect(Self.isUnavailable(Self.make("preview"))) // Injected renderer returns nil.
        let empty = Export.make(snapshot: Self.snapshot(), currency: "USD", action: "copyImage",
            hidePersonalInfo: true, hiddenSourceIDs: [], calendar: Self.calendar,
            renderer: { _, _ in .init(png: Data(), dib: Data([1])) })
        #expect(Self.isUnavailable(empty))
    }

    @Test
    func `large JSON can be saved without exceeding the clipboard text bound`() {
        let snapshot = Self.snapshot(alias: String(repeating: "A", count: 70000))
        #expect(Self.isUnavailable(Self.make("copyJSON", snapshot: snapshot, privacy: false)))
        guard case let .json(data, _, copy, _) = Self.make("saveJSON", snapshot: snapshot, privacy: false) else {
            Issue.record("Expected a file export"); return
        }
        #expect(!copy && data.count > 65536 && data.count < 16 * 1024 * 1024)
    }

    @Test
    func `the view revision binds the captured exchange rates in stable key order`() {
        let key = SymmetricKey(data: Data(repeating: 1, count: 32))
        func revision(_ rates: [String: Double], privacy: Bool = true) -> String {
            WindowsAppSpendSelection.revision(snapshot: Self.snapshot(), query: .init(days: 7, currency: "USD"),
                context: "collection-1", hidePersonalInfo: privacy, key: key, conversionRates: rates)
        }
        #expect(revision(["USD": 1, "EUR": 0.9]) == revision(["EUR": 0.9, "USD": 1]))
        #expect(revision(["USD": 1, "EUR": 0.9]) != revision(["USD": 1, "EUR": 0.95]))
        #expect(revision(["USD": 1]) != revision(["USD": 1], privacy: false))
    }

    @Test
    func `a delivery can be withdrawn before the native consumer performs an effect`() {
        let validity = WindowsSnapshotValidity()
        let delivery = Export.Delivery(requestID: UUID(), hidePersonalInfo: true,
            result: .ready("synthetic"), isCurrent: validity.capture())
        #expect(delivery.isCurrent())
        validity.invalidate()
        #expect(!delivery.isCurrent())
        #expect(validity.capture()())
    }
}
#endif
