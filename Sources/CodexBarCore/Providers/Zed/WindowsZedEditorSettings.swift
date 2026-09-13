#if os(Windows)
import Foundation

/// Reads configuration only; never opens the credential vault or starts a request.
public enum WindowsZedEditorSettings {
    /// CodexBar-specific override matching the editor's custom data directory.
    public static let dataDirectoryEnvironmentKey = "CODEXBAR_ZED_DATA_DIR"

    public enum Failure: Error { case unavailable, invalid, separateCredentialOrigin }

    public static func suggestedOrigin(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> String {
        try Task.checkCancellation()
        if let raw = CodexBarPlatformPaths.environmentValue(self.dataDirectoryEnvironmentKey, environment: environment) {
            let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, path.utf16.count <= 32_767,
                  !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                  NSString(string: path).isAbsolutePath else { throw Failure.unavailable }
            let url = URL(fileURLWithPath: path, isDirectory: true)
                .appendingPathComponent("config", isDirectory: true).appendingPathComponent("settings.json")
            // An explicit but missing profile must not silently select the default editor account.
            return try self.suggestedOrigin(from: url, allowMissingDefaults: false)
        }
        guard let root = CodexBarPlatformPaths.environmentValue("APPDATA", environment: environment),
              !root.isEmpty, NSString(string: root).isAbsolutePath else { throw Failure.unavailable }
        let url = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent("Zed/settings.json")
        return try self.suggestedOrigin(from: url)
    }

    public static func suggestedOrigin(from url: URL) throws -> String {
        try self.suggestedOrigin(from: url, allowMissingDefaults: true)
    }

    private static func suggestedOrigin(from url: URL, allowMissingDefaults: Bool) throws -> String {
        try Task.checkCancellation()
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            guard allowMissingDefaults else { throw Failure.unavailable }
            return ZedStatusProbe.defaultKeychainServiceURL
        } catch { throw Failure.unavailable }
        defer { try? handle.close() }
        let data: Data
        do { data = try handle.read(upToCount: 1_048_577) ?? Data() }
        catch { throw Failure.unavailable }
        try Task.checkCancellation()
        return try self.parseOrigin(data)
    }

    static func parseOrigin(_ data: Data) throws -> String {
        guard data.count <= 1_048_576, String(data: data, encoding: .utf8) != nil else { throw Failure.invalid }
        let json = try self.removingCommentsAndTrailingCommas(data)
        guard let object = try? JSONSerialization.jsonObject(with: json),
              let fields = object as? [String: Any],
              WindowsJSONRootKeys.areUnique(in: json, maximumBytes: 1_048_576) else { throw Failure.invalid }
        func origin(_ key: String) throws -> String? {
            guard let value = fields[key] else { return nil }
            guard let text = value as? String else { throw Failure.invalid }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            guard let result = try? ZedManualCredentialInput.normalizedServiceOrigin(trimmed) else { throw Failure.invalid }
            return result
        }
        let server = try origin("server_url") ?? ZedStatusProbe.defaultKeychainServiceURL
        if let credentials = try origin("credentials_url"), credentials != server {
            // Current import bundles bind one origin to both the vault and the API.
            throw Failure.separateCredentialOrigin
        }
        return server
    }

    private static func removingCommentsAndTrailingCommas(_ data: Data) throws -> Data {
        var bytes = Array(data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        var index = 0
        var quoted = false
        var escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
                index += 1
                continue
            }
            if byte == 34 { quoted = true; index += 1; continue }
            if byte == 47, index + 1 < bytes.count, bytes[index + 1] == 47 {
                while index < bytes.count, bytes[index] != 10, bytes[index] != 13 {
                    bytes[index] = 32; index += 1
                }
                continue
            }
            if byte == 47, index + 1 < bytes.count, bytes[index + 1] == 42 {
                bytes[index] = 32; bytes[index + 1] = 32; index += 2
                var closed = false
                while index < bytes.count {
                    if bytes[index] == 42, index + 1 < bytes.count, bytes[index + 1] == 47 {
                        bytes[index] = 32; bytes[index + 1] = 32; index += 2; closed = true; break
                    }
                    bytes[index] = 32; index += 1
                }
                guard closed else { throw Failure.invalid }
                continue
            }
            index += 1
        }
        guard !quoted else { throw Failure.invalid }
        quoted = false; escaped = false
        for position in bytes.indices {
            let byte = bytes[position]
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 44 {
                var next = position + 1
                while next < bytes.count, [UInt8(32), 9, 10, 13].contains(bytes[next]) { next += 1 }
                if next < bytes.count, bytes[next] == 93 || bytes[next] == 125 { bytes[position] = 32 }
            }
        }
        return Data(bytes)
    }
}
#endif
