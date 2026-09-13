#if os(Windows)
import Foundation
import WinSDK

/// Unpackaged per-user registration only. Does not alter StartupApproved or machine policy.
enum WindowsStartupRegistration {
    enum State: Equatable { case absent, registered, conflict, unavailable }
    enum Failure: Error { case unavailable, conflict }
    private static let runKey = "Software\\Microsoft\\Windows\\CurrentVersion\\Run"
    private static let valueName = "CodexBarWindows"

    private static func command() throws -> String {
        var path = [UInt16](repeating: 0, count: 32768)
        let count = GetModuleFileNameW(nil, &path, DWORD(path.count))
        guard count > 0, count < DWORD(path.count) else { throw Failure.unavailable }
        let text = String(decoding: path.prefix(Int(count)), as: UTF16.self)
        guard text.lowercased().hasSuffix(".exe"), !text.contains("\""),
              !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              text.utf16.count + 2 < 260 else { throw Failure.unavailable }
        return "\"" + text + "\""
    }

    private static func read(_ key: HKEY) throws -> String? {
        var type: DWORD = 0
        var size: DWORD = 0
        let result = valueName.withCString(encodedAs: UTF16.self) {
            RegQueryValueExW(key, $0, nil, &type, nil, &size)
        }
        if result == ERROR_FILE_NOT_FOUND { return nil }
        guard result == ERROR_SUCCESS, type == DWORD(REG_SZ), size >= 2, size <= 1024, size % 2 == 0
        else { throw Failure.conflict }
        var units = [UInt16](repeating: 0, count: Int(size / 2))
        let fetched = valueName.withCString(encodedAs: UTF16.self) { name in
            units.withUnsafeMutableBytes { raw in
                RegQueryValueExW(key, name, nil, &type, raw.baseAddress?.assumingMemoryBound(to: BYTE.self), &size)
            }
        }
        guard fetched == ERROR_SUCCESS, type == DWORD(REG_SZ), size >= 2, size % 2 == 0,
              Int(size / 2) <= units.count else { throw Failure.unavailable }
        let content = units.prefix(Int(size / 2))
        guard content.last == 0, !content.dropLast().contains(0) else { throw Failure.conflict }
        return String(decoding: content.dropLast(), as: UTF16.self)
    }

    static func state() -> State {
        do {
            let expected = try self.command()
            var key: HKEY?
            let opened = runKey.withCString(encodedAs: UTF16.self) {
                RegOpenKeyExW(HKEY_CURRENT_USER, $0, 0, REGSAM(KEY_QUERY_VALUE), &key)
            }
            if opened == ERROR_FILE_NOT_FOUND { return .absent }
            guard opened == ERROR_SUCCESS, let key else { return .unavailable }
            defer { RegCloseKey(key) }
            guard let existing = try self.read(key) else { return .absent }
            return existing == expected ? .registered : .conflict
        } catch Failure.conflict { return .conflict }
        catch { return .unavailable }
    }

    static func setRegistered(_ enabled: Bool) throws {
        let expected = try self.command()
        var key: HKEY?
        let opened = runKey.withCString(encodedAs: UTF16.self) {
            RegCreateKeyExW(HKEY_CURRENT_USER, $0, 0, nil, DWORD(REG_OPTION_NON_VOLATILE),
                            REGSAM(KEY_QUERY_VALUE | KEY_SET_VALUE), nil, &key, nil)
        }
        guard opened == ERROR_SUCCESS, let key else { throw Failure.unavailable }
        defer { RegCloseKey(key) }
        let existing = try self.read(key)
        guard existing == nil || existing == expected else { throw Failure.conflict }
        if enabled {
            guard existing == nil else { return }
            let units = Array(expected.utf16) + [0]
            let result = valueName.withCString(encodedAs: UTF16.self) { name in
                units.withUnsafeBytes {
                    RegSetValueExW(key, name, 0, DWORD(REG_SZ), $0.baseAddress?.assumingMemoryBound(to: BYTE.self), DWORD($0.count))
                }
            }
            guard result == ERROR_SUCCESS else { throw Failure.unavailable }
        } else if existing != nil {
            let result = valueName.withCString(encodedAs: UTF16.self) { RegDeleteValueW(key, $0) }
            guard result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND else { throw Failure.unavailable }
        }
    }
}
#endif
