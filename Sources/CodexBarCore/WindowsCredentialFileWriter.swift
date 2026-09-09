#if os(Windows)
import Foundation
import WinSDK

/// Windows equivalent of the POSIX credential-file writer.
///
/// The temporary file receives a protected DACL granting only the current
/// token's user SID before the first WriteFile call. Publication occurs only
/// after the handle is closed, using MoveFileExW replacement in the same
/// directory.
enum WindowsCredentialFileWriter {
    static func writePrivate(
        _ data: Data,
        to url: URL,
        beforePublish: ((URL) throws -> Void)? = nil) throws
    {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let staged = directory.appendingPathComponent(
            ".\(url.lastPathComponent).codexbar-staged-\(UUID().uuidString)")

        var published = false
        var stagedCreated = false
        do {
            try withUserDACL { securityDescriptor, acl in
                let handle = try openNewFile(staged, securityDescriptor: securityDescriptor, acl: acl)
                stagedCreated = true
                var closed = false
                defer { if !closed { CloseHandle(handle) } }
                try writeAll(data, to: handle, path: staged.path)
                guard FlushFileBuffers(handle) != 0 else { throw win32Error(path: staged.path) }
                guard CloseHandle(handle) != 0 else { throw win32Error(path: staged.path) }
                closed = true
            }
            try beforePublish?(staged)
            // Re-apply the protected DACL after the callback and while the staged
            // path is still private, so callback-side metadata changes cannot
            // widen access immediately before publication.
            try protect(at: staged)
            try replace(staged, with: url)
            published = true
        } catch {
            if !published, stagedCreated { try? fm.removeItem(at: staged) }
            throw error
        }
    }

    static func repairPermissions(at url: URL) {
        try? protect(at: url)
    }

    private static func protect(at url: URL) throws {
        let path = Array(url.path.utf16) + [0]
        let handle: HANDLE? = path.withUnsafeBufferPointer {
            CreateFileW(
                $0.baseAddress,
                DWORD(READ_CONTROL | WRITE_DAC),
                DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE),
                nil,
                DWORD(OPEN_EXISTING),
                DWORD(FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT),
                nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { throw win32Error(path: url.path) }
        defer { CloseHandle(handle) }
        var info = BY_HANDLE_FILE_INFORMATION()
        guard GetFileInformationByHandle(handle, &info) != 0 else { throw win32Error(path: url.path) }
        guard (info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)) == 0 else {
            throw win32Error(path: url.path, code: DWORD(ERROR_NOT_SUPPORTED))
        }
        try withUserDACL { _, acl in
            let status = SetSecurityInfo(
                handle, SE_OBJECT_TYPE.SE_FILE_OBJECT,
                SECURITY_INFORMATION(DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION),
                nil, nil, acl, nil)
            guard status == ERROR_SUCCESS else { throw win32Error(path: url.path, code: status) }
        }
    }

