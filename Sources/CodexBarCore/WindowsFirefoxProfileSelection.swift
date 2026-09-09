// Adapted from SweetCookieKit 0.5.2, d5ea6d92298779ec0c3ddf7d3d99da186a305e14.
// Copyright (c) 2026 Peter Steinberger. MIT; see docs/windows-port/SweetCookieKit-LICENSE.txt.
#if os(Windows)
import Foundation

/// Preserves upstream stable Firefox/ESR channel filtering. This does not prove an application is installed.
enum WindowsFirefoxProfileSelection {
    static func includes(profile: URL, readText: ((String) -> String?)? = nil) -> Bool {
        let read = readText ?? self.readMetadata
        guard let compatibility = read(profile.appendingPathComponent("compatibility.ini").path) else { return true }
        var candidates: [URL] = []
        if let path = self.value(named: "LastAppDir", in: compatibility),
           let directory = WindowsFirefoxProfiles.absoluteDirectory(path)
        {
            candidates.append(directory.deletingLastPathComponent().appendingPathComponent("application.ini"))
        }
        if let path = self.value(named: "LastPlatformDir", in: compatibility),
           let directory = WindowsFirefoxProfiles.absoluteDirectory(path)
        {
            candidates.append(directory.appendingPathComponent("application.ini"))
        }
        for candidate in candidates {
            guard let application = read(candidate.path),
                  let name = self.value(named: "RemotingName", in: application), !name.isEmpty else { continue }
            return ["firefox", "firefox-esr"].contains(name.lowercased())
        }
        // SweetCookieKit's stable Firefox policy includes unidentified profiles; named other channels are excluded.
        return true
    }

    private static func value(named name: String, in text: String) -> String? {
        let prefix = "\(name)="
        for line in text.split(whereSeparator: { $0.isNewline }) where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func readMetadata(at path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 65_537), data.count <= 65_536 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
#endif
