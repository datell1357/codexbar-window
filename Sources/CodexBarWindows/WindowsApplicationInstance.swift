#if os(Windows)
import Foundation
import WinSDK

/// Acquired before constructing any runtime. The process keeps this lease through its final exit.
/// It protects startup ownership only; it does not authenticate a widget host or certify stored data.
final class WindowsApplicationInstance {
    enum Failure: Error {
        case occupied
        case windows(DWORD)
        case invalidStorage

        var exitCode: DWORD {
            switch self {
            case .occupied: DWORD(ERROR_ALREADY_EXISTS)
            case let .windows(code): code == 0 ? DWORD(ERROR_GEN_FAILURE) : code
            case .invalidStorage: DWORD(ERROR_INVALID_DATA)
            }
        }
    }

    private let file: HANDLE
    // Keeping every directory open without delete sharing prevents this path from being renamed
    // underneath the lock. The OS-known folder's ancestors remain outside this lease's boundary.
    private let directories: [HANDLE]

    private init(file: HANDLE, directories: [HANDLE]) {
        self.file = file
        self.directories = directories
    }

    static func acquire() throws -> WindowsApplicationInstance {
        var identifier = FOLDERID_LocalAppData
        var knownPath: PWSTR?
        let result = SHGetKnownFolderPath(&identifier, 0, nil, &knownPath)
        guard result >= 0, let knownPath else {
            if let knownPath { CoTaskMemFree(knownPath) }
            throw Failure.invalidStorage
        }
        let root = String(decodingCString: knownPath, as: UTF16.self)
        CoTaskMemFree(knownPath)
        guard !root.isEmpty, (root as NSString).isAbsolutePath else { throw Failure.invalidStorage }
        var session: DWORD = 0
        guard ProcessIdToSessionId(GetCurrentProcessId(), &session) else { throw Failure.windows(GetLastError()) }

        var directories: [HANDLE] = []
        var file: HANDLE?
        var transferred = false
        defer {
            if !transferred {
                if let file { _ = CloseHandle(file) }
                for directory in directories.reversed() { _ = CloseHandle(directory) }
            }
        }
        directories.append(try self.openDirectory(root))
        let local = URL(fileURLWithPath: root, isDirectory: true)
        let data = local.appendingPathComponent("CodexBar", isDirectory: true)
        let runtime = data.appendingPathComponent("Runtime", isDirectory: true)
        try self.withUserSecurity { attributes in
            for directory in [data, runtime] {
                let created = directory.path.withCString(encodedAs: UTF16.self) {
                    CreateDirectoryW($0, attributes)
                }
                if !created {
                    let error = GetLastError()
                    guard error == ERROR_ALREADY_EXISTS else { throw Failure.windows(error) }
                }
                // Check and pin each component before creating anything below it.
                directories.append(try self.openDirectory(directory.path))
            }
            let lock = runtime.appendingPathComponent("instance-session-\(session).lock")
            let opened = lock.path.withCString(encodedAs: UTF16.self) {
                CreateFileW($0, DWORD(GENERIC_READ | GENERIC_WRITE), 0, attributes, DWORD(OPEN_ALWAYS),
                    DWORD(FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT), nil)
            }
            guard let opened, opened != INVALID_HANDLE_VALUE else {
                let error = GetLastError()
                if error == ERROR_SHARING_VIOLATION || error == ERROR_LOCK_VIOLATION { throw Failure.occupied }
                throw Failure.windows(error)
            }
            file = opened
            var info = BY_HANDLE_FILE_INFORMATION()
            guard GetFileType(opened) == DWORD(FILE_TYPE_DISK), GetFileInformationByHandle(opened, &info),
                  info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) == 0,
                  info.nNumberOfLinks == 1, info.nFileSizeHigh == 0, info.nFileSizeLow == 0 else {
                throw Failure.invalidStorage
            }
        }
        guard let file else { throw Failure.invalidStorage }
        let instance = WindowsApplicationInstance(file: file, directories: directories)
        transferred = true
        return instance
    }

    private static func openDirectory(_ path: String) throws -> HANDLE {
        let opened = path.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, DWORD(FILE_READ_ATTRIBUTES), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE), nil,
                DWORD(OPEN_EXISTING), DWORD(FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT), nil)
        }
        guard let opened, opened != INVALID_HANDLE_VALUE else { throw Failure.windows(GetLastError()) }
        var info = BY_HANDLE_FILE_INFORMATION()
        guard GetFileType(opened) == DWORD(FILE_TYPE_DISK), GetFileInformationByHandle(opened, &info),
              info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0,
              info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) == 0 else {
            _ = CloseHandle(opened)
            throw Failure.invalidStorage
        }
        return opened
    }

    /// This ACL is used only when creating our directories/file. Existing ACLs are not rewritten.
    private static func withUserSecurity<T>(_ body: (UnsafeMutablePointer<SECURITY_ATTRIBUTES>) throws -> T) throws -> T {
        var token: HANDLE?
        guard OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_QUERY), &token), let token else {
            throw Failure.windows(GetLastError())
        }
        defer { _ = CloseHandle(token) }
        var length: DWORD = 0
        _ = GetTokenInformation(token, TOKEN_INFORMATION_CLASS.TokenUser, nil, 0, &length)
        guard GetLastError() == ERROR_INSUFFICIENT_BUFFER,
              length >= MemoryLayout<TOKEN_USER>.size, length <= 65536 else { throw Failure.invalidStorage }
        let allocation = Int(length)
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: allocation, alignment: MemoryLayout<TOKEN_USER>.alignment)
        defer { bytes.deallocate() }
        guard GetTokenInformation(token, TOKEN_INFORMATION_CLASS.TokenUser, bytes, length, &length),
              length >= MemoryLayout<TOKEN_USER>.size, length <= allocation,
              let sid = bytes.assumingMemoryBound(to: TOKEN_USER.self).pointee.User.Sid, IsValidSid(sid) else {
            throw Failure.invalidStorage
        }
        var trustee = TRUSTEE_W()
        trustee.MultipleTrusteeOperation = MULTIPLE_TRUSTEE_OPERATION.NO_MULTIPLE_TRUSTEE
        trustee.TrusteeForm = TRUSTEE_FORM.TRUSTEE_IS_SID
        trustee.TrusteeType = TRUSTEE_TYPE.TRUSTEE_IS_USER
        trustee.ptstrName = sid.assumingMemoryBound(to: WCHAR.self)
        var entry = EXPLICIT_ACCESS_W()
        entry.grfAccessPermissions = DWORD(GENERIC_ALL)
        entry.grfAccessMode = ACCESS_MODE.SET_ACCESS
        entry.grfInheritance = DWORD(SUB_CONTAINERS_AND_OBJECTS_INHERIT)
        entry.Trustee = trustee
        var acl: UnsafeMutablePointer<ACL>?
        let status = SetEntriesInAclW(1, &entry, nil, &acl)
        guard status == ERROR_SUCCESS, let acl else { throw Failure.windows(status) }
        defer { _ = LocalFree(acl) }
        var descriptor = SECURITY_DESCRIPTOR()
        guard InitializeSecurityDescriptor(&descriptor, DWORD(SECURITY_DESCRIPTOR_REVISION)),
              SetSecurityDescriptorDacl(&descriptor, true, acl, false),
              SetSecurityDescriptorControl(&descriptor, SECURITY_DESCRIPTOR_CONTROL(SE_DACL_PROTECTED),
                  SECURITY_DESCRIPTOR_CONTROL(SE_DACL_PROTECTED)) else { throw Failure.windows(GetLastError()) }
        return try withUnsafeMutablePointer(to: &descriptor) { pointer in
            var attributes = SECURITY_ATTRIBUTES()
            attributes.nLength = DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size)
            attributes.lpSecurityDescriptor = UnsafeMutableRawPointer(pointer)
            attributes.bInheritHandle = false
            return try body(&attributes)
        }
    }

    deinit {
        _ = CloseHandle(self.file)
        for directory in self.directories.reversed() { _ = CloseHandle(directory) }
    }
}
#endif
