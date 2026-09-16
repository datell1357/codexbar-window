#if os(Windows)
import CodexBarCore
import Foundation
import WinSDK

enum WindowsLocalSettingsRecoveryCommand {
    private enum Failure: Error { case wrongScope, preferencesMayHaveChanged }

    private struct Record: Encodable {
        let schemaVersion = 1
        let operationID: UUID
        let backupID: UUID
        let status: String
        let recordedAt = Date()
        let configurationPresent: Bool
        let widgetsPresent: Bool
        let runtimeValidation = "NOT_RUN"
    }

    static func run(arguments: [String]) -> UINT? {
        guard let command = arguments.first, command.hasPrefix("--settings-backup") ||
            command.hasPrefix("--settings-restore") else { return nil }
        if command == "--settings-backup-help", arguments.count == 1 {
            self.write(self.help, to: .standardOutput)
            return 0
        }
        guard (command == "--settings-backup" && arguments.count == 2) ||
            (command == "--settings-restore-new" && arguments.count == 3) ||
            (command == "--settings-restore-preferences" && arguments.count == 4 &&
             arguments[3] == "--replace-current-preferences") else {
            self.write(self.help, to: .standardError)
            return UINT(ERROR_INVALID_PARAMETER)
        }
        do {
            // No defaults object or app runtime is constructed before exclusive ownership succeeds.
            let ownership = try WindowsApplicationInstance.acquireForSettingsRecovery()
            return try withExtendedLifetime(ownership) {
                if command == "--settings-backup" {
                    let destination = try WindowsRecoveryFileAccess.explicitPath(arguments[1])
                    let archive = try WindowsLocalSettingsBackup.encode(WindowsLocalSettingsBackup.capture())
                    try WindowsRecoveryFileAccess.publish(archive, to: destination)
                    self.write("Local settings backup saved: config, Windows preferences and widget configuration.\n" +
                        "History, plugin files/approvals and OS credential stores are not included.\n", to: .standardOutput)
                } else {
                    let source = try WindowsRecoveryFileAccess.explicitPath(arguments[1])
                    let destination = try WindowsRecoveryFileAccess.explicitPath(arguments[2])
                    let bytes = try WindowsRecoveryFileAccess.read(source, limit: WindowsLocalSettingsBackup.maximumArchiveBytes)
                    let snapshot = try WindowsLocalSettingsBackup.decode(bytes)
                    if command == "--settings-restore-new" {
                        guard snapshot.scope == .localSettings else { throw Failure.wrongScope }
                        try self.materialize(snapshot, at: destination)
                        self.write("Settings files saved in the new folder. No config or preferences were activated.\n" +
                            "Use --settings-restore-preferences for the separate, explicit preference replacement.\n",
                            to: .standardOutput)
                    } else {
                        try self.restorePreferences(snapshot, recoveryDirectory: destination)
                        self.write("Windows preferences were restored and read back. The previous preferences are backed up\n" +
                            "in the recovery folder. Config files and Windows-managed widget placement were not changed.\n",
                            to: .standardOutput)
                    }
                }
                return 0
            }
        } catch let failure as WindowsApplicationInstance.Failure {
            let message = switch failure {
            case .occupied: "Close CodexBar in every session before backing up or restoring local settings."
            case .windows, .invalidStorage: "Exclusive settings ownership could not be established."
            }
            self.write(message + "\n", to: .standardError)
            return failure.exitCode
        } catch Failure.preferencesMayHaveChanged {
            self.write("Preference restoration did not finish. Preferences may already have changed.\n" +
                "Keep the recovery folder and its previous-preferences.cbsbak; do not assume rollback occurred.\n",
                to: .standardError)
            return UINT(ERROR_GEN_FAILURE)
        } catch Failure.wrongScope {
            self.write("This archive contains preference recovery only, not a local settings file set.\n", to: .standardError)
            return UINT(ERROR_INVALID_DATA)
        } catch let failure as WindowsLocalSettingsBackup.Failure {
            let message = switch failure {
            case .invalidSnapshot: "The settings archive is invalid, incomplete or outside the supported bounds."
            case .unsupportedVersion: "The settings archive version is not supported."
            case .invalidPreferences: "The preferences contain unsupported or oversized property-list values."
            case .preferencesUnavailable: "The current Windows preferences could not be read or synchronized."
            case .changed: "Settings changed during collection. Close other writers and retry with a new output path."
            }
            self.write(message + "\n", to: .standardError)
            return UINT(ERROR_INVALID_DATA)
        } catch is WindowsConfigurationBackup.Failure {
            self.write("The config/protection format could not be recovered in this Windows profile.\n", to: .standardError)
            return UINT(ERROR_INVALID_DATA)
        } catch {
            self.write("Settings recovery failed. Use readable local inputs and an unused output on an ACL-supporting drive.\n" +
                "Any partial recovery folder was preserved; no completed result should be inferred.\n", to: .standardError)
            return UINT(ERROR_GEN_FAILURE)
        }
    }

