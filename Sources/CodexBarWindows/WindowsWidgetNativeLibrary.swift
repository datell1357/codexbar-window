#if os(Windows)
import Foundation
import WinSDK

/// Load only the installed backend DLL selected by the trusted installation resolver.
/// Every native server owner must retain this object until its worker is joined and server destroyed.
final class WindowsWidgetNativeLibrary: @unchecked Sendable {
    enum Failure: Error, Sendable { case invalidLocation, unavailable, missingExport, incompatibleVersion }
    typealias RequestHandler = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, UInt32,
        UnsafeMutablePointer<UInt8>?, UInt32, UnsafeMutablePointer<UInt32>?) -> Int32
    typealias Create = @convention(c) (UnsafeMutableRawPointer?, RequestHandler?,
        UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
    typealias Name = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt16>?, UInt32,
        UnsafeMutablePointer<UInt32>?) -> Int32
    typealias Start = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32
    typealias Operation = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias Status = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?,
        UnsafeMutablePointer<Int32>?) -> Int32
    private typealias Version = @convention(c) () -> UInt32

    // Immutable C entry points; the launcher State retains this DLL for their whole lifetime.
    struct LaunchExports: @unchecked Sendable {
        typealias Create = @convention(c) (UnsafePointer<UInt16>?, UInt32,
            UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
        typealias Process = @convention(c) (UnsafeMutableRawPointer?,
            UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
        typealias Accept = @convention(c) (UInt32, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
        typealias Deliver = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, UInt32) -> Int32
        typealias Status = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?,
            UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> Int32
        let create: Create
        let accept: Accept?
        let process: Process
        let deliver: Deliver
        let stop: Operation
        let status: Status
        let destroy: Operation
    }

    /// Older ABI-v1 server DLLs remain usable for server-only callers; launching requires these exports too.
    func launchExports() throws -> LaunchExports {
        func resolve<T>(_ name: String, as type: T.Type) throws -> T {
            guard let address = name.withCString({ GetProcAddress(self.module, $0) }) else { throw Failure.missingExport }
            return unsafeBitCast(address, to: type)
        }
        let accept = "CBWidgetLaunchAccept".withCString { GetProcAddress(self.module, $0) }
            .map { unsafeBitCast($0, to: LaunchExports.Accept.self) }
        return try LaunchExports(create: resolve("CBWidgetLaunchCreate", as: LaunchExports.Create.self),
            accept: accept,
            process: resolve("CBWidgetLaunchProcess", as: LaunchExports.Process.self),
            deliver: resolve("CBWidgetLaunchDeliver", as: LaunchExports.Deliver.self),
            stop: resolve("CBWidgetLaunchStop", as: Operation.self),
            status: resolve("CBWidgetLaunchStatus", as: LaunchExports.Status.self),
            destroy: resolve("CBWidgetLaunchDestroy", as: Operation.self))
    }

    private let module: HMODULE
    let create: Create
    let name: Name
    let start: Start
    let cancel: Operation
    let join: Operation
    let status: Status
    let destroy: Operation

    init(installedDLL: URL) throws {
        let url = installedDLL.standardizedFileURL
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              url.lastPathComponent == "CodexBarWidgetBackend.dll", !url.hasDirectoryPath,
              !url.path.contains("\0"), url.path.utf16.count <= 32767 else { throw Failure.invalidLocation }
        // Absolute DLL path plus constrained dependency search; never resolve from cwd or PATH.
        let flags = DWORD(LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32)
        guard let module = url.path.withCString(encodedAs: UTF16.self, {
            LoadLibraryExW($0, nil, flags)
        }) else { throw Failure.unavailable }
        var loaded = false
        defer { if !loaded { FreeLibrary(module) } }
        func resolve<T>(_ name: String, as type: T.Type) throws -> T {
            guard let address = name.withCString({ GetProcAddress(module, $0) }) else { throw Failure.missingExport }
            return unsafeBitCast(address, to: type)
        }
        let version: Version = try resolve("CBWidgetBackendABIVersion", as: Version.self)
        guard version() == 1 else { throw Failure.incompatibleVersion }
        self.create = try resolve("CBWidgetServerCreate", as: Create.self)
        self.name = try resolve("CBWidgetServerName", as: Name.self)
        self.start = try resolve("CBWidgetServerStart", as: Start.self)
        self.cancel = try resolve("CBWidgetServerCancel", as: Operation.self)
        self.join = try resolve("CBWidgetServerJoin", as: Operation.self)
        self.status = try resolve("CBWidgetServerStatus", as: Status.self)
        self.destroy = try resolve("CBWidgetServerDestroy", as: Operation.self)
        self.module = module
        loaded = true
    }
    deinit { FreeLibrary(self.module) }
}
#endif
