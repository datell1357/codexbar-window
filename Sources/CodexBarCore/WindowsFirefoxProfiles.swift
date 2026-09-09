#if os(Windows)
import Foundation

/// The normal profiles.ini registry contract; does not select an active profile or infer a release channel.
enum WindowsFirefoxProfiles {
    static func profileDirectories(in text: String, relativeTo root: URL) -> [URL] {
        guard !text.contains("\0") else { return [] }
        let withoutBOM = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let text = withoutBOM.replacingOccurrences(of: "\r\n", with: "\n")
        var sections: [String: [String: String]] = [:]
        var section: String?
        for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            if raw.first == "#" || raw.first == ";" { continue }
            let line = raw.drop(while: { $0 == " " || $0 == "\t" })
            guard !line.isEmpty else { continue }
            if line.first == "[" {
                section = nil
                // nsINIParser accepts an unclosed header when the remaining name is otherwise valid.
                let closing = line.firstIndex(of: "]") ?? line.endIndex
                let name = String(line[line.index(after: line.startIndex) ..< closing])
                let trailing = closing == line.endIndex ? line[line.endIndex...] : line[line.index(after: closing)...]
                guard !name.isEmpty, !name.contains("["),
                      trailing.allSatisfy({ $0 == " " || $0 == "\t" }) else { continue }
                section = name
                continue
            }
            guard let section, let equals = line.firstIndex(of: "="), equals != line.startIndex else { continue }
            let key = String(line[..<equals])
            let value = String(line[line.index(after: equals)...])
            // Mozilla compares keys exactly and preserves value whitespace; later duplicate keys win.
            sections[section, default: [:]][key] = value
        }

        var profiles: [URL] = []
        var index = 0
        while let entry = sections["Profile\(index)"], let isRelative = entry["IsRelative"] {
            index += 1
            // A missing IsRelative ends enumeration, but missing Name or Path only skips that numbered entry.
            guard entry["Name"] != nil, let path = entry["Path"], !path.isEmpty else { continue }
            let profile: URL?
            if isRelative == "1" {
                profile = self.relativeProfile(path, root: root)
            } else {
                profile = self.absoluteProfile(path)
            }
            if let profile, !profiles.contains(profile) { profiles.append(profile) }
        }
        return profiles
    }

    private static func relativeProfile(_ path: String, root: URL) -> URL? {
        // Gecko serializes relative descriptors with '/' even on Windows. Preserve normal leading parent traversal.
        // Malformed descriptors and embedded Windows separators are not interpreted as a second path syntax.
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":") else { return nil }
        var result = root
        var encounteredChild = false
        for component in path.split(separator: "/", omittingEmptySubsequences: false) {
            guard !component.isEmpty, component != ".",
                  !component.contains(where: { "<>\"|?*".contains($0) }) else { return nil }
            if component == ".." {
                guard !encounteredChild else { return nil }
                let parent = result.deletingLastPathComponent()
                guard parent != result else { return nil }
                result = parent
            } else {
                encounteredChild = true
                result.appendPathComponent(String(component), isDirectory: true)
            }
        }
        return result.standardizedFileURL
    }

    private static func absoluteProfile(_ path: String) -> URL? {
        guard !path.contains("/"), !path.contains(where: { "<>\"|?*".contains($0) }),
              !path.hasPrefix("\\\\.\\") else { return nil }
        let bytes = Array(path.utf8.prefix(3))
        let driveRooted = bytes.count == 3 &&
            ((65...90).contains(bytes[0]) || (97...122).contains(bytes[0])) &&
            bytes[1] == 58 && bytes[2] == 92
        let unc = path.hasPrefix("\\\\") && path.dropFirst(2).split(separator: "\\").count >= 2
        guard driveRooted || unc else { return nil }
        guard !(driveRooted ? path.dropFirst(2) : path[...]).contains(":") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }
}
#endif
