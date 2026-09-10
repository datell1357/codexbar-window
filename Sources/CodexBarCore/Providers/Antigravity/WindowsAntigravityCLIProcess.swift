#if os(Windows)
import Foundation
import WinSDK

struct AntigravityPTYProcessLauncher: AntigravityCLIProcessLaunching {
    func launch(binary: String) throws -> any AntigravityCLIProcessHandle {
        try launch(binary: binary, arguments: [])
    }

    func launch(binary: String, arguments: [String]) throws -> any AntigravityCLIProcessHandle {
        let env = TTYCommandRunner.enrichedEnvironment(baseEnv: ProcessInfo.processInfo.environment, home: NSHomeDirectory())
        var launchEnvironment = env
        launchEnvironment["PWD"] = NSHomeDirectory()
        guard let target = WindowsCommandResolver.resolve(executable: binary, override: nil, environment: env) else { throw AntigravityCLISession.SessionError.launchFailed("Missing CLI '\(binary)'") }
        let process = try WindowsTrackedConPTYProcess.launch(target: target.target, arguments: arguments, environment: launchEnvironment, currentDirectoryURL: URL(fileURLWithPath: NSHomeDirectory()))
        guard process.processID <= DWORD(Int32.max) else {
            process.terminate(); process.close()
            throw AntigravityCLISession.SessionError.launchFailed("Windows process identifier is out of range")
        }
        return WindowsAntigravityCLIProcess(process: process, executablePath: target.sourcePath)
    }
}

final class WindowsAntigravityCLIProcess: AntigravityCLIProcessHandle, @unchecked Sendable {
    private let process: WindowsTrackedConPTYProcess
    private let stateLock = NSLock()
    private var lastFailure: String?
    let executablePath: String
    init(process: WindowsTrackedConPTYProcess, executablePath: String) { self.process = process; self.executablePath = executablePath }
    var pid: pid_t { Int32(process.processID) }
    var isRunning: Bool { !process.isExited }
    var processGroup: pid_t? { nil }
    var outputFailureDescription: String? { stateLock.lock(); defer { stateLock.unlock() }; return lastFailure }
    func assignProcessGroup() -> pid_t? { nil }
    func sendExit() throws { try process.write(Data("/exit\r".utf8), deadline: Date().addingTimeInterval(0.2), cancellationCheck: { false }) }
    func closePTY() { process.close() }
    func terminateRoot() { process.terminate() }
    func killRoot() { process.terminate() }
    func descendantPIDs() -> [pid_t] { [] }
    func terminateTree(signal: Int32, knownDescendants: [pid_t]) { process.terminate() }
    func killDescendants(_ descendants: [pid_t]) {}
    func drainOutput() -> Data {
        switch process.read() {
        case let .data(data): return data
        case .eof: return Data()
        case .overflow:
            stateLock.lock(); lastFailure = "ConPTY output overflow"; stateLock.unlock(); return Data()
        case let .failed(code):
            stateLock.lock(); lastFailure = "ConPTY read failed (\(code))"; stateLock.unlock(); return Data()
        }
    }
}

struct AntigravityProcessIdentityProvider: AntigravityCLIProcessIdentityProviding {
    static var currentUserID: UInt32 { 0 }
    func ownerUserID(for pid: pid_t) -> UInt32? { nil }
    func lookup(pid: pid_t) -> AntigravityCLIProcessLookupResult {
        guard pid > 0, UInt64(pid) <= UInt64(UInt32.max) else { return .notRunning }
        guard let handle = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), 0, DWORD(pid)) else {
            let error = GetLastError()
            if error == ERROR_INVALID_PARAMETER { return .notRunning }
            if error == ERROR_ACCESS_DENIED { return .inaccessible(error) }
            return .indeterminate(error)
        }
        defer { CloseHandle(handle) }
        var exitCode: DWORD = STILL_ACTIVE
        guard GetExitCodeProcess(handle, &exitCode) != 0 else { return .indeterminate(GetLastError()) }
        guard exitCode == STILL_ACTIVE else { return .notRunning }
        var size: DWORD = 32768
        var path = [WCHAR](repeating: 0, count: Int(size))
        guard QueryFullProcessImageNameW(handle, 0, &path, &size) != 0 else { return .indeterminate(GetLastError()) }
        let executablePath = String(decoding: path.prefix(Int(size)), as: UTF16.self)
        var creation = FILETIME(), exit = FILETIME(), kernel = FILETIME(), user = FILETIME()
        guard GetProcessTimes(handle, &creation, &exit, &kernel, &user) != 0 else { return .indeterminate(GetLastError()) }
        let ticks = (UInt64(creation.dwHighDateTime) << 32) | UInt64(creation.dwLowDateTime)
        return .running(AntigravityCLIProcessIdentity(executablePath: executablePath, startEpoch: (Double(ticks) / 10_000_000) - 11_644_473_600))
    }

    func identity(for pid: pid_t) -> AntigravityCLIProcessIdentity? {
        guard case .running(let identity) = lookup(pid: pid) else { return nil }
        return identity
    }
}

