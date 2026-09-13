#if os(Windows)
import Foundation

/// Encodes a bounded RGB raster using PNG's lossless, uncompressed DEFLATE blocks.
/// Keeping this encoder small avoids another native codec dependency for share cards.
enum WindowsPNGEncoder {
    static func encode(width: Int, height: Int, rgb: Data) -> Data? {
        guard width > 0, height > 0, width <= 2048, height <= 2048,
              rgb.count == width * height * 3 else { return nil }
        var scanlines = Data(capacity: rgb.count + height)
        for row in 0..<height {
            scanlines.append(0) // PNG filter: None.
            scanlines.append(rgb[(row * width * 3)..<((row + 1) * width * 3)])
        }
        var zlib = Data([0x78, 0x01])
        var offset = 0
        while offset < scanlines.count {
            let count = min(65535, scanlines.count - offset)
            zlib.append(offset + count == scanlines.count ? 1 : 0)
            let length = UInt16(count)
            let inverse = ~length
            zlib.append(contentsOf: [UInt8(truncatingIfNeeded: length), UInt8(length >> 8),
                                    UInt8(truncatingIfNeeded: inverse), UInt8(inverse >> 8)])
            zlib.append(scanlines[offset..<(offset + count)])
            offset += count
        }
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in scanlines { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        appendBigEndian((b << 16) | a, to: &zlib)
        var png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        var header = Data()
        appendBigEndian(UInt32(width), to: &header)
        appendBigEndian(UInt32(height), to: &header)
        header.append(contentsOf: [8, 2, 0, 0, 0]) // RGB, 8 bits/channel, no interlace.
        chunk("IHDR", bytes: header, into: &png)
        chunk("IDAT", bytes: zlib, into: &png)
        chunk("IEND", bytes: Data(), into: &png)
        return png
    }

    private static func appendBigEndian(_ value: UInt32, to data: inout Data) {
        data.append(contentsOf: [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
                                UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
    }

    private static func chunk(_ type: String, bytes: Data, into output: inout Data) {
        appendBigEndian(UInt32(bytes.count), to: &output)
        let tag = Data(type.utf8)
        output.append(tag)
        output.append(bytes)
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in tag + bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xEDB8_8320 : 0) }
        }
        appendBigEndian(crc ^ 0xFFFF_FFFF, to: &output)
    }
}
#endif
