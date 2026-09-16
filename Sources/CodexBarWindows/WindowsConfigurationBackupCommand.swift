#if os(Windows)
import CodexBarCore
import Foundation
import WinSDK

/// Runs before tray/runtime construction. Recovery always publishes a new file and never activates it.
enum WindowsConfigurationBackupCommand {
    private enum Failure: Error { case invalidPath, unavailableInput, invalidInput, unavailableOutput }

    static func run(arguments: [String]) -> UINT? {
        guard let command = arguments.first,
              command.hasPrefix("--config-backup") || command.hasPrefix("--config-restore") else {
            return nil
        }
        if command == "--config-backup-help", arguments.count == 1 {
            self.write(self.help, to: .standardOutput)
            return 0
        }
        guard (command == "--config-backup" && arguments.count == 2) ||
            (command == "--config-restore-new" && arguments.count == 3) else {
            self.write(self.help, to: .standardError)
            return UINT(ERROR_INVALID_PARAMETER)
        }
        do {
            if command == "--config-backup" {
                let source = CodexBarConfigStore.defaultURL()
                let destination = try self.explicitPath(arguments[1])
                let bytes = try self.read(source, limit: WindowsConfigurationBackup.maximumConfigurationBytes)
                let archive = try WindowsConfigurationBackup.archive(storedConfiguration: bytes)
                try self.publish(archive, to: destination)
                self.write("Configuration-only backup saved. Other settings, history and credential stores are not included.\n",
                           to: .standardOutput)
            } else {
                let source = try self.explicitPath(arguments[1])
                let destination = try self.explicitPath(arguments[2])
                let bytes = try self.read(source, limit: WindowsConfigurationBackup.maximumArchiveBytes)
                let restored = try WindowsConfigurationBackup.restore(bytes)
                try self.publish(restored.storedData, to: destination)
                self.write("Configuration restored to the new file. It was not activated; no running app was changed.\n",
                           to: .standardOutput)
            }
            return 0
        } catch let failure as WindowsConfigurationBackup.Failure {
            let message: String
            switch failure {
            case .invalidConfiguration: message = "The configuration is invalid or exceeds the supported size."
            case .unsupportedVersion: message = "The configuration schema is not supported by this version."
            case .invalidArchive: message = "The backup is invalid, incomplete or exceeds the supported size."
            case .protectionUnavailable:
                message = "Windows profile protection is unavailable. Use the original Windows profile and recovery keys."
            }
            self.write(message + "\n", to: .standardError)
            return UINT(ERROR_INVALID_DATA)
        } catch let failure as Failure {
            let message: String
            switch failure {
            case .invalidPath: message = "Use a local absolute file path with existing regular parent directories."
            case .unavailableInput: message = "The input file is missing, busy or inaccessible."
            case .invalidInput: message = "The input must be one nonempty regular file within the supported size."
            case .unavailableOutput:
                message = "The output could not be saved. Choose an unused path on a drive supporting private file permissions."
            }
            self.write(message + "\n", to: .standardError)
            return UINT(ERROR_GEN_FAILURE)
        } catch {
            // Never print Foundation/JSON/DPAPI diagnostics containing paths, tokens or config values.
            self.write("Configuration recovery failed; no successful result was recorded.\n", to: .standardError)
            return UINT(ERROR_GEN_FAILURE)
        }
    }

    private static func explicitPath(_ text: String) throws -> URL {
        _ = try self.pathComponents(text)
        return URL(fileURLWithPath: text)
    }

    /// Reject UNC/device paths, streams, common DOS aliases, reserved names and traversal components.
    private static func pathComponents(_ path: String) throws -> (root: String, components: [String]) {
        let text = path.replacingOccurrences(of: "/", with: "\\")
        let units = Array(text.utf16)
        guard units.count >= 4, units.count < 32700,
              (65...90).contains(Int(units[0])) || (97...122).contains(Int(units[0])),
              units[1] == 58, units[2] == 92 else { throw Failure.invalidPath }
        let parts = text.dropFirst(3).split(separator: "\\", omittingEmptySubsequences: false).map(String.init)
        let reserved = Set(["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"] +
                           (1...9).flatMap { ["COM\($0)", "LPT\($0)"] } +
                           ["COM¹", "COM²", "COM³", "LPT¹", "LPT²", "LPT³"])
        for part in parts {
            guard !part.isEmpty, part != ".", part != "..", !part.hasSuffix("."), !part.hasSuffix(" "),
                  !part.unicodeScalars.contains(where: { $0.value < 32 || "<>:\"|?*".unicodeScalars.contains($0) }),
                  !reserved.contains(String(part.split(separator: ".").first ?? "").uppercased()) else {
                throw Failure.invalidPath
            }
        }
        return (String(text.prefix(3)), parts)
    }

