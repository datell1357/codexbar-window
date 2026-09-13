#if os(Windows)
import Foundation
import CodexBarCore

/// A user-scoped encrypted write-ahead record. Never stores account labels or plaintext tokens.
struct WindowsAccountRemovalJournal {
    enum Failure: Error { case invalidRecord }
    private struct Entry: Codable { let id: UUID; let encrypted: Data }
    private struct Envelope: Codable { let version: Int; let entries: [Entry] }
    let fileURL: URL
    private static let maximumBytes = 16 * 1024 * 1024

    func load() throws -> [UUID: ProviderTokenAccount] {
        let data: Data
        do { data = try Data(contentsOf: self.fileURL) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return [:] }
        guard data.count <= Self.maximumBytes else { throw Failure.invalidRecord }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == 1, envelope.entries.count <= 128,
              Set(envelope.entries.map(\.id)).count == envelope.entries.count else { throw Failure.invalidRecord }
        var result: [UUID: ProviderTokenAccount] = [:]
        for entry in envelope.entries {
            let plain = try WindowsTokenAccountProtection.removalRecoveryPayload(entry.encrypted, accountID: entry.id, protect: false)
            guard plain.count <= 65_536, let token = String(data: plain, encoding: .utf8),
                  !token.isEmpty, !token.contains("\0") else { throw Failure.invalidRecord }
            result[entry.id] = ProviderTokenAccount(id: entry.id, label: "", token: token, addedAt: 0, lastUsed: nil)
        }
        return result
    }

    func save(_ accounts: [UUID: ProviderTokenAccount]) throws {
        guard accounts.count <= 128 else { throw Failure.invalidRecord }
        let entries = try accounts.values.sorted { $0.id.uuidString < $1.id.uuidString }.map { account in
            guard !account.token.isEmpty, account.token.utf8.count <= 65_536,
                  !account.token.contains("\0") else { throw Failure.invalidRecord }
            return Entry(id: account.id, encrypted: try WindowsTokenAccountProtection.removalRecoveryPayload(
                Data(account.token.utf8), accountID: account.id, protect: true))
        }
        let data = try JSONEncoder().encode(Envelope(version: 1, entries: entries))
        guard data.count <= Self.maximumBytes else { throw Failure.invalidRecord }
        try WindowsCredentialFileWriter.writePrivate(data, to: self.fileURL)
    }
}
#endif
