#if os(Windows)
import CodexBarCore
import Foundation

/// A single provider/owner snapshot. The UI receives an opaque context token, never a
/// history account key, credential digest or another owner's account bucket.
struct WindowsPlanUtilizationHistorySnapshot: Sendable {
    let providerID: ProviderInstanceID
    let contextToken: UUID
    let title: String
    let hidePersonalInfo: Bool
    let usageCapturedAt: Date
    let loadedAt: Date
    let series: [PlanUtilizationHistoryChart.Series]
    let sessionEquivalentForecast: SessionEquivalentForecastCore?
    let forecastWorkDays: Int?
    let restoredExactOwnership: Bool
    let isCurrent: @Sendable () -> Bool
}

enum WindowsPlanUtilizationHistoryResult: Sendable {
    case snapshot(WindowsPlanUtilizationHistorySnapshot)
    case ownershipReview(WindowsPlanHistoryOwnershipReview)
    case ownershipApplied(backupID: UUID, receiptRecorded: Bool)
    case ownershipInterrupted(backupID: UUID?)
    case unavailable(Failure)

    enum Failure: Sendable {
        case changed, noCurrentUsage, busy, invalidData, loadFailed, ownershipReviewRequired, ownershipHidden, ownershipNoCandidates

        var message: String {
            let key: String = switch self {
            case .changed: "plan_history_changed"
            case .noCurrentUsage: "plan_history_noCurrentUsage"
            case .busy: "plan_history_busy"
            case .invalidData: "plan_history_invalidData"
            case .loadFailed: "plan_history_loadFailed"
            case .ownershipReviewRequired: "plan_history_recoveryOwnerRequired"
            case .ownershipHidden: "history_owner_hidden"
            case .ownershipNoCandidates: "history_owner_empty"
            }
            return WindowsStatusLocalization.text(key)
        }
    }
}
#endif
