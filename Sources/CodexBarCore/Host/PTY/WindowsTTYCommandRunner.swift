#if os(Windows)
import Foundation

typealias pid_t = Int32

private enum WindowsTTYProcessRegistry {
    private static let lock = NSCondition()
    nonisolated(unsafe) private static var shuttingDown = false
    nonisolated(unsafe) private static var launches = 0
    nonisolated(unsafe) private static var processes: [pid_t: WindowsConPTYProcess] = [:]
    static func beginLaunch() -> Bool { lock.lock(); defer { lock.unlock() }; guard !shuttingDown else { return false }; launches += 1; return true }
    static func endLaunch() { lock.lock(); launches = max(0, launches - 1); lock.broadcast(); lock.unlock() }
    static func register(_ process: WindowsConPTYProcess) -> Bool { lock.lock(); defer { lock.unlock() }; guard !shuttingDown else { return false }; processes[Int32(bitPattern: process.processID)] = process; return true }
    static func unregister(_ pid: pid_t) { lock.lock(); processes.removeValue(forKey: pid); lock.unlock() }
    static func shutdown() -> [WindowsConPTYProcess] { lock.lock(); shuttingDown = true; while launches > 0 { lock.wait() }; let value = Array(processes.values); processes.removeAll(); lock.unlock(); return value }
}

/// Windows counterpart for the POSIX PTY runner.
///
/// ConPTY-backed runner preserving the POSIX runner's provider-facing contract.
public struct TTYCommandRunner {
    public struct Result: Sendable {
        public enum Completion: Sendable, Equatable {
            case processExited(status: Int32)
            case idleTimeout
            case outputCondition
            case deadlineExceeded
        }

        public let text: String
        public let completion: Completion
    }

    public struct Options: Sendable {
        public var rows: UInt16 = 50
        public var cols: UInt16 = 160
        public var timeout: TimeInterval = 20
        public var idleTimeout: TimeInterval?
        public var workingDirectory: URL?
        public var extraArgs: [String] = []
        public var baseEnvironment: [String: String]?
        public var initialDelay: TimeInterval = 0.4
        public var sendEnterEvery: TimeInterval?
        public var sendOnSubstrings: [String: String]
        public var stopOnURL: Bool
        public var stopOnSubstrings: [String]
        public var settleAfterStop: TimeInterval
        public var forceCodexStatusMode: Bool
        public var useProviderProbeWorkingDirectory: Bool
        public var returnOnEmptyProcessExit: Bool
        public var cancellationCheck: @Sendable () -> Bool

        public init(
            rows: UInt16 = 50, cols: UInt16 = 160, timeout: TimeInterval = 20,
            idleTimeout: TimeInterval? = nil, workingDirectory: URL? = nil,
            extraArgs: [String] = [], baseEnvironment: [String: String]? = nil,
            initialDelay: TimeInterval = 0.4, sendEnterEvery: TimeInterval? = nil,
            sendOnSubstrings: [String: String] = [:], stopOnURL: Bool = false,
            stopOnSubstrings: [String] = [], settleAfterStop: TimeInterval = 0.25,
            forceCodexStatusMode: Bool = false, useProviderProbeWorkingDirectory: Bool = false,
            returnOnEmptyProcessExit: Bool = false,
            cancellationCheck: @escaping @Sendable () -> Bool = { Task<Never, Never>.isCancelled })
        {
            self.rows = rows; self.cols = cols; self.timeout = timeout
            self.idleTimeout = idleTimeout; self.workingDirectory = workingDirectory
            self.extraArgs = extraArgs; self.baseEnvironment = baseEnvironment
            self.initialDelay = initialDelay; self.sendEnterEvery = sendEnterEvery
            self.sendOnSubstrings = sendOnSubstrings; self.stopOnURL = stopOnURL
            self.stopOnSubstrings = stopOnSubstrings; self.settleAfterStop = settleAfterStop
            self.forceCodexStatusMode = forceCodexStatusMode
            self.useProviderProbeWorkingDirectory = useProviderProbeWorkingDirectory
            self.returnOnEmptyProcessExit = returnOnEmptyProcessExit
            self.cancellationCheck = cancellationCheck
        }
    }

