import Foundation

/// Shared pace calculations and candidate assembly used by predictive quota warnings.
public enum PredictivePaceWarningCandidateCore {
    public struct SourceWindows: Sendable {
        public let session: RateWindow?
        public let weekly: RateWindow?

        public init(session: RateWindow?, weekly: RateWindow?) {
            self.session = session
            self.weekly = weekly
        }
    }

    public struct Candidate: Sendable {
        public let window: QuotaWarningWindow
        public let rateWindow: RateWindow
        public let pace: UsagePace

        public init(window: QuotaWarningWindow, rateWindow: RateWindow, pace: UsagePace) {
            self.window = window
            self.rateWindow = rateWindow
            self.pace = pace
        }
    }

    public static func sessionPace(
        provider: UsageProvider,
        window: RateWindow,
        now: Date = .init()) -> UsagePace?
    {
        let capability = ProviderDescriptorRegistry.descriptor(for: provider).pace
        guard capability.supportsSessionPace(window: window, now: now),
              window.remainingPercent > 0,
              let pace = UsagePace.weekly(window: window, now: now, defaultWindowMinutes: 300),
              pace.expectedUsedPercent >= 3
        else { return nil }
        return pace
    }

    public static func linearWeeklyPace(
        provider: UsageProvider,
        window: RateWindow,
        dataConfidence: UsageDataConfidence,
        now: Date = .init(),
        workDays: Int? = nil) -> UsagePace?
    {
        let capability = ProviderDescriptorRegistry.descriptor(for: provider).pace
        guard capability.allowsPace(dataConfidence: dataConfidence),
              window.remainingPercent > 0
        else { return nil }

        let paceWindow: RateWindow
        if let windowMinutes = window.windowMinutes, windowMinutes > 0 {
            // Codex's caller-selected projection already resolves its historical window. Other
            // providers expand calendar-month sentinels before applying linear pacing.
            paceWindow = provider == .codex ? window : capability.resolvedResetWindowForPace(window)
        } else {
            return nil
        }

        guard let pace = UsagePace.weekly(
            window: paceWindow,
            now: now,
            defaultWindowMinutes: 10080,
            workDays: workDays),
            pace.expectedUsedPercent >= 3
        else { return nil }
        return pace
    }

    public static func candidates(
        provider: UsageProvider,
        sourceWindows: SourceWindows,
        weeklyPace: UsagePace?,
        now: Date = .init()) -> [Candidate]
    {
        guard provider == .codex || provider == .claude else { return [] }

        var result: [Candidate] = []
        if let sessionWindow = sourceWindows.session,
           !sessionWindow.isSyntheticPlaceholder,
           let pace = Self.sessionPace(provider: provider, window: sessionWindow, now: now)
        {
            result.append(Candidate(window: .session, rateWindow: sessionWindow, pace: pace))
        }
        if let weeklyWindow = sourceWindows.weekly, let weeklyPace {
            result.append(Candidate(window: .weekly, rateWindow: weeklyWindow, pace: weeklyPace))
        }
        return result
    }
}
