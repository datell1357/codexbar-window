#if os(Windows)
import CodexBarCore
import Foundation

public struct WindowsRemoteFocusRequest: Sendable {
    public let hostID: String
    public let sessionID: String
    public let generation: UInt64
}

public struct WindowsRemoteSessionMenuItem: Sendable {
    public let title: String
    public let request: WindowsRemoteFocusRequest
    public let isEnabled: Bool
}

public struct WindowsRemoteSessionMenuSnapshot: Sendable {
    public let enabled: Bool
    public let rows: [WindowsRemoteSessionMenuItem]
    public let messages: [String]
    public static let disabled = Self(enabled: false, rows: [], messages: [])
}

public actor WindowsRemoteSessionsRuntime {
    public typealias Publisher = @Sendable (WindowsRemoteSessionMenuSnapshot) -> Void
    private struct RefreshResult: Sendable {
        let hosts: [RemoteSessionHostResult]
        let message: String?
        let discoveryFailed: Bool
        let cancelled: Bool
    }
    private let defaults: UserDefaults
    private var settings = WindowsRemoteSessionSettings.defaults
    private var publisher: Publisher = { _ in }
    private var started = false
    private var terminated = false
    private var generation: UInt64 = 0
    private var loop: Task<Void, Never>?
    private var deferred: Task<Void, Never>?
    private var fetchTask: Task<RefreshResult, Never>?
    private var focusTask: Task<RemoteSessionFocusResult, Never>?
    private var queued = false
    private var hosts: [RemoteSessionHostResult] = []
    private var message: String?

    public init() {
        self.defaults = UserDefaults(suiteName: WindowsRefreshSettings.suiteName) ?? .standard
    }

    public func setPublisher(_ publisher: @escaping Publisher) { self.publisher = publisher; self.publish() }

    public func start() {
        guard !self.started, !self.terminated else { return }
        self.started = true
        self.loadSettings()
        self.reconcileSchedule()
        self.publish()
    }

    private func loadSettings() {
        do { self.settings = try WindowsRemoteSessionSettings.load(from: self.defaults) }
        catch {
            self.settings = .defaults
            self.message = "Remote session settings could not be read."
        }
    }

    public func settingsDidChange() async {
        guard self.started else { return }
        self.generation &+= 1
        self.fetchTask?.cancel(); self.focusTask?.cancel()
        self.hosts = []; self.message = nil
        self.loadSettings()
        self.queued = self.settings.enabled && self.fetchTask != nil
        self.reconcileSchedule()
        self.publish()
        if self.settings.enabled { await self.refresh() }
    }

    public func presentationDidChange() { self.publish() }

    private func reconcileSchedule() {
        guard self.started, self.settings.enabled else {
            self.loop?.cancel(); self.loop = nil
            return
        }
        guard self.loop == nil else { return }
        self.loop = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    public func refresh() async {
        guard self.started, self.settings.enabled, !Task.isCancelled else { return }
        guard self.fetchTask == nil else { self.queued = true; return }
        let settings = self.settings
        let generation = self.generation
        let task = Task.detached(priority: .utility) { await Self.collect(settings: settings) }
        self.fetchTask = task; self.publish()
        let result = await task.value
        self.fetchTask = nil
        if self.started, self.settings.enabled, self.generation == generation, !result.cancelled {
            let old = Dictionary(self.hosts.map { ($0.host.lowercased(), $0) }, uniquingKeysWith: { _, new in new })
            self.hosts = result.hosts.map { host in
                guard host.error != nil, let previous = old[host.host.lowercased()] else { return host }
                return RemoteSessionHostResult(
                    host: host.host, sessions: previous.sessions, error: host.error, target: host.target ?? previous.target)
            }
            if result.discoveryFailed {
                let current = Set(self.hosts.map { $0.host.lowercased() })
                self.hosts += old.values.filter { !current.contains($0.host.lowercased()) }.map {
                    RemoteSessionHostResult(host: $0.host, sessions: $0.sessions,
                                            error: "Discovery unavailable", target: $0.target)
                }
            }
            self.hosts.sort { $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending }
            self.message = result.message
            self.publish()
        }
        let repeatRequested = self.queued; self.queued = false
        if repeatRequested, self.started, self.settings.enabled, self.deferred == nil {
            self.deferred = Task { [weak self] in await self?.runDeferred() }
        }
    }

    private func runDeferred() async { self.deferred = nil; await self.refresh() }

    private static func collect(settings: WindowsRemoteSessionSettings) async -> RefreshResult {
        let fetcher = RemoteSessionFetcher()
        var targets = settings.targets
        var message: String?
        var discoveryFailed = false
        if settings.discoverTailscale {
            switch await fetcher.discoverTargets() {
            case let .available(discovered):
                var seen = Set(targets.map(\.id))
                targets += discovered.filter { seen.insert($0.id).inserted }
            case let .unavailable(reason): message = reason; discoveryFailed = true
            case .cancelled: return .init(hosts: [], message: nil, discoveryFailed: false, cancelled: true)
            }
        }
        if targets.count > 32 {
            message = [message, "Showing the first 32 remote hosts; configure manual hosts to select others."]
                .compactMap { $0 }.joined(separator: " ")
        }
        guard !Task.isCancelled else { return .init(hosts: [], message: nil, discoveryFailed: false, cancelled: true) }
        let hosts = await fetcher.fetch(targets: Array(targets.prefix(32)))
        return .init(hosts: hosts, message: message, discoveryFailed: discoveryFailed, cancelled: Task.isCancelled)
    }

    public func focus(_ request: WindowsRemoteFocusRequest) async {
        guard self.started, self.settings.enabled, self.generation == request.generation,
              self.focusTask == nil,
              let host = self.hosts.first(where: { $0.host.lowercased() == request.hostID }),
              host.error == nil, let target = host.target,
              host.sessions.contains(where: { $0.id == request.sessionID })
        else { return }
        let generation = self.generation
        let task = Task.detached(priority: .userInitiated) {
            await RemoteSessionFetcher().focus(sessionID: request.sessionID, target: target)
        }
        self.focusTask = task
        let result = await task.value
        self.focusTask = nil
        guard self.started, self.settings.enabled, self.generation == generation, !Task.isCancelled else { return }
        switch result {
        case .focused: self.message = "The remote CLI accepted the focus request. Exact tab selection is not confirmed."
        case .failed: self.message = "The remote focus request failed. Refresh the list and check the host settings."
        }
        self.publish()
    }

    public func shutdown() async {
        self.started = false; self.terminated = true; self.generation &+= 1; self.queued = false
        let loop = self.loop, deferred = self.deferred, fetch = self.fetchTask, focus = self.focusTask
        self.loop = nil; self.deferred = nil
        loop?.cancel(); deferred?.cancel(); fetch?.cancel(); focus?.cancel()
        self.hosts = []; self.message = nil; self.settings = .defaults
        self.publisher(.disabled)
        _ = await fetch?.value; _ = await focus?.value
        await loop?.value; await deferred?.value
    }

    private func publish() {
        guard self.settings.enabled else {
            self.publisher(.init(enabled: false, rows: [], messages: self.message.map { [$0] } ?? []))
            return
        }
        let hide = self.defaults.object(forKey: "hidePersonalInfo") as? Bool ?? false
        let style = WindowsSessionLabelStyle.load(self.defaults)
        var messages = self.message.map { [$0] } ?? []
        if self.fetchTask != nil { messages.append("Refreshing remote sessions…") }
        var rows: [WindowsRemoteSessionMenuItem] = []
        for (index, host) in self.hosts.enumerated() {
            let hostLabel = hide ? "Remote host \(index + 1)" : host.host
            if host.error != nil { messages.append("\(hostLabel): unavailable; previous rows are disabled.") }
            else if host.sessions.isEmpty { messages.append("\(hostLabel): no sessions reported.") }
            for session in host.sessions.prefix(32) where rows.count < 128 {
                let detail = style.label(session, hidePersonalInfo: hide) ?? session.provider.rawValue
                let plainTitle = "\(hostLabel) · \(detail)".unicodeScalars.filter {
                    !CharacterSet.controlCharacters.contains($0)
                }.map { String($0) }.joined()
                let title = String(plainTitle.prefix(160)).replacingOccurrences(of: "&", with: "&&")
                rows.append(.init(title: title,
                                  request: .init(hostID: host.host.lowercased(), sessionID: session.id, generation: self.generation),
                                  isEnabled: host.error == nil && host.target != nil))
            }
        }
        if self.hosts.isEmpty, self.fetchTask == nil, messages.isEmpty { messages.append("No remote hosts configured or discovered.") }
        if self.hosts.reduce(0, { $0 + $1.sessions.count }) > rows.count { messages.append("The remote session menu is truncated.") }
        self.publisher(.init(enabled: true, rows: rows, messages: messages))
    }
}
#endif
