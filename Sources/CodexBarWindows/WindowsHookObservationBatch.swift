#if os(Windows)
import CodexBarCore
import Foundation

/// One refresh's account results. The runtime owns the prior keys and configuration generation.
enum WindowsHookObservationBatch {
    struct Account: Sendable {
        let providerInstanceID: String
        let discriminator: String
        let lanes: WindowsHookObservationMapper.AccountLanes?
        let failure: WindowsHookObservationMapper.RefreshFailure?
    }
    struct Result: Sendable {
        let observations: [HookProviderObservation]
        let failures: [HookEvent]
        let retainedKeys: Set<HookQuotaLaneKey>
    }
    enum Failure: Error { case invalidAccount, duplicateAccount, oversized }

    static func make(accounts: [Account], previousKeys: Set<HookQuotaLaneKey>, now: Date) throws -> Result {
        guard accounts.count <= 256, previousKeys.count <= 4096 else { throw Failure.oversized }
        var owners: [String: Set<String>] = [:]
        var grouped: [String: [HookQuotaLaneObservation]] = [:]
        var preserved: [String: Set<HookQuotaLaneKey>] = [:]
        var failures: [HookEvent] = []
        var laneCount = 0
        for account in accounts {
            guard !account.providerInstanceID.isEmpty, !account.discriminator.isEmpty,
                  !account.discriminator.contains("\u{1F}"),
                  (account.lanes != nil) != (account.failure != nil) else { throw Failure.invalidAccount }
            guard owners[account.providerInstanceID, default: []].insert(account.discriminator).inserted else {
                throw Failure.duplicateAccount
            }
            let prefix = account.discriminator + "\u{1F}"
            let previous = Set(previousKeys.filter {
                $0.provider == account.providerInstanceID && $0.accountDiscriminator?.hasPrefix(prefix) == true
            })
            if grouped[account.providerInstanceID] == nil { grouped[account.providerInstanceID] = [] }
            if let current = account.lanes {
                guard current.lanes.allSatisfy({
                    $0.key.provider == account.providerInstanceID && $0.key.accountDiscriminator?.hasPrefix(prefix) == true
                }) else { throw Failure.invalidAccount }
                grouped[account.providerInstanceID, default: []].append(contentsOf: current.lanes)
                preserved[account.providerInstanceID, default: []].formUnion(
                    WindowsHookObservationMapper.unavailableExtraLanes(previous: previous, current: current,
                        providerInstanceID: account.providerInstanceID, accountDiscriminator: account.discriminator))
                laneCount += current.lanes.count
            } else if let reason = account.failure {
                // Preserve every failed account lane, while successful sibling accounts still advance.
                preserved[account.providerInstanceID, default: []].formUnion(previous)
                failures.append(HookEvent(event: .refreshFailed, provider: account.providerInstanceID,
                    status: reason.rawValue, timestamp: now))
            }
            guard laneCount <= 4096 else { throw Failure.oversized }
        }
        var retained = Set<HookQuotaLaneKey>()
        var observations: [HookProviderObservation] = []
        for provider in grouped.keys.sorted() {
            let lanes = grouped[provider] ?? []
            let unavailable = preserved[provider] ?? []
            retained.formUnion(lanes.map(\.key))
            retained.formUnion(unavailable)
            guard retained.count <= 4096 else { throw Failure.oversized }
            observations.append(HookProviderObservation(provider: provider, lanes: lanes,
                unavailableLaneKeys: unavailable))
        }
        // Accounts absent from this complete refresh roster are deliberately not retained.
        return Result(observations: observations, failures: failures, retainedKeys: retained)
    }
}
#endif
