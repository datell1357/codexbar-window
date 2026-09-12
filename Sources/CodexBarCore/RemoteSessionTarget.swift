import Foundation

/// The remote OS, not the OS running CodexBar. Unknown hosts must be configured before SSH execution.
public enum RemoteSessionPlatform: String, Codable, Sendable {
    case unspecified
    case posix
    case windows

    static var legacyDefault: Self {
        #if os(Windows)
        .unspecified
        #else
        .posix
        #endif
    }

    static func tailscaleOS(_ value: String) -> Self? {
        switch value.lowercased() {
        case "windows": .windows
        case "macos", "linux": .posix
        default: nil
        }
    }
}

public struct RemoteSessionTarget: Codable, Equatable, Sendable, Identifiable {
    public let host: String
    public let platform: RemoteSessionPlatform
    public let executablePath: String?

    public var id: String { self.host.lowercased() }

    public init(host: String, platform: RemoteSessionPlatform, executablePath: String? = nil) {
        self.host = host
        self.platform = platform
        self.executablePath = executablePath
    }

    /// Compatible with the existing comma-separated host setting. An explicit prefix also works
    /// when Tailscale is unavailable. Paths remain a typed API option rather than URI command text.
    public init?(configurationValue: String, defaultPlatform: RemoteSessionPlatform = .unspecified) {
        var host = configurationValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let platform: RemoteSessionPlatform
        if host.lowercased().hasPrefix("windows://") {
            host = String(host.dropFirst("windows://".count))
            platform = .windows
        } else if host.lowercased().hasPrefix("posix://") {
            host = String(host.dropFirst("posix://".count))
            platform = .posix
        } else {
            guard !host.contains("://") else { return nil }
            platform = defaultPlatform
        }
        guard Self.isValidHost(host) else { return nil }
        self.init(host: host, platform: platform)
    }

    /// Pure configuration check shared with native editors; never opens a process or connection.
    public var configurationError: String? {
        do {
            _ = try RemoteSessionCommandBuilder.arguments(target: self, operation: .list)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public var configurationValue: String {
        switch self.platform {
        case .windows: "windows://" + self.host
        case .posix: "posix://" + self.host
        case .unspecified: self.host
        }
    }

    static func isValidHost(_ host: String) -> Bool {
        !host.isEmpty && host.utf8.count <= 1024 && !host.hasPrefix("-") &&
            !host.contains("/") && !host.contains("\\") &&
            !host.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0)
            }
    }

    static func normalized(_ targets: [Self]) -> [Self] {
        var result: [Self] = []
        var indices: [String: Int] = [:]
        for target in targets where Self.isValidHost(target.host) {
            if let index = indices[target.id] {
                // A discovered/explicit OS can resolve a plain Windows host setting. Preserve an
                // already explicit target (manual targets precede discovered targets).
                if result[index].platform == .unspecified, target.platform != .unspecified {
                    result[index] = target
                }
            } else {
                indices[target.id] = result.count
                result.append(target)
            }
        }
        return result
    }
}

public enum RemoteSessionFocusResult: Equatable, Sendable {
    case focused
    case failed(String)
}

enum RemoteSessionCommandError: LocalizedError {
    case invalidHost
    case unknownPlatform
    case invalidSessionID
    case invalidExecutablePath

    var errorDescription: String? {
        switch self {
        case .invalidHost: "Invalid remote session host."
        case .unknownPlatform:
            "Choose the remote OS: use windows://user@host or posix://user@host."
        case .invalidSessionID: "Invalid remote session identifier."
        case .invalidExecutablePath: "Invalid remote CodexBar CLI path."
        }
    }
}

/// Encodes a fixed operation with quoted data. It never probes or executes a command itself.
enum RemoteSessionCommandBuilder {
    enum Operation {
        case list
        case focus(String)
    }

