#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

struct WindowsFirefoxProfileSelectionTests {
    private let profile = URL(fileURLWithPath: "C:/Synthetic/Profiles/work", isDirectory: true)

    @Test
    func `unknown profiles retain upstream stable fallback`() {
        #expect(WindowsFirefoxProfileSelection.includes(profile: self.profile, readText: { _ in nil }))
    }

    @Test
    func `platform metadata distinguishes stable ESR and other channels`() {
        let profile = self.profile
        let compatibility = profile.appendingPathComponent("compatibility.ini").path
        let application = URL(fileURLWithPath: "C:\\Synthetic\\Firefox", isDirectory: true)
            .appendingPathComponent("application.ini").path
        for name in ["firefox", "Firefox-ESR", "firefox-beta", "firefox-dev", "firefox-nightly"] {
            let included = WindowsFirefoxProfileSelection.includes(profile: profile) { path in
                if path == compatibility { return "LastPlatformDir=C:\\Synthetic\\Firefox\r\n" }
                if path == application { return "[App]\r\nRemotingName=\(name)\r\n" }
                Issue.record("Unexpected metadata path")
                return nil
            }
            #expect(included == ["firefox", "firefox-esr"].contains(name.lowercased()))
        }
    }

    @Test
    func `app metadata takes precedence and invalid relative paths are not read`() {
        let profile = self.profile
        let compatibility = profile.appendingPathComponent("compatibility.ini").path
        let application = URL(fileURLWithPath: "C:\\Synthetic\\Beta", isDirectory: true)
            .appendingPathComponent("application.ini").path
        #expect(!WindowsFirefoxProfileSelection.includes(profile: profile) { path in
            if path == compatibility {
                return "LastAppDir=C:\\Synthetic\\Beta\\browser\nLastPlatformDir=relative\\directory\n"
            }
            if path == application { return "RemotingName=firefox-beta\n" }
            Issue.record("Unexpected metadata path")
            return nil
        })
    }

    @Test
    func `installation evidence rejects absent executables and mismatched paths`() {
        let compatibility = self.profile.appendingPathComponent("compatibility.ini").path
        let executable = URL(fileURLWithPath: "C:\\Synthetic\\Firefox", isDirectory: true)
            .appendingPathComponent("firefox.exe")
        let read: (String) -> String? = { path in
            path == compatibility ? "LastPlatformDir=C:\\Synthetic\\Firefox\n" : nil
        }
        #expect(WindowsFirefoxProfileSelection.hasInstalledApplication(
            profile: self.profile, readText: read, isRegularFile: { $0 == executable.path }))
        #expect(!WindowsFirefoxProfileSelection.hasInstalledApplication(
            profile: self.profile, readText: read, isRegularFile: { _ in false }))
        #expect(!WindowsFirefoxProfileSelection.hasInstalledApplication(
            profile: self.profile, readText: { _ in nil }, isRegularFile: { _ in true }))
        #expect(!WindowsFirefoxProfileSelection.hasInstalledApplication(
            profile: self.profile, readText: read, isRegularFile: { _ in true },
            applicationURL: URL(fileURLWithPath: "C:\\Other\\firefox.exe")))
        #expect(WindowsFirefoxProfileSelection.hasInstalledApplication(
            profile: self.profile, readText: read, isRegularFile: { $0 == executable.path },
            applicationURL: URL(fileURLWithPath: executable.path.uppercased())))
    }

}
#endif
