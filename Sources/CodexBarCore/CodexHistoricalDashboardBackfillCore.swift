import Foundation

/// Pure selection logic for Codex dashboard historical backfill.
///
/// The caller remains responsible for persisting the selected breakdown. This
/// helper only binds an authorized live dashboard to the reference weekly
/// window and calibration timestamp, or to a closely timed fallback window.
public enum CodexHistoricalDashboardBackfillCore {
    public struct Candidate: Sendable {
        public let usageBreakdown: [OpenAIDashboardDailyBreakdown]
        public let referenceWindow: RateWindow
        public let calibrationAt: Date
        public let attachedAccountEmail: String?

        public init(
            usageBreakdown: [OpenAIDashboardDailyBreakdown],
            referenceWindow: RateWindow,
            calibrationAt: Date,
            attachedAccountEmail: String?)
        {
            self.usageBreakdown = usageBreakdown
            self.referenceWindow = referenceWindow
            self.calibrationAt = calibrationAt
            self.attachedAccountEmail = attachedAccountEmail
        }
    }

    public static func candidate(
        authorizedDashboard: CodexAuthorizedDashboard,
        fallbackWeekly: RateWindow?,
        fallbackUpdatedAt: Date?) -> Candidate?
    {
        let decision = authorizedDashboard.decision
        guard authorizedDashboard.input.sourceKind == .liveWeb,
              decision.disposition == .attach,
              decision.allowedEffects.contains(.historicalBackfill)
        else { return nil }

        let usageBreakdown = OpenAIDashboardDailyBreakdown.removingSkillUsageServices(
            from: authorizedDashboard.dashboard.usageBreakdown)
        guard !usageBreakdown.isEmpty else { return nil }

        let attachedAccountEmail = CodexCLIDashboardAuthorityContext.attachmentEmail(
            from: authorizedDashboard.input)
        if let dashboardWeekly = CodexReconciledState.fromAttachedDashboard(
            snapshot: authorizedDashboard.dashboard,
            provider: .codex,
            accountEmail: attachedAccountEmail,
            accountPlan: nil)?.weekly
        {
            return Candidate(
                usageBreakdown: usageBreakdown,
                referenceWindow: dashboardWeekly,
                calibrationAt: authorizedDashboard.dashboard.updatedAt,
                attachedAccountEmail: attachedAccountEmail)
        }

        guard let fallbackWeekly,
              let fallbackUpdatedAt,
              abs(fallbackUpdatedAt.timeIntervalSince(authorizedDashboard.dashboard.updatedAt)) <= 5 * 60
        else { return nil }

        return Candidate(
            usageBreakdown: usageBreakdown,
            referenceWindow: fallbackWeekly,
            calibrationAt: min(fallbackUpdatedAt, authorizedDashboard.dashboard.updatedAt),
            attachedAccountEmail: attachedAccountEmail)
    }
}
