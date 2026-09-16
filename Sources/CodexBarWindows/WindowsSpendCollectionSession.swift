#if os(Windows)
import Foundation
import CodexBarCore

/// One captured collection can span many local inventory slices. Successful and failed remote
/// sources are retained inside that collection; only pending local sources are queried again.
actor WindowsSpendCollectionSession {
    typealias Scan = WindowsSpendDashboardController.Scan
    typealias NativeLoader = @Sendable (Int, Set<String>?, Date) async throws -> Scan
    typealias SupplementLoader = @Sendable (Date, Int) throws -> WindowsOpenCodexSpendSource.Inventory
    enum Failure: Error { case invalidContinuation, invalidResults }

    private struct State {
        let days: Int
        let now: Date
        var native: Scan
        let supplement: WindowsOpenCodexSpendSource.Inventory
    }
    private let sourceProviders: [String: UsageProvider]
    private var sourceIDs: Set<String> { Set(self.sourceProviders.keys) }
    private let settings: WindowsSpendSettings
    private let nativeLoader: NativeLoader
    private let supplementLoader: SupplementLoader
    private var generation: UInt64 = 0
    private var state: State?

    init(sourceProviders: [String: UsageProvider], settings: WindowsSpendSettings,
         nativeLoader: @escaping NativeLoader, supplementLoader: @escaping SupplementLoader) {
        self.sourceProviders = sourceProviders
        self.settings = settings
        self.nativeLoader = nativeLoader
        self.supplementLoader = supplementLoader
    }

    func begin(days: Int) async throws -> Scan {
        self.generation &+= 1
        let generation = self.generation
        self.state = nil
        let now = Date()
        let native = try await self.nativeLoader(days, nil, now)
        try Task.checkCancellation()
        guard generation == self.generation else { throw CancellationError() }
        try Self.requireResults(native, matching: self.sourceProviders)
        let supplement = try self.supplementLoader(now, days)
        let state = State(days: days, now: now, native: native, supplement: supplement)
        self.state = state
        return self.project(state)
    }

    func resume(days: Int, sourceIDs: Set<String>) async throws -> Scan {
        guard var state = self.state, state.days == days, !sourceIDs.isEmpty,
              sourceIDs == Set(state.native.sourceFailures.filter(\.localInventoryPending).map(\.sourceID)),
              sourceIDs.isSubset(of: self.sourceIDs) else { throw Failure.invalidContinuation }
        self.generation &+= 1
        let generation = self.generation
        let next = try await self.nativeLoader(days, sourceIDs, state.now)
        try Task.checkCancellation()
        guard generation == self.generation else { throw CancellationError() }
        try Self.requireResults(next, matching: self.sourceProviders.filter { sourceIDs.contains($0.key) })
        let replacedProviders = Set(state.native.sourceFailures.filter { sourceIDs.contains($0.sourceID) }.map(\.provider))
        var names = state.native.subscriptionNames.filter { !sourceIDs.contains($0.key) }
        names.merge(next.subscriptionNames) { _, new in new }
        state.native = Scan(
            inputs: state.native.inputs.filter { !sourceIDs.contains($0.id) } + next.inputs,
            subscriptionNames: names,
            sourceFailures: state.native.sourceFailures.filter { !sourceIDs.contains($0.sourceID) } + next.sourceFailures,
            capturedAt: state.now,
            widgetCosts: state.native.widgetCosts.filter { !replacedProviders.contains($0.provider) } + next.widgetCosts,
            widgetCostFailures: state.native.widgetCostFailures.filter { !sourceIDs.contains($0.sourceID) } + next.widgetCostFailures,
            retentionEligibleSourceIDs: state.native.retentionEligibleSourceIDs.subtracting(sourceIDs)
                .union(next.retentionEligibleSourceIDs))
        self.state = state
        return self.project(state)
    }

    private func project(_ state: State) -> Scan {
        let merged = WindowsOpenCodexSpendSource.apply(
            state.supplement, to: state.native.inputs, settings: self.settings,
            now: state.now, historyDays: state.days)
        var scan = state.native
        scan.inputs = merged.inputs
        scan.openCodexObservation = merged.observation
        return scan
    }

    private static func requireResults(_ scan: Scan, matching providers: [String: UsageProvider]) throws {
        let expected = Set(providers.keys)
        let ids = scan.inputs.map(\.id) + scan.sourceFailures.map(\.sourceID)
        guard ids.count == Set(ids).count, Set(ids) == expected,
              scan.inputs.allSatisfy({ providers[$0.id] == $0.provider && $0.sourceKind == .native }),
              scan.sourceFailures.allSatisfy({ providers[$0.sourceID] == $0.provider }),
              scan.widgetCostFailures.allSatisfy({ providers[$0.sourceID] == $0.provider }),
              scan.subscriptionNames.keys.allSatisfy(expected.contains),
              scan.retentionEligibleSourceIDs.isSubset(of: expected),
              scan.sourceFailures.allSatisfy({ !$0.localInventoryPending || $0.provider == .claude || $0.provider == .vertexai })
        else { throw Failure.invalidResults }
    }
}
#endif
