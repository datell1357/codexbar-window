#if os(Windows)
import Foundation

enum WindowsSubprocessRunner {
    private static let log = CodexBarLog.logger(LogCategories.subprocess)

    private final class TimeoutState: @unchecked Sendable {
        private let lock = NSLock()
        private var active = true
        private var didTimeout = false
        private var terminationError: String?
        private let failures: AsyncStream<String>.Continuation

        init(failures: AsyncStream<String>.Continuation) {
            self.failures = failures
        }

        func trigger(_ process: WindowsProcess) {
            self.lock.withLock {
                guard self.active, !self.didTimeout, self.terminationError == nil else { return }
                do {
                    self.didTimeout = try process.terminateIfRunning()
                } catch {
                    let message = error.localizedDescription
                    self.terminationError = message
                    self.failures.yield(message)
                }
            }
        }

        func finish() {
            self.lock.withLock {
                self.active = false
                self.failures.finish()
            }
        }

        var result: (didTimeout: Bool, terminationError: String?) {
            self.lock.withLock { (self.didTimeout, self.terminationError) }
        }
    }

    static func run(
        binary: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        maxOutputBytes: Int?,
        standardInput: Any?,
        currentDirectoryURL: URL?,
        acceptsNonZeroExit: Bool,
        label: String) async throws -> SubprocessResult
    {
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw SubprocessRunnerError.binaryNotFound(binary)
        }

        let start = Date()
        let binaryName = URL(fileURLWithPath: binary).lastPathComponent
        self.log.debug("Subprocess start", metadata: ["label": label, "binary": binaryName, "timeout": "\(timeout)"])
        let normalizedMax = maxOutputBytes.map { max(0, $0) }
        let captureMax = normalizedMax.map { $0 == Int.max ? Int.max : $0 + 1 } ?? ProcessPipeCapture.defaultMaxBytes
        let process = try WindowsProcess.launch(
            executable: binary,
            arguments: arguments,
            environment: environment,
            currentDirectoryURL: currentDirectoryURL,
            standardInput: standardInput)
        let (terminationFailures, failureContinuation) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let timeoutState = TimeoutState(failures: failureContinuation)
        let timer: DispatchSourceTimer? = if timeout.isFinite {
            let timer = DispatchSource.makeTimerSource()
            let nanoseconds = max(0, timeout * 1_000_000_000).rounded(.towardZero)
            timer.schedule(deadline: .now() + .nanoseconds(Int(exactly: nanoseconds) ?? Int.max))
            timer.setEventHandler { timeoutState.trigger(process) }
            timer.resume()
            timer
        } else {
            nil
        }

        defer {
            timeoutState.finish()
            timer?.cancel()
        }
        do {
            let output: WindowsProcess.Output
            let exitCode: Int32
            do {
                let pair = try await withTaskCancellationHandler {
                    try Task.checkCancellation()
                    return try await withThrowingTaskGroup(of: Either.self) { group -> (WindowsProcess.Output, Int32) in
                        group.addTask {
                            for await failure in terminationFailures {
                                throw SubprocessRunnerError.launchFailed(failure)
                            }
                            return .monitorFinished
                        }
                        group.addTask {
                            do {
                                return .exit(try await process.wait())
                            } catch {
                                process.terminate()
                                throw error
                            }
                        }
                        group.addTask {
                            do {
                                return .output(try await process.capture(maxBytes: captureMax))
                            } catch {
                                // Terminate before the task group joins the sibling waiter.
                                process.terminate()
                                throw error
                            }
                        }
                        do {
                            var pendingOutput: WindowsProcess.Output?
                            var pendingExit: Int32?
                            while let value = try await group.next() {
                                switch value {
                                case let .exit(code): pendingExit = code
                                case let .output(captured): pendingOutput = captured
                                case .monitorFinished: break
                                }
                                if let pendingOutput, let pendingExit {
                                    // End the otherwise idle monitor before the task group joins it.
                                    timeoutState.finish()
                                    group.cancelAll()
                                    return (pendingOutput, pendingExit)
                                }
                            }
                        } catch {
                            group.cancelAll()
                            throw error
                        }
                        throw SubprocessRunnerError.launchFailed("Process completed without exit status")
                    }
                } onCancel: {
                    process.terminate()
                }
                try Task.checkCancellation()
                output = pair.0
                exitCode = pair.1
            } catch {
                process.terminate()
                throw error
            }
            timeoutState.finish()
            timer?.cancel()

            let timeoutResult = timeoutState.result
            if let terminationError = timeoutResult.terminationError {
                throw SubprocessRunnerError.launchFailed(terminationError)
            }
            if timeoutResult.didTimeout {
                self.log.warning("Subprocess timed out", metadata: [
                    "label": label, "binary": binaryName,
                    "duration_ms": "\(Int(Date().timeIntervalSince(start) * 1000))",
                ])
                throw SubprocessRunnerError.timedOut(label)
            }
            if let normalizedMax,
               output.stdout.count > normalizedMax || output.stderr.count > normalizedMax
            {
                self.log.warning("Subprocess output exceeded memory limit", metadata: ["label": label, "binary": binaryName])
                throw SubprocessRunnerError.outputTooLarge(label)
            }
            let stdout = ProcessPipeCapture.decodeUTF8(output.stdout)
            let stderr = ProcessPipeCapture.decodeUTF8(output.stderr)
            if exitCode != 0, !acceptsNonZeroExit {
                self.log.warning("Subprocess failed", metadata: [
                    "label": label, "binary": binaryName, "status": "\(exitCode)",
                    "duration_ms": "\(Int(Date().timeIntervalSince(start) * 1000))",
                ])
                throw SubprocessRunnerError.nonZeroExit(code: exitCode, stderr: stderr)
            }
            self.log.debug("Subprocess exit", metadata: [
                "label": label, "binary": binaryName, "status": "\(exitCode)",
                "duration_ms": "\(Int(Date().timeIntervalSince(start) * 1000))",
            ])
            return SubprocessResult(stdout: stdout, stderr: stderr)
        } catch {
            self.log.warning("Subprocess error", metadata: [
                "label": label, "binary": binaryName,
                "duration_ms": "\(Int(Date().timeIntervalSince(start) * 1000))",
            ])
            timer?.cancel()
            process.terminate()
            throw error
        }
    }

    private enum Either: Sendable {
        case exit(Int32)
        case output(WindowsProcess.Output)
        case monitorFinished
    }
}
#endif
