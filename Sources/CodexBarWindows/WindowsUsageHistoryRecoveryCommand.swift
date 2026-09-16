#if os(Windows)
import CodexBarCore
import Foundation
import WinSDK

enum WindowsUsageHistoryRecoveryCommand {
    static func run(arguments: [String]) -> UINT? {
        guard let command = arguments.first,
              command.hasPrefix("--history-backup") || command.hasPrefix("--history-restore") ||
              command.hasPrefix("--history-resume") else { return nil }
        if command == "--history-backup-help", arguments.count == 1 {
            self.write(self.help, to: .standardOutput)
            return 0
        }
        guard (command == "--history-backup" && arguments.count == 2) ||
            (command == "--history-restore-new" && arguments.count == 3) ||
            (command == "--history-restore-missing" && arguments.count == 4 &&
             arguments[3] == "--restore-to-current-history") ||
            (command == "--history-resume" && arguments.count == 5 &&
             UUID(uuidString: arguments[3]) != nil && arguments[4] == "--resume-missing-history") else {
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
                    } else if command == "--history-restore-missing" {
                        let result = try WindowsUsageHistoryRecovery.restoreMissing(from: archive, operationDirectory: destination)
                        self.write("Usage history files published to previously absent targets (\(result.publishedFiles) files).\n" +
                            "Operation ID: \(result.operationID.uuidString.lowercased())\n" +
                            "Existing histories were not merged or replaced. Application behavior has not been validated.\n",
                            to: .standardOutput)
                    } else {
                        guard let operationID = UUID(uuidString: arguments[3]) else {
                            throw WindowsUsageHistoryRecovery.Failure.invalidOperation
                        }
                        let result = try WindowsUsageHistoryRecovery.resumeMissing(from: archive,
                            operationDirectory: destination, operationID: operationID)
                        let status = result.alreadyCompleted ? "Already completed; current files reconciled." : "History restoration reconciled."
                        self.write(status + "\nOperation ID: \(result.operationID.uuidString.lowercased())\n" +
                            "Newly published: \(result.publishedFiles); matching existing files: \(result.reconciledFiles).\n" +
                            "Account ownership and application behavior have not been validated.\n",
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
            case .changed: "History input or archive bytes changed during the operation. Preserve partial output and review the operation records."
            case .invalidDestination: "Use a new output outside the live CodexBar data root and outside the archive folder."
            case .destinationOccupied: "At least one target history file already exists. No replacement or merge was requested."
            case .invalidOperation:
                "The selected restore operation is unsupported, incomplete, changed or bound to different history locations. " +
                "Resume requires version 2 records and the original operation ID and archive. Preserve all records."
            case .restoredFileChanged:
                "A restored file or its ownership marker differs from the original operation, or a previously published file is missing. " +
                "No replacement or resurrection was authorized. Preserve the archive and current files for separate recovery."
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
    CodexBarWindows --history-resume <archive-folder> <operation-folder> <operation-uuid> --resume-missing-history
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
    Resume requires the original version 2 prepared record, protected plan, archive and operation UUID.
    Matching existing files and markers are reconciled. Changed files or known published files that
    were later deleted block resume. Missing unrecorded targets require the explicit resume flag.
    Keep all per-entry and per-attempt records. Version 1 restore operations cannot be resumed here.
    No account merging, identity rewriting, replacement, deletion or automatic rollback is performed.
    A partial restore can leave published targets; preserve the archive and operation records.
    Raw history content is preserved, not repaired or certified as readable by this app version.
    Limits: 1024 provider files plus pace history, 32 MiB per file, 512 MiB total raw bytes.
    New outputs must be local paths outside the live data root; output parents must already exist.
    Resume uses the existing operation folder and keeps earlier records unchanged.
    Keep archives outside package/install data that Windows may remove during uninstall.

    """
}
#endif
