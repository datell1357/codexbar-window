#if os(Windows)
import Foundation
import CodexBarCore

public struct WindowsSessionQuotaNotification: Sendable {
    public let providerID: ProviderInstanceID?
    public let title: String
    public let body: String
    public let isCurrent: @Sendable () -> Bool

    public init(title: String, body: String, providerID: ProviderInstanceID? = nil,
                isCurrent: @escaping @Sendable () -> Bool = { true }) {
        self.providerID = providerID
        self.title = title
        self.body = body
        self.isCurrent = isCurrent
    }
}
#endif
