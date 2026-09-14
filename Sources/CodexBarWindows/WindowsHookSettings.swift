#if os(Windows)
import CodexBarCore
import Foundation

/// Value-only editor contract. Commands stay in the editor, never in diagnostic summaries.
public struct WindowsHookSettingsSnapshot: Sendable, Equatable {
    public let config: HooksConfig

    public init(config: HooksConfig) { self.config = config }
}

public enum WindowsHookSettingsMutation: Sendable {
    case setEnabled(Bool)
    case insert(HookRule, at: Int)
    case replace(id: String, with: HookRule)
    case remove(id: String)
    case move(id: String, to: Int)
}

public enum WindowsHookSettingsFailure: Error, Sendable {
    case changed, missingRule, duplicateID, invalidPosition, tooManyRules
    case invalidExecutable, invalidProvider, invalidThreshold, invalidTimeout, invalidCommand
}

/// Pure config patching; performs no filesystem, credential, or process operations.
public enum WindowsHookSettingsEditor {
    public static func applying(
        _ mutation: WindowsHookSettingsMutation,
        expected: WindowsHookSettingsSnapshot,
        to current: CodexBarConfig) throws -> CodexBarConfig
    {
        var hooks = current.hooks ?? HooksConfig()
        guard hooks == expected.config else { throw WindowsHookSettingsFailure.changed }
        // Disabling remains available even if a hand-edited rule is malformed.
        if case .setEnabled(false) = mutation {
            hooks.enabled = false
            var result = current
            result.hooks = hooks
            return result
        }
        switch mutation {
        case let .setEnabled(enabled): hooks.enabled = enabled
        case let .insert(rule, index):
            guard (0...hooks.events.count).contains(index) else { throw WindowsHookSettingsFailure.invalidPosition }
            guard hooks.events.count < HooksConfig.maximumRuleCount else { throw WindowsHookSettingsFailure.tooManyRules }
            hooks.events.insert(rule, at: index)
        case let .replace(id, rule):
            guard rule.id == id else { throw WindowsHookSettingsFailure.invalidCommand }
            let index = try self.uniqueIndex(id: id, in: hooks.events)
            hooks.events[index] = rule
        case let .remove(id):
            hooks.events.remove(at: try self.uniqueIndex(id: id, in: hooks.events))
        case let .move(id, destination):
            guard hooks.events.indices.contains(destination) else { throw WindowsHookSettingsFailure.invalidPosition }
            let index = try self.uniqueIndex(id: id, in: hooks.events)
            let rule = hooks.events.remove(at: index)
            hooks.events.insert(rule, at: destination)
        }
        try self.validate(hooks)
        var result = current
        result.hooks = hooks
        return result
    }

    public static func validate(_ config: HooksConfig) throws {
        guard config.events.count <= HooksConfig.maximumRuleCount else { throw WindowsHookSettingsFailure.tooManyRules }
        var ids = Set<String>()
        for rule in config.events {
            guard ids.insert(rule.id).inserted else { throw WindowsHookSettingsFailure.duplicateID }
            guard rule.hasValidExecutablePath else { throw WindowsHookSettingsFailure.invalidExecutable }
            guard rule.hasKnownProvider else { throw WindowsHookSettingsFailure.invalidProvider }
            guard rule.hasValidThreshold else { throw WindowsHookSettingsFailure.invalidThreshold }
            guard rule.hasValidTimeout else { throw WindowsHookSettingsFailure.invalidTimeout }
            guard rule.hasValidCommandShape else { throw WindowsHookSettingsFailure.invalidCommand }
        }
    }

    private static func uniqueIndex(id: String, in rules: [HookRule]) throws -> Int {
        let indices = rules.indices.filter { rules[$0].id == id }
        guard !indices.isEmpty else { throw WindowsHookSettingsFailure.missingRule }
        guard indices.count == 1 else { throw WindowsHookSettingsFailure.duplicateID }
        return indices[0]
    }
}
#endif
