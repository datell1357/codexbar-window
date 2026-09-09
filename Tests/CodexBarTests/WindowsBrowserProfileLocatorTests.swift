#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

struct WindowsBrowserProfileLocatorTests {
    @Test
    func `uses case insensitive local app data and rejects non directory candidates`() {
        let home = URL(fileURLWithPath: "C:/SyntheticHome", isDirectory: true)
        let root = URL(fileURLWithPath: "D:/SyntheticData/Google/Chrome Beta/User Data", isDirectory: true)
        let valid = root.appendingPathComponent("Profile 2", isDirectory: true)
        let directories = [
            root.path: ["Default", "Profile 2", "user-file", "Cache", "Profile ../outside", "user-\\outside"],
            valid.path: [],
        ]
        let profiles = WindowsBrowserProfileLocator.profileDirectories(
            for: .chromeBeta,
            home: home,
            environment: ["localappdata": "D:/SyntheticData"],
            fileExists: { $0 == root.path },
            directoryContents: { directories[$0] })
        #expect(profiles == [valid])
    }

    @Test
    func `falls back to home local app data and keeps unsupported browsers unavailable`() {
        let home = URL(fileURLWithPath: "C:/SyntheticHome", isDirectory: true)
        let root = home.appendingPathComponent("AppData/Local/Microsoft/Edge SxS/User Data", isDirectory: true)
        let profile = root.appendingPathComponent("Default", isDirectory: true)
        let directories = [root.path: ["Default"], profile.path: []]
        let profiles = WindowsBrowserProfileLocator.profileDirectories(
            for: .edgeCanary,
            home: home,
            environment: [:],
            fileExists: { $0 == root.path },
            directoryContents: { directories[$0] })
        #expect(profiles == [profile])
        let unsupported = WindowsBrowserProfileLocator.profileDirectories(
            for: .firefox,
            home: home,
            environment: [:],
            fileExists: { _ in Issue.record("Unsupported browser must not probe the filesystem"); return true },
            directoryContents: { _ in Issue.record("Unsupported browser must not enumerate profiles"); return [] })
        #expect(unsupported.isEmpty)
    }

    @Test
    func `profile presence does not enable installation or cookie capability`() {
        let home = URL(fileURLWithPath: "C:/SyntheticHome", isDirectory: true)
        let root = home.appendingPathComponent("AppData/Local/Chromium/User Data", isDirectory: true)
        let profile = root.appendingPathComponent("Default", isDirectory: true)
        let directories = [root.path: ["Default"], profile.path: []]
        let detection = BrowserDetection(
            homeDirectory: home.path,
            cacheTTL: 0,
            fileExists: { $0 == root.path },
            directoryContents: { directories[$0] },
            environment: [:])
        #expect(detection.hasUsableProfileData(.chromium))
        #expect(!detection.isAppInstalled(.chromium))
        #expect(!detection.isCookieSourceAvailable(.chromium))
        #expect(!BrowserCookieAccessGate.shouldAttempt(.chromium))
        #expect([Browser.chromium].cookieImportCandidates(using: detection).isEmpty)
    }
}
#endif
