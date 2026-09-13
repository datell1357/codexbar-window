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
    }

    private let reader: any ZedCredentialsReading

    public init() { self.reader = WindowsZedEditorCredentialsReader() }

    init(reader: any ZedCredentialsReading) { self.reader = reader }

    public func loadAndValidate(
        serviceURL: String = ZedStatusProbe.defaultKeychainServiceURL,
        transport: (any ProviderHTTPTransport)? = nil) async throws -> ValidatedAccount
    {
        try Task.checkCancellation()
        let origin = try ZedManualCredentialInput.bundle("1 placeholder " + serviceURL).serviceURL
        let reader = self.reader
        let readTask = Task.detached {
            try Task.checkCancellation()
            let credentials = try reader.loadCredentials(serviceURL: origin)
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
        let pinnedReader = PinnedReader(credentials: parsed.credentials, serviceURL: parsed.serviceURL)
        let settings = ZedClientSettings(credentialsURL: parsed.serviceURL, serverURL: parsed.serviceURL)
        // Probe and saved bundle use this one captured credential, even if the editor switches accounts.
        let snapshot = try await ZedStatusProbe(credentialsReader: pinnedReader, transport: transport,
            settingsLoader: { settings }).fetch()
        try Task.checkCancellation()
        return ValidatedAccount(userID: parsed.credentials.userID, snapshot: snapshot,
            credentialBundle: parsed.credentials.userID + " " + parsed.credentials.accessToken + " " + parsed.serviceURL,
            serviceURL: parsed.serviceURL)
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
