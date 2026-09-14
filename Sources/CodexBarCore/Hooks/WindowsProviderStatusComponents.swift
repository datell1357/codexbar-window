#if os(Windows)
import Foundation

public struct WindowsProviderStatusSnapshot: Sendable, Equatable {
    public let indicator: HookProviderStatus
    /// Nil means no component response was obtained; an empty array is a loaded empty list.
    public let components: [WindowsProviderStatusComponent]?

    public init(indicator: HookProviderStatus, components: [WindowsProviderStatusComponent]? = nil) {
        self.indicator = indicator
        self.components = components
    }
}

/// Public service components. Kept separate from account/usage observations.
public struct WindowsProviderStatusComponent: Sendable, Equatable {
    public let id: String
    public let name: String
    public let indicator: HookProviderStatus
    public let rawStatus: String
    public let children: [WindowsProviderStatusComponent]

    public init(id: String, name: String, rawStatus: String, children: [Self] = []) {
        self.id = id
        self.name = name
        self.rawStatus = rawStatus
        self.indicator = Self.indicator(for: rawStatus)
        self.children = children
    }

    public static func indicator(for status: String) -> HookProviderStatus {
        switch status {
        case "operational": .none
        case "degraded_performance": .minor
        case "partial_outage": .major
        case "major_outage", "full_outage": .critical
        case "under_maintenance": .maintenance
        default: .unknown
        }
    }

    /// Descriptor allowlists match exact, normalized top-level names only.
    /// Children of an allowed group remain visible, matching the original app.
    public static func filtered(_ components: [Self], allowlist: Set<String>?) -> [Self] {
        guard let allowlist else { return components }
        return components.filter { allowlist.contains($0.name) }
    }
}

extension WindowsProviderStatusProbe {
    public static func decodeStatuspageComponents(_ data: Data) throws -> [WindowsProviderStatusComponent] {
        try Task.checkCancellation()
        guard data.count <= 1024 * 1024 else { throw Failure.oversized }
        struct Component: Decodable {
            let id: String
            let name: String
            let status: String
            let group: Bool?
            let group_id: String?
            let position: Int?
        }
        struct Response: Decodable { let components: [Component] }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw Failure.invalidResponse }
        guard response.components.count <= 4096 else { throw Failure.oversized }
        var ids = Set<String>()
        for component in response.components {
            guard !component.id.isEmpty, ids.insert(component.id).inserted,
                  component.id.utf8.count <= 1024, component.name.utf8.count <= 4096,
                  component.status.utf8.count <= 256 else { throw Failure.invalidResponse }
        }
        let ordered = response.components.enumerated().sorted {
            let left = $0.element.position ?? 0
            let right = $1.element.position ?? 0
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
        let visible = ordered.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let groupIDs = Set(visible.filter { $0.group == true }.map(\.id))
        func row(_ component: Component, children: [WindowsProviderStatusComponent] = []) -> WindowsProviderStatusComponent {
            WindowsProviderStatusComponent(id: component.id,
                name: component.name.trimmingCharacters(in: .whitespacesAndNewlines),
                rawStatus: component.status, children: children)
        }
        var children: [String: [WindowsProviderStatusComponent]] = [:]
        for component in visible {
            try Task.checkCancellation()
            if component.group == true {
                // This contract has a single level of groups. Reject malformed nesting.
                guard component.group_id == nil else { throw Failure.invalidResponse }
            } else if let parent = component.group_id {
                guard groupIDs.contains(parent) else { throw Failure.invalidResponse }
                children[parent, default: []].append(row(component))
            }
        }
        return visible.compactMap { component in
            if component.group == true { return row(component, children: children[component.id] ?? []) }
            if component.group_id != nil { return nil }
            return row(component)
        }
    }
}
#endif
