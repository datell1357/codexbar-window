import Foundation

public struct RemoteSessionHostResult: Equatable, Sendable, Identifiable {
    public let host: String
    public let sessions: [AgentSession]
    public let error: String?
    public let target: RemoteSessionTarget?

    public var id: String {
        self.host
    }

    public var isReachable: Bool {
        self.error == nil
    }

    public init(
        host: String,
        sessions: [AgentSession],
        error: String?,
        target: RemoteSessionTarget? = nil)
    {
        self.host = host
        self.sessions = sessions
        self.error = error
        self.target = target
    }
}

public enum TailscaleStatusParser {
    /// Parses hosts from `tailscale status --json` output.
    ///
    /// Returns `nil` when `data` is not recognizable Tailscale status JSON — a failed, wrong, or
    /// non-Tailscale `tailscale` binary — so callers can fall through to the next candidate. Returns a
    /// possibly-empty list for a valid status that simply has no eligible peers (a real answer, stop).
    package static func parseHosts(from data: Data, excludingLocalHost localHost: String? = nil) -> [String]? {
        self.parseTargets(from: data, excludingLocalHost: localHost)?.map { target in
            #if os(Windows)
            target.configurationValue
            #else
            target.platform == .windows ? target.configurationValue : target.host
            #endif
        }
    }

    public static func parseTargets(
        from data: Data,
        excludingLocalHost localHost: String? = nil) -> [RemoteSessionTarget]?
    {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let rawBackendState = root["BackendState"] {
            guard let backendState = rawBackendState as? String,
                  backendState.caseInsensitiveCompare("Running") == .orderedSame
            else { return nil }
        }

        let selfStatus: [String: Any]?
        if let rawSelf = root["Self"] {
            guard let parsedSelf = rawSelf as? [String: Any] else { return nil }
            selfStatus = parsedSelf
        } else {
            selfStatus = nil
        }

        let peers: [[String: Any]]
        let hasPeerShape: Bool
        switch root["Peer"] {
        case let dictionary as [String: [String: Any]]:
            peers = Array(dictionary.values)
            hasPeerShape = true
        case let array as [[String: Any]]:
            peers = array
            hasPeerShape = true
        case is NSNull:
            peers = []
            hasPeerShape = true
        case nil:
            peers = []
            hasPeerShape = false
        default:
            return nil
        }
        guard selfStatus != nil || hasPeerShape else { return nil }
        let localLabels = Set([
            localHost,
            selfStatus?["DNSName"] as? String,
            selfStatus?["HostName"] as? String,
        ].compactMap(self.firstDNSLabel).map { $0.lowercased() })

        var seen = Set<String>()
        return peers.compactMap { peer -> RemoteSessionTarget? in
            guard peer["Online"] as? Bool == true,
                  let operatingSystem = peer["OS"] as? String,
                  let platform = RemoteSessionPlatform.tailscaleOS(operatingSystem),
                  let label = self.firstDNSLabel(peer["DNSName"] as? String),
                  RemoteSessionTarget.isValidHost(label)
            else { return nil }
            let normalized = label.lowercased()
            guard !localLabels.contains(normalized), seen.insert(normalized).inserted else { return nil }
            return RemoteSessionTarget(host: label, platform: platform)
        }.sorted { $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending }
    }

    /// Convenience returning `[]` for unparseable output. Prefer `parseHosts` when the caller needs to
    /// distinguish a failed probe from an empty tailnet.
    public static func hosts(from data: Data, excludingLocalHost localHost: String? = nil) -> [String] {
        self.parseHosts(from: data, excludingLocalHost: localHost) ?? []
    }

    private static func firstDNSLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard let label = trimmed.split(separator: ".").first, !label.isEmpty else { return nil }
        return String(label)
    }
}

public enum RemoteSessionDiscoveryOutcome: Sendable {
    case available([RemoteSessionTarget])
    case unavailable(String)
    case cancelled
}

public struct RemoteSessionFetcher: Sendable {
    public static let bundledCLIFallback = "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI"

    public init() {}

    public func discoveredHosts(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        localHost: String = ProcessInfo.processInfo.hostName) async -> [String]
    {
        guard case let .available(targets) = await self.discoverTargets(environment: environment, localHost: localHost)
        else { return [] }
        return targets.map { target in
            #if os(Windows)
            target.configurationValue
            #else
            target.platform == .windows ? target.configurationValue : target.host
            #endif
        }
    }

