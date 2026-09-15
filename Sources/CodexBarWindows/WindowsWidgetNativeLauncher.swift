#if os(Windows)
import Dispatch
import Foundation
import WinSDK

struct WindowsWidgetInstallation: Sendable {
    enum Failure: Error { case unavailable, componentsMissing }
    let host: URL
    let backend: URL

    /// Resolve only beside this packaged executable, inside its current package installation root.
    /// Unpackaged installs keep their existing tray behavior while widget packaging is unavailable.
    static func resolve() throws -> Self? {
        var count: UINT32 = 0
        let identity = GetCurrentPackageFullName(&count, nil)
        if identity == APPMODEL_ERROR_NO_PACKAGE { return nil }
        guard identity == ERROR_INSUFFICIENT_BUFFER, count > 1 else { throw Failure.unavailable }
        count = 0
        guard GetCurrentPackagePath(&count, nil) == ERROR_INSUFFICIENT_BUFFER, count > 1, count <= 32768 else {
            throw Failure.unavailable
        }
        var package = [UInt16](repeating: 0, count: Int(count))
        guard GetCurrentPackagePath(&count, &package) == ERROR_SUCCESS,
              count > 1, count <= package.count, package[Int(count) - 1] == 0 else { throw Failure.unavailable }
        var root = String(decoding: package.prefix(Int(count) - 1), as: UTF16.self)
        if !root.hasSuffix("\\") { root += "\\" }
        var path = [UInt16](repeating: 0, count: 32768)
        let length = GetModuleFileNameW(nil, &path, DWORD(path.count))
        guard length > 0, length < path.count else { throw Failure.unavailable }
        let image = String(decoding: path.prefix(Int(length)), as: UTF16.self)
        guard image.lowercased().hasPrefix(root.lowercased()) else { throw Failure.unavailable }
        let application = URL(fileURLWithPath: image)
        guard application.lastPathComponent.lowercased() == "codexbarwindows.exe" else { throw Failure.unavailable }
        let directory = application.deletingLastPathComponent()
        let host = directory.appendingPathComponent("CodexBarWidgetHost.exe")
        let backend = directory.appendingPathComponent("CodexBarWidgetBackend.dll")
        for file in [host, backend] {
            let attributes = file.path.withCString(encodedAs: UTF16.self) { GetFileAttributesW($0) }
            if attributes == DWORD(INVALID_FILE_ATTRIBUTES) {
                let error = GetLastError()
                if error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND { throw Failure.componentsMissing }
                throw Failure.unavailable
            }
            guard attributes & DWORD(FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) == 0 else {
                throw Failure.unavailable
            }
        }
        return Self(host: host, backend: backend)
    }
}