    public enum Error: Swift.Error, LocalizedError, Sendable {
        case binaryNotFound(String)
        case launchFailed(String)
        case timedOut
        case outputTooLarge

        public var errorDescription: String? {
            switch self {
            case let .binaryNotFound(binary): "Missing CLI '\(binary)'. Add it to PATH."
            case let .launchFailed(message): "Failed to launch process: \(message)"
            case .timedOut: "PTY command timed out."
            case .outputTooLarge: "PTY command produced more output than CodexBar can safely process."
            }
        }
    }

    public init() {}

    public func run(
        binary: String,
        send script: String,
        options: Options = Options(),
        onURLDetected: (@Sendable () -> Void)? = nil) throws -> Result
    {
        let base = options.baseEnvironment ?? ProcessInfo.processInfo.environment
        guard let resolved = WindowsCommandResolver.resolve(executable: binary, override: nil, environment: base) else { throw Error.binaryNotFound(binary) }
        let requestName = URL(fileURLWithPath: binary).lastPathComponent
        let descriptor = ProviderDescriptorRegistry.all.first { $0.cli.name.caseInsensitiveCompare(binary) == .orderedSame || $0.cli.name.caseInsensitiveCompare(requestName) == .orderedSame || $0.cli.name.caseInsensitiveCompare(URL(fileURLWithPath: resolved.sourcePath).lastPathComponent) == .orderedSame }
        guard WindowsTTYProcessRegistry.beginLaunch() else { throw Error.launchFailed("App shutdown in progress") }
        let process: WindowsConPTYProcess
        let workingDirectory = options.workingDirectory ?? (options.useProviderProbeWorkingDirectory ? descriptor?.cli.ttyLaunch?.probeWorkingDirectory?() : nil)
        do { process = try WindowsConPTYProcess.launch(target: resolved.target, arguments: options.extraArgs, environment: Self.enrichedEnvironment(baseEnv: base, home: base.first { $0.key.caseInsensitiveCompare("HOME") == .orderedSame }?.value ?? NSHomeDirectory()), currentDirectoryURL: workingDirectory, rows: options.rows, cols: options.cols) }
        catch { WindowsTTYProcessRegistry.endLaunch(); throw Error.launchFailed(error.localizedDescription) }
        guard WindowsTTYProcessRegistry.register(process) else { WindowsTTYProcessRegistry.endLaunch(); process.close(); throw Error.launchFailed("App shutdown in progress") }
        WindowsTTYProcessRegistry.endLaunch()
        var didExceedOutputLimit = false
        defer {
            WindowsTTYProcessRegistry.unregister(Int32(bitPattern: process.processID))
            if !didExceedOutputLimit, process.isExited == false { try? process.write(Data("/exit\n".utf8), deadline: Date().addingTimeInterval(0.15), cancellationCheck: { false }) }
            process.close()
        }
        func check() throws { if options.cancellationCheck() { process.terminate(); throw CancellationError() } }
        let deadline = Date().addingTimeInterval(max(0, options.timeout))
        func write(_ data: Data, until limit: Date? = nil) throws {
            do { try process.write(data, deadline: limit ?? deadline, cancellationCheck: options.cancellationCheck) }
            catch is CancellationError { throw CancellationError() }
            catch is WindowsConPTYProcess.WriteError { throw Error.timedOut }
            catch { throw Error.launchFailed(error.localizedDescription) }
        }
        func writeText(_ text: String, until limit: Date? = nil) throws {
            guard let data = text.data(using: .utf8), !data.isEmpty else { return }
            try write(data, until: limit)
        }
        do { try process.resume() }
        catch is CancellationError { throw CancellationError() }
        catch let error as Error { throw error }
        catch { throw Error.launchFailed(error.localizedDescription) }
        if options.initialDelay > 0 { Thread.sleep(forTimeInterval: min(options.initialDelay, max(0, deadline.timeIntervalSinceNow))) }; try check()
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        let codexCommand = descriptor?.cli.ttyStatusCommand
        let codex = options.forceCodexStatusMode || codexCommand != nil
        let statusOnly = codex && trimmed == (codexCommand ?? "/status")
        // Codex status probes must wait for the update prompt before sending
        // /status. Generic providers can receive their script immediately.
        let delayInitialSend = codex && statusOnly
        var output = BoundedOutputBuffer(); var lastOutput = Date(); var lastEnter = codex ? Date.distantPast : Date(); var nextCursor = Date.distantPast
        var scanTail = Data()
        let cursorQuery = Data([0x1b, 0x5b, 0x36, 0x6e])
        let scanNeedleLengths = options.stopOnSubstrings.map { $0.utf8.count }
            + options.sendOnSubstrings.keys.map { $0.utf8.count }
            + [Data("http://".utf8).count, Data("https://".utf8).count]
            + [cursorQuery.count]
        let maxScanTail = max(0, (scanNeedleLengths.max() ?? 1) - 1)
        var statusTail = Data()
        var updateTail = Data()
        let statusMarkers = ["Credits:", "5h limit", "5-hour limit", "Weekly limit"].map { Data($0.utf8) }
        let updateMarkers = ["update available!", "run bun install -g @openai/codex", "0.60.1 ->"].map { Data($0.utf8) }
        var scriptSentAt: Date? = delayInitialSend ? nil : Date(); var resendRetries = 0; var enterRetries = 0; var stopped = false; var idleStopped = false; var sawURL = false; var sentNeedles = Set<String>(); var sawStatus = false; var skippedUpdate = false; var stoppedForDeadline = false; var recentText = ""
        var sentScript = !delayInitialSend
        var sawEOF = false
        var exitedBeforeDeadline = false
        do {
            if !delayInitialSend, !trimmed.isEmpty {
                try writeText(codex ? script : trimmed)
                try writeText("\r")
                if codex { Thread.sleep(forTimeInterval: 0.15); try writeText("\r\u{1b}") }
            }
        } catch is CancellationError { throw CancellationError() }
        catch let error as Error { throw error }
        catch is WindowsConPTYProcess.WriteError { throw Error.timedOut }
        catch { throw Error.launchFailed(error.localizedDescription) }
        while Date() < deadline {
            try check()
            switch process.read() {
            case let .data(data) where !data.isEmpty:
                lastOutput = Date(); guard output.append(data) else { didExceedOutputLimit = true; process.terminate(); throw Error.outputTooLarge }
                recentText = String((recentText + (String(data: data, encoding: .utf8) ?? "")).suffix(8192))
                var scanData = Data(); scanData.append(scanTail); scanData.append(data)
                scanTail = maxScanTail > 0 ? Data(scanData.suffix(maxScanTail)) : Data()
                var lowerData = data
                lowerData = Data(lowerData.map { ($0 >= 65 && $0 <= 90) ? $0 + 32 : $0 })
                var statusWindow = Data(); statusWindow.append(statusTail); statusWindow.append(data)
                var updateWindow = Data(); updateWindow.append(updateTail); updateWindow.append(lowerData)
                statusTail = Data(statusWindow.suffix(63)); updateTail = Data(updateWindow.suffix(127))
                if Date() >= nextCursor, scanData.range(of: cursorQuery) != nil {
                    try? write(Data([0x1b, 0x5b, 0x31, 0x3b, 0x31, 0x52]), until: min(deadline, Date().addingTimeInterval(0.25))); nextCursor = Date().addingTimeInterval(1)
                }
                for (needle, keys) in options.sendOnSubstrings where !codex {
                    guard !sentNeedles.contains(needle), (scanData.range(of: Data(needle.utf8)) != nil || recentText.contains(needle) || recentText.replacingOccurrences(of: "\r", with: "").contains(needle)) else { continue }
                    try? write(Data(keys.utf8), until: min(deadline, Date().addingTimeInterval(0.5))); sentNeedles.insert(needle)
                }
                if codex {
                    if statusMarkers.contains(where: { statusWindow.range(of: $0) != nil }) { sawStatus = true }
                    if !skippedUpdate && updateMarkers.contains(where: { updateWindow.range(of: $0) != nil }) {
                        try? write(Data("\u{1b}[B".utf8), until: min(deadline, Date().addingTimeInterval(0.5))); Thread.sleep(forTimeInterval: 0.12); try? write(Data("\r".utf8), until: min(deadline, Date().addingTimeInterval(0.5))); Thread.sleep(forTimeInterval: 0.15); try? write(Data("\r/status\r".utf8), until: min(deadline, Date().addingTimeInterval(0.5))); skippedUpdate = true; sentScript = false; scriptSentAt = nil; sawStatus = false; output.removeAll(); statusTail.removeAll(); updateTail.removeAll(); scanTail.removeAll()
                        Thread.sleep(forTimeInterval: 0.3)
                    }
                }
                if !codex, !sawURL, (scanData.range(of: Data("http://".utf8)) != nil || scanData.range(of: Data("https://".utf8)) != nil) {
                    sawURL = true
                    onURLDetected?(); if options.stopOnURL { stopped = true }
                }
                if !codex, options.stopOnSubstrings.contains(where: { scanData.range(of: Data($0.utf8)) != nil }) { stopped = true }
            case .overflow: didExceedOutputLimit = true; process.terminate(); throw Error.outputTooLarge
            case .eof: sawEOF = true; if !codex && process.isExited { stopped = true }
            case let .failed(code): process.terminate(); throw Error.launchFailed("ConPTY read failed (\(code))")
            default: break
            }
            if !codex, process.isExited { exitedBeforeDeadline = true; break }
            if stopped { break }
            if codex && sawStatus { stopped = true; break }
            if codex && ((!sentScript && !skippedUpdate) || (!sawStatus && scriptSentAt == nil)) {
                try writeText(trimmed); try writeText("\r"); sentScript = true; scriptSentAt = Date(); lastEnter = Date(); output.removeAll(); statusTail.removeAll(); updateTail.removeAll(); scanTail.removeAll(); sawStatus = false; Thread.sleep(forTimeInterval: 0.2)
            } else if codex && !sawStatus, Date().timeIntervalSince(lastEnter) >= 1.2, enterRetries < 6 {
                try writeText("\r"); enterRetries += 1; lastEnter = Date(); Thread.sleep(forTimeInterval: 0.12)
            } else if codex && !sawStatus, let sentAt = scriptSentAt, Date().timeIntervalSince(sentAt) >= 3, resendRetries < 2 {
                try writeText("/status\r"); scriptSentAt = Date(); lastEnter = Date(); resendRetries += 1; output.removeAll(); statusTail.removeAll(); updateTail.removeAll(); scanTail.removeAll(); sawStatus = false; Thread.sleep(forTimeInterval: 0.22)
            }
            if !codex, !sawURL, let every = options.sendEnterEvery, Date().timeIntervalSince(lastEnter) >= every { try writeText("\r"); lastEnter = Date() }
            if !codex, let idle = options.idleTimeout, !output.isEmpty, Date().timeIntervalSince(lastOutput) >= idle { stopped = true; idleStopped = true; break }
            Thread.sleep(forTimeInterval: 0.06)
        }
        if stopped {
            let settle = codex ? 2.0 : min(max(0, options.settleAfterStop), max(0, deadline.timeIntervalSinceNow))
            if settle > 0 {
                let settleDeadline = Date().addingTimeInterval(settle)
                while Date() < settleDeadline {
                    try check()
                    switch process.read() {
                    case let .data(data) where !data.isEmpty:
                        lastOutput = Date()
                        guard output.append(data) else { didExceedOutputLimit = true; process.terminate(); throw Error.outputTooLarge }
                        var cursorData = Data(); cursorData.append(scanTail); cursorData.append(data)
                        scanTail = maxScanTail > 0 ? Data(cursorData.suffix(maxScanTail)) : Data()
                        if Date() >= nextCursor, cursorData.range(of: cursorQuery) != nil {
                            try? write(Data([0x1b, 0x5b, 0x31, 0x3b, 0x31, 0x52]), until: min(settleDeadline, Date().addingTimeInterval(0.25)))
                            nextCursor = Date().addingTimeInterval(1)
                        }
                    case .overflow:
                        didExceedOutputLimit = true; process.terminate(); throw Error.outputTooLarge
                    case let .failed(code):
                        process.terminate(); throw Error.launchFailed("ConPTY read failed (\(code))")
                    case .eof: break
                    default: Thread.sleep(forTimeInterval: 0.02)
                    }
                }
            }
        }
        let naturalExit = !stopped && exitedBeforeDeadline
        if !codex, !exitedBeforeDeadline && !stopped {
            // Give a deadline-bound command a short non-blocking tail drain
            // before terminating the job, matching the POSIX runner's 0.2–0.5s
            // post-deadline window.
            let tail = min(0.5, max(0.2, options.settleAfterStop))
            let tailDeadline = Date().addingTimeInterval(tail)
            while Date() < tailDeadline {
                try check()
            switch process.read() {
            case let .data(data) where !data.isEmpty:
                guard output.append(data) else { didExceedOutputLimit = true; process.terminate(); throw Error.outputTooLarge }
                var tailScan = Data(); tailScan.append(scanTail); tailScan.append(data)
                scanTail = maxScanTail > 0 ? Data(tailScan.suffix(maxScanTail)) : Data()
                if Date() >= nextCursor, tailScan.range(of: cursorQuery) != nil { try? write(Data([0x1b,0x5b,0x31,0x3b,0x31,0x52]), until: min(tailDeadline, Date().addingTimeInterval(0.25))); nextCursor = Date().addingTimeInterval(1) }
                if !sawURL, (tailScan.range(of: Data("http://".utf8)) != nil || tailScan.range(of: Data("https://".utf8)) != nil) { sawURL = true; onURLDetected?() }
                case .overflow: didExceedOutputLimit = true; process.terminate(); throw Error.outputTooLarge
                case .eof: sawEOF = true
                case let .failed(code): process.terminate(); throw Error.launchFailed("ConPTY read failed (\(code))")
                default: Thread.sleep(forTimeInterval: 0.02)
                }
            }
            stoppedForDeadline = true
            if !process.isExited { process.terminate() }
        }
        // Preserve the POSIX post-exit drain contract: process reaping and
        // terminal delivery are separate events, so retain trailing output.
        if !codex && naturalExit {
            let drainDeadline = Date().addingTimeInterval(1.0)
            while Date() < drainDeadline {
                try check()
                switch process.read() {
                case let .data(data) where !data.isEmpty:
                    guard output.append(data) else { didExceedOutputLimit = true; process.terminate(); throw Error.outputTooLarge }
                    var drainScan = Data(); drainScan.append(scanTail); drainScan.append(data)
                    scanTail = maxScanTail > 0 ? Data(drainScan.suffix(maxScanTail)) : Data()
                    if Date() >= nextCursor, drainScan.range(of: cursorQuery) != nil { try? write(Data([0x1b,0x5b,0x31,0x3b,0x31,0x52]), until: min(drainDeadline, Date().addingTimeInterval(0.25))); nextCursor = Date().addingTimeInterval(1) }
                    if !sawURL, (drainScan.range(of: Data("http://".utf8)) != nil || drainScan.range(of: Data("https://".utf8)) != nil) { sawURL = true; onURLDetected?() }
                case .overflow: didExceedOutputLimit = true; process.terminate(); throw Error.outputTooLarge
                case .eof: sawEOF = true; break
                case let .failed(code):
                    process.terminate(); throw Error.launchFailed("ConPTY read failed (\(code))")
                default: Thread.sleep(forTimeInterval: 0.02); continue
                }
                if sawEOF { break }
                if process.isExited { Thread.sleep(forTimeInterval: 0.02) }
            }
            if !sawEOF { throw Error.timedOut }
        }
        let text = String(data: output.data, encoding: .utf8) ?? ""; let status = process.exitStatus
        guard !text.isEmpty || (options.returnOnEmptyProcessExit && status != nil) else { throw Error.timedOut }
        let completion: Result.Completion = if stoppedForDeadline { .deadlineExceeded } else if let status { .processExited(status: status) } else if idleStopped { .idleTimeout } else if stopped { .outputCondition } else { .deadlineExceeded }
        return Result(text: text, completion: completion)
    }