    public func discoverTargets(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        localHost: String = ProcessInfo.processInfo.hostName) async -> RemoteSessionDiscoveryOutcome
    {
        let probeEnvironment = Self.tailscaleCLIEnvironment(from: environment)
        let candidates = Self.localTailscaleBinaryCandidates(environment: environment)
            .filter { FileManager.default.isExecutableFile(atPath: $0) }
        guard !Task.isCancelled else { return .cancelled }
        guard !candidates.isEmpty else { return .unavailable("Tailscale CLI was not found.") }
        for binary in candidates {
            guard !Task.isCancelled else { return .cancelled }
            do {
                let result = try await SubprocessRunner.run(
                    binary: binary, arguments: ["status", "--json"], environment: probeEnvironment,
                    timeout: 5, label: "Tailscale session host discovery")
                guard !Task.isCancelled else { return .cancelled }
                if let targets = TailscaleStatusParser.parseTargets(
                    from: Data(result.stdout.utf8), excludingLocalHost: localHost)
                {
                    return .available(targets)
                }
            } catch is CancellationError { return .cancelled }
            catch { continue }
        }
        return .unavailable("Tailscale discovery failed or is not signed in.")
    }

    /// Runs `tailscale status --json` on each candidate in order, falling through to the next when a
    /// candidate fails (`run` returns nil), returns invalid status JSON, or reports an inactive backend.
    /// Returns the first candidate's parsed hosts (possibly empty), or `[]` if none succeed. This keeps
    /// the app-binary fallback working even when an earlier — but non-functional — `tailscale` variant
    /// is installed (e.g. an open-source/Homebrew CLI that isn't the active client).
    package static func firstDiscoveredHosts(
        candidates: [String],
        localHost: String?,
        run: (String) async -> Data?) async -> [String]
    {
        for binary in candidates {
            guard let data = await run(binary),
                  let hosts = TailscaleStatusParser.parseHosts(from: data, excludingLocalHost: localHost)
            else { continue }
            return hosts
        }
        return []
    }

    public func fetch(
        hosts: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment) async -> [RemoteSessionHostResult]
    {
        let targets = hosts.compactMap {
            RemoteSessionTarget(configurationValue: $0, defaultPlatform: .legacyDefault)
        }
        return await self.fetch(targets: targets, environment: environment)
    }

    public func fetch(
        targets: [RemoteSessionTarget],
        environment: [String: String] = ProcessInfo.processInfo.environment) async -> [RemoteSessionHostResult]
    {
        let normalized = RemoteSessionTarget.normalized(targets)
        return await withTaskGroup(
            of: RemoteSessionHostResult.self,
            returning: [RemoteSessionHostResult].self)
        { group in
            var iterator = normalized.makeIterator()
            for _ in 0..<min(4, normalized.count) {
                guard !Task.isCancelled, let target = iterator.next() else { break }
                group.addTask { await self.fetch(target: target, environment: environment) }
            }
            var results: [RemoteSessionHostResult] = []
            while let result = await group.next() {
                results.append(result)
                if Task.isCancelled {
                    group.cancelAll()
                } else if let target = iterator.next() {
                    group.addTask { await self.fetch(target: target, environment: environment) }
                }
            }
            return results.sorted {
                $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending
            }
        }
    }

    /// Compatibility entry point. New UI callers should consume the structured focus result.
    public func focus(
        sessionID: String,
        host: String,
        environment: [String: String] = ProcessInfo.processInfo.environment) async
    {
        guard let target = RemoteSessionTarget(configurationValue: host, defaultPlatform: .legacyDefault) else { return }
        _ = await self.focus(sessionID: sessionID, target: target, environment: environment)
    }

