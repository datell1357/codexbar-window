#if os(Windows)
import CodexBarCore
import Foundation

/// Editable fields for the native rule form. Arguments are individual values, never a shell line.
public struct WindowsHookRuleDraft: Sendable, Equatable {
    public let id: String
    public var enabled: Bool
    public var event: HookEventType
    public var provider: String?
    public var executable: String
    public var arguments: [String]
    /// Blank means use the provider warning thresholds; otherwise percent USED, not remaining.
    public var usedPercent: String
    public var timeoutSeconds: String

    public init(rule: HookRule? = nil) {
        self.id = rule?.id ?? UUID().uuidString
        self.enabled = rule?.enabled ?? false
        self.event = rule?.event ?? .quotaLow
        self.provider = rule?.provider
        self.executable = rule?.executable ?? ""
        self.arguments = rule?.arguments ?? []
        self.usedPercent = rule?.threshold.map { String($0 * 100) } ?? ""
        self.timeoutSeconds = String(rule?.timeoutSeconds ?? HookRule.defaultTimeoutSeconds)
    }

    public mutating func insertArgument(_ value: String = "", at index: Int) throws {
        guard (0...self.arguments.count).contains(index),
              self.arguments.count < HookRule.maximumArgumentCount else {
            throw WindowsHookSettingsFailure.invalidCommand
        }
        try Self.validateArgument(value)
        self.arguments.insert(value, at: index)
    }

    public mutating func replaceArgument(at index: Int, with value: String) throws {
        guard self.arguments.indices.contains(index) else { throw WindowsHookSettingsFailure.invalidPosition }
        try Self.validateArgument(value)
        self.arguments[index] = value
    }

    public mutating func removeArgument(at index: Int) throws {
        guard self.arguments.indices.contains(index) else { throw WindowsHookSettingsFailure.invalidPosition }
        self.arguments.remove(at: index)
    }

    public func rule() throws -> HookRule {
        guard !self.executable.contains("\0"), !self.id.contains("\0") else {
            throw WindowsHookSettingsFailure.invalidCommand
        }
        for argument in self.arguments { try Self.validateArgument(argument) }
        guard let timeout = Self.number(self.timeoutSeconds) else { throw WindowsHookSettingsFailure.invalidTimeout }
        let threshold: Double?
        if self.event == .quotaLow {
            let text = self.usedPercent.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { threshold = nil }
            else {
                guard let percent = Self.number(text), percent > 0, percent <= 100 else {
                    throw WindowsHookSettingsFailure.invalidThreshold
                }
                threshold = percent / 100
            }
        } else { threshold = nil }
        let rule = HookRule(id: self.id, enabled: self.enabled, event: self.event,
            provider: self.provider, threshold: threshold, executable: self.executable,
            arguments: self.arguments, timeoutSeconds: timeout)
        try WindowsHookSettingsEditor.validate(HooksConfig(events: [rule]))
        return rule
    }

    private static func validateArgument(_ value: String) throws {
        guard !value.contains("\0"), value.utf8.count <= HookRule.maximumStringBytes else {
            throw WindowsHookSettingsFailure.invalidCommand
        }
    }

    /// Form fields use a dot decimal separator, no grouping or units. Exponents preserve very small existing thresholds.
    private static func number(_ value: String) -> Double? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 64,
              text.range(of: #"^[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
              let result = Double(text), result.isFinite else { return nil }
        return result
    }
}
#endif
