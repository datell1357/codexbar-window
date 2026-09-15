#if os(Windows)
import CodexBarCore
import Foundation

/// Produces a template and separate data for the Windows Widgets host. Performs no publication.
public enum WindowsWidgetAdaptiveCard {
    public struct Payload: Sendable {
        public let template: String
        public let data: String
        public let nextRefresh: Date
    }
    public enum Failure: Error, Sendable { case unsupportedKind, invalidContent, oversized, missingActionToken }
    /// The caller supplies translated labels and a display locale independently of provider data.
    public struct Labels: Sendable {
        public var refreshFailed = "Usage could not be refreshed. It will be retried shortly."
        public var unavailableWidget = "This widget is currently unavailable."
        public var cancelSettings = "Cancel"
        public var customize = "Widget settings"
        public var saveSettings = "Save settings"
        public var metric = "Metric"
        public var window = "Usage window"
        public var credits = "Credits remaining"
        public var extraUsageBalance = "Extra usage balance"
        public var apiEstimate = "API estimate · not billed"
        public var todayCost = "Today’s cost"
        public var monthCost = "Last 30 days cost"
        public var noData = "No usage data"
        public var disabled = "Provider disabled"
        public var waiting = "Waiting for a refresh"
        public var stale = "Data may be out of date"
        public var unknown = "Unavailable"
        public var used = "used"
        public var remaining = "remaining"
        public var updated = "Updated"
        public var resets = "Resets"
        public var codeReview = "Code review"
        public var tokens = "tokens"
        public var session = "Session"
        public var weekly = "Weekly"
        public var full = "Full"
        public var spent = "Spent"
        public var conserving = "Conserving"
        public var onPace = "On pace"
        public var overPace = "Over pace"
        public var weeklyBlocked = "Session blocked by the weekly limit"
        public var runsOut = "Estimated run-out"
        public var afterReset = "After reset"
        public var burnLegend = "Solid: average burn; dashed: ideal pace; dotted: projection."

        public var historyCost = "Daily cost"
        public var historyTokens = "Daily tokens"
        public var historyMissing = "Missing days"
        public var historyUnknown = "Unknown observations"
        public var historyLegend = "Gaps: missing days; marks below the baseline: unavailable; small baseline bars: zero."
        public var maximum = "Maximum"
        public var provider = "Provider"
        public var selectProvider = "Switch provider"
        public init() {}
    }

    public static func make(_ presentation: WindowsWidgetPresentation, locale: Locale,
                            labels: Labels = Labels(), actionToken: UUID? = nil,
                            theme: WindowsWidgetHistoryImage.Theme = .light, rightToLeft: Bool = false,
                            resetTimesShowAbsolute: Bool = true) throws -> Payload {
        try self.make(presentation, locale: locale, labels: labels, actionToken: actionToken, theme: theme,
            rightToLeft: rightToLeft, resetTimesShowAbsolute: resetTimesShowAbsolute,
            chartAppearance: Result { try WindowsWidgetChartAccessibility.capture() })
    }

