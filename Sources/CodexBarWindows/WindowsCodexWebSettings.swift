#if os(Windows)
import CodexBarCore

/// The value-only Codex web settings shown by the native Windows editor.
/// The manual cookie itself is deliberately never exposed in a snapshot.
public struct WindowsCodexWebSettingsSnapshot: Sendable, Equatable {
    public let sourceMode: ProviderSourceMode
    public let cookieSource: ProviderCookieSource
    public let hasStoredManualHeader: Bool

    public init(
        sourceMode: ProviderSourceMode,
        cookieSource: ProviderCookieSource,
        hasStoredManualHeader: Bool)
    {
        self.sourceMode = sourceMode
        self.cookieSource = cookieSource
        self.hasStoredManualHeader = hasStoredManualHeader
    }
}

/// Secret mutations supported by the Windows editor. There is intentionally no
/// clear case in this slice; turning cookies off leaves the stored secret intact.
public enum WindowsCodexWebSettingsSecretPatch: Sendable, Equatable {
    case unchanged
    case replace(String)
}

public typealias WindowsCodexWebSettingsManualHeaderPatch = WindowsCodexWebSettingsSecretPatch

public struct WindowsCodexWebSettingsPatch: Sendable, Equatable {
    /// Nil preserves the stored source mode.
    public let sourceMode: ProviderSourceMode?
    /// Nil preserves the stored cookie source.
    public let cookieSource: ProviderCookieSource?
    public let manualHeader: WindowsCodexWebSettingsSecretPatch

    public var manualCookieHeader: WindowsCodexWebSettingsSecretPatch {
        self.manualHeader
    }

    public init(
        sourceMode: ProviderSourceMode? = nil,
        cookieSource: ProviderCookieSource? = nil,
        manualHeader: WindowsCodexWebSettingsSecretPatch = .unchanged)
    {
        self.sourceMode = sourceMode
        self.cookieSource = cookieSource
        self.manualHeader = manualHeader
    }

    public init(
        sourceMode: ProviderSourceMode? = nil,
        cookieSource: ProviderCookieSource? = nil,
        manualCookieHeader: WindowsCodexWebSettingsSecretPatch)
    {
        self.init(sourceMode: sourceMode, cookieSource: cookieSource, manualHeader: manualCookieHeader)
    }

    public var isUnchanged: Bool {
        self.sourceMode == nil && self.cookieSource == nil && self.manualHeader == .unchanged
    }
}

public enum WindowsCodexWebSettingsLoadResult: Sendable {
    case loaded(WindowsCodexWebSettingsSnapshot)
    case providerMissing
    case shuttingDown
    case failed(String)
}

public enum WindowsCodexWebSettingsSaveResult: Sendable {
    case saved(WindowsCodexWebSettingsSnapshot)
    case unchanged(WindowsCodexWebSettingsSnapshot)
    case providerMissing
    case shuttingDown
    case failed(String)
}
#endif
