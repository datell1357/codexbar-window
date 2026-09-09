#if os(Windows)
import Foundation
import WinSDK

/// Windows TCP listener lookup backed by IP Helper's owner-PID tables.
/// The API returns rows for both IPv4 and IPv6 and never falls back to a
/// shell utility (which would be unavailable or ambiguous on Windows).
enum WindowsListeningTCPPorts {
    // MIB_TCP_STATE_LISTEN is the stable IP Helper value for LISTEN.
    private static let listenState: UInt32 = 2
    private static let errorInsufficientBuffer = UInt32(ERROR_INSUFFICIENT_BUFFER)
    private static let maxTableBytes = 16 * 1024 * 1024

    static func ports(pid: Int, timeout: TimeInterval) async throws -> [Int] {
        try Task.checkCancellation()
        let deadline = Date().addingTimeInterval(max(0, timeout))
        guard pid > 0, UInt64(pid) <= UInt64(UInt32.max) else { return [] }
        var ports = Set<Int>()
        ports.formUnion(try Self.readIPv4(pid: UInt32(pid), deadline: deadline))
        try Task.checkCancellation()
        ports.formUnion(try Self.readIPv6(pid: UInt32(pid), deadline: deadline))
        try Task.checkCancellation()
        return ports.sorted()
    }

    private static func readIPv4(pid: UInt32, deadline: Date) throws -> Set<Int> {
        try Self.checkDeadline(deadline)
        let rowSize = MemoryLayout<MIB_TCPROW_OWNER_PID>.stride
        let data = try Self.table(
            family: UInt32(AF_INET),
            tableClass: TCP_TABLE_CLASS.TCP_TABLE_OWNER_PID_ALL,
            rowSize: rowSize,
            deadline: deadline)
        var result = Set<Int>()
        guard data.count >= MemoryLayout<UInt32>.size else { return result }
        let count = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let rowCount = min(Int(count), max(0, (data.count - MemoryLayout<UInt32>.size) / rowSize))
        for index in 0..<rowCount {
            try Self.checkDeadline(deadline)
            let offset = MemoryLayout<UInt32>.size + index * rowSize
            guard offset + rowSize <= data.count else { break }
            let row = data.withUnsafeBytes { raw -> (UInt32, UInt16, UInt32) in
                let state = raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                let portBytes = raw.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self)
                let owner = raw.loadUnaligned(fromByteOffset: offset + 20, as: UInt32.self)
                return (state, UInt16(truncatingIfNeeded: portBytes).bigEndian, owner)
            }
            if row.0 == Self.listenState, row.2 == pid, row.1 > 0 { result.insert(Int(row.1)) }
        }
        return result
    }

    private static func readIPv6(pid: UInt32, deadline: Date) throws -> Set<Int> {
        try Self.checkDeadline(deadline)
        let rowSize = MemoryLayout<MIB_TCP6ROW_OWNER_PID>.stride
        let data = try Self.table(
            family: UInt32(AF_INET6),
            tableClass: TCP_TABLE_CLASS.TCP_TABLE_OWNER_PID_ALL,
            rowSize: rowSize,
            deadline: deadline)
        var result = Set<Int>()
        guard data.count >= MemoryLayout<UInt32>.size else { return result }
        let count = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let rowCount = min(Int(count), max(0, (data.count - MemoryLayout<UInt32>.size) / rowSize))
        for index in 0..<rowCount {
            try Self.checkDeadline(deadline)
            let offset = MemoryLayout<UInt32>.size + index * rowSize
            guard offset + rowSize <= data.count else { break }
            let row = data.withUnsafeBytes { raw -> (UInt32, UInt16, UInt32) in
                let state = raw.loadUnaligned(fromByteOffset: offset + 48, as: UInt32.self)
                let portBytes = raw.loadUnaligned(fromByteOffset: offset + 20, as: UInt32.self)
                let owner = raw.loadUnaligned(fromByteOffset: offset + 52, as: UInt32.self)
                return (state, UInt16(truncatingIfNeeded: portBytes).bigEndian, owner)
            }
            if row.0 == Self.listenState, row.2 == pid, row.1 > 0 { result.insert(Int(row.1)) }
        }
        return result
    }

    private static func table(
        family: UInt32,
        tableClass: TCP_TABLE_CLASS,
        rowSize: Int,
        deadline: Date) throws -> Data {
        guard rowSize > 0 else { return Data() }
        try Self.checkDeadline(deadline)
        var byteCount: ULONG = 0
        var status = GetExtendedTcpTable(nil, &byteCount, 0, family, tableClass, 0)
        try Self.checkDeadline(deadline)
        if status == 0 { return Data() }
        guard status == Self.errorInsufficientBuffer, byteCount > 0 else {
            throw AntigravityStatusProbeError.portDetectionFailed(
                "GetExtendedTcpTable failed (status \(status))")
        }
        var capacity = Int(byteCount)
        for _ in 0..<3 {
            guard capacity > 0 else {
                throw AntigravityStatusProbeError.portDetectionFailed("invalid TCP table size")
            }
            guard capacity <= Self.maxTableBytes else {
                throw AntigravityStatusProbeError.portDetectionFailed("TCP table exceeds size limit")
            }
            try Self.checkDeadline(deadline)
            var data = Data(count: capacity)
            status = data.withUnsafeMutableBytes { raw in
                var size = ULONG(raw.count)
                let result = GetExtendedTcpTable(raw.baseAddress, &size, 0, family, tableClass, 0)
                if result == Self.errorInsufficientBuffer, size > ULONG(raw.count) { capacity = Int(size) }
                return result
            }
            try Self.checkDeadline(deadline)
            if status == 0 { return data }
            if status != Self.errorInsufficientBuffer {
                throw AntigravityStatusProbeError.portDetectionFailed(
                    "GetExtendedTcpTable failed (status \(status))")
            }
        }
        throw AntigravityStatusProbeError.portDetectionFailed("GetExtendedTcpTable buffer resize limit reached")
    }

    private static func checkDeadline(_ deadline: Date) throws {
        try Task.checkCancellation()
        if Date() >= deadline { throw AntigravityStatusProbeError.timedOut }
    }
}
#endif
