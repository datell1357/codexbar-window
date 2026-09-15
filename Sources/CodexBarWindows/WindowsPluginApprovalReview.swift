#if os(Windows)
import CodexBarCore
import Foundation

public struct WindowsPluginApprovalReview: Sendable {
    let token: UUID
    let instanceID: ProviderInstanceID
    let name: String
    let sourceHash: String
    let binding: ProviderPluginApprovalBinding
    let previousBinding: ProviderPluginApprovalBinding?
    let alreadyApproved: Bool
    let approvalAvailable: Bool
    let isEnabled: Bool?
    // Local-only review provenance; never include in a clipboard or diagnostic summary.
    let fileURL: URL?
}

enum WindowsPluginApprovalFailure: Error {
    case unavailable, busy, missingPlugin, changed, confirmationRequired
}
public enum WindowsPluginApprovalReply: Sendable {
    case review(WindowsPluginApprovalReview)
    case settings(WindowsPluginSettingsSnapshot)
    case saved
    case installed
    case installFailed(WindowsPluginInstallFailure)
    case removal(WindowsPluginRemovalReview)
    case removed
    case failedFileRemoved
    case removalFailed(WindowsPluginRemovalFailure)
    case replacement(WindowsPluginReplacementReview)
    case replaced
    case reinstalled
    case restoredBackup
    case replacementFailed(WindowsPluginReplacementFailure)
    case failed
}
#endif
