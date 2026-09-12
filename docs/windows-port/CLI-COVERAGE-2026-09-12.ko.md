# CLI/HTTP 전수 대응표

[행동 계약](BEHAVIOR-CONTRACTS-2026-09-12.ko.md)의 BC-011~017을 함께 적용한다. TOON usage-only와 guard 종료 코드/unknown 상태는 옵션 선언 외 필수 계약이다.

원본 command registration과 dispatch를 대조했다. 30개 등록 노드는 parent/default를 포함하며 30개의 서로 다른 실행 명령이라는 뜻이 아니다. 아래 옵션은 **169개 선언**이며 공유 옵션이 명령별로 반복된다.

기본 진입은 usage, sessions→list, config→validate, hooks→list, cache→clear, cookie→refresh, plugins→list. `plugins list`는 별도 옵션 struct가 없다. 전역 help/version과 기존 오류/종료 코드도 유지한다.

공통 수락: 옵션 이름/alias/형식/기본값/상호배타 조건·headless 여부·stdout/stderr·JSON-only·실패/취소·종료 코드. Mac 전용 help 문구는 Windows의 실제 capability에 맞춘다. `--allow-keychain-prompt`는 Mac Keychain API 자체가 아니라 대화형 credential 접근 허용 계약으로 명시적으로 이전/문서화하며 아무 효과 없는 성공 옵션으로 남기지 않는다.


## usage

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `-v`, `--verbose` | `var verbose: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:16` |
| `--json-output` | `var jsonOutput: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:19` |
| `--log-level` | `var logLevel: String?` | `Sources/CodexBarCLI/CLIOptions.swift:22` |
| `--provider` | `var provider: ProviderSelection?` | `Sources/CodexBarCLI/CLIOptions.swift:25` |
| `--account` | `var account: String?` | `Sources/CodexBarCLI/CLIOptions.swift:30` |
| `--account-index` | `var accountIndex: Int?` | `Sources/CodexBarCLI/CLIOptions.swift:33` |
| `--all-accounts` | `var allAccounts: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:36` |
| `--format` | `var format: OutputFormat?` | `Sources/CodexBarCLI/CLIOptions.swift:39` |
| `--json` | `var jsonShortcut: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:42` |
| `--json-only` | `var jsonOnly: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:45` |
| `--no-credits` | `var noCredits: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:48` |
| `--no-color` | `var noColor: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:51` |
| `--pretty` | `var pretty: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:54` |
| `--status` | `var status: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:57` |
| `--web` | `var web: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:60` |
| `--source` | `var source: String?` | `Sources/CodexBarCLI/CLIOptions.swift:63` |
| `--app-auto-verifier` | `var appAutoVerifier: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:66` |
| `--web-timeout` | `var webTimeout: Double?` | `Sources/CodexBarCLI/CLIOptions.swift:71` |
| `--web-debug-dump-html` | `var webDebugDumpHtml: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:74` |
| `--antigravity-plan-debug` | `var antigravityPlanDebug: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:77` |
| `--augment-debug` | `var augmentDebug: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:80` |

## cards

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `-v`, `--verbose` | `var verbose: Bool = false` | `Sources/CodexBarCLI/CLICardsCommand.swift:14` |
| `--json-output` | `var jsonOutput: Bool = false` | `Sources/CodexBarCLI/CLICardsCommand.swift:17` |
| `--log-level` | `var logLevel: String?` | `Sources/CodexBarCLI/CLICardsCommand.swift:20` |
| `--provider` | `var provider: ProviderSelection?` | `Sources/CodexBarCLI/CLICardsCommand.swift:23` |
| `--account` | `var account: String?` | `Sources/CodexBarCLI/CLICardsCommand.swift:28` |
| `--account-index` | `var accountIndex: Int?` | `Sources/CodexBarCLI/CLICardsCommand.swift:31` |
| `--all-accounts` | `var allAccounts: Bool = false` | `Sources/CodexBarCLI/CLICardsCommand.swift:34` |
| `--no-credits` | `var noCredits: Bool = false` | `Sources/CodexBarCLI/CLICardsCommand.swift:37` |
| `--no-color` | `var noColor: Bool = false` | `Sources/CodexBarCLI/CLICardsCommand.swift:40` |
| `--status` | `var status: Bool = false` | `Sources/CodexBarCLI/CLICardsCommand.swift:43` |
| `--web` | `var web: Bool = false` | `Sources/CodexBarCLI/CLICardsCommand.swift:46` |
| `--source` | `var source: String?` | `Sources/CodexBarCLI/CLICardsCommand.swift:49` |
| `--web-timeout` | `var webTimeout: Double?` | `Sources/CodexBarCLI/CLICardsCommand.swift:52` |
| `--web-debug-dump-html` | `var webDebugDumpHtml: Bool = false` | `Sources/CodexBarCLI/CLICardsCommand.swift:55` |
| `--antigravity-plan-debug` | `var antigravityPlanDebug: Bool = false` | `Sources/CodexBarCLI/CLICardsCommand.swift:58` |
| `--augment-debug` | `var augmentDebug: Bool = false` | `Sources/CodexBarCLI/CLICardsCommand.swift:61` |
| `--brief` | `var brief: Bool = false` | `Sources/CodexBarCLI/CLICardsCommand.swift:64` |

