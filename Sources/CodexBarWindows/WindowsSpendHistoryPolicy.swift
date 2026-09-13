#if os(Windows)
/// Same history horizon as the original spend/activity controller. This is a scan
/// request policy, not evidence that every provider supplied a full year of data.
enum WindowsSpendHistoryPolicy {
    static let activityDays = 365
    static let scanDays = activityDays
}
#endif
