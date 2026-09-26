#if os(Windows)
import Foundation
import Testing
@testable import CodexBarWindows

/// In-memory fixtures only. No defaults, power reads, timers, providers or UI.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsAppGeneralPreferencesTests {
    private typealias Preferences = WindowsAppGeneralPreferences
    private static let initial = Preferences.Values(frequency: "adaptive", lowPowerMode: "off",
        statusChecksEnabled: true, refreshOnMenuOpen: false)

    @Test
    func `supported cadence and power choices preserve unrelated preferences`() throws {
        #expect(Preferences.frequencies.count == 7)
        for frequency in Preferences.frequencies {
            let changed = try #require(Self.initial.applying(.init(key: "frequency",
                expectedRevision: Self.initial.revision, choice: frequency.rawValue)))
            #expect(changed.frequency == frequency.rawValue)
            #expect(changed.lowPowerMode == "off")
            #expect(changed.statusChecksEnabled)
            #expect(!changed.refreshOnMenuOpen)
        }
        for mode in WindowsRefreshSettings.LowPowerModePreference.allCases {
            let changed = try #require(Self.initial.applying(.init(key: "lowPowerMode",
                expectedRevision: Self.initial.revision, choice: mode.rawValue)))
            #expect(changed.lowPowerMode == mode.rawValue)
            #expect(changed.frequency == "adaptive")
        }
    }

    @Test
    func `agent aware legacy value can be displayed and changed away from but not enabled`() throws {
        var legacy = Self.initial
        legacy.frequency = "adaptiveAgentAware"
        #expect(Preferences.Page(legacy).values.frequency == "adaptiveAgentAware")
        #expect(!Preferences.Mutation(key: "frequency", expectedRevision: legacy.revision,
            choice: "adaptiveAgentAware").isValid)
        let otherField = try #require(legacy.applying(.init(key: "statusChecksEnabled",
            expectedRevision: legacy.revision, value: false)))
        #expect(otherField.frequency == "adaptiveAgentAware")
        #expect(!otherField.statusChecksEnabled)
        let recovered = try #require(legacy.applying(.init(key: "frequency",
            expectedRevision: legacy.revision, choice: "fiveMinutes")))
        #expect(recovered.frequency == "fiveMinutes")
    }

    @Test
    func `typed allowlist rejects credentials consent mixed shapes and malformed revisions`() {
        let revision = Self.initial.revision
        let invalid: [Preferences.Mutation] = [
            .init(key: "apiKey", expectedRevision: revision, choice: "private"),
            .init(key: "adaptiveActivityScanConsent", expectedRevision: revision, choice: "allowed"),
            .init(key: "frequency", expectedRevision: revision, value: true, choice: "adaptive"),
            .init(key: "frequency", expectedRevision: revision, value: true),
            .init(key: "frequency", expectedRevision: revision, choice: "everySecond"),
            .init(key: "frequency", expectedRevision: revision, choice: "Adaptive"),
            .init(key: "lowPowerMode", expectedRevision: revision, choice: "battery"),
            .init(key: "statusChecksEnabled", expectedRevision: revision),
            .init(key: "refreshOnMenuOpen", expectedRevision: revision, value: false, choice: "false"),
            .init(key: "frequency", expectedRevision: "old", choice: "manual"),
            .init(key: "frequency", expectedRevision: String(repeating: "x", count: 64), choice: "manual")
        ]
        for mutation in invalid {
            #expect(!mutation.isValid)
            #expect(Self.initial.applying(mutation) == nil)
        }
    }

    @Test
    func `revision binds all general settings independently of display settings`() {
        var revisions = Set<String>()
        for frequency in WindowsRefreshSettings.Frequency.allCases {
            for power in WindowsRefreshSettings.LowPowerModePreference.allCases {
                for status in [true, false] {
                    for menu in [true, false] {
                        let values = Preferences.Values(frequency: frequency.rawValue, lowPowerMode: power.rawValue,
                            statusChecksEnabled: status, refreshOnMenuOpen: menu)
                        #expect(values.revision.count == 64)
                        revisions.insert(values.revision)
                    }
                }
            }
        }
        #expect(revisions.count == 8 * 3 * 4)
    }

    @Test
    func `stale app write cannot overwrite a changed tray preference`() {
        var stored = Self.initial
        stored.lowPowerMode = "automatic"
        var writes = 0
        var flushes = 0
        let result = Preferences.save(.init(key: "frequency", expectedRevision: Self.initial.revision, choice: "manual"),
            read: { stored }, write: { _, _ in writes += 1 }, synchronize: { flushes += 1; return true })
        #expect(result.status == "settingsChanged")
        #expect(result.page.values == stored)
        #expect(!result.changed)
        #expect(writes == 0)
        #expect(flushes == 0)
    }

    @Test
    func `unchanged and invalid writes do not persist or schedule work`() {
        for mutation in [
            Preferences.Mutation(key: "frequency", expectedRevision: Self.initial.revision, choice: "adaptive"),
            .init(key: "unknown", expectedRevision: Self.initial.revision, value: true)
        ] {
            var writes = 0
            var flushes = 0
            let result = Preferences.save(mutation, read: { Self.initial },
                write: { _, _ in writes += 1 }, synchronize: { flushes += 1; return true })
            #expect(!result.changed)
            #expect(writes == 0)
            #expect(flushes == 0)
            #expect(result.status == (mutation.key == "unknown" ? "invalidRequest" : "ok"))
        }
    }

    @Test
    func `save returns persisted values and an explicit runtime reconciliation signal`() {
        var stored = Self.initial
        var writes = 0
        var flushes = 0
        let result = Preferences.save(.init(key: "refreshOnMenuOpen", expectedRevision: stored.revision, value: true),
            read: { stored }, write: { updated, previous in
                #expect(previous == Self.initial)
                stored = updated
                writes += 1
            }, synchronize: { flushes += 1; return true })
        #expect(result.status == "ok")
        #expect(result.changed)
        #expect(result.page.values.refreshOnMenuOpen)
        #expect(result.page.values.frequency == "adaptive")
        #expect(result.page.revision != Self.initial.revision)
        #expect(writes == 1)
        #expect(flushes == 1)
    }

    @Test
    func `failed flush reports uncertain persistence without reverting or replaying`() {
        var stored = Self.initial
        var writes = 0
        let result = Preferences.save(.init(key: "statusChecksEnabled", expectedRevision: stored.revision, value: false),
            read: { stored }, write: { updated, _ in stored = updated; writes += 1 }, synchronize: { false })
        #expect(result.status == "settingsSaveFailed")
        #expect(result.changed)
        #expect(!result.page.values.statusChecksEnabled)
        #expect(!stored.statusChecksEnabled)
        #expect(writes == 1)
    }

    @Test
    func `post flush external changes are returned as conflicts instead of claimed success`() {
        var stored = Self.initial
        let result = Preferences.save(.init(key: "frequency", expectedRevision: stored.revision, choice: "manual"),
            read: { stored }, write: { updated, _ in stored = updated }, synchronize: {
                stored.lowPowerMode = "on"
                return true
            })
        #expect(result.status == "settingsChanged")
        #expect(result.changed)
        #expect(result.page.values.frequency == "manual")
        #expect(result.page.values.lowPowerMode == "on")
    }

    @Test
    func `request fields cannot mix general writes with other operations`() throws {
        let mutation = Preferences.Mutation(key: "frequency", expectedRevision: Self.initial.revision, choice: "manual")
        func request(_ method: String = "setGeneralPreference") -> WindowsAppProtocol.Request {
            .init(protocolVersion: 1, requestID: UUID(), generation: UUID(), method: method, mutation: nil,
                generalPreferencesMutation: method == "setGeneralPreference" ? mutation : nil)
        }
        #expect(Preferences.accepts(request()))
        #expect(Preferences.accepts(request("generalPreferences")))
        #expect(!Preferences.accepts(request("snapshot")))
        var mixed = request()
        mixed.spendQuery = .init()
        #expect(!Preferences.accepts(mixed))
        mixed = request()
        mixed.spendPreferencesQuery = .init()
        #expect(!Preferences.accepts(mixed))
        mixed = request("generalPreferences")
        mixed.generalPreferencesMutation = mutation
        #expect(!Preferences.accepts(mixed))
        mixed = request()
        mixed.generalPreferencesMutation = nil
        #expect(!Preferences.accepts(mixed))
        let decoded = try WindowsAppProtocol.request(JSONEncoder().encode(request()))
        #expect(Preferences.accepts(decoded))
        #expect(decoded.generalPreferencesMutation?.choice == "manual")
    }

    @Test
    func `general response is a small nonsecret typed envelope`() throws {
        var response = WindowsAppProtocol.Response(protocolVersion: 1, requestID: UUID(), generation: UUID(),
            status: "ok", snapshot: nil)
        response.generalPreferences = .init(Self.initial)
        let data = try WindowsAppProtocol.response(response)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let page = try #require(root["generalPreferences"] as? [String: Any])
        let values = try #require(page["values"] as? [String: Any])
        #expect(Set(values.keys) == ["frequency", "lowPowerMode", "statusChecksEnabled", "refreshOnMenuOpen"])
        #expect(data.count < 2048)
        let decoded = try JSONDecoder().decode(WindowsAppProtocol.Response.self, from: data)
        #expect(decoded.generalPreferences?.values == Self.initial)
        #expect(decoded.generalPreferences?.revision == Self.initial.revision)
        #expect(decoded.snapshot == nil)
    }
}
#endif