actor WindowsWidgetNativeLauncher {
    enum Failure: Error, Sendable { case native(Int32), closed, invalidStatus }
    struct Status: Sendable {
        let phase: UInt32
        let exitCode: UInt32
        let forced: Bool
    }
    final class ProcessHandle: @unchecked Sendable {
        let address: UInt
        private let handle: HANDLE
        init(borrowing process: UnsafeMutableRawPointer) throws {
            var handle: HANDLE?
            guard DuplicateHandle(GetCurrentProcess(), process, GetCurrentProcess(), &handle,
                DWORD(PROCESS_DUP_HANDLE | PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE), false, 0),
                let handle else { throw Failure.native(Int32(bitPattern: 0x80070000 | (GetLastError() & 0xffff))) }
            self.handle = handle
            self.address = UInt(bitPattern: handle)
        }
        deinit { _ = CloseHandle(self.handle) }
    }

    private final class State: @unchecked Sendable {
        let library: WindowsWidgetNativeLibrary
        let api: WindowsWidgetNativeLibrary.LaunchExports
        let queue = DispatchQueue(label: "CodexBar.widgets.host-launch", qos: .utility)
        var launch: UnsafeMutableRawPointer?
        var terminal: Status?
        var nativeLease: Unmanaged<State>?
        init(installation: WindowsWidgetInstallation) throws {
            self.library = try WindowsWidgetNativeLibrary(installedDLL: installation.backend)
            self.api = try self.library.launchExports()
        }
        func perform<T: Sendable>(_ operation: @escaping @Sendable (State) throws -> T) async throws -> T {
            try await withCheckedThrowingContinuation { continuation in
                self.queue.async { continuation.resume(with: Result { try operation(self) }) }
            }
        }
        static func check(_ result: Int32) throws { if result < 0 { throw Failure.native(result) } }
        func status() throws -> Status {
            if let terminal = self.terminal { return terminal }
            guard let launch = self.launch else { throw Failure.closed }
            var phase: UInt32 = 0, exitCode: UInt32 = 0, forced: UInt32 = 0
            try Self.check(self.api.status(launch, &phase, &exitCode, &forced))
            guard phase <= 2, forced <= 1 else { throw Failure.invalidStatus }
            return Status(phase: phase, exitCode: exitCode, forced: forced == 1)
        }
        func close() async throws -> Status {
            try await self.perform { state in
                if let terminal = state.terminal { return terminal }
                guard let launch = state.launch else { throw Failure.closed }
                try Self.check(state.api.stop(launch))
                let status = try state.status()
                guard status.phase == 2 else { throw Failure.invalidStatus }
                try Self.check(state.api.destroy(launch))
                state.launch = nil
                state.terminal = status
                let lease = state.nativeLease
                state.nativeLease = nil
                lease?.release()
                return status
            }
        }
    }
    private let state: State
    private var closing: Task<Status, Error>?
    private var stopRequested = false
    private init(state: State) { self.state = state }

    /// Keep the DLL loaded while awaiting OS activation. Native admission completes/cancels its
    /// overlapped connect before returning. Task cancellation is checked between one-second calls.
    static func waitForActivation(installation: WindowsWidgetInstallation) async throws -> WindowsWidgetNativeLauncher {
        let state = try State(installation: installation)
        while true {
            try Task.checkCancellation()
            let admitted = try await state.perform { state in
                guard let accept = state.api.accept else { throw WindowsWidgetNativeLibrary.Failure.missingExport }
                var launch: UnsafeMutableRawPointer?
                let result = accept(1000, &launch)
                if result == 1, launch == nil { return false } // S_FALSE: no client in this interval.
                try State.check(result)
                guard result == 0, let launch else { throw Failure.invalidStatus }
                state.launch = launch
                state.nativeLease = Unmanaged.passRetained(state)
                return true
            }
            if admitted {
                // Return the owner even if cancellation raced admission; runtime must close that exact peer.
                return WindowsWidgetNativeLauncher(state: state)
            }
        }
    }

    static func create(installation: WindowsWidgetInstallation) async throws -> WindowsWidgetNativeLauncher {
        let state = try State(installation: installation)
        try await state.perform { state in
            var launch: UnsafeMutableRawPointer?
            let units = Array(installation.host.path.utf16)
            let result = units.withUnsafeBufferPointer { state.api.create($0.baseAddress, UInt32($0.count), &launch) }
            try State.check(result)
            guard let launch else { throw Failure.native(-2147467259) }
            state.launch = launch
            // Failed cleanup retains DLL code and its native owner until an explicit retry succeeds.
            state.nativeLease = Unmanaged.passRetained(state)
        }
        return WindowsWidgetNativeLauncher(state: state)
    }
    func retainProcess() async throws -> ProcessHandle {
        guard !self.stopRequested else { throw Failure.closed }
        return try await self.state.perform { state in
            guard let launch = state.launch else { throw Failure.closed }
            var borrowed: UnsafeMutableRawPointer?
            try State.check(state.api.process(launch, &borrowed))
            guard let borrowed else { throw Failure.closed }
            return try ProcessHandle(borrowing: borrowed)
        }
    }
    func deliver(_ frame: Data) async throws {
        guard !self.stopRequested else { throw Failure.closed }
        try await self.state.perform { state in
            guard let launch = state.launch else { throw Failure.closed }
            guard frame.count <= 4112 else { throw Failure.invalidStatus }
            try frame.withUnsafeBytes { buffer in
                try State.check(state.api.deliver(launch, buffer.bindMemory(to: UInt8.self).baseAddress, UInt32(buffer.count)))
            }
        }
    }
    func status() async throws -> Status { try await self.state.perform { try $0.status() } }
    func close() async throws -> Status {
        self.stopRequested = true
        if let closing = self.closing { return try await closing.value }
        let state = self.state
        let task = Task { try await state.close() }
        self.closing = task
        do { return try await task.value }
        catch { self.closing = nil; throw error }
    }
    deinit {
        let state = self.state
        let pending = self.closing
        Task {
            if let pending {
                do { _ = try await pending.value; return }
                catch { /* Retry only after the previous attempt has finished. */ }
            }
            _ = try? await state.close()
        }
    }
}
#endif
