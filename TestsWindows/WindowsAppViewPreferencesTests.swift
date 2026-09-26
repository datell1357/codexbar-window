#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarWindows

/// In-memory persistence closures only. No UserDefaults, files, windows or transport are accessed.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsAppViewPreferencesTests {
    private typealias Preferences = WindowsAppViewPreferences
    private final class Memory: @unchecked Sendable {
        enum Failure: Error { case injected }
        private let lock = NSLock()
        private var data: Data?
        private var writes = 0
        private var readFailure = false
        private var writeFailure = false
        private var failAfterWrite = false
        private var corruptAfterWrite = false
        init(_ data: Data? = nil) { self.data = data }
        func read() throws -> Data? {
            self.lock.lock()
            defer { self.lock.unlock() }
            if self.readFailure { throw Failure.injected }
            return self.data
        }
        func write(_ data: Data) throws {
            self.lock.lock()
            defer { self.lock.unlock() }
            self.writes += 1
            if self.writeFailure && !self.failAfterWrite { throw Failure.injected }
            self.data = self.corruptAfterWrite ? Data("corrupt".utf8) : data
            if self.writeFailure { throw Failure.injected }
        }
        func inject(readFailure: Bool = false, writeFailure: Bool = false,
                    failAfterWrite: Bool = false, corruptAfterWrite: Bool = false) {
            self.lock.lock()
            defer { self.lock.unlock() }
            self.readFailure = readFailure; self.writeFailure = writeFailure
            self.failAfterWrite = failAfterWrite; self.corruptAfterWrite = corruptAfterWrite
        }
        var writeCount: Int {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.writes
        }
        func store() -> Preferences.Store {
            Preferences.Store(read: { try self.read() }, write: { try self.write($0) })
        }
    }
    private static var choices: Preferences.Values {
        .init(navigation: "spend", days: 90, currency: "EUR", section: "sessions",
              chart: "tokens", comparePeriods: true, selectedDay: "2026-09-26")
    }

    @Test
    func `missing preferences use display defaults without writing or collecting`() {
        let memory = Memory()
        let page = memory.store().page()
        #expect(page.status == "ready" && page.values == Preferences.Values())
        #expect(page.values.currency == nil && page.values.selectedDay == nil)
        #expect(memory.writeCount == 0)
        #expect(page.revision.count == 64)
    }

    @Test
    func `only bounded display choices and real calendar dates can be persisted`() {
        #expect(Self.choices.isValid)
        var variants: [Preferences.Values] = []
        var value = Self.choices; value.days = 365; #expect(value.isValid)
        value = Self.choices; value.selectedDay = "2024-02-29"; #expect(value.isValid)
        value = Self.choices; value.schemaVersion = 2; variants.append(value)
        value = Self.choices; value.days = 8; variants.append(value)
        value = Self.choices; value.days = 366; variants.append(value)
        value = Self.choices; value.navigation = "credentials"; variants.append(value)
        value = Self.choices; value.section = "private-account"; variants.append(value)
        value = Self.choices; value.chart = "execute"; variants.append(value)
        value = Self.choices; value.currency = "usd"; variants.append(value)
        value = Self.choices; value.currency = "C:\\private"; variants.append(value)
        for day in ["2026-02-29", "2026-9-26", "2026-13-01", "2026-09-26T00:00:00Z"] {
            value = Self.choices; value.selectedDay = day; variants.append(value)
        }
        #expect(variants.allSatisfy { !$0.isValid })
        #expect(!Preferences.Mutation(expectedRevision: "old", values: Self.choices).isValid)
        #expect(!Preferences.Mutation(expectedRevision: String(repeating: "Z", count: 64), values: Self.choices).isValid)
    }

    @Test
    func `valid choices round trip through persistence with a changed revision`() throws {
        let memory = Memory()
        let store = memory.store()
        let original = store.page()
        let result = store.save(.init(expectedRevision: original.revision, values: Self.choices))
        #expect(result.status == "ok")
        #expect(result.page.values == Self.choices)
        #expect(result.page.revision != original.revision)
        #expect(store.page().revision == result.page.revision)
        #expect(memory.writeCount == 1)
        let data = try #require(memory.read())
        #expect(data.count < Preferences.maximumStoredBytes)
        #expect(try JSONDecoder().decode(Preferences.Values.self, from: data) == Self.choices)
    }

    @Test
    func `corrupt oversized and newer records are preserved instead of overwritten`() throws {
        var future = Self.choices
        future.schemaVersion = 2
        let fixtures = [
            Data(), Data("invalid".utf8), Data("{}".utf8), Data(#"{"schemaVersion":1,"days":true}"#.utf8),
            Data(repeating: 32, count: Preferences.maximumStoredBytes + 1), try JSONEncoder().encode(future)
        ]
        for data in fixtures {
            let memory = Memory(data)
            let store = memory.store()
            let page = store.page()
            #expect(page.status == "invalid" || page.status == "unsupported")
            #expect(page.values == Preferences.Values())
            let result = store.save(.init(expectedRevision: page.revision, values: Self.choices))
            #expect(result.status == "viewPreferencesUnavailable")
            #expect(try memory.read() == data)
            #expect(memory.writeCount == 0)
        }
    }

    @Test
    func `a stale window revision cannot overwrite a newer saved selection`() {
        let memory = Memory()
        let store = memory.store()
        let original = store.page()
        let first = store.save(.init(expectedRevision: original.revision, values: Self.choices))
        var later = Self.choices
        later.days = 7
        let stale = store.save(.init(expectedRevision: original.revision, values: later))
        #expect(first.status == "ok" && stale.status == "settingsChanged")
        #expect(stale.page.values == Self.choices && memory.writeCount == 1)
        let explicit = store.save(.init(expectedRevision: stale.page.revision, values: later))
        #expect(explicit.status == "ok" && explicit.page.values.days == 7)
    }

    @Test
    func `flush failure remains unconfirmed even after an in-memory write`() {
        for afterWrite in [false, true] {
            let memory = Memory()
            let store = memory.store()
            let initial = store.page()
            memory.inject(writeFailure: true, failAfterWrite: afterWrite)
            let failed = store.save(.init(expectedRevision: initial.revision, values: Self.choices))
            #expect(failed.status == "settingsSaveFailed")
            #expect(failed.page.values == (afterWrite ? Self.choices : Preferences.Values()))
            memory.inject()
            let retried = store.save(.init(expectedRevision: store.page().revision, values: Self.choices))
            #expect(retried.status == "ok" && retried.page.values == Self.choices)
            // An explicit retry flushes again even if the readback already equals the requested values.
            #expect(memory.writeCount == 2)
        }
    }

    @Test
    func `unreadable or mismatched persistence is not acknowledged as a saved view`() {
        let memory = Memory()
        let store = memory.store()
        let original = store.page()
        memory.inject(readFailure: true)
        #expect(store.page().status == "readFailed")
        #expect(store.save(.init(expectedRevision: original.revision, values: Self.choices)).status
            == "viewPreferencesUnavailable")
        #expect(memory.writeCount == 0)
        memory.inject(corruptAfterWrite: true)
        let changed = store.save(.init(expectedRevision: original.revision, values: Self.choices))
        #expect(changed.status == "settingsSaveFailed" && changed.page.status == "invalid")
    }

    @Test
    func `view state uses its own bounded protocol fields without account or collection settings`() throws {
        let page = Preferences.page(data: try JSONEncoder().encode(Self.choices))
        let request = WindowsAppProtocol.Request(protocolVersion: 1, requestID: UUID(), generation: UUID(),
            method: "setViewPreferences", mutation: nil,
            viewPreferencesMutation: .init(expectedRevision: page.revision, values: Self.choices))
        let bytes = try JSONEncoder().encode(request)
        #expect(bytes.count < WindowsAppProtocol.maximumRequestBytes)
        let decoded = try WindowsAppProtocol.request(bytes)
        #expect(decoded.viewPreferencesMutation?.values == Self.choices)
        #expect(decoded.spendQuery == nil && decoded.spendPreferencesMutation == nil && decoded.spendAction == nil)
        let response = WindowsAppProtocol.Response(protocolVersion: 1, requestID: request.requestID,
            generation: request.generation!, status: "ok", snapshot: nil, viewPreferences: page)
        let wire = String(decoding: try WindowsAppProtocol.response(response), as: UTF8.self)
        #expect(wire.contains("viewPreferences") && wire.contains("selectedDay"))
        for forbidden in ["sourceID", "account", "collectionEnabled", "preferredCurrencyCode", "path", "detail"] {
            #expect(!wire.contains(forbidden))
        }
    }

    @Test
    func `heatmap points carry calendar dates rather than localized labels as selection keys`() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let day = calendar.date(from: .init(year: 2026, month: 9, day: 26))!
        let snapshot = WindowsSpendDashboardController.Snapshot(generation: 1, phase: .ready,
            model: .init(requestedDays: 7, groups: [], tokenActivity: [.init(day: day, totalTokens: 0)]),
            sharePayload: nil, loadedAt: day, stale: false, failure: nil,
            openCodexObservation: .disabled, sourceFailures: [])
        let page = WindowsAppSpendProjection.make(snapshot: snapshot, query: .init(days: 7, chart: "tokens"),
            hidePersonalInfo: true, calendar: calendar, selectionRevision: String(repeating: "0", count: 64))
        #expect(page.points.first?.dayKey == "2026-09-26")
        #expect(page.points.first?.level == 2) // Confirmed-zero activity semantics are retained.
    }
}
#endif