## guard

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `-v`, `--verbose` | `var verbose: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:85` |
| `--json-output` | `var jsonOutput: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:88` |
| `--log-level` | `var logLevel: String?` | `Sources/CodexBarCLI/CLIOptions.swift:91` |
| `--provider` | `var provider: ProviderSelection?` | `Sources/CodexBarCLI/CLIOptions.swift:94` |
| `--min-remaining` | `var minRemaining: Double?` | `Sources/CodexBarCLI/CLIOptions.swift:97` |
| `--window` | `var window: String?` | `Sources/CodexBarCLI/CLIOptions.swift:100` |
| `--timeout` | `var timeout: Double?` | `Sources/CodexBarCLI/CLIOptions.swift:103` |
| `--json` | `var json: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:108` |
| `--pretty` | `var pretty: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:111` |
| `--fail-open` | `var failOpen: Bool = false` | `Sources/CodexBarCLI/CLIOptions.swift:114` |

## cost

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `-v`, `--verbose` | `var verbose: Bool = false` | `Sources/CodexBarCLI/CLICostCommand.swift:865` |
| `--json-output` | `var jsonOutput: Bool = false` | `Sources/CodexBarCLI/CLICostCommand.swift:868` |
| `--log-level` | `var logLevel: String?` | `Sources/CodexBarCLI/CLICostCommand.swift:871` |
| `--provider` | `var provider: ProviderSelection?` | `Sources/CodexBarCLI/CLICostCommand.swift:874` |
| `--format` | `var format: OutputFormat?` | `Sources/CodexBarCLI/CLICostCommand.swift:879` |
| `--json` | `var jsonShortcut: Bool = false` | `Sources/CodexBarCLI/CLICostCommand.swift:882` |
| `--json-only` | `var jsonOnly: Bool = false` | `Sources/CodexBarCLI/CLICostCommand.swift:885` |
| `--pretty` | `var pretty: Bool = false` | `Sources/CodexBarCLI/CLICostCommand.swift:888` |
| `--no-color` | `var noColor: Bool = false` | `Sources/CodexBarCLI/CLICostCommand.swift:891` |
| `--refresh` | `var refresh: Bool = false` | `Sources/CodexBarCLI/CLICostCommand.swift:894` |
| `--breakdown` | `var breakdown: Bool = false` | `Sources/CodexBarCLI/CLICostCommand.swift:897` |
| `--provider-native-only` | `var providerNativeOnly: Bool = false` | `Sources/CodexBarCLI/CLICostCommand.swift:900` |
| `--days` | `var days: Int?` | `Sources/CodexBarCLI/CLICostCommand.swift:905` |
| `--group-by` | `var groupBy: String?` | `Sources/CodexBarCLI/CLICostCommand.swift:908` |

## sessions list (default)

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `--json` | `var jsonShortcut: Bool = false` | `Sources/CodexBarCLI/CLISessionsCommand.swift:103` |
| `--json-v2` | `var jsonV2: Bool = false` | `Sources/CodexBarCLI/CLISessionsCommand.swift:106` |
| `--pretty` | `var pretty: Bool = false` | `Sources/CodexBarCLI/CLISessionsCommand.swift:109` |

## sessions focus

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `<id>` | `var id: String = ""` | `Sources/CodexBarCLI/CLISessionsCommand.swift:114` |

