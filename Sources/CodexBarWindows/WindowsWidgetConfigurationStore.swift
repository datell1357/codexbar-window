#if os(Windows)
import CodexBarCore
import Foundation
import WinSDK

/// Shared by the app and widget host. Callers supply the installation's per-user settings URL.
public actor WindowsWidgetConfigurationStore {
    public struct Snapshot: Sendable {
        public let configuration: WindowsWidgetConfiguration
        fileprivate let bytes: Data?
        fileprivate let source: URL
    }
    public enum Failure: Error, Sendable {
        case invalidLocation, unavailable, busy, changed, invalidConfiguration
    }

    private let url: URL
    public init(url: URL) { self.url = url.standardizedFileURL }

    public static func defaultURL(configFileURL: URL) -> URL {
        configFileURL.deletingLastPathComponent()
            .appendingPathComponent("WindowsWidgets", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    public func load() throws -> Snapshot {
        try self.validateLocation()
        return try self.readSnapshot()
    }

    /// An exclusive sidecar handle serializes cooperating writers across app/host processes.
    /// The byte comparison rejects edits made against a stale or different store snapshot.
    public func save(expected: Snapshot, mutation: WindowsWidgetConfiguration.Mutation) throws -> Snapshot {
        try self.save(expected: expected, mutations: [mutation])
    }

    /// Validate and persist an inventory reconciliation as one bounded, revision-checked write.
    public func save(expected: Snapshot, mutations: [WindowsWidgetConfiguration.Mutation]) throws -> Snapshot {
        guard mutations.count <= WindowsWidgetConfiguration.maximumInstances else { throw Failure.invalidConfiguration }
        try Task.checkCancellation()
        try self.validateLocation()
        guard expected.source == self.url else { throw Failure.changed }
        let parent = self.url.deletingLastPathComponent()
        do { try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true) }
        catch { throw Failure.unavailable }
        let lockURL = parent.appendingPathComponent(self.url.lastPathComponent + ".lock")
        let handle = lockURL.path.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, DWORD(GENERIC_READ | GENERIC_WRITE), 0, nil, DWORD(OPEN_ALWAYS), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else {
            let error = GetLastError()
            if error == ERROR_SHARING_VIOLATION || error == ERROR_LOCK_VIOLATION { throw Failure.busy }
            throw Failure.unavailable
        }
        defer { CloseHandle(handle) }
        let current = try self.readSnapshot()
        guard current.bytes == expected.bytes else { throw Failure.changed }
        let updated: WindowsWidgetConfiguration
        let encoded: Data
        do {
            var candidate = current.configuration
            for mutation in mutations { candidate = try candidate.applying(mutation) }
            updated = candidate
            encoded = try updated.encoded()
        } catch { throw Failure.invalidConfiguration }
        if updated == current.configuration { return current }
        try Task.checkCancellation()
        do { try encoded.write(to: self.url, options: .atomic) }
        catch { throw Failure.unavailable }
        return Snapshot(configuration: updated, bytes: encoded, source: self.url)
    }

    private func validateLocation() throws {
        guard self.url.isFileURL, !self.url.lastPathComponent.isEmpty,
              self.url.path != "/", !self.url.hasDirectoryPath else { throw Failure.invalidLocation }
    }

    private func readSnapshot() throws -> Snapshot {
        let data: Data?
        do {
            data = try WindowsBoundedFileReader.readIfPresent(at: self.url,
                maximumBytes: WindowsWidgetConfiguration.maximumEncodedBytes)
        } catch { throw Failure.unavailable }
        guard let data else {
            return Snapshot(configuration: WindowsWidgetConfiguration(), bytes: nil, source: self.url)
        }
        let configuration: WindowsWidgetConfiguration
        do { configuration = try WindowsWidgetConfiguration.decode(data) }
        catch { throw Failure.invalidConfiguration }
        return Snapshot(configuration: configuration, bytes: data, source: self.url)
    }
}
#endif
