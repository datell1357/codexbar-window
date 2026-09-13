#if os(Windows)
import Foundation

/// Explicit import backend. The caller owns confirmation and protected persistence.
public struct WindowsZedEditorSessionImporter: Sendable {
    public struct ValidatedAccount: Sendable {
        public let userID: String
        public let snapshot: ZedUsageSnapshot
        /// Secret material: pass only to the protected account store, never to display or logging.
        public let credentialBundle: String
        public let serviceURL: String
        public let credentialServiceURL: String
    }

    private let reader: any ZedCredentialsReading

    public init() { self.reader = WindowsZedEditorCredentialsReader() }

    init(reader: any ZedCredentialsReading) { self.reader = reader }

    public func loadAndValidate(
        serviceURL: String = ZedStatusProbe.defaultKeychainServiceURL,
        credentialServiceURL: String? = nil,
        transport: (any ProviderHTTPTransport)? = nil) async throws -> ValidatedAccount
    {
        try Task.checkCancellation()
        let origin = try ZedManualCredentialInput.normalizedServiceOrigin(serviceURL)
        let credentialOrigin = try ZedManualCredentialInput.normalizedServiceOrigin(credentialServiceURL ?? origin)
        let settings = ZedClientSettings(credentialsURL: credentialOrigin, serverURL: origin)
        // Apply the shared trust rule before opening the vault, not just before sending the token.
        guard settings.cloudAPIURL != nil else { throw ZedStatusProbeError.untrustedServerConfiguration }
        let reader = self.reader
        let readTask = Task.detached {
            try Task.checkCancellation()
            let credentials = try reader.loadCredentials(serviceURL: credentialOrigin)
            try Task.checkCancellation()
            return credentials
        }
        let credentials = try await withTaskCancellationHandler {
            try await readTask.value
        } onCancel: {
            readTask.cancel()
        }
        try Task.checkCancellation()
        guard let credentials else { throw ZedStatusProbeError.notSignedIn }
        let bundle = credentials.userID + " " + credentials.accessToken + " " + origin
        let parsed = try ZedManualCredentialInput.bundle(bundle)
        let pinnedReader = PinnedReader(credentials: parsed.credentials, serviceURL: credentialOrigin)
        // Probe and saved bundle use this one captured credential, even if the editor switches accounts.
        let snapshot = try await ZedStatusProbe(credentialsReader: pinnedReader, transport: transport,
            settingsLoader: { settings }).fetch()
        try Task.checkCancellation()
        return ValidatedAccount(userID: parsed.credentials.userID, snapshot: snapshot,
            credentialBundle: parsed.credentials.userID + " " + parsed.credentials.accessToken + " " + parsed.serviceURL,
            serviceURL: parsed.serviceURL, credentialServiceURL: credentialOrigin)
    }

    private struct PinnedReader: ZedCredentialsReading, Sendable {
        let credentials: ZedCredentials
        let serviceURL: String

        func loadCredentials(serviceURL: String) throws -> ZedCredentials? {
            try Task.checkCancellation()
            guard serviceURL == self.serviceURL else { throw ZedStatusProbeError.untrustedServerConfiguration }
            return self.credentials
        }
    }
}
#endif
