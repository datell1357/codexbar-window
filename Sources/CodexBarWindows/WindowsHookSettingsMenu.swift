#if os(Windows)
import CodexBarCore
import Foundation
import WinSDK

/// One explicit edit per presentation. The caller persists the returned mutation asynchronously.
public enum WindowsHookSettingsMenu {
    public static func show(
        owner: HWND, snapshot: WindowsHookSettingsSnapshot,
        isCurrent: @escaping () -> Bool) -> WindowsHookSettingsMutation?
    {
        let privacy = WindowsUsagePresentationSettings.load().hidePersonalInfo
        let rightToLeft = WindowsStatusLocalization.isRightToLeft
        func valid() -> Bool {
            IsWindow(owner) != 0 && isCurrent() &&
                WindowsUsagePresentationSettings.load().hidePersonalInfo == privacy
        }
        guard valid(), snapshot.config.events.count <= HooksConfig.maximumRuleCount,
              let menu = CreatePopupMenu() else { return nil }
        defer { _ = DestroyMenu(menu) }
        let config = snapshot.config
        guard append(config.enabled ? WindowsStatusLocalization.text("Disable all hooks") : WindowsStatusLocalization.text("Enable configured hooks"), command: 1, to: menu),
              append(WindowsStatusLocalization.text("hooks_add_rule"), command: 2, to: menu, enabled: config.events.count < HooksConfig.maximumRuleCount)
        else { return nil }
        if config.events.isEmpty {
            guard append(WindowsStatusLocalization.text("hooks_empty"), command: 0, to: menu, enabled: false) else { return nil }
        }
        for (index, rule) in config.events.enumerated() {
            guard let actions = CreatePopupMenu() else { return nil }
            let base = UINT_PTR(0x100 + index * 8)
            let complete = append(WindowsStatusLocalization.text("Edit rule…"), command: base, to: actions) &&
                append(rule.enabled ? WindowsStatusLocalization.text("Disable rule") : WindowsStatusLocalization.text("Enable rule"), command: base + 1, to: actions) &&
                append(WindowsStatusLocalization.text("Move up"), command: base + 2, to: actions, enabled: index > 0) &&
                append(WindowsStatusLocalization.text("Move down"), command: base + 3, to: actions, enabled: index + 1 < config.events.count) &&
                append(WindowsStatusLocalization.text("hooks_delete_rule"), command: base + 4, to: actions)
            guard complete else { _ = DestroyMenu(actions); return nil }
            // Do not expose executable paths or argument values in the overview.
            let title = "\(index + 1). \(rule.event.rawValue) · \(rule.provider ?? WindowsStatusLocalization.text("hooks_any_provider"))" +
                (rule.enabled ? "" : WindowsStatusLocalization.text(" (disabled)"))
            let added = safeText(title).withCString(encodedAs: UTF16.self) {
                AppendMenuW(menu, UINT(MF_STRING | MF_POPUP), UINT_PTR(UInt(bitPattern: actions)), $0)
            }
            guard added != 0 else { _ = DestroyMenu(actions); return nil }
        }
        var point = POINT()
        guard GetCursorPos(&point) != 0 else { return nil }
        SetForegroundWindow(owner)
        let selected = UINT_PTR(TrackPopupMenu(menu, UINT(TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON) | (rightToLeft ? UINT(TPM_LAYOUTRTL | TPM_RIGHTALIGN) : 0),
            point.x, point.y, 0, owner, nil))
        guard valid(), selected != 0 else { return nil }
        let mutation: WindowsHookSettingsMutation
        if selected == 1 {
            if !config.enabled, !confirm(owner: owner, text: WindowsStatusLocalization.text("Enable configured hooks? Enabled rules can run their configured programs when future usage or service events occur.")) { return nil }
            mutation = .setEnabled(!config.enabled)
        } else if selected == 2 {
            guard let rule = WindowsHookRuleDialog.show(owner: owner, draft: WindowsHookRuleDraft(), isCurrent: valid) else { return nil }
            mutation = .insert(rule, at: config.events.count)
        } else {
            guard selected >= 0x100 else { return nil }
            let index = Int((selected - 0x100) / 8)
            let action = (selected - 0x100) % 8
            guard config.events.indices.contains(index) else { return nil }
            var rule = config.events[index]
            switch action {
            case 0:
                guard let edited = WindowsHookRuleDialog.show(owner: owner, draft: WindowsHookRuleDraft(rule: rule), isCurrent: valid) else { return nil }
                mutation = .replace(id: rule.id, with: edited)
            case 1:
                rule.enabled.toggle()
                mutation = .replace(id: rule.id, with: rule)
            case 2:
                guard index > 0 else { return nil }
                mutation = .move(id: rule.id, to: index - 1)
            case 3:
                guard index + 1 < config.events.count else { return nil }
                mutation = .move(id: rule.id, to: index + 1)
            case 4:
                guard confirm(owner: owner, text: WindowsStatusLocalization.text("Delete the selected hook rule? Other rules and provider settings will be kept.")) else { return nil }
                mutation = .remove(id: rule.id)
            default: return nil
            }
        }
        guard valid() else { return nil }
        return mutation
    }

    private static func append(_ title: String, command: UINT_PTR, to menu: HMENU, enabled: Bool = true) -> Bool {
        safeText(title).withCString(encodedAs: UTF16.self) {
            AppendMenuW(menu, UINT(MF_STRING) | (enabled ? 0 : UINT(MF_GRAYED)), command, $0) != 0
        }
    }
    private static func safeText(_ value: String) -> String {
        value.components(separatedBy: .controlCharacters).joined(separator: " ").replacingOccurrences(of: "&", with: "&&")
    }
    private static func confirm(owner: HWND, text: String) -> Bool {
        text.withCString(encodedAs: UTF16.self) { message in
            WindowsStatusLocalization.text("tab_hooks").withCString(encodedAs: UTF16.self) { title in
                MessageBoxW(owner, message, title, UINT(MB_YESNO | MB_DEFBUTTON2 | MB_ICONQUESTION)) == IDYES
            }
        }
    }
}
#endif