## serve

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `-v`, `--verbose` | `var verbose: Bool = false` | `Sources/CodexBarCLI/CLIServeCommand.swift:6` |
| `--json-output` | `var jsonOutput: Bool = false` | `Sources/CodexBarCLI/CLIServeCommand.swift:9` |
| `--log-level` | `var logLevel: String?` | `Sources/CodexBarCLI/CLIServeCommand.swift:12` |
| `--port` | `var port: Int?` | `Sources/CodexBarCLI/CLIServeCommand.swift:15` |
| `--host` | `var host: String?` | `Sources/CodexBarCLI/CLIServeCommand.swift:18` |
| `--refresh-interval` | `var refreshInterval: Double?` | `Sources/CodexBarCLI/CLIServeCommand.swift:21` |
| `--request-timeout` | `var requestTimeout: Double?` | `Sources/CodexBarCLI/CLIServeCommand.swift:24` |
| `--dashboard-token` | `var dashboardBearer: String?` | `Sources/CodexBarCLI/CLIServeCommand.swift:29` |
| `--allow-plain-http` | `var allowPlainHTTP: Bool = false` | `Sources/CodexBarCLI/CLIServeCommand.swift:34` |
| `--identity` | `var identity: String?` | `Sources/CodexBarCLI/CLIServeCommand.swift:39` |

## dashboard

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `-v`, `--verbose` | `var verbose: Bool = false` | `Sources/CodexBarCLI/CLIDashboardCommand.swift:13` |
| `--json-output` | `var jsonOutput: Bool = false` | `Sources/CodexBarCLI/CLIDashboardCommand.swift:16` |
| `--log-level` | `var logLevel: String?` | `Sources/CodexBarCLI/CLIDashboardCommand.swift:19` |
| `--pretty` | `var pretty: Bool = false` | `Sources/CodexBarCLI/CLIDashboardCommand.swift:22` |
| `--timeout` | `var timeout: Double?` | `Sources/CodexBarCLI/CLIDashboardCommand.swift:25` |
| `--identity` | `var identity: String?` | `Sources/CodexBarCLI/CLIDashboardCommand.swift:30` |
| `--output` | `var output: String?` | `Sources/CodexBarCLI/CLIDashboardCommand.swift:36` |

## config validate (default), config providers

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `-v`, `--verbose` | `var verbose: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:370` |
| `--json-output` | `var jsonOutput: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:373` |
| `--log-level` | `var logLevel: String?` | `Sources/CodexBarCLI/CLIConfigCommand.swift:376` |
| `--format` | `var format: OutputFormat?` | `Sources/CodexBarCLI/CLIConfigCommand.swift:379` |
| `--json` | `var jsonShortcut: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:382` |
| `--json-only` | `var jsonOnly: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:385` |
| `--pretty` | `var pretty: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:388` |

## config dump

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `-v`, `--verbose` | `var verbose: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:393` |
| `--json-output` | `var jsonOutput: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:396` |
| `--log-level` | `var logLevel: String?` | `Sources/CodexBarCLI/CLIConfigCommand.swift:399` |
| `--format` | `var format: OutputFormat?` | `Sources/CodexBarCLI/CLIConfigCommand.swift:402` |
| `--json` | `var jsonShortcut: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:405` |
| `--json-only` | `var jsonOnly: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:408` |
| `--pretty` | `var pretty: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:411` |
| `--show-secrets` | `var showSecrets: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:414` |

## config set-api-key

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `-v`, `--verbose` | `var verbose: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:419` |
| `--json-output` | `var jsonOutput: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:422` |
| `--log-level` | `var logLevel: String?` | `Sources/CodexBarCLI/CLIConfigCommand.swift:425` |
| `--format` | `var format: OutputFormat?` | `Sources/CodexBarCLI/CLIConfigCommand.swift:428` |
| `--json` | `var jsonShortcut: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:431` |
| `--json-only` | `var jsonOnly: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:434` |
| `--pretty` | `var pretty: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:437` |
| `--provider` | `var provider: String?` | `Sources/CodexBarCLI/CLIConfigCommand.swift:440` |
| `--api-key` | `var apiKey: String?` | `Sources/CodexBarCLI/CLIConfigCommand.swift:443` |
| `--stdin` | `var stdin: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:446` |
| `--no-enable` | `var noEnable: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:449` |
| `--label` | `var label: String?` | `Sources/CodexBarCLI/CLIConfigCommand.swift:452` |
| `--usage-scope` | `var usageScope: String?` | `Sources/CodexBarCLI/CLIConfigCommand.swift:455` |
| `--organization-id` | `var organizationId: String?` | `Sources/CodexBarCLI/CLIConfigCommand.swift:458` |
| `--workspace-id` | `var workspaceId: String?` | `Sources/CodexBarCLI/CLIConfigCommand.swift:461` |

