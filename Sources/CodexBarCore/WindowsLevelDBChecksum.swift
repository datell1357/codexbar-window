#if os(Windows)
import Foundation

enum WindowsLevelDBChecksum {
    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0x82F63B78)
        }
        return crc
    }

    static func maskedCRC(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var crc = UInt32.max
        for byte in bytes { crc = self.crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        crc = ~crc
        return ((crc >> 15) | (crc << 17)) &+ 0xA282EAD8
    }
}
#endif