final class AntigravityFileCLISessionRecordStore: AntigravityCLISessionRecordStoring, @unchecked Sendable {
    private let url: URL
    private let fileManager: FileManager
    init(fileURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codexbar/antigravity/agy-session.json"), fileManager: FileManager = .default) { self.url = fileURL; self.fileManager = fileManager }
    func load() throws -> [AntigravityCLISessionRecord] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        if let records = try? decoder.decode([AntigravityCLISessionRecord].self, from: data) { return records }
        return try [decoder.decode(AntigravityCLISessionRecord.self, from: data)]
    }
    func save(_ record: AntigravityCLISessionRecord) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var records: [AntigravityCLISessionRecord]
        do {
            records = try load()
        } catch is DecodingError {
            // Keep the malformed bytes available for diagnosis before recovering.
            let corruptData = try Data(contentsOf: url)
            let backupURL = url.deletingPathExtension()
                .appendingPathExtension("corrupt-\(UUID().uuidString).json")
            // `atomic` and `withoutOverwriting` are mutually exclusive: exclusive
            // creation is required here so an existing backup is never replaced.
            try corruptData.write(to: backupURL, options: .withoutOverwriting)
            records = []
        }
        records.removeAll { Self.sameOwner($0, record) }
        records.append(record)
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
    }
    func remove(_ record: AntigravityCLISessionRecord) throws { var records = try load(); records.removeAll { $0.pid == record.pid && $0.executablePath == record.executablePath && abs($0.startEpoch - record.startEpoch) < 0.001 }; try JSONEncoder().encode(records).write(to: url, options: .atomic) }
    private static func sameOwner(_ lhs: AntigravityCLISessionRecord, _ rhs: AntigravityCLISessionRecord) -> Bool {
        if let lp = lhs.ownerPID, let rp = rhs.ownerPID, let le = lhs.ownerExecutablePath, let re = rhs.ownerExecutablePath, let ls = lhs.ownerStartEpoch, let rs = rhs.ownerStartEpoch {
            return lp == rp && le == re && abs(ls - rs) < 0.001
        }
        return lhs.pid == rhs.pid && lhs.executablePath == rhs.executablePath && abs(lhs.startEpoch - rhs.startEpoch) < 0.001
    }
}

final class AntigravityFileCLISessionLaunchLock: AntigravityCLISessionLaunchLocking, @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager
    init(
        fileURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".codexbar", isDirectory: true)
            .appendingPathComponent("antigravity", isDirectory: true)
            .appendingPathComponent("agy-session.lock"),
        fileManager: FileManager = .default)
    {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func withLock<T>(_ operation: () throws -> T) throws -> T {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let path = Array(fileURL.path.utf16) + [0]
        let handle: HANDLE? = path.withUnsafeBufferPointer { buffer in
            CreateFileW(buffer.baseAddress, DWORD(GENERIC_READ | GENERIC_WRITE), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE), nil, DWORD(OPEN_ALWAYS), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else {
            throw AntigravityCLISession.SessionError.launchFailed("CreateFileW lock failed (\(GetLastError()))")
        }
        defer { CloseHandle(handle) }
        var overlapped = OVERLAPPED()
        guard LockFileEx(handle, DWORD(LOCKFILE_EXCLUSIVE_LOCK), 0, DWORD.max, DWORD.max, &overlapped) != 0 else {
            throw AntigravityCLISession.SessionError.launchFailed("LockFileEx failed (\(GetLastError()))")
        }
        defer { _ = UnlockFileEx(handle, 0, DWORD.max, DWORD.max, &overlapped) }
        return try operation()
    }
}
#endif
