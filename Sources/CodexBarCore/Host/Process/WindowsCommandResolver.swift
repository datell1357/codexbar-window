#if os(Windows)
import Foundation

struct WindowsResolvedCommand {
    let sourcePath: String
    let target: WindowsLaunchTarget
}

/// Provider CLI resolution only. Generic subprocesses/hooks remain native-only.
enum WindowsCommandResolver {
    static func resolve(
        executable: String,
        override: String?,
        environment: [String: String]) -> WindowsResolvedCommand?
    {
        if let override, let command = self.atPath(override, environment: environment) { return command }
        guard !executable.isEmpty, !executable.contains("\0") else { return nil }
        if executable.contains("/") || executable.contains("\\") || executable.contains(":") {
            return self.atPath(executable, environment: environment)
        }
        guard let path = CodexBarPlatformPaths.environmentValue("PATH", environment: environment),
              !path.contains("\0") else { return nil }
        let names = (executable as NSString).pathExtension.isEmpty
            ? [executable + ".exe", executable + ".com", executable + ".cmd"] : [executable]
        for raw in path.split(separator: ";", omittingEmptySubsequences: true) {
            var directory = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if directory.count >= 2, directory.first == "\"", directory.last == "\"" {
                directory = String(directory.dropFirst().dropLast())
            }
            guard !directory.isEmpty else { continue }
            for name in names {
                let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name).path
                if let command = self.atPath(candidate, environment: environment) { return command }
            }
        }
        return nil
    }

    private static func atPath(_ path: String, environment: [String: String]) -> WindowsResolvedCommand? {
        guard !path.isEmpty, !path.contains("\0") else { return nil }
        let suffix = (path as NSString).pathExtension.lowercased()
        if suffix == "exe" || suffix == "com" {
            guard self.isFile(path) else { return nil }
            return WindowsResolvedCommand(sourcePath: path, target: WindowsLaunchTarget(executable: path))
        }
        guard suffix == "cmd", self.isFile(path), let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 65_537), data.count <= 65_536,
              let text = String(data: data, encoding: .utf8),
              let entry = WindowsNPMShim.entryPath(in: text)
        else { return nil }
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        let script = directory.appendingPathComponent(entry.replacingOccurrences(of: "\\", with: "/")).standardizedFileURL.path
        guard self.isFile(script) else { return nil }
        let sibling = directory.appendingPathComponent("node.exe").path
        let node: String?
        if FileManager.default.fileExists(atPath: sibling) {
            node = self.isFile(sibling) ? sibling : nil
        } else {
            node = WindowsExecutableResolver.resolve(executable: "node.exe", override: nil, environment: environment)
        }
        guard let node else { return nil }
        return WindowsResolvedCommand(
            sourcePath: path,
            target: WindowsLaunchTarget(
                executable: node, argumentPrefix: [script], removesJavaScriptPathExtension: true))
    }

    private static func isFile(_ path: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return false }
        return attributes[.type] as? FileAttributeType == .typeRegular
    }
}
#endif