    static func make(_ presentation: WindowsWidgetPresentation, locale: Locale, labels: Labels,
                     actionToken: UUID?, theme: WindowsWidgetHistoryImage.Theme, rightToLeft: Bool,
                     resetTimesShowAbsolute: Bool,
                     chartAppearance: Result<WindowsWidgetChartAccessibility?, Error>) throws -> Payload {
        guard presentation.nextRefresh.timeIntervalSince1970.isFinite else { throw Failure.invalidContent }
        let compact: Bool
        switch presentation.family {
        case .small: compact = true
        case .medium: compact = false
        }
        let numbers = NumberFormatter()
        numbers.locale = locale; numbers.numberStyle = .decimal; numbers.maximumFractionDigits = 1
        let percentages = NumberFormatter()
        percentages.locale = locale; percentages.numberStyle = .percent
        percentages.minimumFractionDigits = 0; percentages.maximumFractionDigits = 1
        let signedPercentages = NumberFormatter()
        signedPercentages.locale = locale; signedPercentages.numberStyle = .percent
        signedPercentages.minimumFractionDigits = 0; signedPercentages.maximumFractionDigits = 1
        signedPercentages.positivePrefix = signedPercentages.plusSign + signedPercentages.positivePrefix
        let dates = DateFormatter()
        dates.locale = locale; dates.dateStyle = .short; dates.timeStyle = .short
        let historyDates = DateFormatter()
        historyDates.locale = locale
        historyDates.timeZone = TimeZone(secondsFromGMT: 0)
        historyDates.dateStyle = .medium; historyDates.timeStyle = .none
        var nextRefresh = presentation.nextRefresh
        var body: [[String: Any]] = []
        var values: [String: String] = [:]

        // Source strings are bound as data, never interpolated into Adaptive Expressions.
        func text(_ value: String, size: String = "Small", subtle: Bool = false) throws {
            guard value.utf8.count <= 4096,
                  !value.unicodeScalars.contains(where: {
                      // Locale formatters may emit these directional marks around numbers and symbols.
                      CharacterSet.controlCharacters.contains($0) && ![0x061C, 0x200E, 0x200F].contains($0.value)
                  })
            else { throw Failure.invalidContent }
            let key = "text\(values.count)"
            values[key] = escapedMarkdown(value)
            body.append(["type": "TextBlock", "text": "${\(key)}", "size": size,
                         "wrap": true, "isSubtle": subtle, "spacing": "Small"])
        }
        func number(_ value: Double?) -> String {
            guard let value, value.isFinite else { return labels.unknown }
            return numbers.string(from: NSNumber(value: value)) ?? labels.unknown
        }
        func percent(_ value: Double?, signed: Bool = false) -> String {
            guard let value, value.isFinite else { return labels.unknown }
            let formatter = signed ? signedPercentages : percentages
            // Models store percentage points (0...100), while percent formatters consume fractions.
            return formatter.string(from: NSNumber(value: value / 100)) ?? labels.unknown
        }
        func count(_ value: Int) -> String {
            numbers.string(from: NSNumber(value: value)) ?? labels.unknown
        }
        func metric(_ value: WindowsWidgetMetric, prominent: Bool) throws {
            let baseTitle: String
            switch value.title {
            case .credits: baseTitle = labels.credits
            case .extraUsageBalance: baseTitle = labels.extraUsageBalance
            case .todayCost: baseTitle = labels.todayCost
            case .last30DaysCost: baseTitle = labels.monthCost
            case .providerPeriod(let period): baseTitle = period
            }
            // Keep provider-specific periods intact and never lose the estimate-versus-billed distinction.
            let title = value.isAPIEstimate ? baseTitle + " · " + labels.apiEstimate : baseTitle
            let amount: String
            switch value.unit {
            case .currency(let code):
                let formatter = NumberFormatter()
                formatter.locale = locale; formatter.numberStyle = .currency; formatter.currencyCode = code
                amount = value.value.flatMap { $0.isFinite ? formatter.string(from: NSNumber(value: $0)) : nil } ?? labels.unknown
            case .credits: amount = number(value.value)
            case .unknownCurrency: amount = labels.unknown
            }
            if compact && !prominent { try text(title + " · " + amount) }
            else {
                try text(title, subtle: true)
                try text(amount, size: prominent ? "ExtraLarge" : "Medium")
            }
            if let count = value.tokenCount, !compact { try text("\(numbers.string(from: NSNumber(value: count)) ?? String(count)) \(labels.tokens)", subtle: true) }
            if value.isStale { try text(labels.stale, subtle: true) }
            if let date = value.updatedAt, !compact || value.isStale {
                guard date.timeIntervalSince1970.isFinite else { throw Failure.invalidContent }
                try text("\(labels.updated) \(dates.string(from: date))", subtle: true)
            }
        }
        func resetLine(_ reset: Date) throws -> String {
            let delta = reset.timeIntervalSince(presentation.renderedAt)
            guard reset.timeIntervalSince1970.isFinite, delta.isFinite else { throw Failure.invalidContent }
            if resetTimesShowAbsolute || delta > 3_155_760_000 {
                return "\(labels.resets) \(dates.string(from: reset))"
            }
            // Reuse the tray countdown semantics; bound the interval before its integer conversion.
            if delta > 0 {
                nextRefresh = min(nextRefresh, presentation.renderedAt.addingTimeInterval(min(60, delta)))
            }
            let window = RateWindow(usedPercent: 0, windowMinutes: nil, resetsAt: reset, resetDescription: nil)
            return UsageFormatter.resetLine(for: window, style: .countdown, now: presentation.renderedAt) ?? labels.unknown
        }
        func quota(_ row: WindowsWidgetUsage.Row) throws {
            let amount = percent(row.displayedPercent)
            let title: String
            // Translate exact shared labels only. IDs and durations alone cannot identify a provider's title.
            switch row.title {
            case "Session": title = labels.session
            case "Weekly": title = labels.weekly
            case "Code review": title = labels.codeReview
            default: title = row.title
            }
            try text("\(title) · \(amount) \(presentation.showUsed ? labels.used : labels.remaining)")
            if let fraction = row.barFraction {
                guard fraction.isFinite, (0...1).contains(fraction) else { throw Failure.invalidContent }
                var columns: [[String: Any]] = []
                for (width, style) in [(fraction, "accent"), (1 - fraction, "emphasis")] where width > 0 {
                    columns.append(["type": "Column", "width": width * 100, "spacing": "None",
                                    "items": [["type": "Container", "minHeight": "4px", "style": style, "items": []]]])
                }
                body.append(["type": "ColumnSet", "columns": columns, "spacing": "Small"])
            }
            if let reset = row.resetsAt, !compact {
                guard reset.timeIntervalSince1970.isFinite else { throw Failure.invalidContent }
                try text(try resetLine(reset), subtle: true)
            }
        }

        func burn(_ geometry: WindowsWidgetBurnGeometry?, title: String, blank: Bool, key: String) throws {
            try text(title, size: "Medium")
            guard let geometry else { try text(labels.noData); return }
            let status: String
            if geometry.depleted { status = labels.spent }
            else if geometry.fresh { status = labels.full }
            else {
                switch geometry.status {
                case .conserving: status = labels.conserving
                case .onPace: status = labels.onPace
                case .overPace: status = labels.overPace
                }
            }
            try text("\(percent(geometry.remainingPercent)) \(labels.remaining) · \(status)")
            if blank { try text(labels.weeklyBlocked) }
            else {
                if !geometry.depleted && !geometry.fresh { try text("\(percent(geometry.margin, signed: true))", subtle: true) }
                values[key] = "data:image/png;base64," + (try WindowsWidgetBurnImage.png(geometry, theme: theme, accessibility: try chartAppearance.get())).base64EncodedString()
                values[key + "Alt"] = title + ". " + labels.burnLegend
                body.append(["type": "Image", "url": "${\(key)}", "altText": "${\(key)Alt}", "size": "Stretch", "spacing": "Small"])
                if !compact { try text(labels.burnLegend, subtle: true) }
                let runOut = geometry.estimatedRunOutAt.map { dates.string(from: $0) } ?? labels.afterReset
                try text("\(labels.runsOut): \(runOut)", subtle: true)
            }
            if let reset = geometry.effectiveResetAt { try text(try resetLine(reset), subtle: true) }
        }

        func history() throws {
            guard let chart = presentation.historyChart else { return }
            if chart.points.isEmpty { try text(labels.noData) }
            else {
                let title: String
                switch chart.mode {
                case .cost: title = labels.historyCost + " · " + (chart.currencyCode ?? labels.unknown)
                case .tokens: title = labels.historyTokens
                }
                let missing = chart.missingDayCount
                let unknown = chart.points.filter { $0.value == nil }.count
                guard let first = chart.points.first, let last = chart.points.last,
                      let firstDate = WindowsWidgetHistory.parseDay(first.dayKey),
                      let lastDate = WindowsWidgetHistory.parseDay(last.dayKey) else { throw Failure.invalidContent }
                // UTC keeps an aggregation day from shifting to the previous day in western time zones.
                let range = first.dayKey == last.dayKey ? historyDates.string(from: firstDate) :
                    historyDates.string(from: firstDate) + " – " + historyDates.string(from: lastDate)
                let caption = "\(title) · \(range) · \(labels.maximum) \(number(chart.maximum))"
                try text(caption, subtle: true)
                let chartHeight = presentation.kind == .history ? (presentation.hostSize == .large ? 90 : 60) : 50
                values["historyImage"] = "data:image/png;base64," + (try WindowsWidgetHistoryImage.png(chart, theme: theme, height: chartHeight, accessibility: try chartAppearance.get())).base64EncodedString()
                values["historyAlternative"] = caption + ". " + labels.historyLegend + " \(labels.historyMissing): \(count(missing)), \(labels.historyUnknown): \(count(unknown))"
                body.append(["type": "Image", "url": "${historyImage}", "altText": "${historyAlternative}",
                             "size": "Stretch", "height": "\(chartHeight)px", "spacing": "Small"])
                try text("\(labels.historyMissing): \(count(missing)) · \(labels.historyUnknown): \(count(unknown))", subtle: true)
                if chart.isStale { try text(labels.stale, subtle: true) }
            }
        }

        try text(ProviderDescriptorRegistry.descriptor(for: presentation.provider).metadata.displayName, size: "Medium")
        switch presentation.state {
        case .missingSnapshot: try text(labels.waiting)
        case .empty: try text(labels.noData)
        case .disabled: try text(labels.disabled)
        case .stale: try text(labels.stale, subtle: true)
        case .ready: break
        }
        if case let .switcher(providers, _) = presentation.body, !providers.isEmpty {
            guard let actionToken else { throw Failure.missingActionToken }
            guard providers.count <= WindowsWidgetConfiguration.selectableProviders.count,
                  Set(providers).count == providers.count,
                  providers.allSatisfy({ WindowsWidgetConfiguration.selectableProviders.contains($0) })
            else { throw Failure.invalidContent }
            values["providerLabel"] = labels.provider
            values["switchLabel"] = labels.selectProvider
            let choices: [[String: Any]] = providers.enumerated().map { index, provider in
                let key = "providerChoice\(index)"
                values[key] = ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
                return ["title": "${\(key)}", "value": provider.rawValue]
            }
            body.append(["type": "Container", "$when": "${$host.isUserContextAuthenticated}", "items": [
                ["type": "Input.ChoiceSet", "id": "provider", "label": "${providerLabel}",
                 "style": "compact", "isMultiSelect": false, "value": presentation.provider.rawValue,
                 "choices": choices],
                ["type": "ActionSet", "actions": [["type": "Action.Execute", "title": "${switchLabel}",
                  "verb": WindowsWidgetAction.switchProviderVerb, "data": ["actionToken": actionToken.uuidString]]]]
            ]])
        }
        switch presentation.body {
        case .unavailable: break
        case .usage(let rows), .switcher(_, let rows), .history(let rows, _):
            if presentation.kind == .history { try history() }
            guard rows.count <= 64 else { throw Failure.invalidContent }
            for row in rows { try quota(row) }
            if let supplement = presentation.supplement {
                if let review = supplement.codeReviewDisplayedPercent, presentation.kind != .history {
                    try text("\(labels.codeReview) · \(percent(review)) \(presentation.showUsed ? labels.used : labels.remaining)")
                }
                if let credits = supplement.creditsBalance, presentation.kind != .history { try metric(credits, prominent: false) }
                if let today = supplement.todayCost { try metric(today, prominent: supplement.compactTokenFallback) }
                if let month = supplement.last30DaysCost { try metric(month, prominent: false) }
            }
            if rows.isEmpty, presentation.supplement?.codeReviewDisplayedPercent == nil,
               presentation.supplement?.creditsBalance == nil, presentation.historyChart == nil,
               presentation.supplement?.todayCost == nil, presentation.supplement?.last30DaysCost == nil {
                try text(labels.noData)
            }
        case .metric(let value): try metric(value, prominent: true)
        case .burnDown(let value):
            let title = value.selected?.windowMinutes == 10080 ? labels.weekly : labels.session
            try burn(value.selectedGeometry(now: presentation.renderedAt), title: title,
                blank: value.blankSelectedChart, key: "burnSelected")
        case .combinedBurnDown(let value):
            try burn(value.sessionGeometry(now: presentation.renderedAt), title: labels.session,
                blank: value.sessionBlockedByWeekly, key: "burnSession")
            try burn(value.weeklyGeometry(now: presentation.renderedAt), title: labels.weekly,
                blank: false, key: "burnWeekly")
        }
        if presentation.kind != .history { try history() }
        if let date = presentation.updatedAt, !compact || presentation.state == .stale {
            guard date.timeIntervalSince1970.isFinite else { throw Failure.invalidContent }
            try text("\(labels.updated) \(dates.string(from: date))", subtle: true)
        }
        let template: [String: Any] = ["type": "AdaptiveCard", "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                                       "version": "1.6", "rtl": rightToLeft, "body": body]
        let templateData = try JSONSerialization.data(withJSONObject: template, options: [.sortedKeys])
        let valueData = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        guard templateData.count <= 256 * 1024, valueData.count <= 256 * 1024,
              let templateJSON = String(data: templateData, encoding: .utf8),
              let dataJSON = String(data: valueData, encoding: .utf8) else { throw Failure.oversized }
        return Payload(template: templateJSON, data: dataJSON, nextRefresh: nextRefresh)
    }

    /// No provider values, raw errors, or actions are retained when replacing a failed card.
    public static func failurePayload(retryable: Bool, labels: Labels = .init(),
                                      rightToLeft: Bool = false, now: Date) throws -> Payload {
        let message = retryable ? labels.refreshFailed : labels.unavailableWidget
        guard now.timeIntervalSince1970.isFinite, message.utf8.count <= 4096,
              !message.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw Failure.invalidContent }
        let template: [String: Any] = ["type": "AdaptiveCard", "version": "1.6", "rtl": rightToLeft,
            "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
            "body": [["type": "TextBlock", "text": "${message}", "wrap": true, "isSubtle": true]]]
        let templateData = try JSONSerialization.data(withJSONObject: template, options: [.sortedKeys])
        let messageData = try JSONSerialization.data(withJSONObject: ["message": escapedMarkdown(message)], options: [.sortedKeys])
        guard let templateJSON = String(data: templateData, encoding: .utf8),
              let dataJSON = String(data: messageData, encoding: .utf8) else { throw Failure.invalidContent }
        return Payload(template: templateJSON, data: dataJSON, nextRefresh: now.addingTimeInterval(retryable ? 60 : 1800))
    }

    private static func escapedMarkdown(_ value: String) -> String {
        var result = ""
        for character in value {
            if "\\`*_{}[]()#+-.!>|".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }
}
#endif
