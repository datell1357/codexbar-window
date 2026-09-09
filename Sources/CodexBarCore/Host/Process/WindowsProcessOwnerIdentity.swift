import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Stable owner identity used when associating a managed process with the
/// account that launched it. Windows stores the binary SID; POSIX stores the
/// numeric uid. The value is deliberately opaque and is never synthesized
/// from a hash or a process id.
package enum ProcessOwnerIdentity: Hashable, Sendable {
    case posixUID(UInt32)
    case windowsSID(Data)

    package enum QueryError: Error, Sendable {
        case unavailable
        case invalidToken
        case queryFailed(UInt32)
        case allocationLimitExceeded
        case invalidSID
    }

    /// Returns the owner of this process using the native identity primitive.
    /// This accessor performs no credential or process probing beyond the
    /// current process token.
    package static func current() throws -> Self {
        #if os(Windows)
        return try WindowsProcessOwnerIdentity.current()
        #elseif canImport(Darwin)
        return .posixUID(UInt32(getuid()))
        #elseif canImport(Glibc)
        return .posixUID(UInt32(getuid()))
        #elseif canImport(Musl)
        return .posixUID(UInt32(getuid()))
        #else
        throw QueryError.unavailable
        #endif
    }
}

#if os(Windows)
import WinSDK

/// Read-only Windows token owner query. Callers retain ownership of handles
/// passed to `identity(forToken:)`; this type never closes borrowed handles.
package enum WindowsProcessOwnerIdentity {
    private static let maximumTokenBufferSize = 1 * 1024 * 1024

    package static func current() throws -> ProcessOwnerIdentity {
        var token: HANDLE?
        guard OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_QUERY), &token) != 0,
              let token
        else {
            throw ProcessOwnerIdentity.QueryError.queryFailed(GetLastError())
        }
        defer { CloseHandle(token) }
        return try identity(forToken: token)
    }

    /// Opens a borrowed process handle's token, reads its owner, and closes
    /// only the temporary token handle. The process handle remains borrowed.
    package static func identity(forProcessHandle process: HANDLE) throws -> ProcessOwnerIdentity {
        guard process != INVALID_HANDLE_VALUE else {
            throw ProcessOwnerIdentity.QueryError.invalidToken
        }
        var token: HANDLE?
        guard OpenProcessToken(process, DWORD(TOKEN_QUERY), &token) != 0,
              let token
        else {
            throw ProcessOwnerIdentity.QueryError.queryFailed(GetLastError())
        }
        defer { CloseHandle(token) }
        return try identity(forToken: token)
    }

    package static func identity(forToken token: HANDLE) throws -> ProcessOwnerIdentity {
        guard token != INVALID_HANDLE_VALUE else {
            throw ProcessOwnerIdentity.QueryError.invalidToken
        }
        var required: DWORD = 0
        _ = GetTokenInformation(token, TOKEN_INFORMATION_CLASS.TokenUser, nil, 0, &required)
        guard required > 0 else {
            throw ProcessOwnerIdentity.QueryError.queryFailed(GetLastError())
        }
        guard required <= DWORD(maximumTokenBufferSize) else {
            throw ProcessOwnerIdentity.QueryError.allocationLimitExceeded
        }

        var buffer = [UInt8](repeating: 0, count: Int(required))
        let copied: BOOL = buffer.withUnsafeMutableBytes { raw in
            GetTokenInformation(
                token,
                TOKEN_INFORMATION_CLASS.TokenUser,
                raw.baseAddress,
                required,
                &required)
        }
        guard copied != 0 else {
            throw ProcessOwnerIdentity.QueryError.queryFailed(GetLastError())
        }
        return try buffer.withUnsafeBytes { raw in
            guard raw.count >= MemoryLayout<TOKEN_USER>.size,
                  let base = raw.baseAddress
            else {
                throw ProcessOwnerIdentity.QueryError.invalidSID
            }
            let tokenUser = base.loadUnaligned(as: TOKEN_USER.self)
            guard let sid = tokenUser.User.Sid
            else {
                throw ProcessOwnerIdentity.QueryError.invalidSID
            }
            let sidAddress = UnsafeRawPointer(sid)
            let baseAddress = UInt(bitPattern: base)
            let sidStart = UInt(bitPattern: sidAddress)
            let sidEnd = baseAddress.addingReportingOverflow(UInt(raw.count))
            let minimumSIDStart = baseAddress.addingReportingOverflow(UInt(MemoryLayout<TOKEN_USER>.size))
            guard !sidEnd.overflow,
                  !minimumSIDStart.overflow,
                  sidStart >= baseAddress,
                  sidStart >= minimumSIDStart.partialValue,
                  sidStart <= sidEnd.partialValue,
                  sidEnd.partialValue - sidStart >= 8
            else {
                throw ProcessOwnerIdentity.QueryError.invalidSID
            }

            // The SID header carries the sub-authority count. Validate the
            // complete variable-length SID is inside the token buffer before
            // calling Win32 helpers that dereference it.
            let sidHeader = sidAddress.assumingMemoryBound(to: UInt8.self)
            let subAuthorityCount = UInt64(sidHeader.advanced(by: 1).pointee)
            let authorityBytes = subAuthorityCount.multipliedReportingOverflow(by: 4)
            let length = UInt64(8).addingReportingOverflow(authorityBytes.partialValue)
            guard subAuthorityCount <= 15,
                  !authorityBytes.overflow,
                  !length.overflow,
                  length.partialValue <= UInt64(sidEnd.partialValue - sidStart),
                  IsValidSid(sid) != 0
            else {
                throw ProcessOwnerIdentity.QueryError.invalidSID
            }
            let sidLength = Int(GetLengthSid(sid))
            guard sidLength > 0,
                  UInt64(sidLength) == length.partialValue,
                  UInt64(sidLength) <= UInt64(sidEnd.partialValue - sidStart)
            else {
                throw ProcessOwnerIdentity.QueryError.invalidSID
            }
            // Copy while `buffer` is alive; the returned Data owns its bytes.
            return .windowsSID(Data(bytes: sid, count: sidLength))
        }
    }
}
#endif
