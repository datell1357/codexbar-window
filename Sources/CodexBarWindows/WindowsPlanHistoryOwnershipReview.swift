#if os(Windows)
import CodexBarCore
import Foundation

public enum WindowsPlanHistoryOwnershipAction: Sendable {
    case review
    case apply(reviewID: UUID, candidateID: UUID)
}

struct WindowsPlanHistoryOwnershipReview: Sendable {
    struct Series: Sendable {
        let name: String
        let minutes: Int
        let count: Int
        let first: Date?
        let last: Date?
    }
    struct Candidate: Sendable {
        let id: UUID
        let unassigned: Bool
        let fingerprint: String
        let series: [Series]
    }
    let id: UUID
    let providerID: ProviderInstanceID
    let contextToken: UUID
    let targetTitle: String
    let documentSHA256: String
    let candidates: [Candidate]
    let isCurrent: @Sendable () -> Bool
}
#endif
