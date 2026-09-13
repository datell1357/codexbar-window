#if os(Windows)
import Foundation
import CodexBarCore

/// UI projection deliberately excludes credentials, organizations and workspace identifiers.
public struct WindowsTokenAccountSelectionSnapshot: Sendable, Equatable {
    public struct Account: Sendable, Equatable {
        public let id: UUID
        public let title: String
        public let labelRevision: String
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

/// The revision compares the stored label without passing its original text to the UI.
public struct WindowsTokenAccountRenameRequest: Sendable {
    public let providerID: ProviderInstanceID
    public let accountID: UUID
    public let expectedLabelRevision: String
    public let replacementLabel: String
}

public enum WindowsTokenAccountRenameResult: Sendable {
    case saved
    case unchanged
    case invalidLabel
    case staleAccount
    case refreshInProgress
    case unavailable
    case shuttingDown
    case failed
}

/// Contains a credential: never log, serialize for diagnostics, or pass this draft back to the UI.
public struct WindowsTokenAccountAddRequest: Sendable {
    public let providerID: ProviderInstanceID
    public let accountID: UUID
    public let label: String
    public let token: String
    public let usageScope: String?
    public let organizationID: String?
    public let workspaceID: String?
    public let expectedSelectedID: UUID?
}

enum WindowsAccountInputRules {
    static func credentialIssue(provider: UsageProvider?, token: String) -> String? {
        guard provider == .windsurf else { return nil }
        do { try WindsurfWebFetcher.validateManualSessionInput(token); return nil }
        catch {
            // Deliberately omit parser details and user input from native controls.
            return "Enter a complete Windsurf session bundle with sessionToken, auth1Token, accountID and primaryOrgID. Values must contain printable ASCII without spaces; the bundle must fit within 64 KiB."
        }
    }

    enum Field { case label, token, scope, organization, workspace }
    static func providerIssue(provider: UsageProvider, support: TokenAccountSupport,
                              scope: String?, organization: String?, workspace: String?) -> (Field, String)? {
        if scope != nil, !support.showsTeamModeControls {
            return (.scope, "This provider does not support a usage scope.")
        }
        if organization != nil, !support.showsOrganizationField && !support.showsTeamModeControls {
            return (.organization, "This provider does not support an organization ID.")
        }
        if workspace != nil, !support.showsTeamModeControls {
            return (.workspace, "This provider does not support a workspace ID.")
        }
        if provider == .zai {
            let effectiveScope = scope?.lowercased() ?? ZaiUsageScope.personal.rawValue
            guard let parsed = ZaiUsageScope(rawValue: effectiveScope) else {
                return (.scope, "Use personal or team for z.ai usage scope, or leave it empty for personal.")
            }
            if parsed == .team {
                if organization == nil { return (.organization, "z.ai team usage requires an Organization ID.") }
                if workspace == nil { return (.workspace, "z.ai team usage requires a Project ID.") }
            }
        }
        return nil
    }

    static func invalidField(label: String, token: String, scope: String?, organization: String?, workspace: String?) -> Field? {
        func safe(_ text: String, limit: Int) -> Bool {
            text.utf16.count <= limit && !text.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
        }
        if !safe(label, limit: 160) { return .label }
        if token.isEmpty || token.utf8.count > 65_536 || token.contains("\0") { return .token }
        for (field, value) in [(Field.scope, scope), (.organization, organization), (.workspace, workspace)] {
            if let value, !safe(value, limit: 512) { return field }
        }
        return nil
    }
}

public enum WindowsTokenAccountAddResult: Sendable {
    case saved(UUID)
    case alreadyAdded(UUID)
    case invalidInput
    case staleSelection
    case refreshInProgress
    case unavailable
    case shuttingDown
    case failed
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
/// Opaque, short-lived authorization to replace one saved credential. No old secret is exposed.
public enum WindowsTokenAccountCredentialLoadResult: Sendable {
    case loaded(ticketID: UUID, provider: UsageProvider)
    case unavailable
    case refreshInProgress
    case shuttingDown
    case failed
}

public enum WindowsTokenAccountCredentialSaveResult: Sendable {
    case saved
    case unchanged
    case invalidInput
    case staleAccount
    case refreshInProgress
    case shuttingDown
    case failed
}

/// Unchanged and clear are distinct, so editing one field preserves the others.
public enum WindowsTokenAccountFieldPatch: Sendable {
    case unchanged
    case replace(String?)
}

public struct WindowsTokenAccountMetadataPatch: Sendable {
    public let usageScope: WindowsTokenAccountFieldPatch
    public let organizationID: WindowsTokenAccountFieldPatch
    public let workspaceID: WindowsTokenAccountFieldPatch

    public init(usageScope: WindowsTokenAccountFieldPatch = .unchanged,
                organizationID: WindowsTokenAccountFieldPatch = .unchanged,
                workspaceID: WindowsTokenAccountFieldPatch = .unchanged) {
        self.usageScope = usageScope
        self.organizationID = organizationID
        self.workspaceID = workspaceID
    }
}

/// Account metadata is private UI data, not diagnostic output. Credentials are excluded.
public struct WindowsTokenAccountMetadataSnapshot: Sendable {
    public let ticketID: UUID
    public let provider: UsageProvider
    public let usageScope: String?
    public let organizationID: String?
    public let workspaceID: String?

    /// Preserve untouched legacy values exactly, including nil versus empty strings.
    public func patch(usageScope: String?, organizationID: String?, workspaceID: String?) -> WindowsTokenAccountMetadataPatch {
        .init(usageScope: usageScope == self.usageScope ? .unchanged : .replace(usageScope),
              organizationID: organizationID == self.organizationID ? .unchanged : .replace(organizationID),
              workspaceID: workspaceID == self.workspaceID ? .unchanged : .replace(workspaceID))
    }
}

public enum WindowsTokenAccountMetadataLoadResult: Sendable {
    case loaded(WindowsTokenAccountMetadataSnapshot)
    case unavailable
    case refreshInProgress
    case shuttingDown
    case failed
}

/// Removal confirmation includes a privacy-filtered label, never a credential.
public struct WindowsTokenAccountRemovalSnapshot: Sendable {
    public let ticketID: UUID
    public let provider: UsageProvider
    public let removesSelectedAccount: Bool
    public let remainingAccountCount: Int
    public let accountPosition: Int
    public let accountTitle: String
    public let hidePersonalInfo: Bool
}

public enum WindowsTokenAccountRemovalLoadResult: Sendable {
    case loaded(WindowsTokenAccountRemovalSnapshot)
    case unavailable
    case refreshInProgress
    case shuttingDown
    case failed
}

public enum WindowsTokenAccountRemovalSaveResult: Sendable {
    case removed
    case removedWithCacheCleanupFailure
    case staleAccount
    case refreshInProgress
    case shuttingDown
    case failed
}

#endif