    static func arguments(target: RemoteSessionTarget, operation: Operation) throws -> [String] {
        guard RemoteSessionTarget.isValidHost(target.host) else { throw RemoteSessionCommandError.invalidHost }
        if case let .focus(id) = operation {
            guard !id.isEmpty, id.utf8.count <= 1024, !id.hasPrefix("-"),
                  !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else { throw RemoteSessionCommandError.invalidSessionID }
        }
        if let path = target.executablePath {
            guard !path.isEmpty, path.utf8.count <= 4096, !path.hasPrefix("-"),
                  !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else { throw RemoteSessionCommandError.invalidExecutablePath }
        }
        let prefix = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=3", target.host]
        switch target.platform {
        case .unspecified:
            throw RemoteSessionCommandError.unknownPlatform
        case .posix:
            let executables = target.executablePath.map { [$0] }
                ?? ["codexbar", RemoteSessionFetcher.bundledCLIFallback]
            let commands = executables.flatMap { executable -> [String] in
                let binary = self.posixQuote(executable)
                switch operation {
                case .list:
                    return ["\(binary) sessions --json-v2", "\(binary) sessions --json"]
                case let .focus(id):
                    return ["\(binary) sessions focus \(self.posixQuote(id))"]
                }
            }
            return prefix + ["sh", "-lc", self.posixQuote(commands.joined(separator: " || "))]
        case .windows:
            if let path = target.executablePath {
                let characters = Array(path)
                let driveAbsolute = characters.count >= 3 && characters[0].isASCII && characters[0].isLetter &&
                    characters[1] == ":" && (characters[2] == "\\" || characters[2] == "/")
                guard path.lowercased().hasSuffix(".exe"), driveAbsolute || path.hasPrefix("\\\\") else {
                    throw RemoteSessionCommandError.invalidExecutablePath
                }
            }
            let script = self.windowsScript(executablePath: target.executablePath, operation: operation)
            // Windows PowerShell consumes UTF-16LE here. Only Base64 crosses the remote login
            // shell, so PowerShell/session/path literals cannot turn into cmd/PowerShell syntax.
            let encoded = Data(script.utf16.flatMap { unit in
                [UInt8(truncatingIfNeeded: unit), UInt8(truncatingIfNeeded: unit >> 8)]
            }).base64EncodedString()
            return prefix + [
                "powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded,
            ]
        }
    }

    private static func windowsScript(executablePath: String?, operation: Operation) -> String {
        let candidates = executablePath.map { [self.powerShellQuote($0)] }
            ?? ["'codexbar.exe'", "'CodexBarCLI.exe'"]
        let invocations: String
        switch operation {
        case .list:
            invocations = "@(@('sessions', '--json-v2'), @('sessions', '--json'))"
        case let .focus(id):
            // The unary comma keeps one argument array nested rather than enumerating its strings.
            invocations = ",@('sessions', 'focus', \(self.powerShellQuote(id)))"
        }
        return """
        $ErrorActionPreference = 'Stop'
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $env:NO_COLOR = '1'
        $candidates = @(\(candidates.joined(separator: ", ")))
        $invocations = \(invocations)
        foreach ($candidate in $candidates) {
            $cliPath = $null
            if ([IO.Path]::IsPathRooted($candidate)) {
                if ([IO.File]::Exists($candidate)) { $cliPath = $candidate }
            } else {
                $command = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                if ($command) { $cliPath = $command.Source }
            }
            if (-not $cliPath) { continue }
            foreach ($invocation in $invocations) {
                $global:LASTEXITCODE = -1
                $ErrorActionPreference = 'Continue'
                $output = @(& $cliPath @invocation 2>$null)
                $exitCode = $LASTEXITCODE
                $ErrorActionPreference = 'Stop'
                if ($exitCode -eq 0) {
                    if ($output.Count -gt 0) { [Console]::Out.WriteLine(($output -join "`n")) }
                    exit 0
                }
            }
        }
        [Console]::Error.WriteLine('Remote CodexBar CLI was not found or the session operation failed.')
        exit 1
        """
    }

    private static func posixQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func powerShellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }
}
