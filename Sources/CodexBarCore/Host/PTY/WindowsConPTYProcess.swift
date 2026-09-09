#if os(Windows)
import Foundation
import WinSDK

/// Small ConPTY process owner used by the Windows TTY runner.
///
/// The process is created suspended and assigned to a kill-on-close Job before
/// it is resumed.  A dedicated reader keeps the pseudoconsole drained while a
/// serial writer prevents a blocked WriteFile from stalling the caller.
final class WindowsConPTYProcess: @unchecked Sendable {
    enum ReadResult: Sendable { case data(Data), eof, overflow, failed(DWORD) }
    enum WriteError: Swift.Error, Sendable { case deadlineExceeded }

    private let process: HANDLE
    let processID: DWORD
    private let suspendedThread: HANDLE
    private let job: HANDLE
    private var console: HPCON?
    private let inputWrite: HANDLE
    private let outputRead: HANDLE
    private let maxOutputBytes: Int
    private let lock = NSLock()
    private var output = Data()
    private var overflowed = false
    private var eof = false
    private var readFailure: DWORD?
    private var closed = false
    private var cleanupScheduled = false
    private var reader: Thread?
    private var readerHandle: HANDLE?
    private var readerReady = false
    private var writerReady = false
    private var workerFailure: DWORD?
    private var writer: Thread?
    private let writeCondition = NSCondition()
    private var writeQueue: [(Data, WriteWaiter)] = []
    private var writerStopped = false
    private var writerHandle: HANDLE?

    private final class WriteWaiter: @unchecked Sendable {
        let condition = NSCondition(); var result: Swift.Error?; var finished = false
    }

    private init(process: HANDLE, processID: DWORD, thread: HANDLE, job: HANDLE, console: HPCON, inputWrite: HANDLE,
                  outputRead: HANDLE, maxOutputBytes: Int) {
        self.process = process
        self.processID = processID
        self.suspendedThread = thread
        self.job = job
        self.console = console
        self.inputWrite = inputWrite
        self.outputRead = outputRead
        self.maxOutputBytes = max(0, maxOutputBytes)
    }

    // Callers own the process lifetime and must invoke close(). Worker threads
    // retain the owner while blocked, so deinit cannot safely spawn cleanup.

    static func launch(target: WindowsLaunchTarget, arguments: [String], environment: [String: String],
                       currentDirectoryURL: URL?, rows: UInt16 = 50, cols: UInt16 = 160,
                       maxOutputBytes: Int = BoundedOutputBuffer.defaultMaxBytes) throws -> WindowsConPTYProcess {
        var command = try WindowsCommandLine.make(executable: target.executable,
                                                  arguments: target.argumentPrefix + arguments)
        let envBlock = try WindowsCommandLine.environmentBlock(target.environment(from: environment))
        var inputRead: HANDLE?
        var inputWrite: HANDLE?
        var outputRead: HANDLE?
        var outputWrite: HANDLE?
        guard rows > 0, cols > 0, rows <= 32_767, cols <= 32_767,
              currentDirectoryURL?.path.utf16.contains(0) != true else { throw SubprocessRunnerError.launchFailed("Invalid ConPTY launch parameters") }
        var security = SECURITY_ATTRIBUTES()
        security.nLength = DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size)
        security.bInheritHandle = 1
        guard CreatePipe(&inputRead, &inputWrite, &security, 0) != 0,
              CreatePipe(&outputRead, &outputWrite, &security, 0) != 0,
              let inputRead, let inputWrite, let outputRead, let outputWrite else {
            if let inputRead { CloseHandle(inputRead) }; if let inputWrite { CloseHandle(inputWrite) }
            if let outputRead { CloseHandle(outputRead) }; if let outputWrite { CloseHandle(outputWrite) }
            throw SubprocessRunnerError.launchFailed("CreatePipe failed")
        }
        guard SetHandleInformation(inputWrite, DWORD(HANDLE_FLAG_INHERIT), 0) != 0,
              SetHandleInformation(outputRead, DWORD(HANDLE_FLAG_INHERIT), 0) != 0 else {
            let error = GetLastError(); CloseHandle(inputRead); CloseHandle(inputWrite)
            CloseHandle(outputRead); CloseHandle(outputWrite)
            throw SubprocessRunnerError.launchFailed("SetHandleInformation failed (\(error))")
        }

