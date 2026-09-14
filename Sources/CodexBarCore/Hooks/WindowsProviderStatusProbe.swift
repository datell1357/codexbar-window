#if os(Windows)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Public Statuspage and incident.io summaries; no credentials or account data.
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
        var proxy = components
        proxy.path = "/proxy/" + (components.host ?? "")
        if let url = proxy.url {
            do { return try self.decodeIncidentSummary(await self.read(url: url, transport: transport)) }
            catch is CancellationError { throw CancellationError() }
            catch { /* Non-incident.io pages fall back to the classic endpoint. */ }
        }
        try Task.checkCancellation()
        return try self.decode(await self.read(
            url: baseURL.appendingPathComponent("api/v2/status.json"), transport: transport))
    }

    private static func read(url: URL, transport: any ProviderHTTPTransport) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: ProviderHTTPResponse
        do { response = try await transport.response(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw Failure.unavailable }
        try Task.checkCancellation()
        guard response.statusCode == 200 else { throw Failure.invalidResponse }
        guard response.data.count <= 1024 * 1024 else { throw Failure.oversized }
        return response.data
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

    /// Missing affected entries are operational; malformed/unknown entries never imply recovery.
    public static func decodeIncidentSummary(_ data: Data) throws -> HookProviderStatus {
        try Task.checkCancellation()
        guard data.count <= 1024 * 1024 else { throw Failure.oversized }
        struct Component: Decodable {
            let component_id: String
            let name: String?
            let hidden: Bool?
        }
        struct Group: Decodable {
            let name: String?
            let hidden: Bool?
            let components: [Component]?
        }
        struct Item: Decodable { let group: Group?; let component: Component? }
        struct Structure: Decodable { let items: [Item] }
        struct Affected: Decodable { let component_id: String; let status: String? }
        struct Summary: Decodable {
            let structure: Structure
            let affected_components: [Affected]?
        }
        struct Response: Decodable { let summary: Summary }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw Failure.invalidResponse }
        let items = response.summary.structure.items
        let affected = response.summary.affected_components ?? []
        guard !items.isEmpty else { throw Failure.invalidResponse }
        guard items.count <= 4096, affected.count <= 4096 else { throw Failure.oversized }
        var statuses: [String: HookProviderStatus] = [:]
        for entry in affected {
            guard !entry.component_id.isEmpty, statuses[entry.component_id] == nil else {
                throw Failure.invalidResponse
            }
            let status: HookProviderStatus
            switch entry.status {
            case "operational": status = .none
            case "degraded_performance": status = .minor
            case "partial_outage": status = .major
            case "major_outage", "full_outage": status = .critical
            case "under_maintenance": status = .maintenance
            default: status = .unknown
            }
            statuses[entry.component_id] = status
        }
        var leaves: [Component] = []
        func visible(_ hidden: Bool?, _ name: String?) -> Bool {
            hidden != true && !(name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        for item in items {
            try Task.checkCancellation()
            if let group = item.group, visible(group.hidden, group.name) {
                leaves.append(contentsOf: (group.components ?? []).filter { visible($0.hidden, $0.name) })
            } else if item.group == nil, let component = item.component,
                      visible(component.hidden, component.name) {
                leaves.append(component)
            }
            guard leaves.count <= 4096 else { throw Failure.oversized }
        }
        guard !leaves.isEmpty else { return .unknown }
        var seen = Set<String>()
        var result: HookProviderStatus = .none
        func rank(_ status: HookProviderStatus) -> Int {
            switch status {
            case .none: 0
            case .maintenance: 1
            case .minor: 2
            case .major: 3
            case .critical: 4
            case .unknown: 5
            }
        }
        for leaf in leaves {
            guard !leaf.component_id.isEmpty, seen.insert(leaf.component_id).inserted else {
                throw Failure.invalidResponse
            }
            let status = statuses[leaf.component_id] ?? .none
            if rank(status) > rank(result) { result = status }
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