## config enable, config disable

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `-v`, `--verbose` | `var verbose: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:466` |
| `--json-output` | `var jsonOutput: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:469` |
| `--log-level` | `var logLevel: String?` | `Sources/CodexBarCLI/CLIConfigCommand.swift:472` |
| `--format` | `var format: OutputFormat?` | `Sources/CodexBarCLI/CLIConfigCommand.swift:475` |
| `--json` | `var jsonShortcut: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:478` |
| `--json-only` | `var jsonOnly: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:481` |
| `--pretty` | `var pretty: Bool = false` | `Sources/CodexBarCLI/CLIConfigCommand.swift:484` |
| `--provider` | `var provider: String?` | `Sources/CodexBarCLI/CLIConfigCommand.swift:487` |

## cache clear (default)

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `-v`, `--verbose` | `var verbose: Bool = false` | `Sources/CodexBarCLI/CLICacheCommand.swift:103` |
| `--json-output` | `var jsonOutput: Bool = false` | `Sources/CodexBarCLI/CLICacheCommand.swift:106` |
| `--log-level` | `var logLevel: String?` | `Sources/CodexBarCLI/CLICacheCommand.swift:109` |
| `--format` | `var format: OutputFormat?` | `Sources/CodexBarCLI/CLICacheCommand.swift:112` |
| `--json` | `var jsonShortcut: Bool = false` | `Sources/CodexBarCLI/CLICacheCommand.swift:115` |
| `--json-only` | `var jsonOnly: Bool = false` | `Sources/CodexBarCLI/CLICacheCommand.swift:118` |
| `--pretty` | `var pretty: Bool = false` | `Sources/CodexBarCLI/CLICacheCommand.swift:121` |
| `--cookies` | `var cookies: Bool = false` | `Sources/CodexBarCLI/CLICacheCommand.swift:124` |
| `--cost` | `var cost: Bool = false` | `Sources/CodexBarCLI/CLICacheCommand.swift:127` |
| `--all` | `var all: Bool = false` | `Sources/CodexBarCLI/CLICacheCommand.swift:130` |
| `--provider` | `var provider: String?` | `Sources/CodexBarCLI/CLICacheCommand.swift:133` |

## cookie refresh (default)

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `-v`, `--verbose` | `var verbose: Bool = false` | `Sources/CodexBarCLI/CLICookieCommand.swift:325` |
| `--json-output` | `var jsonOutput: Bool = false` | `Sources/CodexBarCLI/CLICookieCommand.swift:328` |
| `--json` | `var jsonShortcut: Bool = false` | `Sources/CodexBarCLI/CLICookieCommand.swift:331` |
| `--json-only` | `var jsonOnly: Bool = false` | `Sources/CodexBarCLI/CLICookieCommand.swift:334` |
| `--pretty` | `var pretty: Bool = false` | `Sources/CodexBarCLI/CLICookieCommand.swift:337` |
| `--format` | `var format: OutputFormat?` | `Sources/CodexBarCLI/CLICookieCommand.swift:340` |
| `--all` | `var all: Bool = false` | `Sources/CodexBarCLI/CLICookieCommand.swift:343` |
| `--provider` | `var provider: String?` | `Sources/CodexBarCLI/CLICookieCommand.swift:346` |
| `--allow-keychain-prompt` | `var allowKeychainPrompt: Bool = false` | `Sources/CodexBarCLI/CLICookieCommand.swift:349` |

