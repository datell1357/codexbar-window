#if os(Windows)
import Foundation
import CodexBarCore

public struct WindowsSessionQuotaNotification: Sendable {
    public let providerID: ProviderInstanceID?
    public let title: String
    public let body: String

    public init(title: String, body: String, providerID: ProviderInstanceID? = nil) {
        self.providerID = providerID
        self.title = title
        self.body = body
    }
}
#endif
