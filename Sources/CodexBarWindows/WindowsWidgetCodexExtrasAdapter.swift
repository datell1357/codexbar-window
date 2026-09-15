#if os(Windows)
import CodexBarCore
import Foundation

/// Projects optional values from the same fetch result as the quota observation.
/// Dashboard ownership decisions remain bound to their authorized snapshot.
enum WindowsWidgetCodexExtrasAdapter {
    static func make(presentation: WindowsUsagePresentation, accountRevision: UUID)
        -> WindowsWidgetSnapshotBuilder.CodexExtras?
    {
        guard presentation.provider == .codex, presentation.showOptionalUsage,
              let result = presentation.result else { return nil }
        let credits = result.credits.flatMap { $0.balanceReadSucceeded ? $0 : nil }
        let review: Double?
        let visibility: WindowsWidgetSnapshotBuilder.CodexExtras.DashboardVisibility
        var timestamps: [Date] = []
        if let authorized = result.authorizedDashboard {
            guard authorized.decision.disposition == .attach else { return nil }
            // Never pair authorization for one dashboard with the raw value of another.
            guard result.dashboard == nil || result.dashboard == authorized.dashboard else { return nil }
            visibility = .attached
            review = authorized.decision.allowedEffects.contains(.usageBackfill)
                ? authorized.dashboard.codeReviewRemainingPercent : nil
            if review != nil { timestamps.append(authorized.dashboard.updatedAt) }
        } else {
            // A raw web result does not establish permission to attach account-scoped extras.
            guard result.dashboard == nil else { return nil }
            visibility = .hidden
            review = nil
        }
        let balance: Double?
        if let authorized = result.authorizedDashboard,
           !authorized.decision.allowedEffects.contains(.creditsAttachment) {
            balance = nil
        } else {
            balance = credits?.remaining
            if let credits { timestamps.append(credits.updatedAt) }
        }
        guard balance != nil || review != nil, let updatedAt = timestamps.min() else { return nil }
        return .init(accountRevision: accountRevision, dashboardVisibility: visibility,
            creditsRemaining: balance, codeReviewRemainingPercent: review, updatedAt: updatedAt)
    }
}
#endif
