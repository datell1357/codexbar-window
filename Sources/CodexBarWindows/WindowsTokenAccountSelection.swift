#if os(Windows)
import Foundation
import CodexBarCore

/// UI projection deliberately excludes credentials, organizations and workspace identifiers.
public struct WindowsTokenAccountSelectionSnapshot: Sendable, Equatable {
    public struct Account: Sendable, Equatable {
        public let id: UUID
        public let title: String
    }
    public let providerID: ProviderInstanceID
    public let accounts: [Account]
    public let selectedID: UUID?
    public let requiresManualSource: Bool
}

public struct WindowsTokenAccountSelectionRequest: Sendable {
    public let id: UUID
    public let providerID: ProviderInstanceID
    public let accountID: UUID
    public let expectedSelectedID: UUID?
}

public enum WindowsTokenAccountSelectionLoadResult: Sendable {
    case loaded(WindowsTokenAccountSelectionSnapshot)
    case unavailable
    case shuttingDown
    case failed
}

public enum WindowsTokenAccountSelectionSaveResult: Sendable {
    case saved
    case unchanged
    case refreshInProgress
    case staleSelection
    case unavailable
    case shuttingDown
    case failed
}
#endif
