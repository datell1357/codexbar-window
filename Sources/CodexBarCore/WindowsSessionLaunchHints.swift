#if os(Windows)
import Foundation
import WinSDK

/// Paths must come from the target CLI's own argv. Never resolve them against CodexBar's cwd,
/// expand its environment, or borrow a recent transcript from the scanner's user home.
struct WindowsSessionLaunchHints: Sendable {
    let workingDirectory: String?
    let sessionFile: String?
    static let empty = Self(workingDirectory: nil, sessionFile: nil)

    static func parse(provider: AgentSession.Provider, arguments: [String]) -> Self {
        let values: Set<String>
        let switches: Set<String>
        switch provider {
        case .codex:
            values = ["--cd", "-C", "--model", "-m", "--profile", "-p", "--config", "-c",
                      "--sandbox", "-s", "--ask-for-approval", "-a", "--image", "-i", "--add-dir",
                      "--enable", "--disable", "--local-provider"]
            switches = ["--full-auto", "--dangerously-bypass-approvals-and-sandbox", "--oss", "--search",
                        "--no-alt-screen", "--last", "--all", "--json", "--skip-git-repo-check"]
        case .pi:
            values = ["--session", "--session-dir", "--model", "--provider", "--thinking", "--api-key",
                      "--tools", "--extension", "-e", "--system-prompt", "--append-system-prompt", "--mode"]
            switches = ["--continue", "-c", "--resume", "-r", "--print", "-p", "--no-session",
                        "--no-extensions", "--no-skills", "--no-prompt-templates"]
        case .claude:
            // --add-dir grants tool access; it is not the Claude process's working directory.
            return .empty
        }
        var cwd: String?
        var session: String?
        var index = 0
        var skippedSubcommand = false
        while index < arguments.count {
            let token = arguments[index]
            if token == "--" { break }
            if provider == .codex, !skippedSubcommand, ["exec", "resume", "fork"].contains(token) {
                skippedSubcommand = true; index += 1; continue
            }
            if !token.hasPrefix("-") {
                // Stop at prompt/positional data. If a later path flag could override our earlier
                // path, the prefix alone is not authoritative, so retain PID-only presentation.
                if arguments.dropFirst(index + 1).prefix(while: { $0 != "--" }).contains(where: {
                    $0.hasPrefix("-C") || $0.hasPrefix("--cd") || $0.hasPrefix("--session")
                }) { return .empty }
                break
            }
            let pieces = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let option = String(pieces[0])
            if provider == .pi, ["--continue", "--resume", "-c", "-r", "--no-session"].contains(option) {
                return .empty
            }
            if switches.contains(option), pieces.count == 1 { index += 1; continue }
            if provider == .codex, token.hasPrefix("-C"), token.count > 2 {
                cwd = self.absolutePath(String(token.dropFirst(2)))
                index += 1; continue
            }
            guard values.contains(option) else { return .empty }
            let value: String
            if pieces.count == 2 { value = String(pieces[1]) }
            else {
                index += 1
                guard index < arguments.count, !arguments[index].hasPrefix("-") else { return .empty }
                value = arguments[index]
            }
            if option == "--cd" || option == "-C" { cwd = self.absolutePath(value) }
            if option == "--session" { session = self.absolutePath(value) }
            index += 1
        }
        return Self(workingDirectory: cwd, sessionFile: session)
    }

    static func absolutePath(_ value: String) -> String? {
        let units = Array(value.utf16)
        guard units.count >= 3, units.count <= 4096,
              ((65...90).contains(units[0]) || (97...122).contains(units[0])),
              units[1] == 58, units[2] == 92 || units[2] == 47,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !value.contains("\""), !value.contains("*"), !value.contains("?")
        else { return nil }
        var buffer = [UInt16](repeating: 0, count: 32768)
        let source = units + [0]
        let count = source.withUnsafeBufferPointer { GetFullPathNameW($0.baseAddress, DWORD(buffer.count), &buffer, nil) }
        guard count > 0, count < DWORD(buffer.count) else { return nil }
        return String(decoding: buffer.prefix(Int(count)), as: UTF16.self)
    }

    static func projectName(_ path: String?) -> String? {
        guard let path else { return nil }
        return path.replacingOccurrences(of: "/", with: "\\")
            .split(separator: "\\").last.map { self.label(String($0)) }
    }

