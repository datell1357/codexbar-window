#if os(Windows)
import Foundation

public struct WindowsSessionQuotaNotification: Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}
#endif
