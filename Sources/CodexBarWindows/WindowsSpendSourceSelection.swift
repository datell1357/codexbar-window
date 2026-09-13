#if os(Windows)
import Foundation

public struct WindowsSpendSourceSelection: Sendable {
    public struct Entry: Sendable {
        public let id: String
        public let title: String
        public let included: Bool
    }
    public let generation: UInt64
    public let entries: [Entry]
}

public enum WindowsSpendSourceMutation: Sendable {
    case setIncluded(id: String, included: Bool)
    case showAll
    case hideAll
}

public enum WindowsSpendSourceResult: Sendable {
    case selection(WindowsSpendSourceSelection)
    case saved
    case unavailable(String)
}
#endif
