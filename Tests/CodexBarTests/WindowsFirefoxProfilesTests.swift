#if os(Windows)
import Foundation
import Testing
@testable import CodexBarCore

struct WindowsFirefoxProfilesTests {
    private let root = URL(fileURLWithPath: "C:/Synthetic/Roaming/Mozilla/Firefox", isDirectory: true)

    @Test
    func `reads a normal Windows CRLF registry`() {
        let text = "[Profile0]\r\nName=Work\r\nIsRelative=1\r\nPath=Profiles/work\r\n"
        #expect(WindowsFirefoxProfiles.profileDirectories(in: text, relativeTo: self.root) == [
            self.root.appendingPathComponent("Profiles/work", isDirectory: true).standardizedFileURL,
        ])
    }

    @Test
    func `resolves registered relative and absolute profiles without guessing names`() {
        let text = """
        [Profile0]
        Name=Work
        IsRelative=1
        Path=Profiles/custom.work
        [Profile1]
        Name=External
        IsRelative=0
        Path=D:\\BrowserData\\Work
        [Profile2]
        Name=Shared
        IsRelative=1
        Path=../SharedProfile
        """
        #expect(WindowsFirefoxProfiles.profileDirectories(in: text, relativeTo: self.root) == [
            self.root.appendingPathComponent("Profiles/custom.work", isDirectory: true).standardizedFileURL,
            URL(fileURLWithPath: "D:\\BrowserData\\Work", isDirectory: true).standardizedFileURL,
            self.root.deletingLastPathComponent().appendingPathComponent("SharedProfile", isDirectory: true).standardizedFileURL,
        ])
    }

    @Test
    func `missing relative flag stops but missing name only skips a profile`() {
        let text = """
        [Profile0]
        IsRelative=1
        Path=Profiles/skipped
        [Profile1]
        Name=
        IsRelative=1
        Path=Profiles/retained
        [Profile2]
        Name=NoFlag
        Path=Profiles/missing
        [Profile3]
        Name=Later
        IsRelative=1
        Path=Profiles/notVisited
        """
        #expect(WindowsFirefoxProfiles.profileDirectories(in: text, relativeTo: self.root) == [
            self.root.appendingPathComponent("Profiles/retained", isDirectory: true).standardizedFileURL,
        ])
    }

    @Test
    func `preserves value whitespace and last duplicate keys and tolerates unclosed header`() {
        let text = "\u{FEFF}[Profile0\r\nName=Work\r\nIsRelative=1\r\nPath=Profiles/old\r\n" +
            "[Profile0]\nPath=Profiles/new\n[Profile1]\nName=Skip\nIsRelative= 1\nPath=Profiles/skipped\n"
        #expect(WindowsFirefoxProfiles.profileDirectories(in: text, relativeTo: self.root) == [
            self.root.appendingPathComponent("Profiles/new", isDirectory: true).standardizedFileURL,
        ])
    }

    @Test
    func `firefox locator uses roaming registry and does not enable cookie import`() {
        let root = self.root
        let profile = root.appendingPathComponent("Profiles/custom", isDirectory: true).standardizedFileURL
        let registry = root.appendingPathComponent("profiles.ini").path
        let text = "[Profile0]\nName=Custom\nIsRelative=1\nPath=Profiles/custom\n"
        let detection = BrowserDetection(
            homeDirectory: "C:/UnusedHome",
            fileExists: { $0 == registry },
            directoryContents: { $0 == profile.path ? [] : nil },
            environment: ["appdata": "C:/Synthetic/Roaming"],
            readText: { $0 == registry ? text : nil })
        #expect(detection.hasUsableProfileData(.firefox))
        #expect(!detection.isCookieSourceAvailable(.firefox))
        #expect(!detection.isAppInstalled(.firefox))
    }
}
#endif
