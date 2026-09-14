#if os(Windows)
import Foundation
import CodexBarCore

/// Structured provider action rendered by the Windows tray popup.
///
/// A status entry is actionable only when `statusURL` is a validated provider
/// URL. Providers without a status page remain visible with `disabledText` so
/// the menu does not silently omit a source present in the native descriptor.
public struct WindowsTrayMenuEntry: Sendable, Equatable {
    public let providerID: String
    public let title: String
    public let statusURL: String?
    public let statusVisible: Bool
    public let dashboardURL: String?
    /// Whether this provider should appear in the dashboard submenu. This is
    /// independent from status availability because some providers expose a
    /// status page without a dashboard action.
    public let dashboardVisible: Bool
    /// Provider release notes URL. It is shown only when the corresponding
    /// preference is enabled by the tray host.
    public let changelogURL: String?
    public let changelogVisible: Bool
    public let disabledText: String?
    /// Redacted failure from this provider in the current refresh only.
    public let errorCopyText: String?
    public var tokenAccountSelection: WindowsTokenAccountSelectionSnapshot? = nil
    public var usageCopyText: String? = nil
    /// Public provider state for this refresh; never account usage or identity.
    public var serviceStatus: HookProviderStatus? = nil
    public var serviceComponents: [WindowsProviderStatusComponent]? = nil

    public init(
        providerID: String,
        title: String,
        statusURL: String?,
        statusVisible: Bool = true,
        dashboardURL: String? = nil,
        dashboardVisible: Bool = true,
        changelogURL: String? = nil,
        changelogVisible: Bool = false,
        disabledText: String? = "unavailable",
        errorCopyText: String? = nil)
    {
        self.providerID = providerID
        self.title = title
        self.statusURL = statusURL
        self.statusVisible = statusVisible
        self.dashboardURL = dashboardURL
        self.dashboardVisible = dashboardVisible
        self.changelogURL = changelogURL
        self.changelogVisible = changelogVisible
        self.disabledText = disabledText
        self.errorCopyText = errorCopyText
    }

    public var isEnabled: Bool { self.statusURL != nil }

    public static func serviceStatusLabel(_ status: HookProviderStatus) -> String {
        switch status {
        case .none: WindowsStatusLocalization.text("status_operational")
        case .minor: WindowsStatusLocalization.text("status_degraded")
        case .major: WindowsStatusLocalization.text("status_partial_outage")
        case .critical: WindowsStatusLocalization.text("status_major_outage")
        case .maintenance: WindowsStatusLocalization.text("status_maintenance")
        case .unknown: WindowsStatusLocalization.text("status_unknown")
        }
    }

    public var displayTitle: String {
        let statusLabel = self.serviceStatus.map(Self.serviceStatusLabel)
        let label = statusLabel.map { "\(self.title): \($0)" } ?? self.title
        guard !self.isEnabled, let disabledText, !disabledText.isEmpty else { return label }
        return "\(label) (\(disabledText))"
    }
}
#endif