    static func label(_ text: String) -> String {
        let clean = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            .prefix(64).map { String($0) }.joined()
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct WindowsExplicitSessionMetadata: Sendable {
    let sourceID: String
    let cwd: String?
    let title: String?
    let modifiedAt: Date
    let path: String
}

/// Reads only the selected Pi/OMP header (and optional OMP title slot), with a byte limit and one
/// retained file handle. A changing/inaccessible file produces no enrichment, never another file.
enum WindowsExplicitSessionMetadataReader {
    static func read(
        path: String, dialect: AgentSession.Dialect, now: Date, deadline: Date) -> WindowsExplicitSessionMetadata? {
        guard !Task.isCancelled, Date() < deadline, let absolute = WindowsSessionLaunchHints.absolutePath(path),
              absolute.lowercased().hasSuffix(".jsonl")
        else { return nil }
        let root = Array(String(absolute.prefix(3)).utf16) + [0]
        let drive = root.withUnsafeBufferPointer { GetDriveTypeW($0.baseAddress) }
        guard drive == UINT(DRIVE_FIXED) || drive == UINT(DRIVE_REMOVABLE) || drive == UINT(DRIVE_RAMDISK) else {
            return nil
        }
        let name = Array(absolute.utf16) + [0]
        let handle = name.withUnsafeBufferPointer {
            CreateFileW($0.baseAddress, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE),
                        nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { return nil }
        defer { CloseHandle(handle) }
        guard GetFileType(handle) == DWORD(FILE_TYPE_DISK) else { return nil }
        var before = BY_HANDLE_FILE_INFORMATION()
        guard GetFileInformationByHandle(handle, &before) != 0,
              before.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) == 0
        else { return nil }
        let reader = HeaderReader(handle: handle, deadline: deadline)
        guard let first = reader.nextObject() else { return nil }
        var header = first
        var title: String?
        if dialect == .omp, first["type"] as? String == "title" {
            title = (first["title"] as? String).map(WindowsSessionLaunchHints.label)
            guard let next = reader.nextObject() else { return nil }
            header = next
        }
        guard header["type"] as? String == "session", let id = header["id"] as? String,
              !id.isEmpty, id.utf8.count <= 256,
              !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return nil }
        if dialect == .pi, header["version"] as? Int != 3 { return nil }
        if dialect == .omp, first["type"] as? String != "title" {
            title = (header["title"] as? String).map(WindowsSessionLaunchHints.label)
        }
        guard !Task.isCancelled, Date() < deadline else { return nil }
        var after = BY_HANDLE_FILE_INFORMATION()
        guard GetFileInformationByHandle(handle, &after) != 0,
              before.dwVolumeSerialNumber == after.dwVolumeSerialNumber,
              before.nFileIndexHigh == after.nFileIndexHigh, before.nFileIndexLow == after.nFileIndexLow,
              before.nFileSizeHigh == after.nFileSizeHigh, before.nFileSizeLow == after.nFileSizeLow,
              before.ftLastWriteTime.dwHighDateTime == after.ftLastWriteTime.dwHighDateTime,
              before.ftLastWriteTime.dwLowDateTime == after.ftLastWriteTime.dwLowDateTime
        else { return nil }
        let ticks = (UInt64(after.ftLastWriteTime.dwHighDateTime) << 32) | UInt64(after.ftLastWriteTime.dwLowDateTime)
        let modified = Date(timeIntervalSince1970: Double(ticks) / 10_000_000 - 11_644_473_600)
        return WindowsExplicitSessionMetadata(
            sourceID: id,
            cwd: (header["cwd"] as? String).flatMap(WindowsSessionLaunchHints.absolutePath),
            title: title?.isEmpty == false ? title : nil,
            modifiedAt: min(modified, now), path: absolute)
    }

    private final class HeaderReader {
        let handle: HANDLE
        let deadline: Date
        var buffer = Data()
        var consumed = 0
        var reachedEOF = false
        init(handle: HANDLE, deadline: Date) { self.handle = handle; self.deadline = deadline }

        func nextObject() -> [String: Any]? {
            while !Task.isCancelled, Date() < self.deadline {
                if let newline = self.buffer.firstIndex(of: 10) {
                    let line = self.buffer.prefix(upTo: newline)
                    let copy = Data(line)
                    self.buffer.removeSubrange(...newline)
                    if copy.isEmpty { continue }
                    return (try? JSONSerialization.jsonObject(with: copy)) as? [String: Any]
                }
                if self.reachedEOF {
                    guard !self.buffer.isEmpty else { return nil }
                    let copy = self.buffer; self.buffer.removeAll()
                    return (try? JSONSerialization.jsonObject(with: copy)) as? [String: Any]
                }
                guard self.consumed < 32 * 1024 else { return nil }
                var chunk = [UInt8](repeating: 0, count: min(2048, 32 * 1024 - self.consumed))
                var count: DWORD = 0
                let success = chunk.withUnsafeMutableBytes { ReadFile(self.handle, $0.baseAddress, DWORD($0.count), &count, nil) }
                guard success != 0 else { return nil }
                if count == 0 { self.reachedEOF = true; continue }
                self.consumed += Int(count)
                self.buffer.append(contentsOf: chunk.prefix(Int(count)))
            }
            return nil
        }
    }
}
#endif
