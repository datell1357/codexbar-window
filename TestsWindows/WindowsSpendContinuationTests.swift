#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarWindows

/// Implementation-only fixtures: synthetic snapshots and controllable suspensions, no providers or UI.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsSpendContinuationTests {
    private typealias Controller = WindowsSpendDashboardController
    private typealias Scan = Controller.Scan

    private static func input(_ id: String, provider: UsageProvider = .claude,
                              tokens: Int, now: Date) -> WindowsSpendDashboardModel.ProviderInput {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let entry = CostUsageDailyReport.Entry(date: formatter.string(from: now), inputTokens: tokens,
            outputTokens: 0, totalTokens: tokens, costUSD: Double(tokens), modelsUsed: nil, modelBreakdowns: nil)
        return .init(id: id, provider: provider, displayName: id,
            snapshot: .init(sessionTokens: tokens, sessionCostUSD: Double(tokens),
                last30DaysTokens: tokens, last30DaysCostUSD: Double(tokens), daily: [entry], updatedAt: now))
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { self.lock.lock(); self.count += 1; self.lock.unlock() }
        var value: Int { self.lock.lock(); defer { self.lock.unlock() }; return self.count }
    }

    private actor Native {
        var requests: [(Set<String>?, Date)] = []
        var resumes = 0
        func load(days: Int, ids: Set<String>?, now: Date) -> Scan {
            self.requests.append((ids, now))
            if ids == nil {
                return Scan(inputs: [WindowsSpendContinuationTests.input("remote", provider: .cursor, tokens: 8, now: now)],
                    subscriptionNames: [:], sourceFailures: [.init(sourceID: "local", provider: .claude,
                        localInventoryPending: true, discoveredFiles: 2)], capturedAt: now)
            }
            self.resumes += 1
            if self.resumes == 1 {
                return Scan(inputs: [], subscriptionNames: [:], sourceFailures: [.init(sourceID: "local",
                    provider: .claude, localInventoryPending: true, discoveredFiles: 9)], capturedAt: now)
            }
            return Scan(inputs: [WindowsSpendContinuationTests.input("local", tokens: 20, now: now)],
                        subscriptionNames: [:], capturedAt: now)
        }
    }

    @Test
    func `continuations fetch only pending sources and apply a captured supplement once`() async throws {
        let native = Native()
        let supplements = Counter()
        var settings = WindowsSpendSettings()
        settings.openCodexUsageLogsEnabled = true
        settings.bucketTimeZoneIdentifier = "GMT"
        let session = WindowsSpendCollectionSession(sourceProviders: ["remote": .cursor, "local": .claude], settings: settings,
            nativeLoader: { days, ids, now in await native.load(days: days, ids: ids, now: now) },
            supplementLoader: { now, _ in
                supplements.increment()
                return .init(snapshots: [.claude: Self.input("supplement", tokens: 5, now: now).snapshot],
                             observation: .available)
            })
        let initial = try await session.begin(days: 30)
        #expect(initial.sourceFailures.first?.localInventoryPending == true)
        _ = try await session.resume(days: 30, sourceIDs: ["local"])
        let completed = try await session.resume(days: 30, sourceIDs: ["local"])
        #expect(completed.sourceFailures.isEmpty)
        #expect(completed.inputs.first { $0.id == "remote" }?.snapshot.last30DaysTokens == 8)
        #expect(completed.inputs.first { $0.id == "local" }?.snapshot.last30DaysTokens == 25)
        let requests = await native.requests
        #expect(requests.count == 3)
        #expect(requests[0].0 == nil)
        #expect(requests[1].0 == ["local"] && requests[2].0 == ["local"])
        #expect(Set(requests.map { $0.1 }).count == 1)
        #expect(supplements.value == 1)
        do {
            _ = try await session.resume(days: 30, sourceIDs: ["remote"])
            Issue.record("Completed remote sources must not be admitted as continuations")
        } catch WindowsSpendCollectionSession.Failure.invalidContinuation { }
        #expect(await native.requests.count == 3)
    }

    private actor Gate {
        private var blocked: CheckedContinuation<Void, Never>?
        private var entered = false
        private var observers: [CheckedContinuation<Void, Never>] = []
        func pause() async throws {
            try Task.checkCancellation()
            await withCheckedContinuation { continuation in
                self.blocked = continuation
                self.entered = true
                let observers = self.observers
                self.observers = []
                for observer in observers { observer.resume() }
            }
            try Task.checkCancellation()
        }
        func waitUntilEntered() async {
            if self.entered { return }
            await withCheckedContinuation { self.observers.append($0) }
        }
        func release() { self.blocked?.resume(); self.blocked = nil }
    }

    private final class Publications: @unchecked Sendable {
        private struct Waiter {
            let sequence: UInt64
            let phase: Controller.Phase
            let continuation: CheckedContinuation<Controller.Snapshot, Never>
        }
        private let lock = NSLock()
        private var last: Controller.Snapshot?
        private var waiters: [Waiter] = []
        func record(_ value: Controller.Snapshot) {
            self.lock.lock()
            self.last = value
            let ready = self.waiters.filter { value.publicationSequence > $0.sequence && value.phase == $0.phase }
            self.waiters.removeAll { value.publicationSequence > $0.sequence && value.phase == $0.phase }
            self.lock.unlock()
            for waiter in ready { waiter.continuation.resume(returning: value) }
        }
        func wait(after sequence: UInt64, phase: Controller.Phase) async -> Controller.Snapshot {
            await withCheckedContinuation { continuation in
                self.lock.lock()
                if let last = self.last, last.publicationSequence > sequence, last.phase == phase {
                    self.lock.unlock()
                    continuation.resume(returning: last)
                } else {
                    self.waiters.append(Waiter(sequence: sequence, phase: phase, continuation: continuation))
                    self.lock.unlock()
                }
            }
        }
    }

    private actor InitialResults {
        private var calls = 0
        let now = Date()
        let eligible: Bool
        init(eligible: Bool) { self.eligible = eligible }
        func load() -> Scan {
            self.calls += 1
            if self.calls == 1 {
                return Scan(inputs: [WindowsSpendContinuationTests.input("local", tokens: 10, now: self.now)],
                            subscriptionNames: [:], capturedAt: self.now)
            }
            return Scan(inputs: [], subscriptionNames: [:], sourceFailures: [.init(sourceID: "local", provider: .claude,
                localInventoryPending: true, discoveredFiles: 10)], capturedAt: self.now,
                retentionEligibleSourceIDs: self.eligible ? ["local"] : [])
        }
    }

    @Test(arguments: [false, true])
    func `automatic catch up retains display data only with explicit scope eligibility`(eligible: Bool) async throws {
        let initial = InitialResults(eligible: eligible)
        let gate = Gate()
        let publications = Publications()
        let resumes = Counter()
        var options = Controller.Options()
        options.bucketTimeZoneIdentifier = "GMT"
        let controller = Controller(loader: { _ in await initial.load() }, continuationLoader: { _, ids in
            #expect(ids == ["local"])
            resumes.increment()
            return Scan(inputs: [Self.input("local", tokens: 20, now: Date())], subscriptionNames: [:])
        }, continuationPause: { try await gate.pause() }, options: options, publisher: { publications.record($0) })
        await controller.refresh()
        await controller.refresh()
        await gate.waitUntilEntered()
        let pending = await controller.snapshot()
        #expect(pending.continuingLocalDiscovery)
        #expect(pending.phase == .partial)
        #expect(pending.sharePayload == nil)
        #expect(pending.retainedSourceDates.isEmpty == !eligible)
        #expect(pending.stale == eligible)
        if case let .available(costs, failures) = pending.widgetPublication {
            #expect(costs.isEmpty)
            #expect(failures.count == 1)
        } else { Issue.record("Expected independent fresh widget publication with a pending source") }
        await controller.refresh()
        #expect(resumes.value == 0)
        await gate.release()
        let complete = await publications.wait(after: pending.publicationSequence, phase: .ready)
        #expect(!complete.continuingLocalDiscovery)
        #expect(complete.retainedSourceDates.isEmpty)
        #expect(!complete.stale)
        #expect(resumes.value == 1)
        await controller.stop()
    }

    @Test
    func `invalidation cancels a suspended continuation and withdraws previous display values`() async throws {
        let gate = Gate()
        let calls = Counter()
        let controller = Controller(loader: { _ in
            Scan(inputs: [], subscriptionNames: [:], sourceFailures: [.init(sourceID: "local", provider: .claude,
                localInventoryPending: true)])
        }, continuationLoader: { _, _ in
            calls.increment()
            return Scan(inputs: [], subscriptionNames: [:])
        }, continuationPause: { try await gate.pause() }, publisher: { _ in })
        await controller.refresh()
        await gate.waitUntilEntered()
        await controller.invalidateSourceContext()
        await gate.release()
        let snapshot = await controller.snapshot()
        #expect(snapshot.phase == .idle)
        #expect(!snapshot.continuingLocalDiscovery)
        #expect(snapshot.retainedSourceDates.isEmpty)
        #expect(snapshot.sharePayload == nil)
        #expect(calls.value == 0)
        await controller.stop()
    }

    @Test
    func `the same source ID cannot publish another provider during continuation`() async throws {
        let session = WindowsSpendCollectionSession(sourceProviders: ["local": .claude], settings: .init(),
            nativeLoader: { _, pending, now in
                if pending == nil {
                    return Scan(inputs: [], subscriptionNames: [:], sourceFailures: [.init(sourceID: "local",
                        provider: .claude, localInventoryPending: true)])
                }
                return Scan(inputs: [Self.input("local", provider: .cursor, tokens: 100, now: now)], subscriptionNames: [:])
            }, supplementLoader: { _, _ in .init(snapshots: [:], observation: .disabled) })
        _ = try await session.begin(days: 30)
        do {
            _ = try await session.resume(days: 30, sourceIDs: ["local"])
            Issue.record("A source's captured provider must stay fixed")
        } catch WindowsSpendCollectionSession.Failure.invalidResults { }
    }

    @Test
    func `unknown source results cannot replace a pending collection`() async throws {
        let session = WindowsSpendCollectionSession(sourceProviders: ["expected": .claude], settings: .init(),
            nativeLoader: { _, _, now in
                Scan(inputs: [Self.input("wrong", tokens: 100, now: now)], subscriptionNames: [:])
            }, supplementLoader: { _, _ in .init(snapshots: [:], observation: .disabled) })
        do {
            _ = try await session.begin(days: 30)
            Issue.record("Mismatched source identity must fail")
        } catch WindowsSpendCollectionSession.Failure.invalidResults { }
    }
}
#endif