    private static func openNewFile(
        _ url: URL,
        securityDescriptor: UnsafeMutablePointer<SECURITY_DESCRIPTOR>,
        acl: UnsafeMutablePointer<ACL>) throws -> HANDLE
    {
        let path = Array(url.path.utf16) + [0]
        var attributes = SECURITY_ATTRIBUTES()
        attributes.nLength = DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size)
        attributes.lpSecurityDescriptor = securityDescriptor
        attributes.bInheritHandle = 0
        let handle: HANDLE? = path.withUnsafeBufferPointer {
            CreateFileW(
                $0.baseAddress,
                DWORD(GENERIC_WRITE | READ_CONTROL | WRITE_DAC),
                0,
                &attributes,
                DWORD(CREATE_NEW),
                DWORD(FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT),
                nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { throw win32Error(path: url.path) }
        do {
            var volumeFlags: DWORD = 0
            guard GetVolumeInformationByHandleW(handle, nil, 0, nil, nil, &volumeFlags, nil, 0) != 0 else {
                throw win32Error(path: url.path)
            }
            guard (volumeFlags & DWORD(FILE_PERSISTENT_ACLS)) != 0 else {
                throw win32Error(path: url.path, code: DWORD(ERROR_NOT_SUPPORTED))
            }
            let status = SetSecurityInfo(
                handle, SE_OBJECT_TYPE.SE_FILE_OBJECT,
                SECURITY_INFORMATION(DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION),
                nil, nil, acl, nil)
            guard status == ERROR_SUCCESS else { throw win32Error(path: url.path, code: status) }
        } catch {
            CloseHandle(handle)
            _ = path.withUnsafeBufferPointer { DeleteFileW($0.baseAddress) }
            throw error
        }
        return handle
    }

    private static func writeAll(_ data: Data, to handle: HANDLE, path: String) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                var written: DWORD = 0
                let remaining = min(data.count - offset, Int(DWORD.max))
                let ok = WriteFile(
                    handle,
                    base.advanced(by: offset),
                    DWORD(remaining),
                    &written,
                    nil)
                guard ok != 0 else { throw win32Error(path: path) }
                guard written > 0 else { throw win32Error(path: path, code: DWORD(ERROR_WRITE_FAULT)) }
                offset += Int(written)
            }
        }
    }

    private static func replace(_ staged: URL, with destination: URL) throws {
        let source = Array(staged.path.utf16) + [0]
        let target = Array(destination.path.utf16) + [0]
        let ok = source.withUnsafeBufferPointer { sourceBuffer in
            target.withUnsafeBufferPointer { targetBuffer in
                MoveFileExW(
                    sourceBuffer.baseAddress,
                    targetBuffer.baseAddress,
                    DWORD(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
            }
        }
        guard ok != 0 else { throw win32Error(path: destination.path) }
    }

    private static func withUserDACL<T>(_ body: (UnsafeMutablePointer<SECURITY_DESCRIPTOR>, UnsafeMutablePointer<ACL>) throws -> T) throws -> T {
        var token: HANDLE?
        guard OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_QUERY), &token) != 0,
              let token
        else { throw win32Error(path: "process token") }
        defer { CloseHandle(token) }

        var size: DWORD = 0
        _ = GetTokenInformation(token, TOKEN_INFORMATION_CLASS.TokenUser, nil, 0, &size)
        guard size > 0 else { throw win32Error(path: "token user") }
        var tokenBuffer = [UInt8](repeating: 0, count: Int(size))
        guard tokenBuffer.withUnsafeMutableBytes({
            GetTokenInformation(token, TOKEN_INFORMATION_CLASS.TokenUser, $0.baseAddress, size, &size)
        }) != 0 else { throw win32Error(path: "token user") }

        return try tokenBuffer.withUnsafeMutableBytes { rawBuffer in
            let tokenUser = rawBuffer.baseAddress!.assumingMemoryBound(to: TOKEN_USER.self)
            var trustee = TRUSTEE_W()
            trustee.pMultipleTrustee = nil
            trustee.MultipleTrusteeOperation = MULTIPLE_TRUSTEE_OPERATION.NO_MULTIPLE_TRUSTEE
            trustee.TrusteeForm = TRUSTEE_FORM.TRUSTEE_IS_SID
            trustee.TrusteeType = TRUSTEE_TYPE.TRUSTEE_IS_USER
            guard let sid = tokenUser.pointee.User.Sid else {
                throw win32Error(path: "token user", code: DWORD(ERROR_INVALID_DATA))
            }
            trustee.ptstrName = sid.assumingMemoryBound(to: WCHAR.self)
            var entry = EXPLICIT_ACCESS_W()
            entry.grfAccessPermissions = DWORD(GENERIC_ALL)
            entry.grfAccessMode = ACCESS_MODE.SET_ACCESS
            entry.grfInheritance = DWORD(NO_INHERITANCE)
            entry.Trustee = trustee
            var acl: UnsafeMutablePointer<ACL>?
            let status = SetEntriesInAclW(1, &entry, nil, &acl)
            guard status == ERROR_SUCCESS else { throw win32Error(path: "user DACL", code: status) }
            guard let acl else { throw win32Error(path: "user DACL", code: DWORD(ERROR_INVALID_DATA)) }
            defer { LocalFree(acl) }
            var descriptor = SECURITY_DESCRIPTOR()
            guard InitializeSecurityDescriptor(&descriptor, DWORD(SECURITY_DESCRIPTOR_REVISION)) != 0,
                  SetSecurityDescriptorDacl(&descriptor, 1, acl, 0) != 0,
                  SetSecurityDescriptorControl(
                      &descriptor,
                      SECURITY_DESCRIPTOR_CONTROL(SE_DACL_PROTECTED),
                      SECURITY_DESCRIPTOR_CONTROL(SE_DACL_PROTECTED)) != 0
            else { throw win32Error(path: "security descriptor") }
            return try withUnsafeMutablePointer(to: &descriptor) { descriptorPointer in
                try body(descriptorPointer, acl)
            }
        }
    }

    private static func win32Error(path: String, code: DWORD = GetLastError()) -> NSError {
        NSError(domain: "Win32", code: Int(code), userInfo: [NSFilePathErrorKey: path])
    }
}
#endif
