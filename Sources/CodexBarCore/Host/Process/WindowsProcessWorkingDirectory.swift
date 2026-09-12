#if os(Windows)
import Foundation
import WinSDK

/// Experimental, opt-in only. The native-64 RTL CurrentDirectory prefix is not a public ABI.
/// Layout reference: https://github.com/winsiderss/phnt/blob/master/ntrtl.h (RTL_USER_PROCESS_PARAMETERS).
/// Microsoft explicitly permits changes to NtQueryInformationProcess and the returned structures:
/// https://learn.microsoft.com/windows/win32/api/winternl/nf-winternl-ntqueryinformationprocess
/// No environment block, arbitrary memory scan, injection, or privilege adjustment is performed.
enum WindowsProcessWorkingDirectory {
    enum Outcome {
        case available(String)
        case unavailable
    }

    private typealias NtQuery = @convention(c) (
        HANDLE?, UInt32, UnsafeMutableRawPointer?, UInt32, UnsafeMutablePointer<UInt32>?) -> Int32
    private typealias MachineQuery = @convention(c) (
        HANDLE?, UnsafeMutablePointer<UInt16>?, UnsafeMutablePointer<UInt16>?) -> BOOL

    // Explicit little-endian native-64 layout; never applied to WOW64/emulated or 32-bit processes.
    private enum Layout {
        static let basicSize = 48
        static let basicPEB = 8
        static let basicPID = 32
        static let pebParameters = 0x20
        static let directory = 0x38
        static let image = 0x60
        static let command = 0x70
        static let prefixSize = 0x80
    }

    private struct UnicodeDescriptor: Equatable {
        let length: Int
        let capacity: Int
        let address: UInt64
    }

    private struct Parameters: Equatable {
        let address: UInt64
        let header: [UInt8]
        let directory: UnicodeDescriptor
        let image: UnicodeDescriptor
        let command: UnicodeDescriptor
    }

    static func read(process: WindowsProcessSnapshot, deadline: Date) -> Outcome {
        guard MemoryLayout<UInt>.size == 8, !Task.isCancelled, Date() < deadline,
              process.creationTicks > 0,
              let currentOwner = try? ProcessOwnerIdentity.current(), currentOwner == process.owner,
              let handle = OpenProcess(DWORD(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ | SYNCHRONIZE), 0, process.pid),
              handle != INVALID_HANDLE_VALUE
        else { return .unavailable }
        defer { CloseHandle(handle) }
        guard self.matches(handle, process: process),
              (try? WindowsProcessOwnerIdentity.identity(forProcessHandle: handle)) == currentOwner,
              let machineAddress = self.symbol("IsWow64Process2", module: "kernel32.dll"),
              let queryAddress = self.symbol("NtQueryInformationProcess", module: "ntdll.dll")
        else { return .unavailable }
        let machineQuery = unsafeBitCast(machineAddress, to: MachineQuery.self)
        var ownMachine: UInt16 = 0, ownNative: UInt16 = 0, targetMachine: UInt16 = 0, targetNative: UInt16 = 0
        guard machineQuery(GetCurrentProcess(), &ownMachine, &ownNative) != 0,
              machineQuery(handle, &targetMachine, &targetNative) != 0,
              ownMachine == 0, targetMachine == 0, ownNative == targetNative,
              ownNative == 0x8664 || ownNative == 0xAA64
        else { return .unavailable }
        let query = unsafeBitCast(queryAddress, to: NtQuery.self)
        var basic = [UInt8](repeating: 0, count: Layout.basicSize)
        var returned: UInt32 = 0
        let status = basic.withUnsafeMutableBytes {
            query(handle, 0, $0.baseAddress, UInt32($0.count), &returned)
        }
        guard status >= 0, returned == UInt32(Layout.basicSize),
              self.uint64(basic, Layout.basicPID) == UInt64(process.pid)
        else { return .unavailable }
        let peb = self.uint64(basic, Layout.basicPEB)
        let reader = Reader(process: handle, deadline: deadline)
        guard let first = self.parameters(peb: peb, reader: reader),
              let image = reader.string(first.image, limit: 32766),
              let command = reader.string(first.command, limit: 65534),
              command == process.commandLine,
              self.normalizedImage(image) == self.normalizedImage(process.imagePath),
              let cwd = reader.string(first.directory, limit: 8192),
              let normalized = WindowsSessionLaunchHints.absolutePath(cwd),
              let second = self.parameters(peb: peb, reader: reader), first == second,
              reader.string(second.directory, limit: 8192) == cwd,
              reader.string(second.command, limit: 65534) == command,
              self.matches(handle, process: process),
              (try? WindowsProcessOwnerIdentity.identity(forProcessHandle: handle)) == currentOwner,
              !Task.isCancelled, Date() < deadline
        else { return .unavailable }
        return .available(normalized)
    }

