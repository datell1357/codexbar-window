#if os(Windows)
import CodexBarCore
import Foundation

/// Native widget input matching the original session/weekly cap and reset policy.
public struct WindowsWidgetBurnDown: Sendable {
    public let session: RateWindow?
    public let weekly: RateWindow?
    public let selected: RateWindow?
    public let sessionBlockedByWeekly: Bool
    public let blankSelectedChart: Bool
    public let selectedResetOverride: Date?
    public let nextRefresh: Date

    public static func make(from content: WindowsWidgetContentResolver.Content, now: Date) -> Self? {
        guard now.timeIntervalSince1970.isFinite,
              WindowsWidgetConfiguration.burnDownProviders.contains(content.provider) else { return nil }
        let entry = content.entry
        let windows = [entry?.primary, entry?.secondary].compactMap { $0 }.filter { window in
            window.usedPercent.isFinite && (window.resetsAt?.timeIntervalSince1970.isFinite ?? true)
        }
        let weekly = windows.first { $0.windowMinutes == 7 * 24 * 60 }
        let originalSession = windows.first { $0.windowMinutes == 5 * 60 }
        let globalCap = ProviderDescriptorRegistry.descriptor(for: content.provider).presentation.secondaryGloballyCapsPrimary
        let blocked = globalCap && (weekly.map { $0.remainingPercent <= 0 && ($0.resetsAt.map { $0 > now } ?? true) } ?? false)
        let session: RateWindow?
        if let originalSession, blocked, originalSession.remainingPercent > 0 {
            session = RateWindow(usedPercent: 100, windowMinutes: originalSession.windowMinutes,
                resetsAt: originalSession.resetsAt, resetDescription: originalSession.resetDescription,
                nextRegenPercent: originalSession.nextRegenPercent)
        } else { session = originalSession }
        let blank = content.instance.window == .session && blocked && originalSession != nil
        let fallback = now.addingTimeInterval(30 * 60)
        let nextReset = windows.compactMap(\.resetsAt).filter { $0 > now }.min()?.addingTimeInterval(1)
        let refresh = nextReset.map { max(now.addingTimeInterval(5 * 60), min(fallback, $0)) } ?? fallback
        return Self(session: session, weekly: weekly,
            selected: content.instance.window == .session ? session : weekly,
            sessionBlockedByWeekly: blocked, blankSelectedChart: blank,
            selectedResetOverride: blank ? weekly?.resetsAt : nil, nextRefresh: refresh)
    }
}
#endif
