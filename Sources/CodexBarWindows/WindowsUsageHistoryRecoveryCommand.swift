#if os(Windows)
import CodexBarCore
import Foundation
import WinSDK

enum WindowsUsageHistoryRecoveryCommand {
    static func run(arguments: [String]) -> UINT? {
        guard let command = arguments.first,
              command.hasPrefix("--history-backup") || command.hasPrefix("--history-restore") else { return nil }
        if command == "--history-backup-help", arguments.count == 1 {
            self.write(self.help, to: .standardOutput)
            return 0
        }
        guard (command == "--history-backup" && arguments.count == 2) ||
            (command == "--history-restore-new" && arguments.count == 3) ||
            (command == "--history-restore-missing" && arguments.count == 4 &&
             arguments[3] == "--restore-to-current-history") else {
            self.write(self.help, to: .standardError)
            return UINT(ERROR_INVALID_PARAMETER)
        }
        do {
            let ownership = try WindowsApplicationInstance.acquireForSettingsRecovery()
            return try withExtendedLifetime(ownership) {
                if command == "--history-backup" {
                    let destination = try WindowsRecoveryFileAccess.explicitPath(arguments[1])
                    let count = try WindowsUsageHistoryRecovery.backup(to: destination)
                    self.write("Usage history backup saved (\(count) files). Keep the entire archive folder.\n" +
                        "Cost databases, external session logs and credentials are not included.\n", to: .standardOutput)
                } else {
                    let archive = try WindowsRecoveryFileAccess.explicitPath(arguments[1])
                    let destination = try WindowsRecoveryFileAccess.explicitPath(arguments[2])
                    if command == "--history-restore-new" {
                        let count = try WindowsUsageHistoryRecovery.restoreNew(from: archive, to: destination)
                        self.write("Usage history files prepared in the new folder (\(count) files); nothing was activated.\n",
                            to: .standardOutput)
                    } else {
                        let count = try WindowsUsageHistoryRecovery.restoreMissing(from: archive, operationDirectory: destination)
                        self.write("Usage history files published to previously absent targets (\(count) files).\n" +
                            "Existing histories were not merged or replaced. Application behavior has not been validated.\n",
                            to: .standardOutput)
                    }
                }
                return 0
            }
        } catch let failure as WindowsApplicationInstance.Failure {
            let message = switch failure {
            case .occupied: "Close CodexBar in every session before usage history recovery."
            case .windows, .invalidStorage: "Exclusive history recovery ownership could not be established."
            }
            self.write(message + "\n", to: .standardError)
            return failure.exitCode
        } catch let failure as WindowsUsageHistoryRecovery.Failure {
            let message = switch failure {
            case .invalidArchive: "The usage history archive is invalid, incomplete or unsupported."
            case .unsupportedEntries: "The source history directory contains unknown files or nonempty coordination files."
            case .tooLarge: "The supported history file count or total byte limit was exceeded."
            case .changed: "History input or archive bytes changed during the operation. Preserve partial output and retry separately."
            case .invalidDestination: "Use a new output outside the live CodexBar data root and outside the archive folder."
            case .destinationOccupied: "At least one target history file already exists. No replacement or merge was requested."
            case .partialRestore:
                "History restoration was interrupted or failed after publication began. Some target files may exist. " +
                "Keep the original archive and operation folder; no automatic rollback was performed."
            }
            self.write(message + "\n", to: .standardError)
            return UINT(ERROR_INVALID_DATA)
        } catch is WindowsConfigurationBackup.Failure {
            self.write("Windows profile protection could not open or create the history archive.\n", to: .standardError)
            return UINT(ERROR_INVALID_DATA)
        } catch {
            self.write("Usage history recovery failed. Inputs may be missing, busy or inaccessible.\n" +
                "Use local absolute paths, existing output parents and an ACL-supporting drive. " +
                "Partial output was preserved.\n", to: .standardError)
            return UINT(ERROR_GEN_FAILURE)
        }
    }

    private static func write(_ message: String, to handle: FileHandle) { handle.write(Data(message.utf8)) }

    private static let help = """
    CodexBarWindows --history-backup <new-archive-folder>
    CodexBarWindows --history-restore-new <archive-folder> <new-output-folder>
    CodexBarWindows --history-restore-missing <archive-folder> <new-operation-folder> --restore-to-current-history
    CodexBarWindows --history-backup-help

    Close CodexBar in all sessions first. This preserves plan-utilization-history/*.json and
    usage-history.jsonl at their current application data locations, including original account keys.
    It does not back up cost SQLite databases, external session logs, plugins or credential stores.
    Keep the whole encrypted archive folder, including history-manifest.cbhm. An archive without
    its final manifest is incomplete. The original Windows profile/keys are required for decryption.
    Restore-new writes an inactive file set to a new folder. Restore-missing explicitly writes
    to current history locations only if every target file in the archive is absent. Even an existing
    empty file or recovery marker blocks restoration.
    Restored histories use exact saved account keys only. Unassigned and legacy aliases are not
    automatically attached to a current account; explicit ownership review remains necessary.
    No account merging, identity rewriting, replacement, deletion or automatic rollback is performed.
    A partial restore can leave published targets; preserve the archive and operation records.
    Raw history content is preserved, not repaired or certified as readable by this app version.
    Limits: 1024 provider files plus pace history, 32 MiB per file, 512 MiB total raw bytes.
    Outputs must be new local paths outside the live data root; output parents must already exist.
    Keep archives outside package/install data that Windows may remove during uninstall.

    """
}
#endif
