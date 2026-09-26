#if os(Windows)
import CodexBarCore
import Foundation
import WinSDK

/// One optional WinUI child per tray runtime. The child owns the named-pipe listener;
/// both ends authenticate the other process before any application messages are exchanged.
actor WindowsAppHost {
    private final class Child: @unchecked Sendable {
        let process: HANDLE
        let pid: DWORD
        let pipeName: String
        let generation = UUID()
        init(process: HANDLE, pid: DWORD, pipeName: String) {
            self.process = process
            self.pid = pid
            self.pipeName = pipeName
        }
        var alive: Bool { WaitForSingleObject(self.process, 0) == DWORD(WAIT_TIMEOUT) }
        deinit { _ = CloseHandle(self.process) }
    }
    enum Failure: Error { case missingApp, launchFailed, connectionFailed, invalidPeer, ioFailed, timedOut }
    private var child: Child?
    private var pump: Task<Void, Never>?
    private var activation: UInt64 = 0
    private var stopped = false
    private let runtime: WindowsUsageRuntime

    init(runtime: WindowsUsageRuntime) { self.runtime = runtime }

    func open() {
        guard !self.stopped else { return }
        self.activation &+= 1
        if self.child?.alive == true { return }
        guard self.pump == nil else { return }
        do {
            let child = try Self.launch()
            self.child = child
            self.pump = Task.detached { [weak self, runtime] in
                var connectionFailures = 0
                while !Task.isCancelled, child.alive {
                    do {
                        let pipe = try Self.connect(child)
                        defer { _ = CloseHandle(pipe) }
                        var greeted = false
                        var seen = Set<UUID>()
                        connectionFailures = 0
                        while !Task.isCancelled, child.alive {
                            let size = try WindowsAppProtocol.length(Self.read(pipe, count: 4),
                                limit: WindowsAppProtocol.maximumRequestBytes)
                            let request = try WindowsAppProtocol.request(Self.read(pipe, count: size))
                            guard seen.count < 4096, seen.insert(request.requestID).inserted,
                                  greeted || request.method == "hello" else { throw Failure.connectionFailed }
                            var response = await runtime.nativeAppRequest(request, generation: child.generation)
                            if request.method == "hello", response.status == "ok" { greeted = true }
                            response.activation = await self?.currentActivation() ?? 0
                            try Task.checkCancellation()
                            let data = try WindowsAppProtocol.response(response)
                            try Self.write(pipe, data: WindowsAppProtocol.header(length: data.count) + data)
                        }
                    } catch is CancellationError { break }
                    catch {
                        guard !Task.isCancelled, child.alive else { break }
                        connectionFailures += 1
                        // A running window owns reconnection and the user-visible error state.
                        // Never create another runtime or replay a failed mutation.
                        if connectionFailures == 1 {
                            FileHandle.standardError.write(Data("CodexBar: Windows app connection unavailable.\n".utf8))
                        }
                        do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
                    }
                }
                await self?.finished(generation: child.generation)
            }
        } catch {
            let message = "CodexBar could not open the Windows app. Check that the App folder is installed beside the tray executable."
            message.withCString(encodedAs: UTF16.self) { body in
                "CodexBar".withCString(encodedAs: UTF16.self) { title in
                    _ = MessageBoxW(nil, body, title, UINT(MB_OK | MB_ICONERROR))
                }
            }
        }
    }

    func shutdown() async {
        self.stopped = true
        self.pump?.cancel()
        let task = self.pump
        await task?.value
        self.pump = nil
        self.child = nil
    }

    private func currentActivation() -> UInt64 { self.activation }
    private func finished(generation: UUID) {
        guard self.child?.generation == generation else { return }
        self.pump = nil
        self.child = nil
    }

    private static func launch() throws -> Child {
        var units = [UInt16](repeating: 0, count: 32768)
        let count = GetModuleFileNameW(nil, &units, DWORD(units.count))
        guard count > 0, count < units.count else { throw Failure.launchFailed }
        let backend = URL(fileURLWithPath: String(decoding: units.prefix(Int(count)), as: UTF16.self))
        let directory = backend.deletingLastPathComponent().appendingPathComponent("App", isDirectory: true)
        let image = directory.appendingPathComponent("CodexBarApp.exe").path
        for path in [directory.path, image] {
            let attributes = path.withCString(encodedAs: UTF16.self) { GetFileAttributesW($0) }
            guard attributes != DWORD(INVALID_FILE_ATTRIBUTES),
                  attributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) == 0 else { throw Failure.missingApp }
        }
        guard !image.contains("\""), !image.utf16.contains(0) else { throw Failure.launchFailed }
        let pipeName = "CodexBar.UI." + UUID().uuidString.lowercased()
        var command = Array("\"\(image)\" --pipe \(pipeName) --backend-pid \(GetCurrentProcessId())".utf16) + [0]
        // Do not pass provider credentials, proxy secrets or runtime injection variables to the UI.
        let allowed: Set<String> = ["SYSTEMROOT", "WINDIR", "TEMP", "TMP", "LOCALAPPDATA", "APPDATA",
            "USERPROFILE", "PROGRAMDATA", "ALLUSERSPROFILE", "HOMEDRIVE", "HOMEPATH", "OS", "PROCESSOR_ARCHITECTURE"]
        let environment = ProcessInfo.processInfo.environment.filter {
            allowed.contains($0.key.uppercased()) && !$0.value.utf16.contains(0)
        }
        var block: [UInt16] = environment.sorted { $0.key.uppercased() < $1.key.uppercased() }
            .flatMap { Array("\($0.key)=\($0.value)".utf16) + [0] }
        if block.isEmpty { block.append(0) }
        block.append(0)
        var startup = STARTUPINFOW()
        startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
        var process = PROCESS_INFORMATION()
        let created = image.withCString(encodedAs: UTF16.self) { executable in
            directory.path.withCString(encodedAs: UTF16.self) { cwd in
                command.withUnsafeMutableBufferPointer { arguments in
                    block.withUnsafeMutableBytes { environment in
                        CreateProcessW(executable, arguments.baseAddress, nil, nil, false,
                            DWORD(CREATE_UNICODE_ENVIRONMENT), environment.baseAddress, cwd, &startup, &process)
                    }
                }
            }
        }
        guard created, let handle = process.hProcess else { throw Failure.launchFailed }
        if let thread = process.hThread { _ = CloseHandle(thread) }
        return Child(process: handle, pid: process.dwProcessId, pipeName: pipeName)
    }

    private static func connect(_ child: Child) throws -> HANDLE {
        let deadline = GetTickCount64() + 15000
        let name = "\\\\.\\pipe\\" + child.pipeName
        while child.alive {
            try Task.checkCancellation()
            let handle = name.withCString(encodedAs: UTF16.self) {
                CreateFileW($0, DWORD(GENERIC_READ | GENERIC_WRITE), 0, nil, DWORD(OPEN_EXISTING),
                    DWORD(FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION), nil)
            }
            if let handle, handle != INVALID_HANDLE_VALUE {
                var pid: ULONG = 0
                var session: DWORD = 0
                var ownSession: DWORD = 0
                do {
                    guard GetNamedPipeServerProcessId(handle, &pid), pid == child.pid, child.alive,
                          ProcessIdToSessionId(pid, &session),
                          ProcessIdToSessionId(GetCurrentProcessId(), &ownSession), session == ownSession,
                          try WindowsProcessOwnerIdentity.identity(forProcessHandle: child.process)
                            == WindowsProcessOwnerIdentity.current() else { throw Failure.invalidPeer }
                    return handle
                } catch { _ = CloseHandle(handle); throw error }
            }
            guard GetTickCount64() < deadline else { throw Failure.timedOut }
            Sleep(100)
        }
        throw Failure.connectionFailed
    }

    private static func read(_ handle: HANDLE, count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { throw Failure.ioFailed }
            var offset = 0
            while offset < count {
                offset += try self.transfer(handle, buffer: base.advanced(by: offset), count: count - offset, writing: false)
            }
        }
        return data
    }

    private static func write(_ handle: HANDLE, data: Data) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { throw Failure.ioFailed }
            var offset = 0
            while offset < data.count {
                offset += try self.transfer(handle, buffer: UnsafeMutableRawPointer(mutating: base.advanced(by: offset)),
                    count: data.count - offset, writing: true)
            }
        }
    }

    /// Keep the OVERLAPPED, event and buffer alive through cancellation completion.
    private static func transfer(_ handle: HANDLE, buffer: UnsafeMutableRawPointer,
                                 count: Int, writing: Bool) throws -> Int {
        try Task.checkCancellation()
        guard let event = CreateEventW(nil, true, false, nil) else { throw Failure.ioFailed }
        defer { _ = CloseHandle(event) }
        var operation = OVERLAPPED()
        operation.hEvent = event
        let started = writing
            ? WriteFile(handle, buffer, DWORD(count), nil, &operation)
            : ReadFile(handle, buffer, DWORD(count), nil, &operation)
        if !started, GetLastError() != ERROR_IO_PENDING { throw Failure.ioFailed }
        let deadline = GetTickCount64() + 30000
        while true {
            let wait = WaitForSingleObject(event, 100)
            if wait == DWORD(WAIT_OBJECT_0) { break }
            if Task.isCancelled || GetTickCount64() >= deadline || wait != DWORD(WAIT_TIMEOUT) {
                _ = CancelIoEx(handle, &operation)
                var drained: DWORD = 0
                _ = GetOverlappedResult(handle, &operation, &drained, true)
                try Task.checkCancellation()
                throw Failure.timedOut
            }
        }
        var transferred: DWORD = 0
        guard GetOverlappedResult(handle, &operation, &transferred, false),
              transferred > 0, transferred <= count else { throw Failure.ioFailed }
        return Int(transferred)
    }
}
#endif
