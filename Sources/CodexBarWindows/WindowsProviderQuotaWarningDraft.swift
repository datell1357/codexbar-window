#if os(Windows)
import CodexBarCore

/// The three provider-level choices for one quota-warning window.
public enum WindowsProviderQuotaWarningMode: Sendable, Equatable, Hashable {
    case global
    case custom
    case off
}

/// A minimal mutation for one provider quota-warning window.
public enum WindowsProviderQuotaWarningLanePatch: Sendable, Equatable {
    case unchanged
    case clear
    case replace(QuotaWarningWindowConfig)
}

/// Mutable, value-only editor state for one provider quota-warning window.
public struct WindowsProviderQuotaWarningLaneDraft: Sendable, Equatable {
    public let globalThresholds: [Int]
    public private(set) var mode: WindowsProviderQuotaWarningMode

    private let originalConfig: QuotaWarningWindowConfig?
    private var currentConfig: QuotaWarningWindowConfig?

    public init(config: QuotaWarningWindowConfig?, globalThresholds: [Int]) {
        let normalized = config?.hasOverride == true ? config : nil
        self.originalConfig = normalized
        self.currentConfig = normalized
        self.mode = Self.mode(for: normalized)
        self.globalThresholds = QuotaWarningThresholds.sanitized(globalThresholds)
    }

    /// Apply each transition immediately to the draft, as the original picker does.
    public mutating func selectMode(_ mode: WindowsProviderQuotaWarningMode) {
        guard mode != self.mode else { return }
        let explicitThresholds = self.currentConfig?.thresholds.map(QuotaWarningThresholds.sanitized)
        switch mode {
        case .global:
            self.currentConfig = nil
        case .custom:
            self.currentConfig = QuotaWarningWindowConfig(thresholds: explicitThresholds, enabled: true)
        case .off:
            self.currentConfig = QuotaWarningWindowConfig(
                thresholds: self.mode == .custom ? explicitThresholds : nil,
                enabled: false)
        }
        self.mode = mode
    }

    /// Preserve inherited values when an untouched override still follows global thresholds.
    public mutating func setThresholds(upper: Int?, lower: Int?) {
        guard var config = self.currentConfig, config.hasOverride else { return }
        let resolved = QuotaWarningThresholds.resolved(upper: upper, lower: lower)
        let current = config.thresholds.map(QuotaWarningThresholds.sanitized)
        guard current != resolved else { return }
        if current == nil, resolved == self.globalThresholds { return }
        config.thresholds = resolved
        self.currentConfig = config
    }

    public var thresholds: [Int] {
        QuotaWarningThresholds.sanitized(self.currentConfig?.thresholds ?? self.globalThresholds)
    }

    /// Compare the final draft with its original snapshot to avoid unrelated writes.
    public var resultingPatch: WindowsProviderQuotaWarningLanePatch {
        guard self.currentConfig != self.originalConfig else { return .unchanged }
        guard let config = self.currentConfig else { return .clear }
        return .replace(QuotaWarningWindowConfig(thresholds: config.thresholds, enabled: config.enabled))
    }

    private static func mode(for config: QuotaWarningWindowConfig?) -> WindowsProviderQuotaWarningMode {
        guard let config else { return .global }
        return config.isEnabled(global: true) ? .custom : .off
    }
}

/// The independent session and weekly mutations for one provider.
public struct WindowsProviderQuotaWarningPatch: Sendable, Equatable {
    public let session: WindowsProviderQuotaWarningLanePatch
    public let weekly: WindowsProviderQuotaWarningLanePatch

    public init(
        session: WindowsProviderQuotaWarningLanePatch = .unchanged,
        weekly: WindowsProviderQuotaWarningLanePatch = .unchanged)
    {
        self.session = session
        self.weekly = weekly
    }

    public init(
        session: WindowsProviderQuotaWarningLaneDraft,
        weekly: WindowsProviderQuotaWarningLaneDraft)
    {
        self.init(session: session.resultingPatch, weekly: weekly.resultingPatch)
    }

    public var isUnchanged: Bool {
        self.session == .unchanged && self.weekly == .unchanged
    }
}
#endif
