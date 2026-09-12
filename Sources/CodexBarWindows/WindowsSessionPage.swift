#if os(Windows)
import Foundation

public struct WindowsSessionPageRequest: Sendable {
    public let index: Int
    public let generation: UInt64
}

/// A bounded view over an existing result set. Paging never launches a scan by itself.
public struct WindowsSessionPage: Sendable {
    public let index: Int
    public let count: Int
    public let totalItems: Int
    public let range: Range<Int>
    public let generation: UInt64

    public static let empty = Self(index: 0, totalItems: 0, generation: 0)

    public init(index: Int, totalItems: Int, generation: UInt64, pageSize: Int = 32) {
        let total = max(0, totalItems)
        let size = max(1, pageSize)
        let count = max(1, total / size + (total % size == 0 ? 0 : 1))
        let selected = min(max(0, index), count - 1)
        let lower = selected * size
        self.index = selected
        self.count = count
        self.totalItems = total
        self.range = lower..<(lower + min(size, total - lower))
        self.generation = generation
    }

    public var previous: WindowsSessionPageRequest? {
        self.index > 0 ? .init(index: self.index - 1, generation: self.generation) : nil
    }
    public var next: WindowsSessionPageRequest? {
        self.index + 1 < self.count ? .init(index: self.index + 1, generation: self.generation) : nil
    }
    public var title: String {
        "Page \(self.index + 1) of \(self.count) · \(self.totalItems) entries"
    }
}
#endif
