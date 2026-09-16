#if os(Windows)
import CodexBarCore
import Foundation
import WinSDK

/// Runs before tray/runtime construction. Recovery always publishes a new file and never activates it.
enum WindowsConfigurationBackupCommand {
    private typealias Failure = WindowsRecoveryFileAccess.Failure

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
                let destination = try WindowsRecoveryFileAccess.explicitPath(arguments[1])
                let bytes = try WindowsRecoveryFileAccess.read(source, limit: WindowsConfigurationBackup.maximumConfigurationBytes)
                let archive = try WindowsConfigurationBackup.archive(storedConfiguration: bytes)
                try WindowsRecoveryFileAccess.publish(archive, to: destination)
                self.write("Configuration-only backup saved. Other settings, history and credential stores are not included.\n",
                           to: .standardOutput)
            } else {
                let source = try WindowsRecoveryFileAccess.explicitPath(arguments[1])
                let destination = try WindowsRecoveryFileAccess.explicitPath(arguments[2])
                let bytes = try WindowsRecoveryFileAccess.read(source, limit: WindowsConfigurationBackup.maximumArchiveBytes)
                let restored = try WindowsConfigurationBackup.restore(bytes)
                try WindowsRecoveryFileAccess.publish(restored.storedData, to: destination)
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
            case .missingInput, .unavailableInput: message = "The input file is missing, busy or inaccessible."
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
