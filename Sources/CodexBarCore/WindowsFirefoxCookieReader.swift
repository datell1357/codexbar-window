// Adapted from SweetCookieKit 0.5.2, d5ea6d92298779ec0c3ddf7d3d99da186a305e14.
// Copyright (c) 2026 Peter Steinberger. MIT; see docs/windows-port/SweetCookieKit-LICENSE.txt.
#if os(Windows)
import CSQLite3
import Foundation

enum WindowsFirefoxCookieReader {
    /// Reads one SQLite snapshot, including committed WAL content, without copying the database.
    /// Read-only WAL access can fail when SQLite cannot access the required shared-memory state.
    /// The busy handler waits at most 250 ms per lock contention; this is not a total query deadline.
    static func read(from databaseURL: URL, query: BrowserCookieQuery) throws -> [BrowserCookieRecord] {
        guard databaseURL.isFileURL, !databaseURL.path.utf8.contains(0) else {
            throw Self.failure(SQLITE_MISUSE)
        }
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw Self.failure(openResult == SQLITE_OK ? SQLITE_ERROR : openResult)
        }
        defer { sqlite3_close(database) }
        let timeoutResult = sqlite3_busy_timeout(database, 250)
        guard timeoutResult == SQLITE_OK else { throw Self.failure(timeoutResult) }
        return try Self.read(database: database, query: query)
    }

    /// Borrows the connection. The caller owns its lifetime and busy-handler configuration.
    static func read(database: OpaquePointer, query: BrowserCookieQuery) throws -> [BrowserCookieRecord] {
        var conditions: [String] = []
        var bindings: [String] = []
        for pattern in query.domains {
            guard !pattern.utf8.contains(0) else { throw Self.failure(SQLITE_MISUSE) }
            switch query.domainMatch {
            case .contains:
                conditions.append("host LIKE ?")
                bindings.append("%\(pattern)%")
            case .suffix:
                conditions.append("host LIKE ?")
                bindings.append("%\(pattern)")
            case .exact:
                let domain = BrowserCookieDomainMatcher.normalizeDomain(pattern)
                conditions.append("(host = ? OR host = ?)")
                bindings.append(domain)
                bindings.append(".\(domain)")
            }
        }
        let predicate = conditions.isEmpty ? "1=1" : conditions.joined(separator: " OR ")
        let sql = """
        SELECT host, name, path, value, expiry, isSecure, isHttpOnly
        FROM moz_cookies
        WHERE \(predicate)
        """
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw Self.failure(prepareResult == SQLITE_OK ? SQLITE_ERROR : prepareResult)
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in bindings.enumerated() {
            guard let index = Int32(exactly: offset + 1) else { throw Self.failure(SQLITE_TOOBIG) }
            // SQLITE_TRANSIENT copies the UTF-8 bytes before withCString releases its buffer.
            let result = value.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
            guard result == SQLITE_OK else { throw Self.failure(result) }
        }

        var records: [BrowserCookieRecord] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return records }
            guard result == SQLITE_ROW else { throw Self.failure(result) }
            guard let host = try Self.text(statement, column: 0),
                  let name = try Self.text(statement, column: 1),
                  let path = try Self.text(statement, column: 2),
                  let value = try Self.text(statement, column: 3)
            else { continue }

            let expiry = sqlite3_column_int64(statement, 4)
            let expires = expiry > 0 ? Date(timeIntervalSince1970: TimeInterval(expiry)) : nil
            if !query.includeExpired, let expires, expires < query.referenceDate { continue }
            records.append(BrowserCookieRecord(
                domain: BrowserCookieDomainMatcher.normalizeDomain(host),
                name: name,
                path: path,
                value: value,
                expires: expires,
                isSecure: sqlite3_column_int(statement, 5) != 0,
                isHTTPOnly: sqlite3_column_int(statement, 6) != 0,
                scope: BrowserCookieDomainMatcher.scope(forStoredDomain: host)))
        }
    }

    private static func text(_ statement: OpaquePointer, column: Int32) throws -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        guard let bytes = sqlite3_column_text(statement, column) else { throw Self.failure(SQLITE_NOMEM) }
        let count = Int(sqlite3_column_bytes(statement, column))
        return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
    }

    private static func failure(_ code: Int32) -> BrowserCookieError {
        .loadFailed(browser: .firefox, details: "Firefox cookie database read failed (SQLite code \(code)).")
    }
}
#endif
