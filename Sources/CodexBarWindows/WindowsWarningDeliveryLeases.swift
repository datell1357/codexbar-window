#if os(Windows)
import CodexBarCore
import Foundation

/// Runtime-owned delivery validity, independent of the reducers' already-notified episode records.
struct WindowsWarningDeliveryLeases {
    private struct Scope: Equatable {
        let owner: String
        let configRevision: Data?
    }
    private struct Threshold {
        let validity: WindowsSnapshotValidity
        let threshold: Int
        let reset: Date?
        let minutes: Int?
        let source: QuotaWarningTransitionCore.Source?
        let settings: WindowsQuotaWarningSettings
    }
    private var scopes: [ProviderInstanceID: Scope] = [:]
    private var thresholds: [QuotaWarningTransitionCore.Key: Threshold] = [:]
    private var pace: [PredictivePaceWarningTransitionCore.Key: WindowsSnapshotValidity] = [:]

    mutating func prepare(providerID: ProviderInstanceID, owner: String, configRevision: Data?) {
        let scope = Scope(owner: owner, configRevision: configRevision)
        if self.scopes[providerID] != scope { self.invalidate(providerID: providerID) }
        self.scopes[providerID] = scope
    }

    mutating func invalidate(providerID: ProviderInstanceID) {
        self.clearThresholds(providerID: providerID)
        self.clearPace(providerID: providerID)
        self.scopes.removeValue(forKey: providerID)
    }

    mutating func retainProviders(_ enabled: Set<ProviderInstanceID>) {
        for id in Array(self.scopes.keys) where !enabled.contains(id) { self.invalidate(providerID: id) }
    }

    mutating func clearThresholds(providerID: ProviderInstanceID? = nil) {
        for key in Array(self.thresholds.keys) where providerID == nil || key.provider.instanceID == providerID {
            self.thresholds.removeValue(forKey: key)?.validity.invalidate()
        }
    }

    mutating func clearPace(providerID: ProviderInstanceID? = nil) {
        for key in Array(self.pace.keys) where providerID == nil || key.provider.instanceID == providerID {
            self.pace.removeValue(forKey: key)?.invalidate()
        }
    }

    mutating func reconcileThresholds(provider: UsageProvider,
                                     candidates: [QuotaWarningTransitionCore.Candidate],
                                     settings: WindowsQuotaWarningSettings) {
        for key in Array(self.thresholds.keys) where key.provider == provider {
            guard let pending = self.thresholds[key] else { continue }
            let candidate = candidates.first { $0.key == key && settings.isEnabled(for: key.lane) }
            let keep = candidate.map { candidate in
                let sameReset = pending.reset == candidate.window.resetsAt || {
                    guard let lhs = pending.reset, let rhs = candidate.window.resetsAt else { return false }
                    return abs(lhs.timeIntervalSince(rhs)) < 120
                }()
                return !candidate.window.isSyntheticPlaceholder && candidate.window.remainingPercent.isFinite
                    && candidate.window.remainingPercent <= Double(pending.threshold)
                    && pending.minutes == candidate.window.windowMinutes && sameReset
                    && pending.source == candidate.source && pending.settings == settings
            } ?? false
            if !keep { self.thresholds.removeValue(forKey: key)?.validity.invalidate() }
        }
    }

    mutating func registerThreshold(_ candidate: QuotaWarningTransitionCore.Candidate, threshold: Int,
                                    settings: WindowsQuotaWarningSettings) -> @Sendable () -> Bool {
        self.thresholds.removeValue(forKey: candidate.key)?.validity.invalidate()
        let validity = WindowsSnapshotValidity()
        self.thresholds[candidate.key] = Threshold(validity: validity, threshold: threshold,
            reset: candidate.window.resetsAt, minutes: candidate.window.windowMinutes,
            source: candidate.source, settings: settings)
        return validity.capture()
    }

    mutating func reconcilePace(provider: UsageProvider, warningKeys: [PredictivePaceWarningTransitionCore.Key]) {
        for key in Array(self.pace.keys) where key.provider == provider {
            let replacement = warningKeys.first {
                $0.accountDiscriminator == key.accountDiscriminator && $0.window == key.window
                    && $0.resetWindow.belongsToSameCycle(as: key.resetWindow)
            }
            guard let replacement else {
                self.pace.removeValue(forKey: key)?.invalidate()
                continue
            }
            if replacement != key, let validity = self.pace.removeValue(forKey: key) {
                self.pace.removeValue(forKey: replacement)?.invalidate()
                self.pace[replacement] = validity
            }
        }
    }

    mutating func registerPace(_ key: PredictivePaceWarningTransitionCore.Key) -> @Sendable () -> Bool {
        for old in Array(self.pace.keys) where old.provider == key.provider && old.window == key.window {
            self.pace.removeValue(forKey: old)?.invalidate()
        }
        let validity = WindowsSnapshotValidity()
        self.pace[key] = validity
        return validity.capture()
    }
}
#endif
