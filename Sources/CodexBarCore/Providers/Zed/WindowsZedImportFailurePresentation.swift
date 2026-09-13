#if os(Windows)
import Foundation

/// Only known, fixed error messages may cross the import UI boundary.
public enum WindowsZedImportFailurePresentation {
    public static func message(for error: any Error) -> String {
        if error is CancellationError { return "The Zed editor import was cancelled." }
        if let failure = error as? ZedStatusProbeError {
            return failure.errorDescription ?? "The Zed account could not be verified."
        }
        if let failure = error as? WindowsZedEditorCredentialsReader.Failure {
            return failure.errorDescription ?? "The Zed editor credential could not be read."
        }
        if let failure = error as? WindowsZedEditorSettings.Failure {
            return failure.errorDescription ?? "The Zed editor settings could not be read."
        }
        if error is ZedManualCredentialInput.Failure {
            return "The Zed editor credential or server address has an unsupported format. Check the addresses and sign in again."
        }
        if let failure = error as? URLError {
            if failure.code == .cancelled { return "The Zed editor import was cancelled." }
            if failure.code == .timedOut { return "The Zed editor import timed out. Check connectivity and retry." }
        }
        return "The Zed editor account could not be verified. Check editor sign-in and server settings, then retry."
    }
}
#endif