    public func focus(
        sessionID: String,
        target: RemoteSessionTarget,
        environment: [String: String] = ProcessInfo.processInfo.environment) async -> RemoteSessionFocusResult
    {
        do {
            let arguments = try RemoteSessionCommandBuilder.arguments(target: target, operation: .focus(sessionID))
            try Task.checkCancellation()
            guard let ssh = self.sshExecutable(environment: environment) else {
                return .failed("ssh not found")
            }
            _ = try await SubprocessRunner.run(
                binary: ssh,
                arguments: arguments,
                environment: environment,
                timeout: 5,
                label: "focus remote agent session")
            try Task.checkCancellation()
            return .focused
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func fetch(
        target: RemoteSessionTarget,
        environment: [String: String]) async -> RemoteSessionHostResult
    {
        // Keep legacy POSIX result equality unchanged; Windows/explicit API targets retain the
        // remote platform and optional path so later focus does not guess the login shell.
        #if os(Windows)
        let retainedTarget: RemoteSessionTarget? = target
        #else
        let retainedTarget = target.platform == .posix && target.executablePath == nil ? nil : target
        #endif
        do {
            let arguments = try RemoteSessionCommandBuilder.arguments(target: target, operation: .list)
            try Task.checkCancellation()
            guard let ssh = self.sshExecutable(environment: environment) else {
                return RemoteSessionHostResult(
                    host: target.host, sessions: [], error: "ssh not found", target: retainedTarget)
            }
            let result = try await SubprocessRunner.run(
                binary: ssh,
                arguments: arguments,
                environment: environment,
                timeout: 5,
                label: "fetch remote agent sessions")
            try Task.checkCancellation()
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var sessions = try decoder.decode([AgentSession].self, from: Data(result.stdout.utf8))
            for index in sessions.indices {
                sessions[index].host = target.host
            }
            return RemoteSessionHostResult(
                host: target.host, sessions: sessions, error: nil, target: retainedTarget)
        } catch {
            return RemoteSessionHostResult(
                host: target.host, sessions: [], error: error.localizedDescription, target: retainedTarget)
        }
    }

    private func sshExecutable(environment: [String: String]) -> String? {
        #if os(Windows)
        if let resolved = self.findExecutable("ssh", environment: environment) { return resolved }
        guard let systemRoot = CodexBarPlatformPaths.environmentValue("SystemRoot", environment: environment) else {
            return nil
        }
        return WindowsExecutableResolver.resolve(
            executable: URL(fileURLWithPath: systemRoot, isDirectory: true)
                .appendingPathComponent("System32/OpenSSH/ssh.exe").path,
            override: nil,
            environment: environment)
        #else
        return self.findExecutable("ssh", environment: environment) ??
            ["/usr/bin/ssh", "/bin/ssh"].first { FileManager.default.isExecutableFile(atPath: $0) }
        #endif
    }

    private static func localTailscaleBinaryCandidates(environment: [String: String]) -> [String] {
        #if os(Windows)
        var candidates: [String] = []
        if let resolved = WindowsExecutableResolver.resolve(
            executable: "tailscale", override: nil, environment: environment)
        {
            candidates.append(resolved)
        }
        for key in ["ProgramW6432", "ProgramFiles", "ProgramFiles(x86)"] {
            guard let directory = CodexBarPlatformPaths.environmentValue(key, environment: environment) else { continue }
            candidates.append(URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("Tailscale/tailscale.exe").path)
        }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.lowercased()).inserted }
        #else
        return self.tailscaleBinaryCandidates(path: environment["PATH"])
        #endif
    }

    /// Tries the v2 session JSON protocol first, then the legacy v1 form, for both PATH and the
    /// bundled app CLI. Each fallback is reached only when the preceding command exits non-zero.
    package static func remoteSessionsCommand() -> String {
        let bundledCLI = Self.shellQuote(Self.bundledCLIFallback)
        return [
            "codexbar sessions --json-v2",
            "codexbar sessions --json",
            "\(bundledCLI) sessions --json-v2",
            "\(bundledCLI) sessions --json",
        ].joined(separator: " || ")
    }

    /// Ordered candidate paths for the `tailscale` CLI, most-preferred first.
    ///
    /// The macOS app ships its CLI as a thin `/bin/sh` wrapper (usually
    /// `/usr/local/bin/tailscale`) around the app's dual-mode binary. We prefer the
    /// wrapper, but a GUI-launched CodexBar inherits a minimal `PATH` (`/usr/bin:/bin`)
    /// that omits the standard CLI locations, so we also probe them explicitly before
    /// falling back to the app binary itself.
    package static func tailscaleBinaryCandidates(path: String?) -> [String] {
        let pathDirs = path?.split(separator: ":").map(String.init) ?? []
        var seen = Set<String>()
        var candidates = (pathDirs + ["/usr/local/bin", "/opt/homebrew/bin"])
            .filter { seen.insert($0).inserted }
            .map { $0 + "/tailscale" }
        // Last resort: the dual-mode app binary. Must be run via
        // `tailscaleCLIEnvironment(from:)` so it stays in CLI mode.
        candidates.append("/Applications/Tailscale.app/Contents/MacOS/Tailscale")
        return candidates
    }

    /// Environment that keeps the dual-mode Tailscale app binary in CLI mode.
    ///
    /// Shell markers alone can still select the GUI path and crash newer app binaries. Force the
    /// documented CLI override for every candidate, including symlinks to the app. Retain the shell
    /// marker for older installations without changing an existing terminal context.
    package static func tailscaleCLIEnvironment(from environment: [String: String]) -> [String: String] {
        var environment = environment
        environment["TAILSCALE_BE_CLI"] = "1"
        if environment["TERM"] == nil, environment["SHLVL"] == nil {
            environment["SHLVL"] = "1"
        }
        return environment
    }

    private func findExecutable(_ name: String, environment: [String: String]) -> String? {
        #if os(Windows)
        return WindowsExecutableResolver.resolve(executable: name, override: nil, environment: environment)
        #else
        let path = environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        return path.split(separator: ":")
            .map { String($0) + "/" + name }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        #endif
    }

    public static func sanitizedHosts(_ hosts: [String]) -> [String] {
        var seen = Set<String>()
        return hosts.compactMap { rawHost in
            let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasUnsafeScalar = host.unicodeScalars.contains { scalar in
                CharacterSet.controlCharacters.contains(scalar) ||
                    CharacterSet.whitespacesAndNewlines.contains(scalar)
            }
            guard !host.isEmpty,
                  !host.hasPrefix("-"),
                  !hasUnsafeScalar,
                  seen.insert(host.lowercased()).inserted
            else { return nil }
            return host
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
