#if os(Windows)
import CodexBarCore
import Foundation

/// Original widget's average-burn projection, not sampled historical usage.
public struct WindowsWidgetBurnGeometry: Sendable {
    public enum Status: Sendable { case conserving, onPace, overPace }
    public enum Failure: Error, Sendable { case invalidWindow }
    public let remainingPercent: Double
    public let elapsedFraction: Double
    public let idealRemainingPercent: Double
    public let margin: Double
    public let slope: Double
    public let projectionEndFraction: Double
    public let projectionEndRemaining: Double
    public let runsOutWithinWindow: Bool
    public let effectiveResetAt: Date?
    /// Suppressed during the first 8% of a window, matching the original fresh-window policy.
    public let estimatedRunOutAt: Date?
    public var depleted: Bool { self.remainingPercent <= 0.5 }
    public var fresh: Bool { self.remainingPercent >= 99.5 }
    public var status: Status { self.margin > 4 ? .conserving : self.margin < -4 ? .overPace : .onPace }

    public init(window: RateWindow, now: Date, blankChart: Bool = false, resetOverride: Date? = nil) throws {
        guard now.timeIntervalSince1970.isFinite, window.usedPercent.isFinite,
              window.resetsAt?.timeIntervalSince1970.isFinite ?? true,
              resetOverride?.timeIntervalSince1970.isFinite ?? true else { throw Failure.invalidWindow }
        let minutes = window.windowMinutes ?? 300
        guard minutes > 0 else { throw Failure.invalidWindow }
        let remaining = max(0, min(100, window.remainingPercent))
        let t: Double
        if let reset = window.resetsAt, let windowMinutes = window.windowMinutes {
            let minutesLeft = max(0, reset.timeIntervalSince(now) / 60)
            t = max(0.001, min(0.999, (Double(windowMinutes) - minutesLeft) / Double(windowMinutes)))
        } else { t = max(0.001, min(0.999, window.usedPercent / 100)) }
        let slope = t > 0.001 ? (remaining - 100) / t : -remaining
        let endT: Double, endV: Double, runsOut: Bool
        if slope < -0.01 {
            let out = t + remaining / -slope
            if out <= 1 { endT = out; endV = 0; runsOut = true }
            else { endT = 1; endV = max(0, remaining + slope * (1 - t)); runsOut = false }
        } else { endT = 1; endV = remaining; runsOut = false }
        let explicitReset = blankChart ? resetOverride : resetOverride ?? window.resetsAt
        let effectiveReset: Date?
        if let explicitReset { effectiveReset = explicitReset > now ? explicitReset : nil }
        else if !blankChart { effectiveReset = now.addingTimeInterval((1 - t) * Double(minutes) * 60) }
        else { effectiveReset = nil }
        let runOut: Date?
        if !blankChart, t >= 0.08, runsOut, slope < -0.01, let reset = effectiveReset {
            let estimate = now.addingTimeInterval(remaining / -slope * Double(minutes) * 60)
            runOut = estimate < reset ? estimate : nil
        } else { runOut = nil }
        self.remainingPercent = remaining; self.elapsedFraction = t
        self.idealRemainingPercent = 100 * (1 - t); self.margin = remaining - self.idealRemainingPercent
        self.slope = slope; self.projectionEndFraction = endT; self.projectionEndRemaining = endV
        self.runsOutWithinWindow = runsOut; self.effectiveResetAt = effectiveReset; self.estimatedRunOutAt = runOut
    }
}
#endif
