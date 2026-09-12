#if os(Windows)
import Foundation
import WinSDK

private final class SessionWindowCandidates {
    let pids: Set<UInt32>
    var windows: [(UInt32, HWND)] = []
    var visited = 0
    var limitReached = false

    init(pids: Set<UInt32>) { self.pids = pids }
}

private func collectSessionWindow(_ window: HWND?, _ context: LPARAM) -> BOOL {
    guard let window, let pointer = UnsafeRawPointer(bitPattern: Int(context)) else { return 0 }
    let candidates = Unmanaged<SessionWindowCandidates>.fromOpaque(pointer).takeUnretainedValue()
    candidates.visited += 1
    guard candidates.visited <= 4096, candidates.windows.count < 128 else {
        candidates.limitReached = true
        return 0
    }
    guard IsWindowVisible(window) != 0, GetWindow(window, UINT(GW_OWNER)) == nil else { return 1 }
    var pid: DWORD = 0
    _ = GetWindowThreadProcessId(window, &pid)
    if candidates.pids.contains(pid) { candidates.windows.append((pid, window)) }
    return 1
}

public enum SessionWindowFocuser {
    /// Uses only per-call state and can run on a worker thread; no main-dispatch-loop dependency.
    /// Native window activation only. No simulated keys, process injection, or permission bypass.
    /// An ancestor window is reported as application-only activation, not exact terminal-tab focus.
    @discardableResult
    public static func focus(_ session: AgentSession, promptForAccessibility: Bool = false) -> SessionFocusResult {
        _ = promptForAccessibility
        guard !Task.isCancelled else { return .failed }
        guard let pid = session.pid, pid > 0,
              let expectedTicks = self.creationTicks(from: session.id, pid: UInt32(pid)),
              let owner = try? ProcessOwnerIdentity.current(),
              let root = self.openProcess(UInt32(pid))
        else { return .failed }
        defer { CloseHandle(root) }
        guard self.ticks(root) == expectedTicks,
              (try? WindowsProcessOwnerIdentity.identity(forProcessHandle: root)) == owner,
              WaitForSingleObject(root, 0) == WAIT_TIMEOUT
        else { return .failed }

        let parents = self.parentMap()
        var handles: [(pid: UInt32, handle: HANDLE)] = [(UInt32(pid), root)]
        defer {
            for entry in handles.dropFirst() { CloseHandle(entry.handle) }
        }
        var visited: Set<UInt32> = [UInt32(pid)]
        var current = UInt32(pid)
        var childCreation = expectedTicks
        for _ in 0..<32 {
            guard let parent = parents[current], parent > 0, visited.insert(parent).inserted,
                  let handle = self.openProcess(parent)
            else { break }
            guard let born = self.ticks(handle), born <= childCreation,
                  (try? WindowsProcessOwnerIdentity.identity(forProcessHandle: handle)) == owner,
                  WaitForSingleObject(handle, 0) == WAIT_TIMEOUT
            else {
                CloseHandle(handle)
                break
            }
            handles.append((parent, handle))
            current = parent
            childCreation = born
        }
        let candidates = SessionWindowCandidates(pids: Set(handles.map(\.pid)))
        let context = LPARAM(Int(bitPattern: Unmanaged.passUnretained(candidates).toOpaque()))
        _ = EnumWindows(collectSessionWindow, context)
        guard !candidates.limitReached, WaitForSingleObject(root, 0) == WAIT_TIMEOUT else { return .failed }
        for process in handles {
            let matching = candidates.windows.filter { $0.0 == process.pid }
            guard !matching.isEmpty else { continue }
            // Multiple windows/tabs need a provider-specific identity match in a future slice.
            guard matching.count == 1, let candidate = matching.first,
                  WaitForSingleObject(process.handle, 0) == WAIT_TIMEOUT,
                  IsWindow(candidate.1) != 0
            else { return .failed }
            var currentOwner: DWORD = 0
            _ = GetWindowThreadProcessId(candidate.1, &currentOwner)
            guard currentOwner == process.pid, WaitForSingleObject(root, 0) == WAIT_TIMEOUT else { return .failed }
            guard !Task.isCancelled else { return .failed }
            if IsIconic(candidate.1) != 0 { _ = ShowWindowAsync(candidate.1, SW_RESTORE) }
            guard !Task.isCancelled, SetForegroundWindow(candidate.1) != 0 else { return .failed }
            return process.pid == UInt32(pid) ? .focused : .activatedApplicationOnly
        }
        return .failed
    }

    private static func creationTicks(from id: String, pid: UInt32) -> UInt64? {
        let fields = id.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 3, fields[0] == "pid", UInt32(fields[1]) == pid,
              let ticks = UInt64(fields[2]), ticks > 0
        else { return nil }
        return ticks
    }

    private static func openProcess(_ pid: UInt32) -> HANDLE? {
        let handle = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE), 0, pid)
        guard let handle, handle != INVALID_HANDLE_VALUE else { return nil }
        return handle
    }

    private static func ticks(_ handle: HANDLE) -> UInt64? {
        var created = FILETIME()
        var exited = FILETIME()
        var kernel = FILETIME()
        var user = FILETIME()
        guard GetProcessTimes(handle, &created, &exited, &kernel, &user) != 0 else { return nil }
        return (UInt64(created.dwHighDateTime) << 32) | UInt64(created.dwLowDateTime)
    }

    private static func parentMap() -> [UInt32: UInt32] {
        guard let snapshot = CreateToolhelp32Snapshot(DWORD(TH32CS_SNAPPROCESS), 0),
              snapshot != INVALID_HANDLE_VALUE
        else { return [:] }
        defer { CloseHandle(snapshot) }
        var entry = PROCESSENTRY32W()
        entry.dwSize = DWORD(MemoryLayout<PROCESSENTRY32W>.size)
        var result: [UInt32: UInt32] = [:]
        var available = Process32FirstW(snapshot, &entry)
        while available != 0, result.count < 32768 {
            result[entry.th32ProcessID] = entry.th32ParentProcessID
            available = Process32NextW(snapshot, &entry)
        }
        return result
    }
}
#endif
