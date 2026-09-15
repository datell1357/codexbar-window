#if os(Windows)
import CodexBarCore
import Foundation
import WinSDK

public enum WindowsPluginInstallFailure: String, Error, Sendable {
    case sourceUnavailable, invalidFile, tooLarge, busy, storageUnavailable
    case pluginLoadFailed, providerCollision, savedStateCollision, filenameCollision, configUnavailable, appUnavailable
    var localizationKey: String { "plugin_install_" + self.rawValue }
}

/// Installs a new local plugin; replacement, activation and permission grants are separate actions.
enum WindowsPluginInstaller {
    static func install(source: URL, reservedIDs: Set<ProviderInstanceID>) throws -> ProviderInstanceID {
        do { return try self.performInstall(source: source, reservedIDs: reservedIDs) }
        catch let failure as WindowsPluginInstallFailure { throw failure }
        catch { throw WindowsPluginInstallFailure.storageUnavailable }
    }

    static func readSource(_ source: URL) throws -> Data {
        guard source.isFileURL, !source.path.contains("\0"),
              ["js", "ts"].contains(source.pathExtension.lowercased()) else {
            throw WindowsPluginInstallFailure.invalidFile
        }
        let bytes: Data
        do {
            let attributes = try source.resourceValues(forKeys: [.isRegularFileKey])
            guard attributes.isRegularFile == true else { throw WindowsPluginInstallFailure.invalidFile }
            bytes = try {
                let file = try FileHandle(forReadingFrom: source)
                defer { try? file.close() }
                var bytes = Data()
                while bytes.count <= UserProviderPlugin.maximumSourceBytes {
                    let part = try file.read(upToCount: min(65536, UserProviderPlugin.maximumSourceBytes + 1 - bytes.count)) ?? Data()
                    if part.isEmpty { return bytes }
                    bytes.append(part)
                }
                throw WindowsPluginInstallFailure.tooLarge
            }()
        } catch let failure as WindowsPluginInstallFailure { throw failure }
        catch { throw WindowsPluginInstallFailure.sourceUnavailable }
        return bytes
    }

    static func withInstallationLock<T>(_ operation: () throws -> T) throws -> T {
        let fm = FileManager.default
        let directory = UserProviderPluginLoader.defaultProvidersDirectory
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent(".install.lock")
        let opened = lockURL.path.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, DWORD(GENERIC_READ|GENERIC_WRITE), 0, nil, DWORD(OPEN_ALWAYS),
                DWORD(FILE_ATTRIBUTE_NORMAL|FILE_FLAG_OPEN_REPARSE_POINT), nil)
        }
        guard let handle = opened, handle != INVALID_HANDLE_VALUE else {
            let code = GetLastError()
            if code == ERROR_SHARING_VIOLATION || code == ERROR_LOCK_VIOLATION { throw WindowsPluginInstallFailure.busy }
            throw WindowsPluginInstallFailure.storageUnavailable
        }
        defer { CloseHandle(handle) }
        var info = BY_HANDLE_FILE_INFORMATION()
        guard GetFileType(handle) == DWORD(FILE_TYPE_DISK), GetFileInformationByHandle(handle, &info) != 0,
              info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT) == 0 else {
            throw WindowsPluginInstallFailure.storageUnavailable
        }
        return try operation()
    }

    private static func performInstall(source: URL, reservedIDs: Set<ProviderInstanceID>) throws -> ProviderInstanceID {
        let bytes = try self.readSource(source)
        return try self.withInstallationLock {
            let fm = FileManager.default
            let directory = UserProviderPluginLoader.defaultProvidersDirectory
            let temporary = directory.appendingPathComponent(".install-" + UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: temporary, withIntermediateDirectories: false)
            defer { try? fm.removeItem(at: temporary) } // Only this invocation's staging directory.
            let staged = temporary.appendingPathComponent(source.lastPathComponent)
            try WindowsCredentialFileWriter.writePrivate(bytes, to: staged)
            let loader = UserProviderPluginLoader()
            let candidate: UserProviderPlugin
            do {
                candidate = try UserProviderPluginLoader(cacheDirectory: temporary.appendingPathComponent("cache", isDirectory: true))
                    .load(fileURL: staged)
            }
            catch { throw WindowsPluginInstallFailure.pluginLoadFailed }
            guard candidate.manifest.id.firstPartyProvider == nil,
                  !loader.discover().contains(where: { $0.instanceID == candidate.manifest.id }) else {
                throw WindowsPluginInstallFailure.providerCollision
            }
            guard !reservedIDs.contains(candidate.manifest.id) else { throw WindowsPluginInstallFailure.savedStateCollision }
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            guard !fm.fileExists(atPath: destination.path) else { throw WindowsPluginInstallFailure.filenameCollision }
            // No replace option: a concurrent creator must cause failure, never overwrite an existing file.
            do { try fm.moveItem(at: staged, to: destination) }
            catch let error as CocoaError where error.code == .fileWriteFileExists {
                throw WindowsPluginInstallFailure.filenameCollision
            }
            return candidate.manifest.id
        }
    }
}
#endif
