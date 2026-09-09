#if os(Windows)
import Foundation
import WinSDK

/// Antigravity-specific façade for the common opaque owner identity. Keeping
/// the provider entry point separate lets session records evolve without
/// exposing token mechanics to the CLI session actor.
package enum AntigravityProcessOwnerIdentity {
    package static func current() throws -> ProcessOwnerIdentity {
        try WindowsProcessOwnerIdentity.current()
    }

    /// Reads the owner from a borrowed process token. The handle remains owned
    /// by the process/session object and is never closed here.
    package static func identity(forToken token: HANDLE) throws -> ProcessOwnerIdentity {
        try WindowsProcessOwnerIdentity.identity(forToken: token)
    }

    package static func identity(forProcessHandle process: HANDLE) throws -> ProcessOwnerIdentity {
        try WindowsProcessOwnerIdentity.identity(forProcessHandle: process)
    }
}
#endif
