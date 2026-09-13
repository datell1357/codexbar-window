#if os(Windows)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Manual account requests carry credentials explicitly. No ambient cookie, cache or
/// URL credential storage may supplement the selected account's headers.
enum WindowsManualAccountHTTPTransport {
    static let shared: ProviderHTTPClient = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        let session = ProviderHTTPClient.redirectGuardedSession(configuration: configuration)
        return ProviderHTTPClient(session: session)
    }()
}
#endif
