#if os(Windows)
import Foundation

/// Encodes a bounded RGB raster using PNG's lossless, uncompressed DEFLATE blocks.
/// Keeping this encoder small avoids another native codec dependency for share cards.
enum WindowsPNGEncoder {
    static func encode(width: Int, height: Int, rgb: Data, preferIndexed: Bool = false) -> Data? {
        guard width > 0, height > 0, width <= 2048, height <= 2048,
              rgb.count == width * height * 3 else { return nil }
        let indexed = preferIndexed ? indexedRaster(rgb) : nil
        let raster = indexed?.pixels ?? rgb
        let stride = width * (indexed == nil ? 3 : 1)
        var scanlines = Data(capacity: raster.count + height)
        for row in 0..<height {
            scanlines.append(0) // PNG filter: None.
            let start = raster.startIndex + row * stride
            scanlines.append(raster[start..<(start + stride)])
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
        header.append(contentsOf: [8, indexed == nil ? 2 : 3, 0, 0, 0]) // 8-bit RGB or palette index.
        chunk("IHDR", bytes: header, into: &png)
        if let indexed { chunk("PLTE", bytes: indexed.palette, into: &png) }
        chunk("IDAT", bytes: zlib, into: &png)
        chunk("IEND", bytes: Data(), into: &png)
        return png
    }

    /// Exact colors only: no quantization, changed pixels, or resolution reduction.
    /// A raster with more than 256 colors falls back to the original RGB encoding.
    private static func indexedRaster(_ rgb: Data) -> (pixels: Data, palette: Data)? {
        var indices = [UInt32: UInt8]()
        var palette = Data()
        var pixels = Data(capacity: rgb.count / 3)
        var offset = rgb.startIndex
        while offset < rgb.endIndex {
            let red = rgb[offset], green = rgb[offset + 1], blue = rgb[offset + 2]
            let color = (UInt32(red) << 16) | (UInt32(green) << 8) | UInt32(blue)
            if let index = indices[color] { pixels.append(index) }
            else {
                guard indices.count < 256 else { return nil }
                let index = UInt8(indices.count)
                indices[color] = index
                palette.append(contentsOf: [red, green, blue])
                pixels.append(index)
            }
            offset += 3
        }
        // PLTE adds 12 bytes of chunk framing in addition to the palette itself.
        guard pixels.count + palette.count + 12 < rgb.count else { return nil }
        return (pixels, palette)
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
