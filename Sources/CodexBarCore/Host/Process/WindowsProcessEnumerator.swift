#if os(Windows)
import Foundation
import WinSDK

/// A point-in-time description of an Antigravity-related process.  All fields
/// are collected from the same PID enumeration pass and are ordered by PID.
package struct WindowsProcessSnapshot: Sendable {
    package let pid: UInt32
    package let imagePath: String
    package let commandLine: String
    package let owner: ProcessOwnerIdentity
    package let creationTime: Date
}

/// Native process discovery for Windows.  The implementation deliberately
/// avoids shelling out (and therefore does not depend on PowerShell or a
/// remote PEB read); candidates that disappear or deny access are skipped.
package enum WindowsProcessEnumerator {
    private static let maximumCommandLineBytes = 128 * 1024
    private static let maximumRetries = 3

    package static func snapshots(deadline: Date? = nil) async throws -> [WindowsProcessSnapshot] {
        try Self.check(deadline)
        guard let snapshot = CreateToolhelp32Snapshot(DWORD(TH32CS_SNAPPROCESS), 0),
              snapshot != INVALID_HANDLE_VALUE
        else { throw ProcessEnumeratorError.enumerationFailed(GetLastError()) }
        defer { CloseHandle(snapshot) }
        try Self.check(deadline)

        var entry = PROCESSENTRY32W()
        entry.dwSize = DWORD(MemoryLayout<PROCESSENTRY32W>.size)
        var pids: [(UInt32, String)] = []
        var result = Process32FirstW(snapshot, &entry)
        let firstError = result == 0 ? GetLastError() : ERROR_SUCCESS
        try Self.check(deadline)
        if result == 0 {
            guard firstError == ERROR_NO_MORE_FILES else { throw ProcessEnumeratorError.enumerationFailed(firstError) }
        }
        while result != 0 {
            try Self.check(deadline)
            if let name = Self.utf16String(entry.szExeFile), Self.isCandidatePath(name) {
                pids.append((entry.th32ProcessID, name))
            }
            result = Process32NextW(snapshot, &entry)
            let nextError = result == 0 ? GetLastError() : ERROR_SUCCESS
            try Self.check(deadline)
            if result == 0 {
                guard nextError == ERROR_NO_MORE_FILES else { throw ProcessEnumeratorError.enumerationFailed(nextError) }
            }
        }

        let query = try Self.ntQueryInformationProcess()
        try Self.check(deadline)
        var snapshots: [WindowsProcessSnapshot] = []
        for (pid, _) in pids.sorted(by: { $0.0 < $1.0 }) {
            try Self.check(deadline)
            let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), 0, pid)
            guard let process, process != INVALID_HANDLE_VALUE else {
                try Self.check(deadline)
                continue
            }
            defer { CloseHandle(process) }
            try Self.check(deadline)

            let image = Self.imagePath(process)
            try Self.check(deadline)
            guard let image, Self.isCandidatePath(image) else { continue }
            let owner = try? WindowsProcessOwnerIdentity.identity(forProcessHandle: process)
            try Self.check(deadline)
            guard let owner else { continue }
            let creationTime = Self.creationTime(process)
            try Self.check(deadline)
            guard let creationTime else { continue }
            let command: String
            do {
                command = try await Self.commandLine(process, query: query, deadline: deadline)
            } catch is CancellationError { throw CancellationError() }
            catch ProcessEnumeratorError.timedOut { throw ProcessEnumeratorError.timedOut }
            catch { continue }
            try Self.check(deadline)
            snapshots.append(WindowsProcessSnapshot(pid: pid, imagePath: image, commandLine: command, owner: owner, creationTime: creationTime))
        }
        try Self.check(deadline)
        return snapshots
    }

    package enum ProcessEnumeratorError: Error, Sendable {
        case enumerationFailed(UInt32)
        case timedOut
    }

    private static func check(_ deadline: Date?) throws {
        if Task.isCancelled { throw CancellationError() }
        if let deadline, Date() >= deadline { throw ProcessEnumeratorError.timedOut }
    }

    private static func isCandidatePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        if lower.contains("antigravity") { return true }
        var base = URL(fileURLWithPath: lower).lastPathComponent
        if base.hasSuffix(".exe") { base.removeLast(4) }
        return base.hasPrefix("language_server") || base.hasPrefix("language-server") ||
            ["agy", "antigravity-cli", "antigravity_cli", "node", "bun"].contains(base)
    }

    private static func utf16String<T>(_ buffer: T) -> String? {
        withUnsafeBytes(of: buffer) { raw in
            let units = raw.bindMemory(to: UInt16.self)
            let end = units.firstIndex(of: 0) ?? units.count
            return String(decoding: units[..<end], as: UTF16.self)
        }
    }

    private static func imagePath(_ handle: HANDLE) -> String? {
        var length: DWORD = DWORD(32768)
        var buffer = [UInt16](repeating: 0, count: Int(length))
        guard QueryFullProcessImageNameW(handle, 0, &buffer, &length) != 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF16.self)
    }

    private static func creationTime(_ handle: HANDLE) -> Date? {
        var created = FILETIME(); var exit = FILETIME(); var kernel = FILETIME(); var user = FILETIME()
        guard GetProcessTimes(handle, &created, &exit, &kernel, &user) != 0 else { return nil }
        let ticks = (UInt64(created.dwHighDateTime) << 32) | UInt64(created.dwLowDateTime)
        return Date(timeIntervalSince1970: (Double(ticks) / 10_000_000) - 11_644_473_600)
    }

    private typealias NtQuery = @convention(c) (HANDLE?, UInt32, UnsafeMutableRawPointer?, UInt32, UnsafeMutablePointer<UInt32>?) -> Int32

    private static func ntQueryInformationProcess() throws -> NtQuery {
        let moduleName = Array("ntdll.dll".utf16) + [0]
        let module: HMODULE? = moduleName.withUnsafeBufferPointer {
            GetModuleHandleW($0.baseAddress)
        }
        let address = "NtQueryInformationProcess".withCString {
            guard let module else { return nil }
            return GetProcAddress(module, $0)
        }
        guard let address else { throw ProcessEnumeratorError.enumerationFailed(ERROR_PROC_NOT_FOUND) }
        return unsafeBitCast(address, to: NtQuery.self)
    }

    private static func commandLine(_ process: HANDLE, query: NtQuery, deadline: Date?) async throws -> String {
        var buffer = [UInt8](repeating: 0, count: MemoryLayout<UNICODE_STRING>.size + 2)
        for _ in 0..<Self.maximumRetries {
            try Self.check(deadline)
            var required: UInt32 = 0
            let status = buffer.withUnsafeMutableBytes { raw -> Int32 in
                query(process, 60, raw.baseAddress, UInt32(raw.count), &required)
            }
            try Self.check(deadline)
            if status >= 0 {
                return try Self.decodeUnicodeString(buffer, deadline: deadline)
            }
            if required > UInt32(buffer.count), required <= UInt32(Self.maximumCommandLineBytes) {
                buffer = [UInt8](repeating: 0, count: Int(required))
            }
        }
        throw ProcessEnumeratorError.enumerationFailed(UInt32(ERROR_INVALID_DATA))
    }

    private static func decodeUnicodeString(_ data: [UInt8], deadline: Date?) throws -> String {
        guard data.count >= MemoryLayout<UNICODE_STRING>.size else { throw ProcessEnumeratorError.enumerationFailed(ERROR_INVALID_DATA) }
        let value = data.withUnsafeBytes { $0.loadUnaligned(as: UNICODE_STRING.self) }
        let length = Int(value.Length)
        guard length > 0,
              length <= Self.maximumCommandLineBytes,
              length % 2 == 0,
              value.MaximumLength >= value.Length,
              let pointer = value.Buffer
        else {
            throw ProcessEnumeratorError.enumerationFailed(ERROR_INVALID_DATA)
        }
        try Self.check(deadline)
        return try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { throw ProcessEnumeratorError.enumerationFailed(ERROR_INVALID_DATA) }
            let start = UInt(bitPattern: base)
            let headerEnd = start.addingReportingOverflow(UInt(MemoryLayout<UNICODE_STRING>.size))
            let end = start.addingReportingOverflow(UInt(raw.count))
            let textStart = UInt(bitPattern: pointer)
            let textEnd = textStart.addingReportingOverflow(UInt(length))
            guard !headerEnd.overflow, !end.overflow, !textEnd.overflow,
                  textStart >= headerEnd.partialValue, textEnd.partialValue <= end.partialValue
            else { throw ProcessEnumeratorError.enumerationFailed(ERROR_INVALID_DATA) }
            let offset = Int(textStart - start)
            let text = (0..<(length / 2)).map { index in
                raw.loadUnaligned(fromByteOffset: offset + index * 2, as: UInt16.self)
            }
            return String(decoding: text, as: UTF16.self)
        }
    }
}
#endif