    public static func terminateActiveProcessesForAppShutdown() { for process in WindowsTTYProcessRegistry.shutdown() { process.terminate(); process.close() } }

    @discardableResult
    static func registerActiveProcessForAppShutdown(pid: pid_t, binary: String) -> Bool {
        _ = pid; _ = binary; return false
    }

    static func beginActiveProcessLaunchForAppShutdown() -> Bool { WindowsTTYProcessRegistry.beginLaunch() }
    static func endActiveProcessLaunchForAppShutdown() { WindowsTTYProcessRegistry.endLaunch() }
    static func updateActiveProcessGroupForAppShutdown(pid: pid_t, processGroup: pid_t?) {
        _ = pid; _ = processGroup
    }
    static func unregisterActiveProcessForAppShutdown(pid: pid_t) { WindowsTTYProcessRegistry.unregister(pid) }

    public static func which(_ tool: String) -> String? {
        // Return a native image for typed WindowsLaunchTarget routing. The
        // WindowsCommandResolver path remains responsible for npm shim parsing.
        return WindowsExecutableResolver.resolve(
            executable: tool,
            override: nil,
            environment: ProcessInfo.processInfo.environment)
    }

    static func locateBundledHelper(_ name: String) -> String? {
        _ = name
        return nil
    }

    public static func enrichedPath() -> String {
        CodexBarPlatformPaths.environmentValue("PATH", environment: ProcessInfo.processInfo.environment) ?? ""
    }

