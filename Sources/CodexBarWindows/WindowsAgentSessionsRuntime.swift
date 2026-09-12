#if os(Windows)
import CodexBarCore
import Foundation

public struct WindowsSessionFocusRequest: Sendable {
    public let sessionID: String
    public let generation: UInt64
}

public struct WindowsSessionMenuItem: Sendable {
    public let title: String
    public let request: WindowsSessionFocusRequest
    public let isEnabled: Bool
}

public struct WindowsSessionMenuSnapshot: Sendable {
    public let enabled: Bool
    public let isRefreshing: Bool
    public let rows: [WindowsSessionMenuItem]
    public let message: String?
    public let page: WindowsSessionPage

    public init(enabled: Bool, isRefreshing: Bool, rows: [WindowsSessionMenuItem], message: String?,
                page: WindowsSessionPage = .empty) {
        self.enabled = enabled; self.isRefreshing = isRefreshing; self.rows = rows; self.message = message
        self.page = page
    }

    public static let disabled = Self(enabled: false, isRefreshing: false, rows: [], message: nil)
}

/// Independent from quota refresh: local process discovery never starts because a provider fetch
/// happens. The explicit Agent Sessions setting owns its schedule, retained identities and actions.
public actor WindowsAgentSessionsRuntime {
    public typealias Publisher = @Sendable (WindowsSessionMenuSnapshot) -> Void
    private let defaults: UserDefaults
    private var publisher: Publisher = { _ in }
    private var running = false
    private var terminated = false
    private var deferredRefreshTask: Task<Void, Never>?
    private var enabled = false
    private var generation: UInt64 = 0
    private var pageIndex = 0
    private var periodicTask: Task<Void, Never>?
    private var scanTask: Task<WindowsSessionScanOutcome, Never>?
    private var focusTask: Task<SessionFocusResult, Never>?
    private var queuedRefresh = false
    private var sessions: [AgentSession] = []
    private var fresh = false
    private var message: String?

    public init() {
        self.defaults = UserDefaults(suiteName: WindowsRefreshSettings.suiteName) ?? .standard
    }

    public func setPublisher(_ publisher: @escaping Publisher) {
        self.publisher = publisher
        self.publish()
    }

    public func start() {
        guard !self.running, !self.terminated else { return }
        self.running = true
        self.enabled = self.defaults.object(forKey: "agentSessionsEnabled") as? Bool ?? false
        self.reconcileSchedule()
        self.publish()
    }

    private func reconcileSchedule() {
        guard self.running, self.enabled else {
            self.periodicTask?.cancel()
            self.periodicTask = nil
            return
        }
        guard self.periodicTask == nil else { return }
        self.periodicTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    private func performDeferredRefresh() async {
        self.deferredRefreshTask = nil
        await self.refresh()
    }

    public func settingsDidChange() async {
        guard self.running else { return }
        self.generation &+= 1
        self.pageIndex = 0
        self.enabled = self.defaults.object(forKey: "agentSessionsEnabled") as? Bool ?? false
        self.focusTask?.cancel()
        self.scanTask?.cancel()
        self.queuedRefresh = self.enabled && self.scanTask != nil
        self.message = nil
        // This callback also changes the native-directory opt-in. Drop prior enrichment immediately.
        self.sessions = []
        self.fresh = false
        self.reconcileSchedule()
        self.publish()
        if self.enabled { await self.refresh() }
    }

    public func movePage(_ request: WindowsSessionPageRequest) -> Bool {
        guard self.running, self.enabled, request.generation == self.generation else { return false }
        self.pageIndex = request.index
        self.publish()
        return true
    }

    public func presentationDidChange() {
        guard self.running else { return }
        self.publish()
    }

    public func refresh() async {
        guard self.running, self.enabled, !Task.isCancelled else { return }
        guard self.scanTask == nil else {
            self.queuedRefresh = true
            return
        }
        let currentGeneration = self.generation
        let nativeDirectoryReadEnabled = self.defaults.object(forKey: "windowsNativeSessionCwdEnabled") as? Bool ?? false
        let metadataRoots: WindowsSessionMetadataRoots
        do { metadataRoots = try self.metadataRoots() }
        catch {
            self.fresh = false
            self.message = "Session metadata folder settings are invalid. Configure absolute local drive paths."
            self.publish()
            return
        }
        let task = Task.detached(priority: .utility) {
            await WindowsAgentSessionScanner.scanOutcome(
                nativeDirectoryReadEnabled: nativeDirectoryReadEnabled, metadataRoots: metadataRoots)
        }
        self.scanTask = task
        self.publish()
        let result = await task.value
        self.scanTask = nil
        if self.running, self.enabled, self.generation == currentGeneration, !Task.isCancelled,
           (self.defaults.object(forKey: "agentSessionsEnabled") as? Bool ?? false),
           nativeDirectoryReadEnabled == (self.defaults.object(forKey: "windowsNativeSessionCwdEnabled") as? Bool ?? false),
           (try? self.metadataRoots()) == metadataRoots
        {
            switch result.status {
            case .complete, .partial:
                self.sessions = result.sessions
                self.fresh = true
                self.message = result.message
            case .failed:
                self.fresh = false
                self.message = result.message ?? "Session discovery failed."
                if !self.sessions.isEmpty {
                    self.message = (self.message ?? "") + " Showing the previous list; actions are disabled."
                }
            case .cancelled:
                break
            }
            self.publish()
        }
        let repeatRequested = self.queuedRefresh
        self.queuedRefresh = false
        if repeatRequested, self.running, self.enabled, self.deferredRefreshTask == nil {
            // Do not inherit a cancelled periodic caller when an off/on change requested new data.
            self.deferredRefreshTask = Task { [weak self] in
                await self?.performDeferredRefresh()
            }
        }
    }

    public func focus(_ request: WindowsSessionFocusRequest) async {
        guard self.running, self.enabled, request.generation == self.generation else { return }
        guard self.focusTask == nil else { return }
        guard self.fresh, let session = self.sessions.first(where: { $0.id == request.sessionID }) else {
            self.message = "This session is no longer available. Refresh the session list."
            self.publish()
            return
        }
        let currentGeneration = self.generation
        let task = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return SessionFocusResult.failed }
            return SessionWindowFocuser.focus(session)
        }
        self.focusTask = task
        let result = await task.value
        self.focusTask = nil
        guard self.running, self.enabled, self.generation == currentGeneration, !Task.isCancelled else { return }
        switch result {
        case .focused:
            self.message = "Session window activated."
        case .activatedApplicationOnly:
            self.message = "Application window activated; the exact terminal tab was not selected."
        case .failed:
            self.message = "Could not activate this session. Its process, window, or foreground permission changed."
        }
        self.publish()
    }

    public func shutdown() async {
        self.running = false
        self.terminated = true
        self.enabled = false
        self.generation &+= 1
        self.queuedRefresh = false
        let deferred = self.deferredRefreshTask
        self.deferredRefreshTask = nil
        deferred?.cancel()
        let periodic = self.periodicTask
        let scan = self.scanTask
        let focus = self.focusTask
        self.periodicTask = nil
        periodic?.cancel()
        scan?.cancel()
        focus?.cancel()
        self.sessions = []
        self.message = nil
        self.fresh = false
        self.publisher(.disabled)
        _ = await scan?.value
        _ = await focus?.value
        await periodic?.value
        await deferred?.value
    }

    private func metadataRoots() throws -> WindowsSessionMetadataRoots {
        guard self.defaults.object(forKey: "windowsSessionMetadataEnabled") as? Bool ?? false else { return .none }
        return try WindowsSessionMetadataRoots.load(
            codexOverride: self.defaults.string(forKey: "windowsCodexSessionDirectory"),
            claudeOverride: self.defaults.string(forKey: "windowsClaudeProjectDirectory"),
            allowNewSessions: self.defaults.object(forKey: "windowsInferNewSessionMetadataEnabled") as? Bool ?? false,
            codexTitleIndexOverride: self.defaults.string(forKey: "windowsCodexTitleIndex"))
    }

    private func publish() {
        guard self.enabled else {
            self.publisher(.disabled)
            return
        }
        let hidePersonalInfo = self.defaults.object(forKey: "hidePersonalInfo") as? Bool ?? false
        let style = WindowsSessionLabelStyle.load(self.defaults)
        let page = WindowsSessionPage(index: self.pageIndex, totalItems: self.sessions.count, generation: self.generation)
        self.pageIndex = page.index
        let rows = self.sessions[page.range].map { session in
            let label = style.label(session, hidePersonalInfo: hidePersonalInfo)
            let process = "PID \(session.pid.map(String.init) ?? "—")"
            let detail = label.map { "\($0) · \(process)" } ?? process
            let provider = session.dialect?.rawValue ?? session.provider.rawValue
            // Ampersands are Win32 menu mnemonic markers; session titles are plain text.
            let title = "\(provider) · \(detail)".replacingOccurrences(of: "&", with: "&&")
            return WindowsSessionMenuItem(
                title: title,
                request: .init(sessionID: session.id, generation: self.generation),
                isEnabled: self.fresh)
        }
        let status = self.message ?? (self.scanTask != nil ? "Scanning local CLI sessions…" :
            (rows.isEmpty ? "No recognized local CLI sessions." : "Labels use available launch paths, opted-in native directories, or selected session headers."))
        self.publisher(.init(enabled: true, isRefreshing: self.scanTask != nil, rows: rows, message: status, page: page))
    }
}
#endif