    private static func parameters(peb: UInt64, reader: Reader) -> Parameters? {
        guard let location = self.add(peb, Layout.pebParameters),
              let pointer = reader.bytes(address: location, count: 8)
        else { return nil }
        let address = self.uint64(pointer, 0)
        guard address % 8 == 0, let header = reader.bytes(address: address, count: 16) else { return nil }
        let maximum = self.uint32(header, 0), length = self.uint32(header, 4), flags = self.uint32(header, 8)
        guard length >= UInt32(Layout.prefixSize), maximum >= length, maximum <= 1024 * 1024,
              flags & 1 != 0,
              let directory = self.descriptor(base: address, offset: Layout.directory, reader: reader),
              let image = self.descriptor(base: address, offset: Layout.image, reader: reader),
              let command = self.descriptor(base: address, offset: Layout.command, reader: reader)
        else { return nil }
        return Parameters(address: address, header: header, directory: directory, image: image, command: command)
    }

    private static func descriptor(base: UInt64, offset: Int, reader: Reader) -> UnicodeDescriptor? {
        guard let address = self.add(base, offset), let bytes = reader.bytes(address: address, count: 16) else { return nil }
        let length = Int(UInt16(bytes[0]) | (UInt16(bytes[1]) << 8))
        let capacity = Int(UInt16(bytes[2]) | (UInt16(bytes[3]) << 8))
        let pointer = self.uint64(bytes, 8)
        guard length > 0, length % 2 == 0, capacity >= length, pointer > 0, pointer % 2 == 0 else { return nil }
        return UnicodeDescriptor(length: length, capacity: capacity, address: pointer)
    }

    private static func matches(_ handle: HANDLE, process: WindowsProcessSnapshot) -> Bool {
        guard GetProcessId(handle) == process.pid, WaitForSingleObject(handle, 0) == WAIT_TIMEOUT else { return false }
        var created = FILETIME(), exited = FILETIME(), kernel = FILETIME(), user = FILETIME()
        guard GetProcessTimes(handle, &created, &exited, &kernel, &user) != 0 else { return false }
        return ((UInt64(created.dwHighDateTime) << 32) | UInt64(created.dwLowDateTime)) == process.creationTicks
    }

    private static func symbol(_ name: String, module: String) -> FARPROC? {
        let units = Array(module.utf16) + [0]
        guard let handle = units.withUnsafeBufferPointer({ GetModuleHandleW($0.baseAddress) }) else { return nil }
        return name.withCString { GetProcAddress(handle, $0) }
    }

    private static func add(_ address: UInt64, _ offset: Int) -> UInt64? {
        guard address > 0 else { return nil }
        let result = address.addingReportingOverflow(UInt64(offset))
        return result.overflow ? nil : result.partialValue
    }

    private static func uint64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { $0 | (UInt64(bytes[offset + $1]) << ($1 * 8)) }
    }
    private static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | (UInt32(bytes[offset + $1]) << ($1 * 8)) }
    }
    private static func normalizedImage(_ raw: String) -> String {
        var path = raw.replacingOccurrences(of: "/", with: "\\")
        for prefix in ["\\\\?\\", "\\??\\"] where path.hasPrefix(prefix) { path = String(path.dropFirst(prefix.count)) }
        return path.lowercased()
    }

    private final class Reader {
        let process: HANDLE
        let deadline: Date
        var remainingBytes = 192 * 1024
        init(process: HANDLE, deadline: Date) { self.process = process; self.deadline = deadline }

        func bytes(address: UInt64, count: Int) -> [UInt8]? {
            guard !Task.isCancelled, Date() < self.deadline, count > 0, count <= 65534,
                  self.remainingBytes >= count, let start = UInt(exactly: address), start > 0,
                  !start.addingReportingOverflow(UInt(count)).overflow,
                  let pointer = UnsafeRawPointer(bitPattern: start)
            else { return nil }
            self.remainingBytes -= count
            var bytes = [UInt8](repeating: 0, count: count)
            var copied: SIZE_T = 0
            let success = bytes.withUnsafeMutableBytes {
                ReadProcessMemory(self.process, pointer, $0.baseAddress, SIZE_T(count), &copied)
            }
            guard success != 0, copied == SIZE_T(count), !Task.isCancelled, Date() < self.deadline else { return nil }
            return bytes
        }

        func string(_ descriptor: UnicodeDescriptor, limit: Int) -> String? {
            guard descriptor.length <= limit, let bytes = self.bytes(address: descriptor.address, count: descriptor.length)
            else { return nil }
            var units: [UInt16] = []
            for index in stride(from: 0, to: bytes.count, by: 2) {
                units.append(UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8))
            }
            guard !units.contains(0) else { return nil }
            let value = String(decoding: units, as: UTF16.self)
            return Array(value.utf16) == units ? value : nil
        }
    }
}
#endif
