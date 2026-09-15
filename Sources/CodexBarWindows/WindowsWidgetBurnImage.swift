#if os(Windows)
import Foundation

/// Solid average-burn segment, dashed ideal pace, dotted projection, and a current-time guide.
public enum WindowsWidgetBurnImage {
    public enum Failure: Error, Sendable { case invalidGeometry, encodingFailed }
    public static func png(_ geometry: WindowsWidgetBurnGeometry, theme: WindowsWidgetHistoryImage.Theme) throws -> Data {
        try self.png(geometry, theme: theme, accessibility: WindowsWidgetChartAccessibility.capture())
    }

    static func png(_ geometry: WindowsWidgetBurnGeometry, theme: WindowsWidgetHistoryImage.Theme,
                    accessibility: WindowsWidgetChartAccessibility?) throws -> Data {
        let t = geometry.elapsedFraction, v = geometry.remainingPercent
        guard t.isFinite, v.isFinite, (0...1).contains(t), (0...100).contains(v),
              geometry.projectionEndFraction.isFinite, (0...1).contains(geometry.projectionEndFraction),
              geometry.projectionEndRemaining.isFinite, (0...100).contains(geometry.projectionEndRemaining)
        else { throw Failure.invalidGeometry }
        let width = 360, height = 72, left = 3, right = 356, top = 4, bottom = 68
        let background: [UInt8] = accessibility?.background ?? (theme == .dark ? [32, 32, 32] : [250, 250, 250])
        let grid: [UInt8] = accessibility?.foreground ?? (theme == .dark ? [90, 90, 90] : [190, 190, 190])
        let ideal: [UInt8] = accessibility?.foreground ?? (theme == .dark ? [180, 180, 180] : [110, 110, 110])
        let standardAccent: [UInt8]
        switch geometry.status {
        case .conserving: standardAccent = theme == .dark ? [80, 210, 160] : [0, 130, 85]
        case .onPace: standardAccent = theme == .dark ? [110, 190, 255] : [0, 105, 190]
        case .overPace: standardAccent = theme == .dark ? [255, 135, 105] : [190, 65, 25]
        }
        let accent = accessibility?.foreground ?? standardAccent
        var pixels = [UInt8](repeating: 0, count: width * height * 3)
        for offset in stride(from: 0, to: pixels.count, by: 3) {
            pixels[offset] = background[0]; pixels[offset + 1] = background[1]; pixels[offset + 2] = background[2]
        }
        func pixel(_ x: Int, _ y: Int, _ color: [UInt8]) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let offset = (y * width + x) * 3
            pixels[offset] = color[0]; pixels[offset + 1] = color[1]; pixels[offset + 2] = color[2]
        }
        func x(_ fraction: Double) -> Int { left + Int((fraction * Double(right - left)).rounded()) }
        func y(_ remaining: Double) -> Int { top + Int(((1 - remaining / 100) * Double(bottom - top)).rounded()) }
        func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, color: [UInt8], dash: Int = 0, thick: Bool = false) {
            let steps = max(1, max(abs(x1 - x0), abs(y1 - y0)))
            for step in 0...steps {
                if dash > 0, (step / dash) % 2 != 0 { continue }
                let fraction = Double(step) / Double(steps)
                let px = x0 + Int((Double(x1 - x0) * fraction).rounded())
                let py = y0 + Int((Double(y1 - y0) * fraction).rounded())
                pixel(px, py, color)
                if thick { pixel(px, py - 1, color) }
            }
        }
        let currentX = x(t), currentY = y(v)
        for px in left...currentX where accessibility == nil {
            let progress = Double(px - left) / Double(max(1, currentX - left))
            let upper = y(100 + (v - 100) * progress)
            for py in upper...bottom {
                let opacity = 0.25 * Double(bottom - py) / Double(max(1, bottom - top))
                let color = zip(background, accent).map { UInt8(Double($0) * (1 - opacity) + Double($1) * opacity) }
                pixel(px, py, color)
            }
        }
        line(left, bottom, right, bottom, color: grid)
        line(currentX, top, currentX, bottom, color: grid)
        line(left, top, right, bottom, color: ideal, dash: 4)
        if geometry.slope < -0.01 {
            line(currentX, currentY, x(geometry.projectionEndFraction), y(geometry.projectionEndRemaining), color: accent, dash: 2)
        }
        line(left, top, currentX, currentY, color: accent, thick: true)
        for dx in -2...2 { for dy in -2...2 { if dx * dx + dy * dy <= 4 { pixel(currentX + dx, currentY + dy, accent) } } }
        guard let png = WindowsPNGEncoder.encode(width: width, height: height, rgb: Data(pixels), preferIndexed: true) else { throw Failure.encodingFailed }
        return png
    }
}
#endif
