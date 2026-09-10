#if os(Windows)
import Foundation

/// Structured provider action rendered by the Windows tray popup.
///
/// A status entry is actionable only when `statusURL` is a validated provider
/// URL. Providers without a status page remain visible with `disabledText` so
/// the menu does not silently omit a source present in the native descriptor.
public struct WindowsTrayMenuEntry: Sendable, Equatable {
    public let providerID: String
    public let title: String
    public let statusURL: String?
    public let dashboardURL: String?
    /// Whether this provider should appear in the dashboard submenu. This is
    /// independent from status availability because some providers expose a
    /// status page without a dashboard action.
    public let dashboardVisible: Bool
    public let disabledText: String?

    public init(
        providerID: String,
        title: String,
        statusURL: String?,
        dashboardURL: String? = nil,
        dashboardVisible: Bool = true,
        disabledText: String? = "unavailable")
    {
        self.providerID = providerID
        self.title = title
        self.statusURL = statusURL
        self.dashboardURL = dashboardURL
        self.dashboardVisible = dashboardVisible
        self.disabledText = disabledText
    }

    public var isEnabled: Bool { self.statusURL != nil }

    public var displayTitle: String {
        guard !self.isEnabled, let disabledText, !disabledText.isEmpty else { return self.title }
        return "\(self.title) (\(disabledText))"
    }
}
#endif
