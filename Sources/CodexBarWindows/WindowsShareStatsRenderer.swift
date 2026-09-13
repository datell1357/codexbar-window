#if os(Windows)
import Foundation
import WinSDK

/// Draws only the sanitized sharing payload; no account paths or session content enter the card.
enum WindowsShareStatsRenderer {
    static func pngData(payload: WindowsShareStatsPayload, calendar: Calendar) -> Data? {
        let width = 1200, height = 630
        guard payload.hasShareableData, let dc = CreateCompatibleDC(nil) else { return nil }
        defer { DeleteDC(dc) }
        var info = BITMAPINFO()
        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = LONG(width)
        info.bmiHeader.biHeight = -LONG(height)
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = DWORD(BI_RGB)
        var pixels: UnsafeMutableRawPointer?
        guard let bitmap = CreateDIBSection(dc, &info, UINT(DIB_RGB_COLORS), &pixels, nil, 0) else { return nil }
        defer { DeleteObject(bitmap) }
        guard let pixels else { return nil }
        guard let previous = SelectObject(dc, bitmap) else { return nil }
        defer { SelectObject(dc, previous) }
        var rect = RECT(left: 0, top: 0, right: LONG(width), bottom: LONG(height))
        guard let brush = CreateSolidBrush(0x00101114) else { return nil }
        let filled = FillRect(dc, &rect, brush)
        DeleteObject(brush)
        guard filled != 0 else { return nil }
        SetBkMode(dc, Int32(TRANSPARENT))
        func draw(_ value: String, x: Int32, y: Int32, w: Int32, size: Int32, color: COLORREF) -> Bool {
            var font = LOGFONTW()
            font.lfHeight = -size
            font.lfWeight = LONG(FW_NORMAL)
            // Use the system's Unicode-capable default face and grayscale antialiasing.
            font.lfCharSet = BYTE(DEFAULT_CHARSET)
            font.lfQuality = BYTE(ANTIALIASED_QUALITY)
            guard let handle = CreateFontIndirectW(&font) else { return false }
            defer { DeleteObject(handle) }
            guard let old = SelectObject(dc, handle) else { return false }
            defer { SelectObject(dc, old) }
            SetTextColor(dc, color)
            var bounds = RECT(left: x, top: y, right: x + w, bottom: y + size + 12)
            var text = Array(value.utf16) + [UInt16(0)]
            return text.withUnsafeMutableBufferPointer {
                DrawTextW(dc, $0.baseAddress, -1, &bounds, UINT(DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX)) != 0
            }
        }
        let primary: COLORREF = 0x00E8F0F5, secondary: COLORREF = 0x009FA8B3, accent: COLORREF = 0x005C8FED
        guard draw("CodexBar", x: 52, y: 32, w: 600, size: 28, color: primary),
              draw("LOCAL SNAPSHOT", x: 890, y: 40, w: 258, size: 17, color: secondary),
              draw("TRACKED TOKENS · LAST \(payload.days) DAYS", x: 52, y: 91, w: 650, size: 20, color: secondary)
        else { return nil }
        let tokenText = payload.totalTokens.map(WindowsShareStatsFormatting.compactCount) ?? "Unavailable"
        guard draw((payload.hasPartialTokens ? "~" : "") + tokenText, x: 52, y: 122, w: 620, size: 72, color: primary)
        else { return nil }
        for (index, currency) in payload.currencies.prefix(2).enumerated() {
            let amount = currency.estimatedCost.map { WindowsShareStatsFormatting.currency($0, code: currency.currencyCode) } ?? "Unavailable"
            let coverage = WindowsShareStatsFormatting.coverageFraction(covered: currency.coveredDayCount, payload: payload)
            guard draw(amount + " estimated" + (currency.isPartial ? " · partial" : ""),
                       x: 730, y: 108 + Int32(index) * 60, w: 418, size: 24, color: accent),
                  draw(currency.currencyCode + " · " + coverage, x: 730, y: 137 + Int32(index) * 60,
                       w: 418, size: 16, color: secondary) else { return nil }
        }
        if payload.currencies.count > 2 {
            guard draw("+\(payload.currencies.count - 2) other currencies included in text stats", x: 730, y: 213,
                       w: 418, size: 14, color: secondary) else { return nil }
        }
        guard draw("PROVIDERS", x: 52, y: 241, w: 510, size: 18, color: secondary),
              draw("TOP MODELS", x: 640, y: 241, w: 508, size: 18, color: secondary) else { return nil }
        let providerLimit = payload.providers.count > 5 ? 4 : 5
        for (index, provider) in payload.providers.prefix(providerLimit).enumerated() {
            let value = provider.estimatedCost.map { WindowsShareStatsFormatting.currency($0, code: provider.currencyCode) + " est." }
                ?? "Spend unavailable"
            guard draw(provider.providerName + (provider.subscriptionName.map { " · " + $0 } ?? ""),
                       x: 52, y: 278 + Int32(index) * 51, w: 530, size: 22, color: primary),
                  draw(value, x: 52, y: 304 + Int32(index) * 51, w: 530, size: 16, color: secondary) else { return nil }
        }
        if payload.providers.count > providerLimit {
            guard draw("+\(payload.providers.count - providerLimit) more providers included", x: 52, y: 503, w: 530,
                       size: 18, color: secondary) else { return nil }
        }
        for (index, model) in payload.topModels.prefix(5).enumerated() {
            let tokens = model.totalTokens.map(WindowsShareStatsFormatting.compactCount) ?? "Unknown"
            guard draw(model.modelName + " · " + model.providerName, x: 640, y: 278 + Int32(index) * 51,
                       w: 508, size: 22, color: primary),
                  draw(tokens + " tokens", x: 640, y: 304 + Int32(index) * 51, w: 508, size: 16, color: secondary)
            else { return nil }
        }
        let footer = "Generated locally · Data through " + WindowsShareStatsFormatting.dataThrough(payload.periodEnd, calendar: calendar)
        guard draw(footer, x: 52, y: 560, w: 1096, size: 18, color: secondary),
              draw("Estimates may use cached exchange rates. Coverage and totals reflect selected sources.",
                   x: 52, y: 590, w: 1096, size: 14, color: secondary), GdiFlush() != 0 else { return nil }
        let bgra = pixels.assumingMemoryBound(to: UInt8.self)
        var rgb = Data(capacity: width * height * 3)
        for index in stride(from: 0, to: width * height * 4, by: 4) {
            rgb.append(contentsOf: [bgra[index + 2], bgra[index + 1], bgra[index]])
        }
        return WindowsPNGEncoder.encode(width: width, height: height, rgb: rgb)
    }
}
#endif
