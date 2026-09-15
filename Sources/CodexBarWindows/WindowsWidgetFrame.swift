#if os(Windows)
import Foundation

/// CBW1 + little-endian UInt32 byte length + UTF-8 JSON bytes. Authentication belongs to the pipe endpoint.
public enum WindowsWidgetFrame {
    public static let maximumPayloadBytes = 256 * 1024
    public enum Failure: Error, Sendable { case oversized, malformed, truncated, closed }
    public static func encode(_ payload: Data) throws -> Data {
        guard !payload.isEmpty else { throw Failure.malformed }
        guard payload.count <= maximumPayloadBytes else { throw Failure.oversized }
        let length = UInt32(payload.count)
        var result = Data([0x43, 0x42, 0x57, 0x31])
        for shift in stride(from: 0, to: 32, by: 8) {
            result.append(UInt8(truncatingIfNeeded: length >> shift))
        }
        result.append(payload)
        return result
    }
    public struct Decoder: Sendable {
        private var header: [UInt8] = []
        private var payload: [UInt8] = []
        private var expected = 0
        private var closed = false
        public init() {}

        /// Bound reads to this size. A malformed stream is terminal; discard this decoder on reconnect.
        public mutating func consume(_ chunk: Data) throws -> [Data] {
            guard !self.closed else { throw Failure.closed }
            do {
                guard chunk.count <= maximumPayloadBytes + 8 else { throw Failure.oversized }
                var frames: [Data] = []
                for byte in chunk {
                    if self.expected == 0 {
                        self.header.append(byte)
                        if self.header.count == 8 {
                            guard Array(self.header.prefix(4)) == [0x43, 0x42, 0x57, 0x31] else { throw Failure.malformed }
                            let count = (0..<4).reduce(UInt32(0)) { $0 | (UInt32(self.header[4 + $1]) << ($1 * 8)) }
                            guard count > 0 else { throw Failure.malformed }
                            guard count <= maximumPayloadBytes else { throw Failure.oversized }
                            self.expected = Int(count)
                            self.payload.reserveCapacity(self.expected)
                            self.header.removeAll(keepingCapacity: true)
                        }
                    } else {
                        self.payload.append(byte)
                        if self.payload.count == self.expected {
                            guard frames.count < 128 else { throw Failure.oversized }
                            frames.append(Data(self.payload))
                            self.payload.removeAll(keepingCapacity: true)
                            self.expected = 0
                        }
                    }
                }
                return frames
            } catch {
                self.closed = true
                self.header = []; self.payload = []; self.expected = 0
                throw error
            }
        }
        public mutating func finish() throws {
            guard !self.closed else { throw Failure.closed }
            self.closed = true
            let partial = !self.header.isEmpty || self.expected != 0
            self.header = []; self.payload = []; self.expected = 0
            if partial { throw Failure.truncated }
        }
    }
}
#endif
