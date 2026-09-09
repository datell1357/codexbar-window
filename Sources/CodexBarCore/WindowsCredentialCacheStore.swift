#if os(Windows)
import Foundation
import WinSDK

/// Raw-data adapter for the per-user Windows Credential Manager.
///
/// Target names are scoped by the cache service and account, so unrelated generic
/// credentials are never included when listing cache keys.
enum WindowsCredentialCacheStore {
    enum LoadResult {
        case found(Data)
        case missing
        case temporarilyUnavailable
        case invalid
    }

    enum ClearResult {
        case removed
        case missing
        case failed
    }

    enum KeysResult {
        case found([String])
        case temporarilyUnavailable
        case failed
    }

    private static let credentialType = CRED_TYPE_GENERIC
    private static let targetSeparator = "::"

    static func load(service: String, account: String) -> LoadResult {
        let target = targetName(service: service, account: account)
        guard isValidComponent(service), isValidComponent(account) else { return .invalid }
        var credential: UnsafeMutablePointer<CREDENTIALW>?
        let status = withWideString(target) { pointer in
            CredReadW(pointer, credentialType, 0, &credential)
        }
        guard status != 0 else {
            return self.loadFailure(GetLastError())
        }
        guard let credential else { return .invalid }
        defer { CredFree(credential) }
        let value = credential.pointee
        guard let blob = value.CredentialBlob, value.CredentialBlobSize > 0 else { return .invalid }
        return .found(Data(bytes: blob, count: Int(value.CredentialBlobSize)))
    }

    static func store(service: String, account: String, data: Data) -> Bool {
        guard isValidComponent(service), isValidComponent(account), !data.isEmpty,
              data.count <= Int(CRED_MAX_CREDENTIAL_BLOB_SIZE)
        else { return false }
        let target = targetName(service: service, account: account)
        return withWideString(target) { targetPointer in
            data.withUnsafeBytes { bytes in
                var credential = CREDENTIALW()
                credential.Type = credentialType
                credential.TargetName = UnsafeMutablePointer(mutating: targetPointer)
                credential.CredentialBlobSize = DWORD(data.count)
                credential.CredentialBlob = UnsafeMutablePointer(mutating: bytes.bindMemory(to: BYTE.self).baseAddress)
                credential.Persist = CRED_PERSIST_LOCAL_MACHINE
                return CredWriteW(&credential, 0) != 0
            }
        }
    }

    static func clear(service: String, account: String) -> ClearResult {
        guard isValidComponent(service), isValidComponent(account) else { return .failed }
        let target = targetName(service: service, account: account)
        let status = withWideString(target) { pointer in
            CredDeleteW(pointer, credentialType, 0)
        }
        guard status != 0 else {
            switch GetLastError() {
            case ERROR_NOT_FOUND:
                return .missing
            case ERROR_BUSY, ERROR_LOCK_VIOLATION, ERROR_ACCESS_DENIED, ERROR_NO_SUCH_LOGON_SESSION:
                return .failed
            default:
                return .failed
            }
        }
        return .removed
    }

    static func keys(service: String, category: String) -> KeysResult {
        guard isValidComponent(service), isValidComponent(category), !service.contains("*") else { return .failed }
        let prefix = targetPrefix(service: service)
        var count: DWORD = 0
        var credentials: UnsafeMutablePointer<UnsafeMutablePointer<CREDENTIALW>?>?
        let status = withWideString("\(prefix)*") { pointer in
            CredEnumerateW(pointer, 0, &count, &credentials)
        }
        guard status != 0 else {
            switch GetLastError() {
            case ERROR_NOT_FOUND:
                return .found([])
            case ERROR_BUSY, ERROR_LOCK_VIOLATION, ERROR_NO_SUCH_LOGON_SESSION:
                return .temporarilyUnavailable
            default:
                return .failed
            }
        }
        defer {
            if let credentials { CredFree(credentials) }
        }
        guard let credentials else { return .failed }
        var identifiers: [String] = []
        for index in 0 ..< Int(count) {
            guard let credential = credentials.advanced(by: index).pointee,
                  credential.pointee.Type == credentialType,
                  let targetName = credential.pointee.TargetName
            else { continue }
            let target = String(decodingCString: targetName, as: UTF16.self)
            guard target.hasPrefix(prefix) else { continue }
            let account = String(target.dropFirst(prefix.count))
            guard account.hasPrefix("\(category).")
            else { continue }
            identifiers.append(String(account.dropFirst(category.count + 1)))
        }
        return .found(identifiers.filter { !$0.isEmpty }.sorted())
    }

    private static func targetPrefix(service: String) -> String {
        "\(service)\(targetSeparator)"
    }

    private static func targetName(service: String, account: String) -> String {
        "\(targetPrefix(service: service))\(account)"
    }

    private static func loadFailure(_ error: DWORD) -> LoadResult {
        switch error {
        case ERROR_NOT_FOUND:
            return .missing
        case ERROR_BUSY, ERROR_LOCK_VIOLATION, ERROR_ACCESS_DENIED, ERROR_NO_SUCH_LOGON_SESSION:
            return .temporarilyUnavailable
        default:
            return .invalid
        }
    }

    private static func isValidComponent(_ value: String) -> Bool {
        !value.utf16.contains(0)
    }

    private static func withWideString<T>(_ string: String, _ body: (UnsafePointer<WCHAR>) -> T) -> T {
        var codeUnits = Array(string.utf16)
        codeUnits.append(0)
        return codeUnits.withUnsafeBufferPointer { body($0.baseAddress!) }
    }
}
#endif