    private static func materialize(_ snapshot: WindowsLocalSettingsBackup.Snapshot, at directory: URL) throws {
        let configuration = try snapshot.configuration.map { try WindowsConfigurationBackup.protectedConfiguration($0) }
        // Keep an encrypted preferences-only archive, not a plaintext export of paths/unknown fields.
        let preferences = try WindowsLocalSettingsBackup.encode(.init(scope: .preferencesRecovery,
            preferences: snapshot.preferences))
        try WindowsRecoveryFileAccess.withNewDirectory(directory) {
            if let configuration {
                try WindowsRecoveryFileAccess.publish(configuration, to: directory.appendingPathComponent("config.json"))
            }
            if let widgets = snapshot.widgets {
                let widgetDirectory = directory.appendingPathComponent("WindowsWidgets", isDirectory: true)
                try WindowsRecoveryFileAccess.withNewDirectory(widgetDirectory) {
                    try WindowsRecoveryFileAccess.publish(widgets, to: widgetDirectory.appendingPathComponent("settings.json"))
                }
            }
            try WindowsRecoveryFileAccess.publish(preferences, to: directory.appendingPathComponent("preferences.cbsbak"))
            let record = Record(operationID: UUID(), backupID: snapshot.backupID,
                status: "FILES_MATERIALIZED_NOT_ACTIVATED", configurationPresent: snapshot.configuration != nil,
                widgetsPresent: snapshot.widgets != nil)
            try WindowsRecoveryFileAccess.publish(JSONEncoder().encode(record),
                to: directory.appendingPathComponent("settings-materialization.json"))
        }
    }

    private static func restorePreferences(_ snapshot: WindowsLocalSettingsBackup.Snapshot,
                                           recoveryDirectory: URL) throws {
        let target = try WindowsLocalSettingsBackup.preferencesDomain(snapshot.preferences)
        let before = try WindowsLocalSettingsBackup.capturePreferences()
        let previous = try WindowsLocalSettingsBackup.encode(.init(scope: .preferencesRecovery, preferences: before))
        let proposed = try WindowsLocalSettingsBackup.encode(.init(scope: .preferencesRecovery,
            preferences: snapshot.preferences))
        let changed = !(try WindowsLocalSettingsBackup.samePreferences(before, snapshot.preferences))
        guard let defaults = UserDefaults(suiteName: WindowsRefreshSettings.suiteName) else {
            throw WindowsLocalSettingsBackup.Failure.preferencesUnavailable
        }
        try WindowsRecoveryFileAccess.withNewDirectory(recoveryDirectory) {
            let operationID = UUID()
            try WindowsRecoveryFileAccess.publish(previous,
                to: recoveryDirectory.appendingPathComponent("previous-preferences.cbsbak"))
            try WindowsRecoveryFileAccess.publish(proposed,
                to: recoveryDirectory.appendingPathComponent("target-preferences.cbsbak"))
            let prepared = Record(operationID: operationID, backupID: snapshot.backupID,
                status: "PREFERENCES_RESTORE_PREPARED", configurationPresent: false, widgetsPresent: false)
            try WindowsRecoveryFileAccess.publish(JSONEncoder().encode(prepared),
                to: recoveryDirectory.appendingPathComponent("preferences-restore-prepared.json"))
            // Catch changes from tools/old app versions that do not participate in profile ownership.
            // This comparison cannot turn UserDefaults' per-key replacement into an atomic transaction.
            guard try WindowsLocalSettingsBackup.samePreferences(before, WindowsLocalSettingsBackup.capturePreferences()) else {
                throw WindowsLocalSettingsBackup.Failure.preferencesUnavailable
            }
            var mutationStarted = false
            do {
                if changed {
                    mutationStarted = true
                    defaults.setPersistentDomain(target, forName: WindowsRefreshSettings.suiteName)
                }
                guard defaults.synchronize(),
                      try WindowsLocalSettingsBackup.samePreferences(snapshot.preferences,
                          WindowsLocalSettingsBackup.capturePreferences()) else {
                    throw Failure.preferencesMayHaveChanged
                }
                let completed = Record(operationID: operationID, backupID: snapshot.backupID,
                    status: changed ? "PREFERENCES_WRITTEN_AND_READ_BACK" : "PREFERENCES_ALREADY_MATCHED",
                    configurationPresent: false, widgetsPresent: false)
                try WindowsRecoveryFileAccess.publish(JSONEncoder().encode(completed),
                    to: recoveryDirectory.appendingPathComponent("preferences-restore-completed.json"))
            } catch {
                if mutationStarted { throw Failure.preferencesMayHaveChanged }
                throw error
            }
        }
    }

    private static func write(_ message: String, to handle: FileHandle) { handle.write(Data(message.utf8)) }

    private static let help = """
    CodexBarWindows --settings-backup <new-backup-file>
    CodexBarWindows --settings-restore-new <backup-file> <new-settings-folder>
    CodexBarWindows --settings-restore-preferences <backup-file> <new-recovery-folder> --replace-current-preferences
    CodexBarWindows --settings-backup-help

    Close CodexBar in all sessions first. Local settings are encrypted for the original Windows
    profile; this is not a device migration or a backup of history, plugin files/approvals or OS credentials.
    Local settings include the selected config, CodexBar.Windows preferences and WindowsWidgets/settings.json.
    Restore-new writes a new folder only. It does not change running apps or select an active config.
    Select its config.json with CODEXBAR_CONFIG on the next launch, if that file was present in the backup.
    Restore-preferences replaces the saved preference domain, including local paths and unknown keys.
    It first saves previous-preferences.cbsbak in the new recovery folder. A failed or interrupted
    replacement can leave partial preferences; use that backup with a fresh recovery folder to restore them.
    File restoration and preference replacement are separate operations, not one atomic transaction.
    Windows-managed widget placement is not restored. Keep backups outside package/install data.
    All explicit paths must be absolute local paths; output parents must exist and outputs must be new.

    """
}
#endif