    static func enrichedEnvironment(
        baseEnv: [String: String] = ProcessInfo.processInfo.environment,
        loginPATH: [String]? = nil,
        home: String = NSHomeDirectory()) -> [String: String]
    {
        var environment = baseEnv
        _ = loginPATH
        // Preserve the caller's environment exactly; unlike the POSIX login
        // shell path enrichment, Windows callers may intentionally provide an
        // isolated or empty PATH for a probe.
        let existingHome = CodexBarPlatformPaths.environmentValue("HOME", environment: environment)
        // Remove empty mixed-case entries before adding the canonical key;
        // WindowsCommandLine rejects duplicate names case-insensitively.
        environment = environment.filter { $0.key.caseInsensitiveCompare("HOME") != .orderedSame }
        environment["HOME"] = (existingHome?.isEmpty == false ? existingHome! : home)
        if CodexBarPlatformPaths.environmentValue("TERM", environment: environment) == nil { environment["TERM"] = "xterm-256color" }
        if CodexBarPlatformPaths.environmentValue("COLORTERM", environment: environment) == nil { environment["COLORTERM"] = "truecolor" }
        if CodexBarPlatformPaths.environmentValue("LANG", environment: environment) == nil { environment["LANG"] = "en_US.UTF-8" }
        if CodexBarPlatformPaths.environmentValue("CI", environment: environment) == nil { environment["CI"] = "0" }
        return environment
    }
}
#endif
