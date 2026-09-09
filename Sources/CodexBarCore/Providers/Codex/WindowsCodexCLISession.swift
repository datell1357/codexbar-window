#if os(Windows)
import Foundation

/// Persistent Codex status session backed by an owned ConPTY lease.
/// The actor owns this object and therefore never attaches to a recycled PID.
actor WindowsCodexCLISession {
    private var process: WindowsTrackedConPTYProcess?
    private var binaryPath: String?
    private var startedAt: Date?
    private var rows: UInt16 = 0
    private var cols: UInt16 = 0
    private var environment: [String: String]?
    private var arguments: [String] = []
    private var workingDirectory: URL?
    private var invalidationGeneration: UInt64

    init(generation: UInt64 = 0) { self.invalidationGeneration = generation }

    func captureStatus(binary: String, options: CodexCLISession.CaptureOptions, generation: UInt64) async throws -> String {
        defer { if Task<Never, Never>.isCancelled { cleanup() } }
        try Task.checkCancellation()
        guard generation == invalidationGeneration else { throw CancellationError() }
        try ensureStarted(binary: binary, options: options)
        if let startedAt {
            let delay = 0.4 - Date().timeIntervalSince(startedAt)
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        }
        try Task.checkCancellation()
        guard generation == invalidationGeneration else { throw CancellationError() }
        try drain()
        let deadline = Date().addingTimeInterval(max(0, options.timeout))
        var output = BoundedOutputBuffer()
        var scan = Data()
        var scanTail = Data()
        var sent = false
        var status = false
        var updatePrompt = false
        var skippedUpdate = false
        var enterRetries = 0
        var resendRetries = 0
        var lastEnter = Date.distantPast
        var sentAt: Date?
        var nextCursor = Date.distantPast

        while Date() < deadline {
            try Task.checkCancellation()
            guard generation == invalidationGeneration else { throw CancellationError() }
            let data = try read()
            if !data.isEmpty {
                guard output.append(data) else { cleanup(); throw CodexCLISession.SessionError.outputTooLarge }
                scan.removeAll(keepingCapacity: true)
                scan.append(scanTail)
                scan.append(data)
                scanTail = Data(scan.suffix(511))
                let lower = CodexCLISession.lowercasedASCII(scan)
                let marker = { (value: String) in lower.range(of: Data(value.utf8)) != nil }
                if marker("credits:") || marker("5h limit") || marker("5-hour limit") || marker("weekly limit") { status = true }
                if !skippedUpdate && (marker("update available!") || marker("run bun install -g @openai/codex") || marker("0.60.1 ->")) { updatePrompt = true }
                if Date() >= nextCursor, scan.range(of: Data([0x1b, 0x5b, 0x36, 0x6e])) != nil {
                    try? write(Data("\u{1b}[1;1R".utf8), deadline: min(deadline, Date().addingTimeInterval(0.25)))
                    nextCursor = Date().addingTimeInterval(1)
                }
            }
            if updatePrompt {
                try? write(Data("\u{1b}[B".utf8), deadline: min(deadline, Date().addingTimeInterval(0.5)))
                try await Task.sleep(nanoseconds: 120_000_000)
                guard generation == invalidationGeneration else { throw CancellationError() }
                try? write(Data("\r".utf8), deadline: min(deadline, Date().addingTimeInterval(0.5)))
                try await Task.sleep(nanoseconds: 150_000_000)
                guard generation == invalidationGeneration else { throw CancellationError() }
                try? write(Data("\r/status\r".utf8), deadline: min(deadline, Date().addingTimeInterval(0.5)))
                updatePrompt = false; skippedUpdate = true; sent = false; status = false; sentAt = nil; scan.removeAll(); scanTail.removeAll(); output.removeAll()
                try await Task.sleep(nanoseconds: 300_000_000)
                guard generation == invalidationGeneration else { throw CancellationError() }
            }
            if !sent {
                try write(Data("/status\r".utf8), deadline: deadline)
                sent = true; sentAt = Date(); lastEnter = Date()
                try await Task.sleep(nanoseconds: 200_000_000)
                guard generation == invalidationGeneration else { throw CancellationError() }
                continue
            }
            if status { break }
            if Date().timeIntervalSince(lastEnter) >= 1.2, enterRetries < 6 {
                try? write(Data("\r".utf8), deadline: min(deadline, Date().addingTimeInterval(0.25)))
                enterRetries += 1; lastEnter = Date()
            } else if let currentSentAt = sentAt, Date().timeIntervalSince(currentSentAt) >= 3, resendRetries < 2 {
                try? write(Data("/status\r".utf8), deadline: min(deadline, Date().addingTimeInterval(0.5)))
                resendRetries += 1; self.resetScan(&scan); self.resetScan(&scanTail); output.removeAll(); status = false; sentAt = Date(); lastEnter = Date()
                try await Task.sleep(nanoseconds: 220_000_000)
                guard generation == invalidationGeneration else { throw CancellationError() }
                continue
            }
            if process?.isExited == true { throw CodexCLISession.SessionError.processExited }
            try await Task.sleep(nanoseconds: 120_000_000)
        }
        if status {
            let settle = Date().addingTimeInterval(2)
            while Date() < settle {
                try Task.checkCancellation()
                guard generation == invalidationGeneration else { throw CancellationError() }
                let data = try read()
                if !data.isEmpty {
                    guard output.append(data) else { cleanup(); throw CodexCLISession.SessionError.outputTooLarge }
                    scan.removeAll(keepingCapacity: true)
                    scan.append(scanTail)
                    scan.append(data)
                    scanTail = Data(scan.suffix(511))
                } else {
                    scan.removeAll(keepingCapacity: true)
                }
                if Date() >= nextCursor, scan.range(of: Data([0x1b, 0x5b, 0x36, 0x6e])) != nil {
                    try? write(Data("\u{1b}[1;1R".utf8), deadline: min(settle, Date().addingTimeInterval(0.25)))
                    nextCursor = Date().addingTimeInterval(1)
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        try Task.checkCancellation()
        guard generation == invalidationGeneration else { throw CancellationError() }
        guard !output.data.isEmpty, let text = String(data: output.data, encoding: .utf8) else { throw CodexCLISession.SessionError.timedOut }
        return text
    }

    func reset() { invalidationGeneration &+= 1; cleanup() }

    private func ensureStarted(binary: String, options: CodexCLISession.CaptureOptions) throws {
        if let process, !process.isExited, binaryPath == binary, rows == options.rows, cols == options.cols,
           environment == options.environment, arguments == options.extraArgs, workingDirectory == options.workingDirectory { return }
        cleanup()
        let env = TTYCommandRunner.enrichedEnvironment(baseEnv: options.environment, home: options.environment["HOME"] ?? NSHomeDirectory())
        guard let resolved = WindowsCommandResolver.resolve(executable: binary, override: nil, environment: env) else { throw CodexCLISession.SessionError.launchFailed("Missing CLI '\(binary)'") }
        do {
            process = try WindowsTrackedConPTYProcess.launch(target: resolved.target, arguments: options.extraArgs, environment: env, currentDirectoryURL: options.workingDirectory, rows: options.rows, cols: options.cols)
        } catch is CancellationError { throw CodexCLISession.SessionError.launchFailed("App shutdown in progress") }
        catch { throw CodexCLISession.SessionError.launchFailed(error.localizedDescription) }
        binaryPath = binary; startedAt = Date(); rows = options.rows; cols = options.cols; environment = options.environment; arguments = options.extraArgs; workingDirectory = options.workingDirectory
    }

    private func read() throws -> Data {
        switch process?.read() {
        case let .data(data): return data
        case .overflow: cleanup(); throw CodexCLISession.SessionError.outputTooLarge
        case let .failed(code): cleanup(); throw CodexCLISession.SessionError.launchFailed("ConPTY read failed (\(code))")
        case .eof, .none: return Data()
        }
    }
    private func drain() throws { _ = try read() }
    private func write(_ data: Data, deadline: Date) throws {
        guard let process else { throw CodexCLISession.SessionError.processExited }
        do { try process.write(data, deadline: deadline, cancellationCheck: { Task<Never, Never>.isCancelled }) }
        catch is CancellationError { cleanup(); throw CancellationError() }
        catch is WindowsConPTYProcess.WriteError { cleanup(); throw CodexCLISession.SessionError.timedOut }
        catch { cleanup(); throw CodexCLISession.SessionError.processExited }
    }
    private func cleanup() {
        guard let process else { return }
        try? process.write(Data("/exit\n".utf8), deadline: Date().addingTimeInterval(0.15), cancellationCheck: { false })
        process.terminate(); process.close(); self.process = nil
        binaryPath = nil; startedAt = nil; rows = 0; cols = 0; environment = nil; arguments.removeAll(); workingDirectory = nil
    }
    private func resetScan(_ scan: inout Data) { scan.removeAll(keepingCapacity: true) }
}
#endif
