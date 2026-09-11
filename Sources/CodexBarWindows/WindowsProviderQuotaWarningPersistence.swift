#if os(Windows)
import CodexBarCore

/// The provider-scoped values shown by the native quota-warning editor.
public struct WindowsProviderQuotaWarningEditorSnapshot: Sendable, Equatable {
    public let providerID: ProviderInstanceID
    public let session: WindowsProviderQuotaWarningLaneDraft
    public let weekly: WindowsProviderQuotaWarningLaneDraft

    public init(
        providerID: ProviderInstanceID,
        session: WindowsProviderQuotaWarningLaneDraft,
        weekly: WindowsProviderQuotaWarningLaneDraft)
    {
        self.providerID = providerID
        self.session = session
        self.weekly = weekly
    }
}

public enum WindowsProviderQuotaWarningLoadResult: Sendable {
    case loaded(WindowsProviderQuotaWarningEditorSnapshot)
    case providerMissing
    case shuttingDown
    case failed(String)
}

public enum WindowsProviderQuotaWarningSaveResult: Sendable {
    case saved(WindowsProviderQuotaWarningEditorSnapshot)
    case unchanged(WindowsProviderQuotaWarningEditorSnapshot)
    case providerMissing
    case shuttingDown
    case failed(String)
}
#endif