    private static func withPinnedParents<T>(_ url: URL, body: () throws -> T) throws -> T {
        guard url.isFileURL else { throw Failure.invalidPath }
        let (root, components) = try self.pathComponents(url.path)
        let drive = root.withCString(encodedAs: UTF16.self) { GetDriveTypeW($0) }
        guard drive == UINT(DRIVE_FIXED) || drive == UINT(DRIVE_REMOVABLE) else { throw Failure.invalidPath }
        var handles: [HANDLE] = []
        defer { for handle in handles.reversed() { CloseHandle(handle) } }
        var path = root
        for component in [""] + Array(components.dropLast()) {
            if !component.isEmpty { path += (path.hasSuffix("\\") ? "" : "\\") + component }
            let opened = path.withCString(encodedAs: UTF16.self) {
                CreateFileW($0, DWORD(FILE_READ_ATTRIBUTES), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE), nil,
                            DWORD(OPEN_EXISTING), DWORD(FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT), nil)
            }
            guard let handle = opened, handle != INVALID_HANDLE_VALUE else { throw Failure.invalidPath }
            handles.append(handle)
            var info = BY_HANDLE_FILE_INFORMATION()
            guard GetFileType(handle) == DWORD(FILE_TYPE_DISK), GetFileInformationByHandle(handle, &info) != 0,
                  info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0,
                  info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) == 0 else {
                throw Failure.invalidPath
            }
        }
        return try body()
    }

    private static func read(_ url: URL, limit: Int) throws -> Data {
        try self.withPinnedParents(url) {
            let opened = url.path.withCString(encodedAs: UTF16.self) {
                CreateFileW($0, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ), nil, DWORD(OPEN_EXISTING),
                            DWORD(FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT), nil)
            }
            guard let handle = opened, handle != INVALID_HANDLE_VALUE else { throw Failure.unavailableInput }
            defer { CloseHandle(handle) }
            var info = BY_HANDLE_FILE_INFORMATION()
            guard GetFileType(handle) == DWORD(FILE_TYPE_DISK), GetFileInformationByHandle(handle, &info) != 0,
                  info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) == 0,
                  info.nNumberOfLinks == 1, info.nFileSizeHigh == 0,
                  info.nFileSizeLow > 0, UInt64(info.nFileSizeLow) <= UInt64(limit) else { throw Failure.invalidInput }
            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                var count: DWORD = 0
                let requested = min(buffer.count, limit - result.count + 1)
                let succeeded = buffer.withUnsafeMutableBytes {
                    ReadFile(handle, $0.baseAddress, DWORD(requested), &count, nil)
                }
                guard succeeded != 0 else { throw Failure.unavailableInput }
                if count == 0 { break }
                guard Int(count) <= requested, Int(count) <= limit - result.count else { throw Failure.invalidInput }
                result.append(contentsOf: buffer.prefix(Int(count)))
            }
            guard result.count == Int(info.nFileSizeLow) else { throw Failure.invalidInput }
            return result
        }
    }

    private static func publish(_ bytes: Data, to destination: URL) throws {
        try self.withPinnedParents(destination) {
            do { try WindowsCredentialFileWriter.writePrivate(bytes, to: destination, publication: .createNew) }
            catch { throw Failure.unavailableOutput }
        }
    }

    private static func write(_ message: String, to handle: FileHandle) {
        handle.write(Data(message.utf8))
    }

    private static let help = """
    CodexBarWindows --config-backup <new-backup-file>
    CodexBarWindows --config-restore-new <backup-file> <new-config-file>
    CodexBarWindows --config-backup-help

    Configuration-file recovery only. Backup reads the normal CODEXBAR_CONFIG / XDG_CONFIG_HOME /
    local app-data config selection; it does not create a missing config or start the app.
    This includes provider configuration, its saved credentials and hook configuration.
    Other preferences, widgets, plugins, history and Windows Credential Manager are not backed up.
    The whole backup is encrypted for the original Windows profile; this is not a device migration.
    Use absolute local paths and existing parent directories. Outputs must not already exist.
    Keep the backup outside package/install data that Windows may remove during uninstall.
    Restore writes a new config with protected secrets. To use it, close CodexBar and explicitly
    select that file with CODEXBAR_CONFIG before the next launch. Other settings are not activated.

    """
}
#endif
