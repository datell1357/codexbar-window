#if os(Windows)
import Foundation
import WinSDK
import ucrt

/// Windows process backend; platform integration and SDK compatibility remain under static review.
/// The job is created before launch and owns the complete descendant tree.
package final class WindowsProcess: @unchecked Sendable {
    struct Output: Sendable {
        let stdout: Data
        let stderr: Data
    }

    /// End reason for one output pipe. `drainTimeout` means the root exited but a descendant
    /// kept the writer open past the bounded post-exit drain window.
    enum StreamTermination: Sendable { case eof, forcedStop, drainTimeout }

    struct StreamResult: Sendable {
        let stdout: StreamTermination
        let stderr: StreamTermination
    }

    private let processHandle: HANDLE
    private let jobHandle: HANDLE
    private let stdoutRead: HANDLE
    private let stderrRead: HANDLE
    private let readMode = ReadMode()

    private init(processHandle: HANDLE, jobHandle: HANDLE, stdoutRead: HANDLE, stderrRead: HANDLE) {
        self.processHandle = processHandle
        self.jobHandle = jobHandle
        self.stdoutRead = stdoutRead
        self.stderrRead = stderrRead
    }

    deinit {
        CloseHandle(self.stdoutRead)
        CloseHandle(self.stderrRead)
        CloseHandle(self.processHandle)
        CloseHandle(self.jobHandle)
    }

    static func launch(
        executable: String,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL?,
        standardInput: Any? = nil,
        mergeStandardError: Bool = false) throws -> WindowsProcess
    {
        guard currentDirectoryURL?.path.contains("\0") != true else {
            throw SubprocessRunnerError.launchFailed("Working directory contains NUL")
        }
        var commandLine = try WindowsCommandLine.make(executable: executable, arguments: arguments)
        let environmentBlock = try WindowsCommandLine.environmentBlock(environment)

        var stdoutRead: HANDLE?
        var stdoutWrite: HANDLE?
        var stderrRead: HANDLE?
        var stderrWrite: HANDLE?
        var security = SECURITY_ATTRIBUTES()
        security.nLength = DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size)
        security.bInheritHandle = 1
        guard CreatePipe(&stdoutRead, &stdoutWrite, &security, 0) != 0 else {
            let error = GetLastError()
            throw SubprocessRunnerError.launchFailed("CreatePipe failed (\(error))")
        }
        guard let stdoutRead, let stdoutWrite else {
            if let stdoutRead { CloseHandle(stdoutRead) }
            if let stdoutWrite { CloseHandle(stdoutWrite) }
            throw SubprocessRunnerError.launchFailed("CreatePipe returned null handle")
        }
        guard CreatePipe(&stderrRead, &stderrWrite, &security, 0) != 0 else {
            let error = GetLastError()
            CloseHandle(stdoutRead)
            CloseHandle(stdoutWrite)
            if let stderrRead { CloseHandle(stderrRead) }
            if let stderrWrite { CloseHandle(stderrWrite) }
            throw SubprocessRunnerError.launchFailed("CreatePipe failed (\(error))")
        }
        guard let stderrRead, let stderrWrite else {
            CloseHandle(stdoutRead)
            CloseHandle(stdoutWrite)
            if let stderrRead { CloseHandle(stderrRead) }
            if let stderrWrite { CloseHandle(stderrWrite) }
            throw SubprocessRunnerError.launchFailed("CreatePipe returned null handle")
        }
        guard SetHandleInformation(stdoutRead, DWORD(HANDLE_FLAG_INHERIT), 0) != 0 else {
            let error = GetLastError()
            CloseHandle(stdoutRead); CloseHandle(stdoutWrite)
            CloseHandle(stderrRead); CloseHandle(stderrWrite)
            throw SubprocessRunnerError.launchFailed("SetHandleInformation failed (\(error))")
        }
        guard SetHandleInformation(stderrRead, DWORD(HANDLE_FLAG_INHERIT), 0) != 0 else {
            let error = GetLastError()
            CloseHandle(stdoutRead); CloseHandle(stdoutWrite)
            CloseHandle(stderrRead); CloseHandle(stderrWrite)
            throw SubprocessRunnerError.launchFailed("SetHandleInformation failed (\(error))")
        }

        let inputSource: HANDLE
        var ownedNullInput: HANDLE?
        defer { if let ownedNullInput { CloseHandle(ownedNullInput) } }
        do {
            if let pipe = standardInput as? Pipe {
                inputSource = try Self.nativeHandle(for: pipe.fileHandleForReading)
            } else if let fileHandle = standardInput as? FileHandle {
                inputSource = try Self.nativeHandle(for: fileHandle)
            } else if standardInput == nil {
                let inheritedInput = GetStdHandle(STD_INPUT_HANDLE)
                if inheritedInput == INVALID_HANDLE_VALUE {
                    let error = GetLastError()
                    throw SubprocessRunnerError.launchFailed("GetStdHandle failed (\(error))")
                }
                if let inheritedInput {
                    inputSource = inheritedInput
                } else {
                    // A GUI host can legitimately have no console. Give its child EOF,
                    // while preserving real inherited stdin when the CLI owns a console.
                    let nullName = Array("NUL".utf16) + [0]
                    let nullInput = nullName.withUnsafeBufferPointer {
                        CreateFileW($0.baseAddress, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE),
                                    nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
                    }
                    guard let nullInput, nullInput != INVALID_HANDLE_VALUE else {
                        let error = GetLastError()
                        throw SubprocessRunnerError.launchFailed("Opening null stdin failed (\(error))")
                    }
                    ownedNullInput = nullInput
                    inputSource = nullInput
                }
            } else {
                throw SubprocessRunnerError.launchFailed("Unsupported standard input type")
            }
        } catch {
            CloseHandle(stdoutRead); CloseHandle(stdoutWrite); CloseHandle(stderrRead); CloseHandle(stderrWrite)
            throw error
        }
        var stdinHandle: HANDLE?
        guard DuplicateHandle(
            GetCurrentProcess(), inputSource, GetCurrentProcess(), &stdinHandle, 0, 1, DWORD(DUPLICATE_SAME_ACCESS)) != 0,
            let stdinHandle
        else {
            let error = GetLastError()
            CloseHandle(stdoutRead); CloseHandle(stdoutWrite); CloseHandle(stderrRead); CloseHandle(stderrWrite)
            throw SubprocessRunnerError.launchFailed("DuplicateHandle failed (\(error))")
        }

        guard let job = CreateJobObjectW(nil, nil) else {
            let error = GetLastError()
            CloseHandle(stdinHandle)
            CloseHandle(stdoutRead); CloseHandle(stdoutWrite); CloseHandle(stderrRead); CloseHandle(stderrWrite)
            throw SubprocessRunnerError.launchFailed("CreateJobObjectW failed (\(error))")
        }
        var limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
        limits.BasicLimitInformation.LimitFlags = DWORD(JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE)
        guard SetInformationJobObject(
            job,
            JOBOBJECTINFOCLASS(JobObjectExtendedLimitInformation),
            &limits,
            DWORD(MemoryLayout<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>.size)) != 0
        else {
            let error = GetLastError()
            CloseHandle(stdinHandle); CloseHandle(job); CloseHandle(stdoutRead); CloseHandle(stdoutWrite); CloseHandle(stderrRead); CloseHandle(stderrWrite)
            throw SubprocessRunnerError.launchFailed("SetInformationJobObject failed (\(error))")
        }

        var startup = STARTUPINFOEXW()
        startup.StartupInfo.cb = DWORD(MemoryLayout<STARTUPINFOEXW>.size)
        startup.StartupInfo.dwFlags = DWORD(STARTF_USESTDHANDLES)
        startup.StartupInfo.hStdOutput = stdoutWrite
        startup.StartupInfo.hStdError = mergeStandardError ? stdoutWrite : stderrWrite
        startup.StartupInfo.hStdInput = stdinHandle

        var attributeSize: SIZE_T = 0
        let sizingResult = InitializeProcThreadAttributeList(nil, 1, 0, &attributeSize)
        let sizingError = GetLastError()
        guard sizingResult == 0, sizingError == ERROR_INSUFFICIENT_BUFFER, attributeSize > 0 else {
            CloseHandle(stdinHandle); CloseHandle(job); CloseHandle(stdoutRead); CloseHandle(stdoutWrite)
            CloseHandle(stderrRead); CloseHandle(stderrWrite)
            throw SubprocessRunnerError.launchFailed("Attribute list sizing failed (\(sizingError))")
        }
        let attributes = UnsafeMutableRawPointer.allocate(byteCount: Int(attributeSize), alignment: MemoryLayout<UInt>.alignment)
        defer { attributes.deallocate() }
        startup.lpAttributeList = attributes.assumingMemoryBound(to: PROC_THREAD_ATTRIBUTE_LIST.self)
        guard InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0, &attributeSize) != 0 else {
            let error = GetLastError()
            CloseHandle(stdinHandle); CloseHandle(job); CloseHandle(stdoutRead); CloseHandle(stdoutWrite); CloseHandle(stderrRead); CloseHandle(stderrWrite)
            throw SubprocessRunnerError.launchFailed("InitializeProcThreadAttributeList failed (\(error))")
        }
        // Merged output shares one child handle, preserving write order instead of concatenating captures.
        // The unused stderr pipe remains parent-owned and reaches EOF when its writer closes below.
        var inherited = mergeStandardError ? [stdinHandle, stdoutWrite] : [stdinHandle, stdoutWrite, stderrWrite]
        var attributeError: DWORD = ERROR_SUCCESS
        var processInfo = PROCESS_INFORMATION()
        let created = inherited.withUnsafeMutableBufferPointer { buffer -> BOOL in
            guard UpdateProcThreadAttribute(
                startup.lpAttributeList,
                0,
                SIZE_T(PROC_THREAD_ATTRIBUTE_HANDLE_LIST),
                buffer.baseAddress,
                SIZE_T(MemoryLayout<HANDLE>.size * buffer.count),
                nil,
                nil) != 0 else {
                attributeError = GetLastError()
                return 0
            }
            let directory = currentDirectoryURL?.path
            let directoryUTF16 = directory.map { Array($0.utf16) + [0] }
            let executableUTF16 = Array(executable.utf16) + [0]
            return commandLine.withUnsafeMutableBufferPointer { command in
                executableUTF16.withUnsafeBufferPointer { executableBuffer in
                    environmentBlock.withUnsafeBufferPointer { env in
                        directoryUTF16?.withUnsafeBufferPointer { cwd in
                            CreateProcessW(
                                executableBuffer.baseAddress,
                                command.baseAddress,
                                nil,
                                nil,
                                1,
                                DWORD(CREATE_SUSPENDED | EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT),
                                UnsafeMutableRawPointer(mutating: env.baseAddress),
                                cwd.baseAddress,
                                &startup.StartupInfo,
                                &processInfo)
                        } ?? CreateProcessW(
                            executableBuffer.baseAddress, command.baseAddress, nil, nil, 1,
                            DWORD(CREATE_SUSPENDED | EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT),
                            UnsafeMutableRawPointer(mutating: env.baseAddress), nil,
                            &startup.StartupInfo, &processInfo)
                    }
                }
            }
        }
        guard attributeError == ERROR_SUCCESS else {
            DeleteProcThreadAttributeList(startup.lpAttributeList)
            CloseHandle(stdinHandle)
            CloseHandle(job); CloseHandle(stdoutRead); CloseHandle(stdoutWrite); CloseHandle(stderrRead); CloseHandle(stderrWrite)
            throw SubprocessRunnerError.launchFailed("UpdateProcThreadAttribute failed (\(attributeError))")
        }
        let createError = created == 0 ? GetLastError() : ERROR_SUCCESS
        DeleteProcThreadAttributeList(startup.lpAttributeList)
        CloseHandle(stdinHandle)
        CloseHandle(stdoutWrite); CloseHandle(stderrWrite)
        guard created != 0 else {
            CloseHandle(job); CloseHandle(stdoutRead); CloseHandle(stderrRead)
            throw SubprocessRunnerError.launchFailed("CreateProcessW failed (\(createError))")
        }
        guard AssignProcessToJobObject(job, processInfo.hProcess) != 0 else {
            let error = GetLastError()
            TerminateProcess(processInfo.hProcess, 1); CloseHandle(processInfo.hProcess); CloseHandle(processInfo.hThread)
            CloseHandle(job); CloseHandle(stdoutRead); CloseHandle(stderrRead)
            throw SubprocessRunnerError.launchFailed("AssignProcessToJobObject failed (\(error))")
        }
        guard ResumeThread(processInfo.hThread) != DWORD.max else {
            let error = GetLastError()
            TerminateProcess(processInfo.hProcess, 1); CloseHandle(processInfo.hThread); CloseHandle(processInfo.hProcess)
            CloseHandle(job); CloseHandle(stdoutRead); CloseHandle(stderrRead)
            throw SubprocessRunnerError.launchFailed("ResumeThread failed (\(error))")
        }
        CloseHandle(processInfo.hThread)
        return WindowsProcess(processHandle: processInfo.hProcess, jobHandle: job, stdoutRead: stdoutRead, stderrRead: stderrRead)
    }

    private static func nativeHandle(for fileHandle: FileHandle) throws -> HANDLE {
        let descriptor = fileHandle.fileDescriptor
        guard descriptor >= 0 else {
            throw SubprocessRunnerError.launchFailed("Invalid standard input file descriptor")
        }
        let rawHandle = _get_osfhandle(descriptor)
        guard rawHandle != -1 else {
            throw SubprocessRunnerError.launchFailed("_get_osfhandle failed")
        }
        guard let handle = HANDLE(bitPattern: UInt(truncatingIfNeeded: rawHandle)) else {
            throw SubprocessRunnerError.launchFailed("Invalid native standard input handle")
        }
        return handle
    }

    /// Retain the owner while waiting; cancellation stops this waiter without closing a live handle.
    /// Process termination is coordinated separately by the runner.
    func wait() async throws -> Int32 {
        let stop = CaptureStop()
        return try await withTaskCancellationHandler {
            try await Task.detached { [self] () throws -> Int32 in
                while !stop.isStopped {
                    let result = WaitForSingleObject(self.processHandle, 50)
                    if result == WAIT_TIMEOUT { continue }
                    guard result == WAIT_OBJECT_0 else {
                        let error = GetLastError()
                        throw SubprocessRunnerError.launchFailed("WaitForSingleObject failed (\(error))")
                    }
                    var code: DWORD = 0
                    guard GetExitCodeProcess(self.processHandle, &code) != 0 else {
                        let error = GetLastError()
                        throw SubprocessRunnerError.launchFailed("GetExitCodeProcess failed (\(error))")
                    }
                    return Int32(bitPattern: code)
                }
                throw CancellationError()
            }.value
        } onCancel: {
            stop.stop()
        }
    }

    private final class CaptureStop: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false

        func stop() { self.lock.withLock { self.stopped = true } }
        var isStopped: Bool { self.lock.withLock { self.stopped } }
    }

    func captureVersionSynchronously(
        timeout: TimeInterval,
        drainTimeout: TimeInterval = 0.25,
        fullOutput: Bool = false) -> String?
    {
        do {
            try self.readMode.acquire(.capture)
        } catch {
            return nil
        }
        defer { self.readMode.release() }

        let maxBytes = 1024 * 1024
        var stdout = Data()
        var rootExited = false
        var exitCode: DWORD = 0
        var stdoutEOF = false
        var stderrEOF = false
        var exitTick: ULONGLONG?
        let startedTick = GetTickCount64()
        let timeoutLimit = timeout.isFinite ? max(0, timeout) : .infinity
        let drainLimit = drainTimeout.isFinite ? max(0, drainTimeout) : .infinity

        do {
            var madeProgress = false
            let readAvailable: (HANDLE, Bool) throws -> Bool = { handle, retain in
                var buffer = [UInt8](repeating: 0, count: 16 * 1024)
                var available: DWORD = 0
                guard PeekNamedPipe(handle, nil, 0, nil, &available, nil) != 0 else {
                    let error = GetLastError()
                    if error == ERROR_BROKEN_PIPE { return true }
                    throw SubprocessRunnerError.launchFailed("PeekNamedPipe failed (\(error))")
                }
                if available == 0 { return false }

                var count: DWORD = 0
                let ok = buffer.withUnsafeMutableBytes { bytes in
                    ReadFile(handle, bytes.baseAddress, min(available, DWORD(bytes.count)), &count, nil)
                }
                guard ok != 0 else {
                    let error = GetLastError()
                    if error == ERROR_BROKEN_PIPE { return true }
                    throw SubprocessRunnerError.launchFailed("ReadFile failed (\(error))")
                }
                if count == 0 { return true }
                madeProgress = true
                if retain, fullOutput, Int(count) > maxBytes - stdout.count {
                    self.terminate()
                    throw SubprocessRunnerError.launchFailed("Version output exceeded memory limit")
                }
                if retain, stdout.count < maxBytes {
                    let retained = min(Int(count), maxBytes - stdout.count)
                    if retained > 0 { stdout.append(contentsOf: buffer.prefix(retained)) }
                }
                return false
            }

            while true {
                let state = WaitForSingleObject(self.processHandle, 0)
                guard state != WAIT_FAILED else {
                    let error = GetLastError()
                    throw SubprocessRunnerError.launchFailed("Process wait failed (\(error))")
                }
                if state == WAIT_OBJECT_0, !rootExited {
                    rootExited = true
                    exitTick = GetTickCount64()
                    guard GetExitCodeProcess(self.processHandle, &exitCode) != 0 else {
                        let error = GetLastError()
                        throw SubprocessRunnerError.launchFailed("GetExitCodeProcess failed (\(error))")
                    }
                }

                if !rootExited, timeoutLimit.isFinite,
                   Double(GetTickCount64() &- startedTick) >= timeoutLimit * 1000
                {
                    guard TerminateJobObject(self.jobHandle, 1) != 0 else {
                        let error = GetLastError()
                        throw SubprocessRunnerError.launchFailed("TerminateJobObject failed (\(error))")
                    }
                    return nil
                }

                madeProgress = false
                if !stderrEOF { stderrEOF = try readAvailable(self.stderrRead, false) }
                if !stdoutEOF { stdoutEOF = try readAvailable(self.stdoutRead, true) }
                if rootExited, stdoutEOF && stderrEOF { break }
                if rootExited, let exitTick,
                   drainLimit.isFinite,
                   Double(GetTickCount64() &- exitTick) >= drainLimit * 1000
                { break }
                if !madeProgress { Sleep(10) }
            }
        } catch {
            return nil
        }

        if fullOutput {
            guard rootExited, exitCode == 0, stdoutEOF && stderrEOF else { return nil }
            guard let text = String(data: stdout, encoding: .utf8), !text.isEmpty else { return nil }
            return text
        }
        guard rootExited, exitCode == 0,
              let firstLine = ProcessPipeCapture.decodeUTF8(stdout)
                  .split(whereSeparator: \.isNewline).first
        else { return nil }
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private final class ReadMode: @unchecked Sendable {
        enum Kind: Sendable { case capture, stream }

        private let lock = NSLock()
        private var owner: Kind?

        func acquire(_ kind: Kind) throws {
            try self.lock.withLock {
                guard self.owner == nil else {
                    throw SubprocessRunnerError.launchFailed("Process output readers are already in use")
                }
                self.owner = kind
            }
        }

        func release() {
            self.lock.withLock { self.owner = nil }
        }
    }

    /// A reader failure must stop its sibling before structured concurrency waits for it.
    /// The caller owns process termination; this scope only stops its two pipe readers.
    func capture(maxBytes: Int) async throws -> Output {
        try self.readMode.acquire(.capture)
        defer { self.readMode.release() }
        let stop = CaptureStop()
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: (Bool, Data).self) { group in
                group.addTask { (true, try await self.read(self.stdoutRead, maxBytes: maxBytes, stop: stop)) }
                group.addTask { (false, try await self.read(self.stderrRead, maxBytes: maxBytes, stop: stop)) }
                var stdout = Data()
                var stderr = Data()
                do {
                    for try await (isStdout, data) in group {
                        if isStdout { stdout = data } else { stderr = data }
                    }
                    try Task.checkCancellation()
                    return Output(stdout: stdout, stderr: stderr)
                } catch {
                    stop.stop()
                    group.cancelAll()
                    throw error
                }
            }
        } onCancel: {
            stop.stop()
        }
    }

    /// Streams raw stdout/stderr chunks without retaining them. Callers should feed each
    /// callback into `BoundedLineBuffer` (or another bounded consumer) for NDJSON framing.
    /// Callbacks must do bounded synchronous work and must not wait for another stream.
    /// Only one capture or stream operation may own the pipe readers at a time.
    func stream(
        onStdout: @escaping @Sendable (Data) throws -> Void,
        onStderr: @escaping @Sendable (Data) throws -> Void,
        onStdoutEnd: @escaping @Sendable (StreamTermination) -> Void = { _ in },
        onStderrEnd: @escaping @Sendable (StreamTermination) -> Void = { _ in }) async throws -> StreamResult
    {
        try self.readMode.acquire(.stream)
        defer { self.readMode.release() }
        let stop = CaptureStop()
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: (Bool, StreamTermination).self) { group in
                group.addTask { (true, try await self.readStream(self.stdoutRead, stop: stop, onData: onStdout)) }
                group.addTask { (false, try await self.readStream(self.stderrRead, stop: stop, onData: onStderr)) }
                var stdout: StreamTermination = .eof
                var stderr: StreamTermination = .eof
                do {
                    for try await (isStdout, termination) in group {
                        if isStdout {
                            stdout = termination
                            onStdoutEnd(termination)
                        } else {
                            stderr = termination
                            onStderrEnd(termination)
                        }
                    }
                    try Task.checkCancellation()
                    return StreamResult(stdout: stdout, stderr: stderr)
                } catch {
                    stop.stop()
                    group.cancelAll()
                    throw error
                }
            }
        } onCancel: {
            stop.stop()
        }
    }

    func terminate() {
        _ = TerminateJobObject(self.jobHandle, 1)
    }

    /// Used by timeout handling to distinguish a completed root from a termination request.
    /// The runner serializes this decision with timeout-state observation.
    @discardableResult
    func terminateIfRunning() throws -> Bool {
        let state = WaitForSingleObject(self.processHandle, 0)
        if state == WAIT_OBJECT_0 { return false }
        guard state == WAIT_TIMEOUT else {
            let error = GetLastError()
            throw SubprocessRunnerError.launchFailed("Process state query failed (\(error))")
        }
        guard TerminateJobObject(self.jobHandle, 1) != 0 else {
            let error = GetLastError()
            throw SubprocessRunnerError.launchFailed("TerminateJobObject failed (\(error))")
        }
        return true
    }

    /// Peek before synchronous reads so descendants holding a writer cannot keep capture alive forever
    /// after the root exits. The caller supplies the exact prefix budget (including an optional overflow byte).
    private func read(_ handle: HANDLE, maxBytes: Int, stop: CaptureStop) async throws -> Data {
        try await Task.detached { [self] () throws -> Data in
            var data = Data()
            let limit = max(0, maxBytes)
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            var exitedAt: ULONGLONG?
            while !stop.isStopped {
                let processState = WaitForSingleObject(self.processHandle, 0)
                if processState == WAIT_FAILED {
                    let error = GetLastError()
                    throw SubprocessRunnerError.launchFailed("Pipe process wait failed (\(error))")
                }
                if processState == WAIT_OBJECT_0, exitedAt == nil { exitedAt = GetTickCount64() }
                if let exitedAt, GetTickCount64() &- exitedAt >= 1000 { break }

                var available: DWORD = 0
                guard PeekNamedPipe(handle, nil, 0, nil, &available, nil) != 0 else {
                    let error = GetLastError()
                    if error == ERROR_BROKEN_PIPE { break }
                    throw SubprocessRunnerError.launchFailed("PeekNamedPipe failed (\(error))")
                }
                if available == 0 {
                    Sleep(10)
                    continue
                }
                var count: DWORD = 0
                let ok = buffer.withUnsafeMutableBytes { bytes in
                    ReadFile(handle, bytes.baseAddress, min(available, DWORD(bytes.count)), &count, nil)
                }
                if ok == 0 {
                    let error = GetLastError()
                    if error == ERROR_BROKEN_PIPE { break }
                    throw SubprocessRunnerError.launchFailed("ReadFile failed (\(error))")
                }
                if count == 0 { break }
                let retained = min(Int(count), max(0, limit - data.count))
                if retained > 0 { data.append(contentsOf: buffer.prefix(retained)) }
            }
            return data
        }.value
    }

    private func readStream(
        _ handle: HANDLE,
        stop: CaptureStop,
        onData: @escaping @Sendable (Data) throws -> Void) async throws -> StreamTermination
    {
        try await Task.detached { [self] () throws -> StreamTermination in
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            var exitedAt: ULONGLONG?
            var didDrainTimeout = false
            while !stop.isStopped {
                let processState = WaitForSingleObject(self.processHandle, 0)
                if processState == WAIT_FAILED {
                    let error = GetLastError()
                    throw SubprocessRunnerError.launchFailed("Pipe process wait failed (\(error))")
                }
                if processState == WAIT_OBJECT_0, exitedAt == nil { exitedAt = GetTickCount64() }
                if let exitedAt, GetTickCount64() &- exitedAt >= 1000 {
                    didDrainTimeout = true
                    break
                }

                var available: DWORD = 0
                guard PeekNamedPipe(handle, nil, 0, nil, &available, nil) != 0 else {
                    let error = GetLastError()
                    if error == ERROR_BROKEN_PIPE { break }
                    throw SubprocessRunnerError.launchFailed("PeekNamedPipe failed (\(error))")
                }
                if available == 0 {
                    Sleep(10)
                    continue
                }
                var count: DWORD = 0
                let ok = buffer.withUnsafeMutableBytes { bytes in
                    ReadFile(handle, bytes.baseAddress, min(available, DWORD(bytes.count)), &count, nil)
                }
                if ok == 0 {
                    let error = GetLastError()
                    if error == ERROR_BROKEN_PIPE { break }
                    throw SubprocessRunnerError.launchFailed("ReadFile failed (\(error))")
                }
                if count == 0 { break }
                try onData(Data(buffer.prefix(Int(count))))
            }
            if stop.isStopped { return .forcedStop }
            return didDrainTimeout ? .drainTimeout : .eof
        }.value
    }
}
#endif
