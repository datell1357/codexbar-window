#if os(Windows)
import CodexBarCore
import Foundation

/// Host-retained customization form. Untrusted form data cannot change widget identity or kind.
public struct WindowsWidgetCustomization: Sendable {
    public static let cancelVerb = "codexbar.cancelWidgetSettings"
    public static let saveVerb = "codexbar.saveWidgetSettings"
    public enum Failure: Error, Sendable { case oversized, malformed, staleForm, invalidSelection }
    public struct Selection: Sendable {
        public let provider: UsageProvider
        public let metric: WindowsWidgetConfiguration.Metric?
        public let window: WindowsWidgetConfiguration.Window?
    }
    private struct Cancellation: Decodable { let actionToken: UUID }
    private struct Submission: Decodable {
        let actionToken: UUID
        let provider: UsageProvider
        let metric: WindowsWidgetConfiguration.Metric?
        let window: WindowsWidgetConfiguration.Window?
    }
    public let instance: WindowsWidgetConfiguration.Instance
    public let settings: WindowsWidgetConfigurationStore.Snapshot
    public let actionToken: UUID
    public let template: String
    public let data: String

    public static func make(instanceID: String, settings: WindowsWidgetConfigurationStore.Snapshot,
                            labels: WindowsWidgetAdaptiveCard.Labels = .init(), rightToLeft: Bool = false) throws -> Self {
        try settings.configuration.validate()
        guard let instance = settings.configuration.instances.first(where: { $0.id == instanceID })
        else { throw WindowsWidgetConfiguration.Failure.missingInstance }
        let token = UUID()
        var values = ["title": labels.customize, "save": labels.saveSettings, "cancel": labels.cancelSettings]
        var fields: [[String: Any]] = [["type": "TextBlock", "text": "${title}", "wrap": true, "weight": "Bolder"]]
        func choices(id: String, label: String, selected: String, options: [(String, String)]) {
            values[id + "Label"] = label
            let items: [[String: String]] = options.enumerated().map { index, option in
                let key = id + "Choice" + String(index)
                values[key] = option.1
                return ["value": option.0, "title": "${\(key)}"]
            }
            fields.append(["type": "Input.ChoiceSet", "id": id, "label": "${\(id)Label}",
                           "value": selected, "choices": items, "isMultiSelect": false, "style": "compact"])
        }
        let provider = instance.kind == .switcher ? settings.configuration.sharedProvider : instance.provider
        choices(id: "provider", label: labels.provider, selected: provider.rawValue,
            options: WindowsWidgetConfiguration.providers(for: instance.kind).map {
                ($0.rawValue, ProviderDescriptorRegistry.descriptor(for: $0).metadata.displayName)
            })
        if instance.kind == .metric {
            choices(id: "metric", label: labels.metric, selected: instance.metric.rawValue,
                options: [("credits", labels.credits), ("todayCost", labels.todayCost), ("last30DaysCost", labels.monthCost)])
        }
        if instance.kind == .burnDown {
            choices(id: "window", label: labels.window, selected: instance.window.rawValue,
                options: [("session", labels.session), ("weekly", labels.weekly)])
        }
        fields.append(["type": "ActionSet", "actions": [
            ["type": "Action.Execute", "title": "${save}", "verb": saveVerb, "data": ["actionToken": token.uuidString]],
            ["type": "Action.Execute", "title": "${cancel}", "verb": cancelVerb,
             "associatedInputs": "none", "data": ["actionToken": token.uuidString]]]])
        let template: [String: Any] = ["type": "AdaptiveCard", "version": "1.6", "rtl": rightToLeft,
            "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
            "body": [["type": "Container", "$when": "${$host.isUserContextAuthenticated}", "items": fields]]]
        let encodedTemplate = try JSONSerialization.data(withJSONObject: template, options: [.sortedKeys])
        let encodedValues = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        guard encodedTemplate.count <= 64 * 1024, encodedValues.count <= 64 * 1024,
              let templateJSON = String(data: encodedTemplate, encoding: .utf8),
              let dataJSON = String(data: encodedValues, encoding: .utf8) else { throw Failure.oversized }
        return Self(instance: instance, settings: settings, actionToken: token, template: templateJSON, data: dataJSON)
    }

    /// Cancellation intentionally ignores unfinished form fields and validates only its retained identity.
    public func validateCancellation(arguments: Data, widgetID: String) throws {
        guard arguments.count <= 4096 else { throw Failure.oversized }
        guard widgetID == self.instance.id else { throw Failure.staleForm }
        let cancellation: Cancellation
        do { cancellation = try JSONDecoder().decode(Cancellation.self, from: arguments) }
        catch { throw Failure.malformed }
        guard cancellation.actionToken == self.actionToken else { throw Failure.staleForm }
    }

    /// Host callback identity and form lifetime must be checked by the coordinator before saving.
    public func selection(arguments: Data, widgetID: String) throws -> Selection {
        guard arguments.count <= 4096 else { throw Failure.oversized }
        guard widgetID == self.instance.id else { throw Failure.staleForm }
        let submission: Submission
        do { submission = try JSONDecoder().decode(Submission.self, from: arguments) }
        catch { throw Failure.malformed }
        guard submission.actionToken == self.actionToken else { throw Failure.staleForm }
        guard WindowsWidgetConfiguration.providers(for: self.instance.kind).contains(submission.provider),
              (self.instance.kind == .metric) == (submission.metric != nil),
              (self.instance.kind == .burnDown) == (submission.window != nil) else { throw Failure.invalidSelection }
        return Selection(provider: submission.provider, metric: submission.metric, window: submission.window)
    }
}
#endif
