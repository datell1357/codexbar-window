# 설정 전수 대응표

[행동 계약](BEHAVIOR-CONTRACTS-2026-09-12.ko.md)의 BC-005~010에 신규/기존/잘못된 값/동의/알림 defaults를 입력별로 고정했다.

[추가 감사](SECONDARY-AUDIT-2026-09-12.ko.md)의 확장키·binding·typed snapshot·alias 계약을 함께 적용한다. 91개 state만으로 전체 provider 설정을 대체하지 않는다.

`SettingsDefaultsState`의 **91개 필드 전부**와 저장/default 소스 위치를 연결했다. provider config 확장·동적 plugin schema는 별도 229개 config_property 및 provider_editor_id 계약에 포함한다. 필드 수는 UI 설정 개수와 다르다.

공통 수락: 원본 초기값·기존 설정 fallback·invalid 값·disabled/hidden 조건·write 실패·onChange refresh·재시작 복원을 유지한다. Raw 필드는 화면용 computed wrapper와 함께 이전한다. 표의 기본값 표현은 원본 코드 일부이며 복잡한 migration의 최종값을 실행 계산한 결과가 아니다.

| 필드 | 원본 초기화/기본값 근거 | Windows 처리 |
|---|---|---|
| `refreshFrequency` | `SettingsStore.swift:504` — `let refreshFrequency = Self.loadRefreshFrequency(             userDefaults: userDefaults,             hadPreviousInstallationState: hadPreviousInstallationState)` | 동일 의미의 Windows 설정/저장·관찰자 |
| `adaptiveActivityScanConsent` | `SettingsStore.swift:507` — `let adaptiveActivityScanConsent = Self.loadAdaptiveActivityScanConsent(userDefaults: userDefaults)` | 동일 의미의 Windows 설정/저장·관찰자 |
| `refreshAllProvidersOnMenuOpen` | `SettingsStore.swift:508` — `let refreshAllProvidersOnMenuOpen = userDefaults.object(             forKey: "refreshAllProvidersOnMenuOpen") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `launchAtLogin` | `SettingsStore.swift:510` — `let launchAtLogin = userDefaults.object(forKey: "launchAtLogin") as? Bool ?? false` | Windows 자동 시작 opt-in 및 시작 상태 감지 |
| `debugMenuEnabled` | `SettingsStore.swift:511` — `let debugMenuEnabled = userDefaults.object(forKey: "debugMenuEnabled") as? Bool ?? false` | Windows 진단 기능; macOS 전용 엔진/권한 항목은 대응 또는 명시된 개발 전용 범위 |
| `debugDisableKeychainAccess` | `SettingsStore.swift:512` — `let debugDisableKeychainAccess = Self.loadDebugDisableKeychainAccess(userDefaults: userDefaults)` | Windows credential 접근·동의 정책으로 대체; Keychain 구현은 배포 제외 |
| `debugFileLoggingEnabled` | `SettingsStore.swift:513` — `let debugFileLoggingEnabled = userDefaults.object(forKey: "debugFileLoggingEnabled") as? Bool ?? false` | Windows 진단 기능; macOS 전용 엔진/권한 항목은 대응 또는 명시된 개발 전용 범위 |
| `debugLogLevelRaw` | `SettingsStore.swift:514` — `let debugLogLevelRaw = userDefaults.string(forKey: "debugLogLevel") ?? CodexBarLog.Level.verbose.rawValue` | Windows 진단 기능; macOS 전용 엔진/권한 항목은 대응 또는 명시된 개발 전용 범위 |
| `debugLoadingPatternRaw` | `SettingsStore.swift:518` — `let debugLoadingPatternRaw = userDefaults.string(forKey: "debugLoadingPattern")` | Windows 진단 기능; macOS 전용 엔진/권한 항목은 대응 또는 명시된 개발 전용 범위 |
| `debugKeepCLISessionsAlive` | `SettingsStore.swift:519` — `let debugKeepCLISessionsAlive = userDefaults.object(forKey: "debugKeepCLISessionsAlive") as? Bool ?? false` | Windows 진단 기능; macOS 전용 엔진/권한 항목은 대응 또는 명시된 개발 전용 범위 |
| `statusChecksEnabled` | `SettingsStore.swift:466` — `statusChecksEnabled: Bool` | 동일 의미의 Windows 설정/저장·관찰자 |
| `sessionQuotaNotificationsEnabled` | `SettingsStore.swift:467` — `sessionQuotaNotificationsEnabled: Bool` | 동일 의미의 Windows 설정/저장·관찰자 |
| `quotaWarningNotificationsEnabled` | `SettingsStore.swift:673` — `quotaWarningNotificationsEnabled: quotaWarnings.notificationsEnabled,` | 동일 의미의 Windows 설정/저장·관찰자 |
| `predictivePaceWarningNotificationsEnabled` | `SettingsStore.swift:468` — `predictivePaceWarningNotificationsEnabled: Bool` | 동일 의미의 Windows 설정/저장·관찰자 |
| `quotaWarningThresholdsRaw` | `SettingsStore.swift:675` — `quotaWarningThresholdsRaw: quotaWarnings.thresholdsRaw,` | 동일 의미의 Windows 설정/저장·관찰자 |
| `quotaWarningSessionThresholdsRaw` | `SettingsStore.swift:676` — `quotaWarningSessionThresholdsRaw: quotaWarnings.sessionThresholdsRaw,` | 동일 의미의 Windows 설정/저장·관찰자 |
| `quotaWarningWeeklyThresholdsRaw` | `SettingsStore.swift:677` — `quotaWarningWeeklyThresholdsRaw: quotaWarnings.weeklyThresholdsRaw,` | 동일 의미의 Windows 설정/저장·관찰자 |
| `quotaWarningSessionEnabled` | `SettingsStore.swift:678` — `quotaWarningSessionEnabled: quotaWarnings.sessionEnabled,` | 동일 의미의 Windows 설정/저장·관찰자 |
| `quotaWarningWeeklyEnabled` | `SettingsStore.swift:679` — `quotaWarningWeeklyEnabled: quotaWarnings.weeklyEnabled,` | 동일 의미의 Windows 설정/저장·관찰자 |
| `quotaWarningSoundEnabled` | `SettingsStore.swift:680` — `quotaWarningSoundEnabled: quotaWarnings.soundEnabled,` | 동일 의미의 Windows 설정/저장·관찰자 |
| `quotaWarningOnScreenAlertEnabled` | `SettingsStore.swift:681` — `quotaWarningOnScreenAlertEnabled: quotaWarnings.onScreenAlertEnabled,` | 동일 의미의 Windows 설정/저장·관찰자 |
| `quotaWarningMarkersVisible` | `SettingsStore.swift:523` — `let quotaWarningMarkersVisible = quotaWarningMarkersVisibleDefault ?? true` | 동일 의미의 Windows 설정/저장·관찰자 |
| `paceVisible` | `SettingsStore.swift:528` — `let paceVisible = paceVisibleDefault ?? true` | 동일 의미의 Windows 설정/저장·관찰자 |
| `weeklyProgressWorkDays` | `SettingsStore.swift:532` — `let weeklyProgressWorkDays = userDefaults.object(forKey: "weeklyProgressWorkDays") as? Int` | 동일 의미의 Windows 설정/저장·관찰자 |
| `workdayTickAppearanceRaw` | `SettingsStore.swift:533` — `let workdayTickAppearanceRaw = userDefaults.string(forKey: "workdayTickAppearance")             ?? WorkdayTickAppearance.subtle.rawValue` | 동일 의미의 Windows 설정/저장·관찰자 |
| `usageBarsShowUsed` | `SettingsStore.swift:535` — `let usageBarsShowUsed = userDefaults.object(forKey: "usageBarsShowUsed") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `resetTimesShowAbsolute` | `SettingsStore.swift:536` — `let resetTimesShowAbsolute = userDefaults.object(forKey: "resetTimesShowAbsolute") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `providerChangelogLinksEnabled` | `SettingsStore.swift:537` — `let providerChangelogLinksEnabled = userDefaults.object(             forKey: "providerChangelogLinksEnabled") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `menuBarShowsBrandIconWithPercent` | `SettingsStore.swift:539` — `let menuBarShowsBrandIconWithPercent = userDefaults.object(             forKey: "menuBarShowsBrandIconWithPercent") as? Bool ?? false` | 트레이/팝업/상시 패널 표시·geometry 설정으로 대응 |
| `menuBarHidesCritters` | `SettingsStore.swift:541` — `let menuBarHidesCritters = userDefaults.object(forKey: "menuBarHidesCritters") as? Bool ?? false` | 트레이/팝업/상시 패널 표시·geometry 설정으로 대응 |
| `menuBarHighContrastOnInactiveDisplays` | `SettingsStore.swift:542` — `let menuBarHighContrastOnInactiveDisplays = userDefaults.object(             forKey: "menuBarHighContrastOnInactiveDisplays") as? Bool ?? false` | 트레이/팝업/상시 패널 표시·geometry 설정으로 대응 |
| `menuBarDisplayModeRaw` | `SettingsStore.swift:544` — `let menuBarDisplayModeRaw = userDefaults.string(forKey: "menuBarDisplayMode")             ?? MenuBarDisplayMode.percent.rawValue` | 트레이/팝업/상시 패널 표시·geometry 설정으로 대응 |
| `menuBarShowsResetTimeWhenExhausted` | `SettingsStore.swift:546` — `let menuBarShowsResetTimeWhenExhausted = userDefaults.object(             forKey: "menuBarShowsResetTimeWhenExhausted") as? Bool ?? false` | 트레이/팝업/상시 패널 표시·geometry 설정으로 대응 |
| `kiroMenuBarDisplayModeRaw` | `SettingsStore.swift:548` — `let kiroMenuBarDisplayModeRaw = userDefaults.string(forKey: "kiroMenuBarDisplayMode")             ?? KiroMenuBarDisplayMode.automatic.rawValue` | 트레이/팝업/상시 패널 표시·geometry 설정으로 대응 |
| `historicalTrackingEnabled` | `SettingsStore.swift:550` — `let historicalTrackingEnabled = userDefaults.object(forKey: "historicalTrackingEnabled") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `multiAccountMenuLayoutRaw` | `SettingsStore.swift:551` — `let multiAccountMenuLayoutRaw = Self.loadMultiAccountMenuLayoutRaw(userDefaults: userDefaults)` | 동일 의미의 Windows 설정/저장·관찰자 |
| `menuBarMetricPreferencesRaw` | `SettingsStore.swift:697` — `menuBarMetricPreferencesRaw: resolvedPreferences,` | 트레이/팝업/상시 패널 표시·geometry 설정으로 대응 |
| `storedMenuBarLayout` | `SettingsStore.swift:553` — `let storedMenuBarLayout = Self.loadMenuBarLayout(userDefaults: userDefaults)` | 트레이/팝업/상시 패널 표시·geometry 설정으로 대응 |
| `menuBarLayoutConditionals` | `SettingsStore.swift:554` — `let menuBarLayoutConditionals = Self.loadMenuBarLayoutConditionals(userDefaults: userDefaults)` | 트레이/팝업/상시 패널 표시·geometry 설정으로 대응 |
| `menuBarLayoutOverridesRaw` | `SettingsStore.swift:555` — `let menuBarLayoutOverridesRaw = Self.loadMenuBarLayoutOverrides(userDefaults: userDefaults)` | 트레이/팝업/상시 패널 표시·geometry 설정으로 대응 |
| `menuBarLayoutSizeRaw` | `SettingsStore.swift:556` — `let menuBarLayoutSizeRaw = userDefaults.string(forKey: "menuBarLayoutSize")             ?? MenuBarLayoutSize.regular.rawValue` | 트레이/팝업/상시 패널 표시·geometry 설정으로 대응 |
| `menuBarLayoutGapRaw` | `SettingsStore.swift:558` — `let menuBarLayoutGapRaw = userDefaults.string(forKey: "menuBarLayoutGap")             ?? MenuBarLayoutGap.regular.rawValue` | 트레이/팝업/상시 패널 표시·geometry 설정으로 대응 |
| `menuBarLayoutVerticalAdjustment` | `SettingsStore.swift:561` — `let menuBarLayoutVerticalAdjustment = max(-20, min(20, rawVerticalAdjustment ?? 0))` | 트레이/팝업/상시 패널 표시·geometry 설정으로 대응 |
| `copilotBudgetExtrasEnabled` | `SettingsStore.swift:562` — `let copilotBudgetExtrasEnabled = userDefaults.object(forKey: "copilotBudgetExtrasEnabled") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `copilotIconSecondaryWindowIDRaw` | `SettingsStore.swift:563` — `let copilotIconSecondaryWindowIDRaw = Self.loadCopilotIconSecondaryWindowIDRaw(userDefaults: userDefaults)` | 동일 의미의 Windows 설정/저장·관찰자 |
| `costUsageEnabled` | `SettingsStore.swift:564` — `let costUsageEnabled = userDefaults.object(forKey: "tokenCostUsageEnabled") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `codexLocalSessionCostLedgerEnabled` | `SettingsStore.swift:565` — `let codexLocalSessionCostLedgerEnabled = userDefaults.object(             forKey: "codexLocalSessionCostLedgerEnabled") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `costUsageHistoryDays` | `SettingsStore.swift:568` — `let costUsageHistoryDays = max(1, min(365, rawCostUsageHistoryDays))` | 동일 의미의 Windows 설정/저장·관찰자 |
| `costUsageBucketTimeZoneIdentifier` | `SettingsStore.swift:570` — `let costUsageBucketTimeZoneIdentifier = CostUsageBucketTimeZone.isValidIdentifier(storedBucketTimeZone)             ? storedBucketTimeZone             : (costUsageEnabled ? CostUsageBucketTimeZone.pinIdentifier() : "")` | 동일 의미의 Windows 설정/저장·관찰자 |
| `openCodexUsageLogsEnabled` | `SettingsStore.swift:576` — `let openCodexUsageLogsEnabled = userDefaults.object(forKey: "openCodexUsageLogsEnabled") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `hideNativeCodexCostWhenOpenCodexPresent` | `SettingsStore.swift:577` — `let hideNativeCodexCostWhenOpenCodexPresent = userDefaults.object(             forKey: "hideNativeCodexCostWhenOpenCodexPresent") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `spendDashboardHiddenSourceIDs` | `SettingsStore.swift:579` — `let spendDashboardHiddenSourceIDs = userDefaults.stringArray(forKey: "spendDashboardHiddenSourceIDs") ?? []` | 동일 의미의 Windows 설정/저장·관찰자 |
| `costComparisonPeriodsEnabled` | `SettingsStore.swift:580` — `let costComparisonPeriodsEnabled = userDefaults.object(             forKey: "costComparisonPeriodsEnabled") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `costSummaryDisplayStyleRaw` | `SettingsStore.swift:582` — `let costSummaryDisplayStyleRaw = Self.loadCostSummaryDisplayStyleRaw(             userDefaults: userDefaults,             costUsageEnabled: costUsageEnabled)` | 동일 의미의 Windows 설정/저장·관찰자 |
| `hidePersonalInfo` | `SettingsStore.swift:585` — `let hidePersonalInfo = userDefaults.object(forKey: "hidePersonalInfo") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `randomBlinkEnabled` | `SettingsStore.swift:586` — `let randomBlinkEnabled = userDefaults.object(forKey: "randomBlinkEnabled") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `confettiOnSessionLimitResetsEnabled` | `SettingsStore.swift:717` — `confettiOnSessionLimitResetsEnabled: confettiOnReset.session,` | 동일 의미의 Windows 설정/저장·관찰자 |
| `confettiOnWeeklyLimitResetsEnabled` | `SettingsStore.swift:718` — `confettiOnWeeklyLimitResetsEnabled: confettiOnReset.weekly,` | 동일 의미의 Windows 설정/저장·관찰자 |
| `menuBarShowsHighestUsage` | `SettingsStore.swift:588` — `let menuBarShowsHighestUsage = userDefaults.object(forKey: "menuBarShowsHighestUsage") as? Bool ?? false` | 트레이/팝업/상시 패널 표시·geometry 설정으로 대응 |
| `claudeOAuthKeychainPromptModeRaw` | `SettingsStore.swift:590` — `let claudeOAuthKeychainPromptModeRaw = userDefaults.string(forKey: "claudeOAuthKeychainPromptMode")         // Explicit consent for reading Claude Code's Keychain item (#2634). Default OFF; never enabled silently.` | Windows credential 접근·동의 정책으로 대체; Keychain 구현은 배포 제외 |
| `claudeOAuthKeychainReadStrategyRaw` | `SettingsStore.swift:589` — `let claudeOAuthKeychainReadStrategyRaw = Self.loadClaudeOAuthKeychainReadStrategyRaw(userDefaults: userDefaults)` | Windows credential 접근·동의 정책으로 대체; Keychain 구현은 배포 제외 |
| `claudeOAuthDirectKeychainReadAllowed` | `SettingsStore.swift:592` — `let claudeOAuthDirectKeychainReadAllowed = userDefaults.object(             forKey: ClaudeOAuthDirectKeychainReadConsent.userDefaultsKey) as? Bool ?? false` | Windows credential 접근·동의 정책으로 대체; Keychain 구현은 배포 제외 |
| `claudeWebExtrasEnabledRaw` | `SettingsStore.swift:594` — `let claudeWebExtrasEnabledRaw = userDefaults.object(forKey: "claudeWebExtrasEnabled") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `showOptionalCreditsAndExtraUsage` | `SettingsStore.swift:596` — `let showOptionalCreditsAndExtraUsage = creditsExtrasDefault ?? true` | 동일 의미의 Windows 설정/저장·관찰자 |
| `claudeDailyRoutinesUsageVisible` | `SettingsStore.swift:602` — `let claudeDailyRoutinesUsageVisible = claudeDailyRoutinesUsageVisibleDefault ?? true` | 동일 의미의 Windows 설정/저장·관찰자 |
| `claudeModelScopedWeeklyUsageVisible` | `SettingsStore.swift:607` — `let claudeModelScopedWeeklyUsageVisible = userDefaults.object(             forKey: "claudeModelScopedWeeklyUsageVisible") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `codexSparkUsageVisible` | `SettingsStore.swift:610` — `let codexSparkUsageVisible = codexSparkUsageVisibleDefault ?? true` | 동일 의미의 Windows 설정/저장·관찰자 |
| `codexExternalOAuthSourcesAllowed` | `SettingsStore.swift:614` — `let codexExternalOAuthSourcesAllowed = userDefaults.object(             forKey: "codexExternalOAuthSourcesAllowed") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `openAIWebAccessEnabled` | `SettingsStore.swift:620` — `let openAIWebAccessEnabled = openAIWebAccessDefault ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `openAIWebBatterySaverEnabled` | `SettingsStore.swift:625` — `let openAIWebBatterySaverEnabled = openAIWebBatterySaverDefault ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `backgroundWorkLowPowerModePreference` | `SettingsStore.swift:629` — `let backgroundWorkLowPowerModePreference = Self.loadLowPowerModePreference(userDefaults: userDefaults)` | 동일 의미의 Windows 설정/저장·관찰자 |
| `providerStorageFootprintsEnabled` | `SettingsStore.swift:631` — `let providerStorageFootprintsEnabled = providerStorageFootprintsDefault ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `jetbrainsIDEBasePath` | `SettingsStore.swift:635` — `let jetbrainsIDEBasePath = userDefaults.string(forKey: "jetbrainsIDEBasePath") ?? ""` | 동일 의미의 Windows 설정/저장·관찰자 |
| `mergeIcons` | `SettingsStore.swift:636` — `let mergeIcons = userDefaults.object(forKey: "mergeIcons") as? Bool ?? true` | 동일 의미의 Windows 설정/저장·관찰자 |
| `switcherShowsIcons` | `SettingsStore.swift:637` — `let switcherShowsIcons = userDefaults.object(forKey: "switcherShowsIcons") as? Bool ?? true` | 동일 의미의 Windows 설정/저장·관찰자 |
| `mergedMenuLastSelectedWasOverview` | `SettingsStore.swift:638` — `let mergedMenuLastSelectedWasOverview = userDefaults.object(             forKey: "mergedMenuLastSelectedWasOverview") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `mergedOverviewSelectedProvidersRaw` | `SettingsStore.swift:640` — `let mergedOverviewSelectedProvidersRaw = userDefaults.array(             forKey: "mergedOverviewSelectedProviders") as? [String] ?? []` | 동일 의미의 Windows 설정/저장·관찰자 |
| `selectedMenuProviderRaw` | `SettingsStore.swift:642` — `let selectedMenuProviderRaw = userDefaults.string(forKey: "selectedMenuProvider")` | 동일 의미의 Windows 설정/저장·관찰자 |
| `providerDetectionCompleted` | `SettingsStore.swift:643` — `let providerDetectionCompleted = userDefaults.object(forKey: "providerDetectionCompleted") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `providersSortedAlphabetically` | `SettingsStore.swift:644` — `let providersSortedAlphabetically = userDefaults.object(             forKey: "providersSortedAlphabetically") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `appLanguageRaw` | `SettingsStore.swift:646` — `let appLanguageRaw = userDefaults.string(forKey: "appLanguage")` | 동일 의미의 Windows 설정/저장·관찰자 |
| `terminalAppRaw` | `SettingsStore.swift:742` — `terminalAppRaw: userDefaults.string(forKey: "terminalApp"),` | Windows terminal/editor 선택·focus capability |
| `agentSessionsEnabled` | `SettingsStore.swift:647` — `let agentSessionsEnabled = userDefaults.object(forKey: "agentSessionsEnabled") as? Bool ?? false` | 동일 의미의 Windows 설정/저장·관찰자 |
| `agentSessionLabelStyleRaw` | `SettingsStore.swift:648` — `let agentSessionLabelStyleRaw = userDefaults.string(forKey: "agentSessionLabelStyle")             ?? AgentSessionLabelStyle.project.rawValue` | 동일 의미의 Windows 설정/저장·관찰자 |
| `agentSessionsManualHosts` | `SettingsStore.swift:650` — `let agentSessionsManualHosts = userDefaults.string(forKey: "agentSessionsManualHosts") ?? ""` | 동일 의미의 Windows 설정/저장·관찰자 |
| `preferredCurrencyCode` | `SettingsStore.swift:651` — `let preferredCurrencyCode = userDefaults.string(forKey: "preferredCurrencyCode") ?? "USD"` | 동일 의미의 Windows 설정/저장·관찰자 |
| `iCloudSyncEnabled` | `SettingsStore.swift:652` — `let iCloudSyncEnabled = userDefaults.object(forKey: "iCloudSyncEnabled") as? Bool ?? false` | Sync/Fleet 동등 설정; 원본 iCloud 상호운용은 별도 G-SYNC gate |
| `iCloudSyncIncludeSecrets` | `SettingsStore.swift:653` — `let iCloudSyncIncludeSecrets = userDefaults.object(forKey: "iCloudSyncIncludeSecrets") as? Bool ?? true` | Sync/Fleet 동등 설정; 원본 iCloud 상호운용은 별도 G-SYNC gate |
| `iCloudSyncSnapshotsEnabled` | `SettingsStore.swift:654` — `let iCloudSyncSnapshotsEnabled = userDefaults.object(forKey: "iCloudSyncSnapshotsEnabled") as? Bool ?? true` | Sync/Fleet 동등 설정; 원본 iCloud 상호운용은 별도 G-SYNC gate |
| `iCloudSyncShowFleetAccounts` | `SettingsStore.swift:655` — `let iCloudSyncShowFleetAccounts = userDefaults.object(forKey: "iCloudSyncShowFleetAccounts") as? Bool ?? true` | Sync/Fleet 동등 설정; 원본 iCloud 상호운용은 별도 G-SYNC gate |
| `iCloudSyncDeviceID` | `SettingsStore.swift:656` — `let iCloudSyncDeviceID = userDefaults.string(forKey: "iCloudSyncDeviceID") ?? UUID().uuidString.lowercased()` | Sync/Fleet 동등 설정; 원본 iCloud 상호운용은 별도 G-SYNC gate |
