#if os(Windows)
import Foundation
import Testing
@testable import CodexBarWindows

/// Pure synthetic wire fixtures. These do not launch the UI, open pipes, or read persisted settings.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowsAppProtocolTests {
    private static func settings(_ bits: Int = 0) -> WindowsAppProtocol.Settings {
        .init(.init(hidePersonalInfo: bits & 1 != 0, showOptionalCreditsAndExtraUsage: bits & 2 != 0,
            usageBarsShowUsed: bits & 4 != 0, resetTimesShowAbsolute: bits & 8 != 0))
    }

    @Test
    func `length prefix is little endian and respects the request boundary`() throws {
        #expect(try WindowsAppProtocol.header(length: 513) == Data([1, 2, 0, 0]))
        #expect(try WindowsAppProtocol.length(Data([0, 16, 0, 0]), limit: 4096) == 4096)
        #expect(throws: WindowsAppProtocol.Failure.self) {
            try WindowsAppProtocol.length(Data([1, 16, 0, 0]), limit: 4096)
        }
    }

    @Test
    func `truncated zero and oversized frames are rejected before allocation`() {
        for bytes in [Data(), Data([1, 0, 0]), Data([0, 0, 0, 0]), Data([255, 255, 255, 255])] {
            #expect(throws: WindowsAppProtocol.Failure.self) {
                try WindowsAppProtocol.length(bytes, limit: WindowsAppProtocol.maximumRequestBytes)
            }
        }
        for count in [-1, 0, WindowsAppProtocol.maximumResponseBytes + 1] {
            #expect(throws: WindowsAppProtocol.Failure.self) { try WindowsAppProtocol.header(length: count) }
        }
    }

    @Test
    func `hello accepts the dotnet null optional fields and camel case UUID keys`() throws {
        let data = Data(#"{"protocolVersion":1,"requestID":"11111111-2222-3333-4444-555555555555","generation":null,"method":"hello","mutation":null}"#.utf8)
        let request = try WindowsAppProtocol.request(data)
        #expect(request.requestID.uuidString == "11111111-2222-3333-4444-555555555555")
        #expect(request.protocolVersion == 1)
        #expect(request.generation == nil)
        #expect(request.mutation == nil)
        #expect(request.method == "hello")
    }

    @Test
    func `missing request ID and malformed mutation do not acquire authority`() {
        for json in [
            #"{"protocolVersion":1,"method":"hello"}"#,
            #"{"protocolVersion":1,"requestID":"not-a-uuid","method":"hello"}"#,
            #"{"protocolVersion":1,"requestID":"11111111-2222-3333-4444-555555555555","method":"setSetting","mutation":{"key":"hidePersonalInfo","value":"true","expectedSettingsRevision":"revision"}}"#
        ] {
            #expect(throws: DecodingError.self) { try WindowsAppProtocol.request(Data(json.utf8)) }
        }
    }

    @Test
    func `request envelope is bounded independently of JSON validity`() {
        #expect(throws: WindowsAppProtocol.Failure.self) { try WindowsAppProtocol.request(Data()) }
        #expect(throws: WindowsAppProtocol.Failure.self) {
            try WindowsAppProtocol.request(Data(repeating: 32, count: WindowsAppProtocol.maximumRequestBytes + 1))
        }
    }

    @Test
    func `each display settings combination has a stable distinct revision`() {
        let revisions = (0..<16).map { Self.settings($0).revision }
        #expect(Set(revisions).count == 16)
        #expect(revisions.allSatisfy { $0.count == 64 })
        #expect(Self.settings(5).revision == Self.settings(5).revision)
        #expect(WindowsAppProtocol.Settings.keys == [
            "hidePersonalInfo", "showOptionalCreditsAndExtraUsage", "usageBarsShowUsed", "resetTimesShowAbsolute"
        ])
        #expect(!WindowsAppProtocol.Settings.keys.contains("apiKey"))
    }

    @Test
    func `display byte limits preserve Unicode scalar boundaries`() {
        let bounded = WindowsAppProtocol.boundedText("한글abc", maximumUTF8Bytes: 4)
        #expect(bounded.text == "한")
        #expect(bounded.truncated)
        let exact = WindowsAppProtocol.boundedText("한글", maximumUTF8Bytes: 6)
        #expect(exact.text == "한글")
        #expect(!exact.truncated)
        #expect(WindowsAppProtocol.boundedText("x", maximumUTF8Bytes: 0).truncated)
    }

    @Test
    func `a single grapheme cannot bypass the payload budget`() {
        let value = "a" + String(repeating: "\u{0301}", count: 10000)
        let bounded = WindowsAppProtocol.boundedText(value, maximumUTF8Bytes: 512)
        #expect(bounded.text.utf8.count <= 512)
        #expect(bounded.truncated)
    }

    @Test
    func `response wire names and absent snapshot match the WinUI reader`() throws {
        let requestID = UUID()
        let generation = UUID()
        let data = try WindowsAppProtocol.response(.init(protocolVersion: 1, requestID: requestID,
            generation: generation, status: "stopped", snapshot: nil, activation: 9))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["requestID"] as? String == requestID.uuidString)
        #expect(object["generation"] as? String == generation.uuidString)
        #expect(object["activation"] as? Int == 9)
        #expect(object["snapshot"] == nil)
        #expect(Set(object.keys) == ["protocolVersion", "requestID", "generation", "status", "activation"])
    }

    @Test
    func `escaped display budget leaves room for the response structure`() throws {
        // An ASCII control needs six JSON bytes; 96 KiB is the runtime's total display-text budget.
        let text = String(repeating: "\u{0001}", count: 512)
        let settings = Self.settings()
        let snapshot = WindowsAppProtocol.Snapshot(
            providers: (0..<64).map { .init(id: "", title: "", rows: [text, text, text]) },
            notices: [], spendSummary: "", refreshing: false, truncated: true, settings: settings,
            settingsRevision: settings.revision)
        let data = try WindowsAppProtocol.response(.init(protocolVersion: 1, requestID: UUID(),
            generation: UUID(), status: "ok", snapshot: snapshot))
        #expect(data.count < WindowsAppProtocol.maximumResponseBytes)
        let decoded = try JSONDecoder().decode(WindowsAppProtocol.Response.self, from: data)
        #expect(decoded.snapshot?.providers.count == 64)
        #expect(decoded.snapshot?.truncated == true)
        #expect(decoded.snapshot?.settings == settings)
    }

    @Test
    func `oversized encoded responses are never sent`() {
        let settings = Self.settings()
        let snapshot = WindowsAppProtocol.Snapshot(providers: [], notices: [],
            spendSummary: String(repeating: "x", count: WindowsAppProtocol.maximumResponseBytes),
            refreshing: false, truncated: false, settings: settings, settingsRevision: settings.revision)
        #expect(throws: WindowsAppProtocol.Failure.self) {
            try WindowsAppProtocol.response(.init(protocolVersion: 1, requestID: UUID(),
                generation: UUID(), status: "ok", snapshot: snapshot))
        }
    }
}
#endif
