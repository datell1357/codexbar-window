#if os(Windows)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Public Statuspage and incident.io summaries; no credentials or account data.
public enum WindowsProviderStatusProbe {
    public enum Source: Sendable, Hashable {
        case statusPage(URL)
        case workspace(productID: String)
    }

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
        try await self.collect(sources.mapValues { Source.statusPage($0) }, deadline: deadline)
    }

    /// Exact source identities share one result within this refresh only. No cross-refresh cache.
    public static func collect(
        _ sources: [String: Source],
        deadline: Date,
        transport: any ProviderHTTPTransport = WindowsManualAccountHTTPTransport.shared) async throws -> [String: HookProviderStatus]
    {
        guard sources.count <= 256 else { throw Failure.oversized }
        try Task.checkCancellation()
        var entries: [(source: Source, providers: [String])] = []
        var indices: [Source: Int] = [:]
        for (provider, source) in sources.sorted(by: { $0.key < $1.key }) {
            if let index = indices[source] { entries[index].providers.append(provider) }
            else {
                indices[source] = entries.count
                entries.append((source, [provider]))
            }
        }
        var result = sources.mapValues { _ in HookProviderStatus.unknown }
        guard !entries.isEmpty, Date() < deadline else { return result }
        // The timer cancels active requests at the submission deadline. Draining remains required.
        await withTaskGroup(of: (Int, HookProviderStatus)?.self) { group in
            group.addTask {
                let remaining = max(0, deadline.timeIntervalSinceNow)
                do { try await Task.sleep(for: .seconds(remaining)) }
                catch { return nil }
                return nil
            }
            var next = 0
            var outstanding = 0
            func enqueue(_ index: Int) {
                let source = entries[index].source
                group.addTask {
                    guard !Task.isCancelled, Date() < deadline else { return (index, .unknown) }
                    let status: HookProviderStatus
                    switch source {
                    case let .statusPage(url):
                        status = (try? await Self.fetch(baseURL: url, transport: transport)) ?? .unknown
                    case let .workspace(productID):
                        status = (try? await Self.fetchWorkspace(productID: productID, transport: transport)) ?? .unknown
                    }
                    guard !Task.isCancelled, Date() < deadline else { return (index, .unknown) }
                    return (index, status)
                }
            }
            while next < min(4, entries.count) {
                enqueue(next)
                next += 1
                outstanding += 1
            }
            while let event = await group.next() {
                guard let (index, status) = event, !Task.isCancelled, Date() < deadline else {
                    group.cancelAll()
                    break
                }
                for provider in entries[index].providers { result[provider] = status }
                outstanding -= 1
                if next < entries.count {
                    enqueue(next)
                    next += 1
                    outstanding += 1
                }
                if outstanding == 0 {
                    group.cancelAll()
                    break
                }
            }
            // Task group scope drains both the timer and any cancelled transport tasks.
        }
        try Task.checkCancellation()
        return result
    }

    public static func fetchWorkspace(
        productID: String,
        transport: any ProviderHTTPTransport = WindowsManualAccountHTTPTransport.shared) async throws -> HookProviderStatus
    {
        guard !productID.isEmpty, productID.utf8.count <= 256,
              let url = URL(string: "https://www.google.com/appsstatus/dashboard/incidents.json") else {
            throw Failure.invalidURL
        }
        return try self.decodeWorkspace(await self.read(url: url, transport: transport), productID: productID)
    }

    public static func decodeWorkspace(_ data: Data, productID: String) throws -> HookProviderStatus {
        try Task.checkCancellation()
        guard !productID.isEmpty, productID.utf8.count <= 256 else { throw Failure.invalidResponse }
        guard data.count <= 1024 * 1024 else { throw Failure.oversized }
        struct Product: Decodable { let id: String }
        struct Update: Decodable { let status: String? }
        struct Incident: Decodable {
            let end: String?
            let statusImpact: String?
            let severity: String?
            let affectedProducts: [Product]?
            let currentlyAffectedProducts: [Product]?
            let mostRecentUpdate: Update?
            let updates: [Update]?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let incidents: [Incident]
        do { incidents = try decoder.decode([Incident].self, from: data) }
        catch { throw Failure.invalidResponse }
        guard incidents.count <= 4096 else { throw Failure.oversized }
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
        for incident in incidents {
            try Task.checkCancellation()
            // An explicitly empty current list overrides historical affected products.
            let products = incident.currentlyAffectedProducts ?? incident.affectedProducts ?? []
            guard products.count <= 4096, (incident.updates?.count ?? 0) <= 4096 else { throw Failure.oversized }
            guard products.contains(where: { $0.id == productID }) else { continue }
            if let end = incident.end {
                // Reject malformed end markers rather than treating the incident as resolved.
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let plain = ISO8601DateFormatter()
                guard fractional.date(from: end) != nil || plain.date(from: end) != nil else {
                    throw Failure.invalidResponse
                }
                continue
            }
            let update = incident.mostRecentUpdate ?? incident.updates?.last
            let status: HookProviderStatus
            switch (update?.status ?? incident.statusImpact)?.uppercased() {
            case "AVAILABLE": status = .none
            case "SERVICE_INFORMATION": status = .minor
            case "SERVICE_DISRUPTION": status = .major
            case "SERVICE_OUTAGE": status = .critical
            case "SERVICE_MAINTENANCE", "SCHEDULED_MAINTENANCE": status = .maintenance
            default:
                switch incident.severity?.lowercased() {
                case "low": status = .minor
                case "medium": status = .major
                case "high": status = .critical
                default: status = .unknown
                }
            }
            if rank(status) > rank(result) { result = status }
        }
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
            let status = WindowsProviderStatusComponent.indicator(for: entry.status ?? "")
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
