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

    /// At most four requests in flight; failed or unattempted sources remain unknown.
    public static func collect(_ sources: [String: URL], deadline: Date) async throws -> [String: HookProviderStatus] {
        guard sources.count <= 256 else { throw Failure.oversized }
        try Task.checkCancellation()
        let entries = sources.sorted { $0.key < $1.key }
        var result = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, HookProviderStatus.unknown) })
        await withTaskGroup(of: (String, HookProviderStatus).self) { group in
            var next = 0
            func enqueue(_ index: Int) {
                let entry = entries[index]
                group.addTask {
                    guard !Task.isCancelled, Date() < deadline else { return (entry.key, .unknown) }
                    let status = (try? await Self.fetch(baseURL: entry.value)) ?? .unknown
                    guard !Task.isCancelled, Date() < deadline else { return (entry.key, .unknown) }
                    return (entry.key, status)
                }
            }
            while next < min(4, entries.count) { enqueue(next); next += 1 }
            while let (key, status) = await group.next() {
                result[key] = status
                if Task.isCancelled || Date() >= deadline { group.cancelAll() }
                else if next < entries.count { enqueue(next); next += 1 }
            }
        }
        try Task.checkCancellation()
        return result
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
