#if os(Windows)
import CodexBarCore
import Foundation

public struct WindowsQuotaWarningNotification: Sendable {
    public let providerName: String
    public let window: QuotaWarningWindow
    public let threshold: Int
    public let currentRemaining: Double
    public let accountDisplayName: String?
    public let windowDisplayLabel: String?

    public init(
        providerName: String,
        window: QuotaWarningWindow,
        threshold: Int,
        currentRemaining: Double,
        accountDisplayName: String? = nil,
        windowDisplayLabel: String? = nil)
    {
        self.providerName = providerName
        self.window = window
        self.threshold = threshold
        self.currentRemaining = currentRemaining
        self.accountDisplayName = accountDisplayName
        self.windowDisplayLabel = windowDisplayLabel
    }

    public func copy(hidePersonalInfo: Bool) -> (title: String, body: String) {
        let label = self.windowDisplayLabel ?? self.window.displayName
        let remaining = "\(Int(min(100, max(0, self.currentRemaining)).rounded()))%"
        let title = "\(self.providerName) \(label) quota low"
        let body: String
        if hidePersonalInfo || self.accountDisplayName == nil {
            body = "\(remaining) left. Reached your \(self.threshold)% \(label) warning threshold."
        } else {
            body = "Account \(self.accountDisplayName!). \(remaining) left. Reached your \(self.threshold)% \(label) warning threshold."
        }
        return (title, body)
    }
}
#endif