        var pseudo: HPCON?
        let size = COORD(X: SHORT(cols), Y: SHORT(rows))
        let pseudoResult = CreatePseudoConsole(size, inputRead, outputWrite, 0, &pseudo)
        guard pseudoResult == S_OK, let pseudo else {
            CloseHandle(inputRead); CloseHandle(inputWrite)
            CloseHandle(outputRead); CloseHandle(outputWrite)
            throw SubprocessRunnerError.launchFailed("CreatePseudoConsole failed (HRESULT \(pseudoResult))")
        }
        CloseHandle(inputRead); CloseHandle(outputWrite)
        var job = CreateJobObjectW(nil, nil)
        guard let job else {
            let error = GetLastError(); ClosePseudoConsole(pseudo); CloseHandle(inputWrite); CloseHandle(outputRead)
            throw SubprocessRunnerError.launchFailed("CreateJobObjectW failed (\(error))") }
        var limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
        limits.BasicLimitInformation.LimitFlags = DWORD(JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE)
        guard SetInformationJobObject(job, JOBOBJECTINFOCLASS(JobObjectExtendedLimitInformation), &limits,
                                      DWORD(MemoryLayout<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>.size)) != 0 else {
            let error = GetLastError(); CloseHandle(job); ClosePseudoConsole(pseudo); CloseHandle(inputWrite); CloseHandle(outputRead)
            throw SubprocessRunnerError.launchFailed("SetInformationJobObject failed (\(error))")
        }
        var startup = STARTUPINFOEXW()
        startup.StartupInfo.cb = DWORD(MemoryLayout<STARTUPINFOEXW>.size)
        var attributeSize: SIZE_T = 0
        let sizingResult = InitializeProcThreadAttributeList(nil, 1, 0, &attributeSize)
        let sizingError = GetLastError()
        guard sizingResult == 0, sizingError == ERROR_INSUFFICIENT_BUFFER, attributeSize > 0 else { CloseHandle(job); ClosePseudoConsole(pseudo); CloseHandle(inputWrite); CloseHandle(outputRead)
            throw SubprocessRunnerError.launchFailed("Attribute list sizing failed (\(sizingError))") }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(attributeSize), alignment: MemoryLayout<UInt>.alignment)
        defer { storage.deallocate() }
        startup.lpAttributeList = storage.assumingMemoryBound(to: PROC_THREAD_ATTRIBUTE_LIST.self)
        guard InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0, &attributeSize) != 0 else {
            let error = GetLastError(); CloseHandle(job); ClosePseudoConsole(pseudo); CloseHandle(inputWrite); CloseHandle(outputRead)
            throw SubprocessRunnerError.launchFailed("InitializeProcThreadAttributeList failed (\(error))")
        }
        defer { DeleteProcThreadAttributeList(startup.lpAttributeList) }
        var processInfo = PROCESS_INFORMATION()
        var attributeError: DWORD = ERROR_SUCCESS
        // PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE receives the HPCON value itself,
        // cast to PVOID (not the address of the Swift variable).
        let created = UpdateProcThreadAttribute(startup.lpAttributeList, 0, SIZE_T(PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE),
                                                 UnsafeMutableRawPointer(mutating: pseudo), SIZE_T(MemoryLayout<HPCON>.size), nil, nil)
        guard created != 0 else { attributeError = GetLastError(); CloseHandle(job); ClosePseudoConsole(pseudo); CloseHandle(inputWrite); CloseHandle(outputRead)
            throw SubprocessRunnerError.launchFailed("UpdateProcThreadAttribute failed (\(attributeError))") }
        let cwd = currentDirectoryURL.map { Array($0.path.utf16) + [0] }
        let exe = Array(target.executable.utf16) + [0]
        let didCreate = command.withUnsafeMutableBufferPointer { cmd in
            exe.withUnsafeBufferPointer { exePtr in envBlock.withUnsafeBufferPointer { env in
                let environment = UnsafeMutableRawPointer(mutating: env.baseAddress)
                cwd?.withUnsafeBufferPointer { dir in CreateProcessW(exePtr.baseAddress, cmd.baseAddress, nil, nil, 0, DWORD(CREATE_SUSPENDED | EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT), environment, dir.baseAddress, &startup.StartupInfo, &processInfo) }
                    ?? CreateProcessW(exePtr.baseAddress, cmd.baseAddress, nil, nil, 0, DWORD(CREATE_SUSPENDED | EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT), environment, nil, &startup.StartupInfo, &processInfo)
            }}
        }
        guard didCreate != 0 else { let error = GetLastError(); CloseHandle(job); ClosePseudoConsole(pseudo); CloseHandle(inputWrite); CloseHandle(outputRead)
            throw SubprocessRunnerError.launchFailed("CreateProcessW failed (\(error))") }
        guard AssignProcessToJobObject(job, processInfo.hProcess) != 0 else { let error = GetLastError(); TerminateProcess(processInfo.hProcess, 1); CloseHandle(processInfo.hThread); CloseHandle(processInfo.hProcess); CloseHandle(job); ClosePseudoConsole(pseudo); CloseHandle(inputWrite); CloseHandle(outputRead); throw SubprocessRunnerError.launchFailed("AssignProcessToJobObject failed (\(error))") }
        let result = WindowsConPTYProcess(process: processInfo.hProcess, processID: processInfo.dwProcessId, thread: processInfo.hThread, job: job, console: pseudo, inputWrite: inputWrite, outputRead: outputRead, maxOutputBytes: maxOutputBytes)
        result.reader = Thread { [weak result] in
            guard let result else { return }
            var handle: HANDLE?
            guard DuplicateHandle(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(), &handle, 0, 0, DWORD(DUPLICATE_SAME_ACCESS)) != 0,
                  let handle else {
                let error = GetLastError()
                result.lock.lock(); result.workerFailure = error; result.readerReady = true; result.lock.unlock()
                return
            }
            result.lock.lock(); result.readerHandle = handle; result.readerReady = true; result.lock.unlock()
            result.readLoop()
        }
        result.reader?.start()
        result.writer = Thread { [weak result] in result?.writeLoop() }
        result.writer?.start()
        result.lock.lock()
        while !result.readerReady || !result.writerReady {
            result.lock.unlock(); Thread.sleep(forTimeInterval: 0.001); result.lock.lock()
        }
        let workerFailure = result.workerFailure
        result.lock.unlock()
        if let workerFailure {
            result.close()
            throw SubprocessRunnerError.launchFailed("ConPTY worker initialization failed (\(workerFailure))")
        }
        return result
    }

    func resume() throws {
        self.lock.lock(); defer { self.lock.unlock() }
        guard !self.closed else { throw CancellationError() }
        guard ResumeThread(self.suspendedThread) != DWORD.max else { throw SubprocessRunnerError.launchFailed("ResumeThread failed (\(GetLastError()))") }
    }

    func read() -> ReadResult {
        self.lock.lock(); defer { self.lock.unlock() }
        if !self.output.isEmpty { let value = self.output; self.output.removeAll(keepingCapacity: true); return .data(value) }
        if let error = self.readFailure { return .failed(error) }
        if self.overflowed { return .overflow }; if self.eof { return .eof }; return .data(Data())
    }

    func write(_ data: Data, deadline: Date?, cancellationCheck: @Sendable () -> Bool) throws {
        guard !data.isEmpty else { return }
        let waiter = WriteWaiter()
        self.lock.lock(); let closed = self.closed; self.lock.unlock()
        guard !closed else { throw CancellationError() }
        self.writeCondition.lock(); guard !self.writerStopped else { self.writeCondition.unlock(); throw CancellationError() }
        self.writeQueue.append((data, waiter)); self.writeCondition.signal(); self.writeCondition.unlock()
        waiter.condition.lock()
        while !waiter.finished {
            if cancellationCheck() || (deadline.map { Date() >= $0 } ?? false) {
                let expired = deadline.map { Date() >= $0 } ?? false
                waiter.condition.unlock(); self.close(); throw expired ? WriteError.deadlineExceeded : CancellationError()
            }
            if let deadline { waiter.condition.wait(until: min(deadline, Date().addingTimeInterval(0.05))) }
            else { waiter.condition.wait(until: Date().addingTimeInterval(0.05)) }
        }
        let error = waiter.result; waiter.condition.unlock()
        if let error { throw error }
    }

    var isExited: Bool {
        self.lock.lock(); defer { self.lock.unlock() }
        return self.closed || WaitForSingleObject(self.process, 0) == WAIT_OBJECT_0
    }
    var exitStatus: Int32? {
        self.lock.lock(); defer { self.lock.unlock() }
        guard !self.closed, WaitForSingleObject(self.process, 0) == WAIT_OBJECT_0 else { return nil }
        var code: DWORD = 0; guard GetExitCodeProcess(self.process, &code) != 0 else { return nil }; return Int32(bitPattern: code)
    }
    func terminate() {
        self.lock.lock(); defer { self.lock.unlock() }
        guard !self.closed else { return }
        _ = TerminateJobObject(self.job, 1)
    }

    /// Request shutdown and let a retained owner perform ordered cleanup.
    /// Synchronous ReadFile/WriteFile calls may still be in flight after the
    /// caller's deadline; closing their pipe or thread handles at that point
    /// would race with the worker and cause use-after-close.
    func close() {
        self.lock.lock()
        guard !self.closed else { self.lock.unlock(); return }
        self.closed = true
        guard !self.cleanupScheduled else { self.lock.unlock(); return }
        self.cleanupScheduled = true
        let readerHandle = self.readerHandle
        self.readerHandle = nil
        self.lock.unlock()

        _ = TerminateJobObject(self.job, 1)
        self.writeCondition.lock()
        self.writerStopped = true
        let pending = self.writeQueue
        self.writeQueue.removeAll()
        let writerHandle = self.writerHandle
        self.writeCondition.broadcast()
        self.writeCondition.unlock()
        for (_, waiter) in pending {
            waiter.condition.lock()
            waiter.result = CancellationError()
            waiter.finished = true
            waiter.condition.broadcast()
            waiter.condition.unlock()
        }
        if let writerHandle { _ = CancelSynchronousIo(writerHandle) }
        // Keep the reader alive until ClosePseudoConsole has been issued;
        // that transition is what releases a blocked ConPTY ReadFile.

        // Keep self alive until both workers exit. ClosePseudoConsole first so
        // the reader blocked in ReadFile can observe EOF/broken-pipe.
        Thread.detachNewThread { [self] in
            self.finishClose(readerHandle: readerHandle, writerHandle: writerHandle)
        }
    }

    private func finishClose(readerHandle: HANDLE?, writerHandle: HANDLE?) {
        self.lock.lock()
        let console = self.console
        self.console = nil
        self.lock.unlock()
        if let console { ClosePseudoConsole(console) }
        if let writerHandle {
            _ = WaitForSingleObject(writerHandle, INFINITE)
            CloseHandle(writerHandle)
        }
        if let readerHandle {
            _ = WaitForSingleObject(readerHandle, INFINITE)
            CloseHandle(readerHandle)
        }
        self.lock.lock()
        CloseHandle(self.inputWrite)
        CloseHandle(self.outputRead)
        CloseHandle(self.suspendedThread)
        CloseHandle(self.process)
        CloseHandle(self.job)
        self.lock.unlock()
    }

    private func readLoop() {
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            var count: DWORD = 0
            let ok = buffer.withUnsafeMutableBytes { ReadFile(self.outputRead, $0.baseAddress, DWORD($0.count), &count, nil) }
            let readError = ok == 0 ? GetLastError() : ERROR_SUCCESS
            self.lock.lock()
            if ok == 0 { if readError == ERROR_BROKEN_PIPE || readError == ERROR_OPERATION_ABORTED { self.eof = true } else { self.readFailure = readError }; self.lock.unlock(); return }
            if count == 0 { self.eof = true; self.lock.unlock(); return }
            if count > 0 { let chunk = Data(buffer[0 ..< Int(count)]); if self.output.count + chunk.count > self.maxOutputBytes { self.overflowed = true } else { self.output.append(chunk) } }
            self.lock.unlock()
        }
    }

    private func writeLoop() {
        var duplicate: HANDLE?
        guard DuplicateHandle(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(), &duplicate, 0, 0, DWORD(DUPLICATE_SAME_ACCESS)) != 0,
              let duplicate else {
            let error = GetLastError()
            self.lock.lock(); self.workerFailure = error; self.writerReady = true; self.lock.unlock()
            return
        }
        self.writeCondition.lock(); self.writerHandle = duplicate; self.writeCondition.broadcast(); self.writeCondition.unlock()
        self.lock.lock(); self.writerReady = true; self.lock.unlock()
        while true {
            self.writeCondition.lock(); while self.writeQueue.isEmpty && !self.writerStopped { self.writeCondition.wait() }
            guard !self.writeQueue.isEmpty else { self.writeCondition.unlock(); return }
            let (data, waiter) = self.writeQueue.removeFirst(); self.writeCondition.unlock()
            var failure: Swift.Error?
            data.withUnsafeBytes { raw in
                var offset = 0
                while offset < data.count {
                    var written: DWORD = 0
                    let ok = WriteFile(self.inputWrite, raw.baseAddress!.advanced(by: offset), DWORD(min(data.count - offset, Int(DWORD.max))), &written, nil)
                    guard ok != 0, written > 0 else { failure = SubprocessRunnerError.launchFailed("ConPTY input write failed (\(GetLastError()))"); break }
                    offset += Int(written)
                }
            }
            waiter.condition.lock(); waiter.result = failure; waiter.finished = true; waiter.condition.broadcast(); waiter.condition.unlock()
        }
    }
}
#endif
