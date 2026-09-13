#if os(Windows)
import Foundation
import WinSDK
import WindowsOperations

final class WindowsCLIPathOperation: @unchecked Sendable {
    enum Action: String, Sendable { case add = "Add", remove = "Remove" }

    private let condition = NSCondition()
    private var stopping = false
    private var active = false
    private var unresolvedChild: Process?

    func requestStop() {
        self.condition.lock()
        self.stopping = true
        self.condition.unlock()
    }

    private var stopRequested: Bool {
        self.condition.lock()
        defer { self.condition.unlock() }
        return self.stopping
    }

    func drain(timeout: TimeInterval) -> Bool {
        self.condition.lock()
        defer { self.condition.unlock() }
        self.stopping = true
        let deadline = Date(timeIntervalSinceNow: max(0, timeout))
        while self.active {
            if !self.condition.wait(until: deadline) { return false }
        }
        return self.unresolvedChild?.isRunning != true
    }

    func run(_ action: Action) -> String {
        self.condition.lock()
        guard !self.stopping, !self.active, self.unresolvedChild?.isRunning != true else {
            self.condition.unlock()
            return "PATH operation cannot start while shutdown or an unresolved helper is pending."
        }
        self.unresolvedChild = nil
        self.active = true
        self.condition.unlock()
        defer {
            self.condition.lock()
            self.active = false
            self.condition.broadcast()
            self.condition.unlock()
        }
        var packageLength: UINT32 = 0
        guard GetCurrentPackageFullName(&packageLength, nil) == APPMODEL_ERROR_NO_PACKAGE else {
            return "PATH setup is available only for an unpackaged app. Package alias integration is still pending."
        }
        guard let script = WindowsOperationsResources.userPathScript else {
            return "PATH setup resource is missing. Restore the complete Windows distribution. No helper was started."
        }
        var module = [UInt16](repeating: 0, count: 32768)
        let moduleCount = GetModuleFileNameW(nil, &module, DWORD(module.count))
        var system = [UInt16](repeating: 0, count: 32768)
        let systemCount = GetSystemDirectoryW(&system, UINT(system.count))
        guard moduleCount > 0, moduleCount < DWORD(module.count),
              systemCount > 0, systemCount < UINT(system.count) else {
            return "The installation or Windows system directory could not be read. No helper was started."
        }
        let modulePath = String(decoding: module.prefix(Int(moduleCount)), as: UTF16.self)
        guard let separator = modulePath.lastIndex(of: "\\") else {
            return "The installation directory is unsupported. No helper was started."
        }
        let directory = String(modulePath[..<separator])
        let shell = String(decoding: system.prefix(Int(systemCount)), as: UTF16.self) +
            "\\WindowsPowerShell\\v1.0\\powershell.exe"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-NoLogo", "-NoProfile", "-NonInteractive", "-File", script.path,
                             "-Action", action.rawValue, "-Directory", directory]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Serialize launch with shutdown so no child starts after stop was accepted.
        self.condition.lock()
        guard !self.stopping else {
            self.condition.unlock()
            return "PATH helper was not started because the app is closing."
        }
        do { try process.run() }
        catch {
            self.condition.unlock()
            return "PATH helper could not start. Check the Windows distribution and organization policy."
        }
        self.condition.unlock()
        let deadline = GetTickCount64() + 30000
        while process.isRunning, !self.stopRequested, GetTickCount64() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            let terminationDeadline = GetTickCount64() + 1500
            while process.isRunning, GetTickCount64() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                self.condition.lock()
                self.unresolvedChild = process
                self.condition.unlock()
                return "PATH helper termination is unconfirmed; further changes are blocked while it runs. " +
                    "Inspect user PATH before retrying."
            }
            return "PATH helper stopped after timeout or shutdown; the change may already have occurred. " +
                "Inspect user PATH before retrying."
        }
        if process.terminationReason == .exit, process.terminationStatus == 0 {
            return "PATH helper completed (the entry may already have matched the request). " +
                "Sign out and sign in again to inherit the environment change. The CLI was not executed."
        }
        return "PATH helper failed or was blocked by policy. Inspect user PATH before retrying. " +
            "No automatic rollback was attempted. See the distribution CLI setup instructions."
    }
}
#endif
