#if os(Windows)
import Foundation

/// Fixed-size in-memory chart. Calendar gaps remain blank; unknown observations get a separate baseline marker.
public enum WindowsWidgetHistoryImage {
    public enum Theme: Sendable { case light, dark }
    public enum Failure: Error, Sendable { case invalidHistory, encodingFailed }

    public static func png(_ history: WindowsWidgetHistory, theme: Theme, height: Int = 100) throws -> Data {
        try self.png(history, theme: theme, height: height, accessibility: WindowsWidgetChartAccessibility.capture())
    }

    static func png(_ history: WindowsWidgetHistory, theme: Theme, height: Int,
                    accessibility: WindowsWidgetChartAccessibility?) throws -> Data {
        guard (50...100).contains(height), history.points.count <= 366, (0...366).contains(history.calendarDayCount),
              history.maximum.isFinite, history.maximum >= 0 else { throw Failure.invalidHistory }
        let width = 400, left = 4, right = 396, baseline = height - 8, top = 4
        let background: [UInt8] = accessibility?.background ?? (theme == .dark ? [32, 32, 32] : [250, 250, 250])
        let grid: [UInt8] = accessibility?.foreground ?? (theme == .dark ? [96, 96, 96] : [190, 190, 190])
        let bar: [UInt8] = accessibility?.foreground ?? (theme == .dark ? [110, 190, 255] : [0, 105, 190])
        let unknown: [UInt8] = accessibility?.foreground ?? (theme == .dark ? [255, 192, 90] : [145, 90, 0])
        var pixels = [UInt8](repeating: 0, count: width * height * 3)
        for offset in stride(from: 0, to: pixels.count, by: 3) {
            pixels[offset] = background[0]; pixels[offset + 1] = background[1]; pixels[offset + 2] = background[2]
        }
        func rectangle(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ color: [UInt8]) {
            guard x0 < x1, y0 < y1 else { return }
            for y in max(0, y0)..<min(height, y1) {
                for x in max(0, x0)..<min(width, x1) {
                    let offset = (y * width + x) * 3
                    pixels[offset] = color[0]; pixels[offset + 1] = color[1]; pixels[offset + 2] = color[2]
                }
            }
        }
        rectangle(left, baseline, right, baseline + 1, grid)
        var previous = -1
        for point in history.points {
            guard point.dayOffset > previous, point.dayOffset < history.calendarDayCount else { throw Failure.invalidHistory }
            previous = point.dayOffset
            let slot = Double(right - left) / Double(max(1, history.calendarDayCount))
            let start = left + Int(Double(point.dayOffset) * slot)
            let end = min(right, max(start + 1, left + Int(Double(point.dayOffset + 1) * slot) - (slot >= 3 ? 1 : 0)))
            if let value = point.value, let fraction = point.fraction {
                guard value.isFinite, value >= 0, fraction.isFinite, (0...1).contains(fraction) else { throw Failure.invalidHistory }
                let barHeight = value == 0 ? 2 : max(3, Int(fraction * Double(baseline - top)))
                rectangle(start, baseline - barHeight, end, baseline, bar)
            } else {
                guard point.value == nil, point.fraction == nil else { throw Failure.invalidHistory }
                rectangle(start, baseline + 3, end, baseline + 6, unknown)
            }
        }
        guard let encoded = WindowsPNGEncoder.encode(width: width, height: height, rgb: Data(pixels), preferIndexed: true) else { throw Failure.encodingFailed }
        return encoded
    }
}
#endif
