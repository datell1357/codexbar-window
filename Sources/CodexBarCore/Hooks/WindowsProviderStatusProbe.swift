#if os(Windows)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Classic Statuspage status only. Uses provider metadata URLs, never credentials or account data.
public enum WindowsProviderStatusProbe {
    public enum Failure: Error { case invalidURL, invalidResponse, oversized, unavailable }

    public static func fetch(
        baseURL: URL,
        transport: any ProviderHTTPTransport = WindowsManualAccountHTTPTransport.shared) async throws -> HookProviderStatus
    {
        try Task.checkCancellation()
        guard let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host?.isEmpty == false,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { throw Failure.invalidURL }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v2/status.json"))
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: ProviderHTTPResponse
        do { response = try await transport.response(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw Failure.unavailable }
        try Task.checkCancellation()
        guard response.statusCode == 200 else { throw Failure.invalidResponse }
        return try self.decode(response.data)
    }

    public static func decode(_ data: Data) throws -> HookProviderStatus {
        try Task.checkCancellation()
        guard data.count <= 1024 * 1024 else { throw Failure.oversized }
        struct Response: Decodable {
            struct Status: Decodable { let indicator: String }
            let status: Status
        }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw Failure.invalidResponse }
        try Task.checkCancellation()
        // Unknown and maintenance are deliberately non-transitions in HookTransitionDetector.
        return HookProviderStatus(rawValue: response.status.indicator) ?? .unknown
    }
}
#endif
