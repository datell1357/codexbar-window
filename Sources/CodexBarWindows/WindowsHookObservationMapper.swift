#if os(Windows)
import CodexBarCore
import Foundation

/// Pure mapping; performs no defaults, credential, network or command access.
enum WindowsHookObservationMapper {
    struct AccountLanes: Sendable {
        let lanes: [HookQuotaLaneObservation]
        let extraWindowsAuthoritative: Bool
    }

    static func lanes(
        provider: UsageProvider,
        providerInstanceID: String,
        snapshot: UsageSnapshot,
        accountDiscriminator: String,
        settings: WindowsQuotaWarningSettings,
        hidePersonalInfo: Bool) -> AccountLanes
    {
        let selected = QuotaWarningTransitionCore.candidates(provider: provider, snapshot: snapshot,
            accountDiscriminator: accountDiscriminator)
        let accountName = hidePersonalInfo ? nil : snapshot.accountEmail(for: provider)
        let lanes = selected.candidates.map { candidate in
            // Changing the quota source establishes a fresh baseline even if the account is unchanged.
            let source = candidate.source?.rawValue ?? "unspecified"
            let owner = accountDiscriminator + "\u{1F}" + source
            return HookQuotaLaneObservation(
                key: HookQuotaLaneKey(provider: providerInstanceID, window: candidate.key.lane,
                    accountDiscriminator: owner, windowID: candidate.key.windowID),
                label: candidate.displayLabel ?? candidate.key.lane.displayName,
                rateWindow: candidate.window,
                // Hook rules are independent of the native notification enable switch.
                fallbackThresholds: settings.thresholds(for: candidate.key.lane).map { (100 - Double($0)) / 100 },
                accountDisplayName: accountName)
        }
        return AccountLanes(lanes: lanes, extraWindowsAuthoritative: selected.reconciliation.authoritative)
    }

    /// Keep only missing extra lanes from this account when the extra list is incomplete.
    /// Explicitly reported nil/synthetic ordinary windows still reset through the detector.
    static func unavailableExtraLanes(
        previous: Set<HookQuotaLaneKey>, current: AccountLanes,
        providerInstanceID: String, accountDiscriminator: String) -> Set<HookQuotaLaneKey>
    {
        guard !current.extraWindowsAuthoritative else { return [] }
        let observed = Set(current.lanes.map(\.key))
        let reportedWindowIDs = Set(current.lanes.compactMap { $0.key.windowID })
        let ownerPrefix = accountDiscriminator + "\u{1F}"
        return Set(previous.filter { key in
            key.provider == providerInstanceID && key.windowID != nil &&
                key.accountDiscriminator?.hasPrefix(ownerPrefix) == true && !observed.contains(key) &&
                !reportedWindowIDs.contains(key.windowID!)
        })
    }

    enum RefreshFailure: String, Sendable {
        case authentication, unavailable, timeout, invalidResponse, unknown
    }

    static func failed(providerInstanceID: String, reason: RefreshFailure) -> HookProviderObservation {
        // Never forward localized errors or response bodies into external commands.
        HookProviderObservation(provider: providerInstanceID, refreshFailureStatus: reason.rawValue)
    }
}
#endif
