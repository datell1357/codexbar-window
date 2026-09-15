#if os(Windows)
import CodexBarCore
import Foundation

enum WindowsSessionEquivalentForecastText {
    static func lines(_ forecast: SessionEquivalentForecastCore, workDays: Int?,
                      localization: WindowsStatusLocalization.Snapshot = .init()) -> [String] {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: localization.language)
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        let raw = forecast.estimatedWindowsToExhaustWeekly
        let estimate = raw.isFinite && raw > 0 ? (min(raw, 1_000_000) * 10).rounded() / 10 : 0
        func number(_ value: Double) -> String {
            formatter.string(from: NSNumber(value: value)) ?? String(value)
        }
        var lines = [
            localization.text("plan_forecast_estimate").replacingOccurrences(of: "{count}", with: number(estimate)),
            localization.text("plan_forecast_windows").replacingOccurrences(of: "{count}", with: number(Double(forecast.windowsUntilReset))),
            localization.text("plan_forecast_samples").replacingOccurrences(of: "{count}", with: number(Double(forecast.sampleCount))),
        ]
        if let workDays, workDays >= 2, workDays < 7 {
            lines.append(localization.text("plan_forecast_workDays").replacingOccurrences(of: "{count}", with: number(Double(workDays))))
        }
        return lines
    }
}
#endif