## diagnose

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `-v`, `--verbose` | `var verbose: Bool = false` | `Sources/CodexBarCLI/DiagnoseOptions.swift:6` |
| `--json-output` | `var jsonOutput: Bool = false` | `Sources/CodexBarCLI/DiagnoseOptions.swift:9` |
| `--log-level` | `var logLevel: String?` | `Sources/CodexBarCLI/DiagnoseOptions.swift:12` |
| `--provider` | `var provider: String?` | `Sources/CodexBarCLI/DiagnoseOptions.swift:15` |
| `--format` | `var format: String?` | `Sources/CodexBarCLI/DiagnoseOptions.swift:18` |
| `--redact` | `var redact: Bool = false` | `Sources/CodexBarCLI/DiagnoseOptions.swift:21` |
| `--output` | `var output: String?` | `Sources/CodexBarCLI/DiagnoseOptions.swift:24` |
| `--pretty` | `var pretty: Bool = false` | `Sources/CodexBarCLI/DiagnoseOptions.swift:27` |

## hooks list (default), hooks enable, hooks disable

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `--format` | `var format: OutputFormat?` | `Sources/CodexBarCLI/CLIHooksCommand.swift:195` |
| `--json` | `var jsonShortcut: Bool = false` | `Sources/CodexBarCLI/CLIHooksCommand.swift:198` |
| `--json-only` | `var jsonOnly: Bool = false` | `Sources/CodexBarCLI/CLIHooksCommand.swift:201` |
| `--pretty` | `var pretty: Bool = false` | `Sources/CodexBarCLI/CLIHooksCommand.swift:204` |

## hooks test

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `<event>` | `var event: String = ""` | `Sources/CodexBarCLI/CLIHooksCommand.swift:209` |
| `--provider` | `var provider: String?` | `Sources/CodexBarCLI/CLIHooksCommand.swift:212` |
| `--format` | `var format: OutputFormat?` | `Sources/CodexBarCLI/CLIHooksCommand.swift:215` |
| `--json` | `var jsonShortcut: Bool = false` | `Sources/CodexBarCLI/CLIHooksCommand.swift:218` |
| `--json-only` | `var jsonOnly: Bool = false` | `Sources/CodexBarCLI/CLIHooksCommand.swift:221` |
| `--pretty` | `var pretty: Bool = false` | `Sources/CodexBarCLI/CLIHooksCommand.swift:224` |

## hooks watch

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `--interval` | `var interval: String?` | `Sources/CodexBarCLI/CLIHooksWatchCommand.swift:374` |
| `--provider` | `var provider: String?` | `Sources/CodexBarCLI/CLIHooksWatchCommand.swift:377` |
| `--verbose` | `var verbose: Bool = false` | `Sources/CodexBarCLI/CLIHooksWatchCommand.swift:380` |
| `--format` | `var format: OutputFormat?` | `Sources/CodexBarCLI/CLIHooksWatchCommand.swift:383` |
| `--json` | `var jsonShortcut: Bool = false` | `Sources/CodexBarCLI/CLIHooksWatchCommand.swift:386` |
| `--json-only` | `var jsonOnly: Bool = false` | `Sources/CodexBarCLI/CLIHooksWatchCommand.swift:389` |
| `--pretty` | `var pretty: Bool = false` | `Sources/CodexBarCLI/CLIHooksWatchCommand.swift:392` |

## plugins fetch

| 옵션 | 원본 선언·기본값 | 근거 |
|---|---|---|
| `<id>` | `var id: String = ""` | `Sources/CodexBarCLI/CLIPluginsCommand.swift:13` |
| `--json` | `var json: Bool = false` | `Sources/CodexBarCLI/CLIPluginsCommand.swift:16` |
| `--pretty` | `var pretty: Bool = false` | `Sources/CodexBarCLI/CLIPluginsCommand.swift:19` |

## HTTP 및 replay

HTTP: GET `/`, `/icons/<name>.svg`, `/health`, `/usage`, `/cost`, `/dashboard/v1/snapshot`. 정적 web UI/icon과 데이터 route 각각의 auth 경계·Host allowlist·method/path 거부·provider/detail/query 검증·cache TTL·강제 refresh/timeout·종료 drain을 유지한다. 실제 경로 선택은 CLIServeRouter와 CLI read request 함수를 근거로 한다.

AdaptiveReplayCLI: `--json`, `--raw-wall-clock`, `--gap-grace`, `--policy` 및 help/input trace·종료 코드. adaptive/adaptive-activity/fixed-2m/5m/15m/30m/manual 정책과 source trace 의미를 유지한다. 개발/진단 도구로 분류하며 원본 GUI 설정과 혼동하지 않는다.
