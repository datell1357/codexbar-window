# CodexBar 포크 기반 Windows 이식 계획

작성일: 2026-09-09. 계획 개정본이며 제품 구현·빌드·전체 의미 분석 완료 보고가 아니다.

## 1. 결정과 기준

GitHub 포크: https://github.com/datell1357/CodexBar — GitHub API의 isFork=true 및 parent=steipete/CodexBar 확인.
로컬 작업 대상: `/Users/yeoreum/Documents/codexbar-window/fork`.
고정 커밋: `928166f899471bbdcb72210641cdec91324d0154`.

**이 포크에서 원본 Swift 코어·공급자·플러그인·CLI·테스트를 최대한 유지하고 Windows 플랫폼 계층과 네이티브 UI를 추가한다.** 이전의 Windows 참조 포트 기반 Rust/Tauri 재구현 권고는 대체한다. `windows-reference`는 비교 자료로만 남긴다. 원본의 macOS와 Linux 경로도 유지하며 향후 upstream 변경을 받아들일 수 있도록 플랫폼 변경을 집중시킨다.

포크는 코드를 재사용할 출발점이지 Windows 실행 파일이 아니다. 현재 Package.swift는 앱/위젯/WebProbe/Watchdog를 macOS에서만 생성한다. Core에도 POSIX 및 Apple API 경로가 남아 있다. 따라서 코어의 Windows 컴파일과 핵심 어댑터 실증이 첫 구현 단계다. 전체 기능 범위는 유지하되 OS 표현과 서비스 상호운용의 차이를 숨기지 않는다.

## 2. 기존 분석 이관과 완전성

포크의 Git 추적 항목은 2,844개이며 SOURCE-MANIFEST.json에 mode·blob hash와 함께 기록했다. 이는 읽기/의미 검토 완료 수가 아니다.
이전 기준 `0cb8c425e2ea5ccf8fc19d1d39ecaa650d8a8b40`에서 74개 파일이 변경됐다. 기존 기능 후보 569행을 FEATURE-MIGRATION.json에 보존했다. 직접 참조 파일이 바뀐 행은 71개, 사라진 참조 경로를 가진 행은 0개다. 간접 호출 영향과 새 기능까지 이 수치로 검증한 것은 아니다.

모든 행은 REVALIDATE_ON_FORK다. 예전 Rust 파일·줄 번호·테스트 계획을 새 포크의 구현 근거로 사용하지 않는다. BASELINE-DELTA.json의 변경 파일부터 검토하되 나머지 파일도 미검토 상태를 유지한다. 기존 후보 수 569를 전체 기능의 확정 분모로 사용하지 않는다.

새 기능 계약은 다음을 갖는다: 원본 commit/path/symbol, 사용자 진입점, 조건·기본값, 계정·인증 소유권, 성공·실패·빈 상태, 부수 효과, Swift 보존/추출/OS 대체 결정, 계획 모듈·인터페이스, fixture 입력/기대 출력, Windows 실증, 미해결 조건, 독립 검토 결과.

생성물·vendored·문서·리소스·테스트·배포 파일도 분류한다. 생성물은 생성기와 결과 일치, vendored는 호출 계약과 플랫폼 빌드, 리소스는 실제 소비자를 확인한다. 경로가 존재한다는 검사만으로 의미 분석 완료 처리하지 않는다.

## 3. 코드 구조와 책임

| 영역 | 원본 근거(포크 상대 경로) | 구현 방식 |
|---|---|---|
| 공급자·계산·파서 | Sources/CodexBarCore/Providers, Vendored, Plugins | Swift 보존. 플랫폼 호출만 주입 가능한 어댑터로 분리 |
| 갱신 알고리즘 | Sources/AdaptiveRefreshCore, AdaptiveReplayKit | 동일 알고리즘·replay 보존. OS 전력/활동 신호만 교체 |
| 앱 상태·설정·메뉴 모델 | Sources/CodexBar/UsageStore*, SettingsStore*, MenuDescriptor* | AppKit/SwiftUI와 섞인 비즈니스 로직을 공용 런타임 타깃으로 이동. Core만 공유해서 앱 동작이 빠지는 것을 방지 |
| CLI·HTTP | Sources/CodexBarCLI | 명령·옵션·JSON·오류·종료 코드 보존. 프로세스/신호/socket 부분을 Windows로 대응 |
| UI | Sources/CodexBar, Sources/CodexBarWidget | C++/Win32 트레이와 WinUI 3 화면을 기본 설계로 제안. Windows Widgets 공급자는 별도 OS 호스트로 구현 |
| 플러그인 엔진 | Sources/CQuickJS, Core/Plugins/QuickJSProviderPluginEngine.swift | 기존 QuickJS·TS transpiler·host API 유지. Node/Chromium을 플러그인 때문에 상주시킬 필요 없음 |
| macOS 전용 서비스 | Sources/CodexBarCore/Host, Sources/CodexBar/Sync, Sources/CodexBarClaudeWebProbe, Sources/CodexBarClaudeWatchdog | Windows 어댑터 또는 동등 기능 보조 프로그램 |

예정 디렉터리(아직 생성/구현하지 않음): Sources/CodexBarRuntime, Sources/CodexBarWindowsHost, Sources/CodexBarWindowsBridge, Windows/App, Windows/Widgets, TestsWindows.

UI→Swift 연결은 G1에서 C ABI와 named-pipe backend를 비교해 확정한다. C ABI 후보에서는 다음 계약을 사용한다. 요청/응답은 버전 있는 UTF-8 JSON DTO를 기본으로 하고 dispose 함수로 메모리 소유권을 명시한다. async 작업은 request ID·취소·완료 callback, 상태 변경은 generation을 포함한 snapshot으로 전달한다. Swift 객체 포인터를 UI에 노출하지 않는다. UI callback은 UI 스레드로 전달하고 종료 시 구독을 해제한다. 고빈도 복사를 피하도록 변경 snapshot만 전달한다.

G1에서 ABI 안정성과 성능을 통과하면 트레이·UI는 같은 프로세스에서 코어 하나를 사용한다. 불가하면 Swift backend 하나를 별도 프로세스로 두고 같은 DTO로 통신한다. 위젯은 비밀 없는 원자적 snapshot을 읽는다. 독립 CLI는 원본의 단독 실행을 유지한다. 앱과 CLI가 동시에 저장·인증 갱신할 경우 계정별 lock, 원자적 저장, 소유권 검증이 필요하다. 앱 실행을 CLI의 필수 조건으로 만들지 않는다. 상주 HTTP 서버는 기본값이 아니다.

## 4. 전체 기능 작업 묶음

아래는 구현 작업 목차다. 569개 후보의 개별 계약 검증을 대신하지 않는다.

| 작업 | 포함 범위 | 계획 구현·검증 책임 |
|---|---|---|
| W01 공급자 전체 | docs/provider-ids.md의 69개 전부, 각 인증·조회 소스·조직·지역·플랜·endpoint·추가 한도 | Core 담당: descriptor/fetch planner/credential/UI 소비자를 연결하고 provider×source×account×outcome fixture 대조. ID만 등록해서 완료하지 않음 |
| W02 계정 | Codex managed/system/profile/workspace, Claude swap, 토큰 계정·전환·재인증·ownership | Auth 담당: Credential Manager/DPAPI 저장 제안, 외부 CLI 소유 credential 갱신 규칙 유지. 동시 갱신·오계정·로그아웃·권한 거부 시험 |
| W03 트레이 | 개별/통합 아이콘, Overview, 최고 사용량, 잔여/사용, 조건식·두 줄·override·단축키·동작 메뉴 | UI 담당: 원본 표시 모델 재사용, 아이콘/팝업/선택형 텍스트 패널. 가변폭 메뉴바 동일성은 별도 게이트 |
| W04 설정 | 모든 pane·검색·언어·통화·provider 순서·초기 감지·PII·터미널·기본값·migration | Runtime/UI 담당: 설정 키 인벤토리와 화면 control 양방향 대조, 저장/재시작/이전 설정 fixture |
| W05 사용량·예측 | primary/secondary/tertiary/extra, credits/reset/freshness, pace·작업일·ETA | Core 담당: 원본 계산 보존. timezone/DST·분모 0·누락과 0·초과·stale 대조 |
| W06 비용 | 로컬/원격 비용, Codex/Claude/pi/OMP/OpenCodex 등, 증분 캐시·가격·보존·출처 | Core 담당: 파서와 저장 의미 보존. 중복·fan-out·overflow·부분 쓰기·회전·재시작·crash fixture |
| W07 대시보드 | 7/30/90/all, 모델·프로젝트·세션, 차트/heatmap·비교·coverage·catch-up·pause/resume·공유 | UI/Core 담당: 동일 집계, native chart/export. clipboard/PNG/JSON 저장까지 검증. 라이브러리만 있는 CSV는 출시 UI로 잘못 소개하지 않음 |
| W08 갱신 | manual/fixed/adaptive/agent-aware·동의·메뉴 열기·저전력·cancel/dedupe·절전 복귀 | Runtime 담당: Windows 전력/활동 이벤트와 원본 decision table 연결; replay와 절전/복귀 실증 |
| W09 알림 | 장애/component·소진/복구/임계/예측·sound/overlay·reset confetti | UI/Host 담당: Windows 알림·렌더링; 전이별 중복 방지와 클릭 동작·알림 권한 거부 시험 |
| W10 위젯 | Switcher/Usage/History/Metric/Burn Down/Combined Burn Down, 선택·크기·인스턴스·stale/empty | Widgets 담당: 원본 snapshot/계산 공유. 실제 Widgets Board 설치·선택·다중 인스턴스·갱신 증거 필요 |
| W11 Sessions | Codex/Claude/pi/OMP 로컬 탐색, active/idle·제목·프라이버시, SSH/Tailscale 원격·버전·focus | Host 담당: Windows 프로세스/터미널 연결, 원격 JSON 유지. 미지원 터미널 focus를 성공 처리하지 않음 |
| W12 CLI/HTTP | usage/cards/cost/dashboard/serve/sessions/guard/config/cache/cookie/hooks/plugins/diagnose 및 하위 옵션 | CLI 담당: help/기본값/출력/schema/exit/인증/route·stream·중단 계약 golden 대조. Winsock/신호 대응 |
| W13 Hooks | 이벤트·규칙·조건·enable/test/watch, stdin JSON·환경변수·timeout | Host 담당: 원본 이벤트 유지, 기본은 원본처럼 shell 없이 executable/arguments 직접 실행·Windows quoting·Job Object 종료. bash 스크립트 자체의 자동 호환은 별도 |
| W14 Plugins | JS/TS 설치/승인/설정/업데이트/비활성/제거, 동적 ID·cache·HTTP/cookie/secret·오류 | Plugins 담당: 기존 engine와 정책 보존. ABI·정수·시간대·메모리/시간 제한·stale snapshot golden |
| W15 Sync/Fleet | portable settings·선택 secrets·usage/account snapshot·장치·충돌·삭제 marker·offline | Sync 담당: 원본 schema 보존. CloudKit 접근권과 macOS 상호운용 실증 전 완성 판정 금지 |
| W16 운영 | 자동 시작·stable/beta·설치/CLI PATH·업데이트·진단/redaction·cache·replay·접근성 | Release 담당: 별도 Windows 서명/배포 feed, 업데이트 실패/rollback/uninstall·키보드/DPI/screenreader 시험 |

69개 ID(독립 지원 대상): codex, openai, azureopenai, claude, clinepass, cursor, opencode, opencodego, alibaba, alibabatokenplan, qwencloud, factory, fireworks, gemini, antigravity, copilot, devin, zai, minimax, manus, kimi, kilo, kiro, vertexai, augment, jetbrains, moonshot, amp, t3chat, ollama, synthetic, openrouter, elevenlabs, warp, windsurf, zed, perplexity, mimo, doubao, sakana, abacus, mistral, deepseek, deepinfra, codebuff, crof, venice, commandcode, qoder, stepfun, bedrock, grok, groq, llmproxy, litellm, deepgram, poe, chutes, neuralwatt, clawrouter, longcat, sub2api, wayfinder, zenmux, aiand, zoommate, xai, notion, ibmbob.

## 5. 먼저 해결할 플랫폼 게이트

- G1 빌드/연결: Swift Windows 툴체인으로 Core·CLI·QuickJS·SQLite·Crypto·Commander·SwiftLog·SweetCookieKit를 빌드하고 fixture 실행. Package.swift의 macOS 전용 의존성 resolution도 분리. UI에서 C ABI로 fetch fixture→snapshot→cancel→dispose 1,000회 검증. 성공 전 재사용 비율·패키지 크기 확약 금지.
- G2 프로세스: Host/Process/SubprocessRunner.swift의 pid_t/SIGTERM/SIGKILL/usleep/kill, PTY·spawn 경로는 Windows process/Job Object/ConPTY로 구현. 공백/한글/따옴표 인자, 자식·손자 timeout, stdout/stderr 동시 포화, credential mutation 중 취소 계약 검증.
- G3 저장·인증: Security/Keychain·파일 잠금·atomic rename·ACL·브라우저 profile/암호화 차이 점검. OAuth 앱 등록/redirect/외부 CLI 소유권도 포함. Chrome/Edge/Firefox의 실제 지원 버전별 자동 로그인 가져오기 성공/잠김/거부를 분리. 수동 토큰만 되고 자동 가져오기가 안 되면 해당 기능은 미완료.
- G4 브라우저: WebKit probe를 필요할 때만 WebView2 호스트로 대응하는 후보. 원본 cookie transaction·조직 검증·Cloudflare·renewal 실패의 롤백을 보존. 사용자 브라우저와 WebView2 세션이 같다고 가정하지 않음. 자동화에 의해 서비스가 차단되면 미해결로 기록.
- G5 Sync: Sources/CodexBar/Sync/CloudSyncEngine.swift의 CloudKit container·entitlement·인증·레코드·암호화 계약을 확인하고 접근 가능한 테스트 container에서 Windows↔macOS 왕복/충돌/삭제를 실증. 포크만으로 원저자 container 접근권을 얻지 못함. 권한/SDK 경로 불가 시 원본 iCloud 연동은 BLOCKED; 별도 backend를 동등 연동 완료로 바꾸지 않음.
- G6 위젯/가변폭: 실제 Windows Widgets Board에서 6종의 표시·선택·상태 갱신을 시험한다. Windows 트레이 아이콘에 macOS 가변폭 메뉴바를 그대로 구현한다고 약속하지 않는다. 모든 토큰/조건식은 보존하되 별도 패널 제안을 사용자에게 보여 동등 UX 수용 여부를 결정한다. 정확한 OS 동일성을 요구하면 제한을 남긴다.
- G7 배포/터미널: clean Windows에서 설치·실행·CLI PATH·자동 시작·업데이트·복구를 검증한다. terminal별 session focus, PowerShell/cmd 및 선택적 WSL hook 경로를 구분한다. WSL은 앱 실행의 필수 전제가 아니다.

G1 실패 시: OS 어댑터 또는 C ABI 포장 범위를 줄여 해결하고 실패 원인을 기록한다. Swift core 자체가 실용적으로 성립하지 않을 때만 언어 재작성 대안을 별도 비교한다. 분석만으로 Rust 전체 재작성으로 되돌리지 않는다.

## 6. 경량화 설계와 측정 계약

상주 대상은 native tray와 공유 코어 하나. 설정/대시보드 창은 열 때 생성하고 닫으면 자원 해제. WebView2는 웹 인증에 필요한 동안만 실행. QuickJS는 필요한 작업의 제한된 worker에만 생성하고 idle 해제하는 정책을 추가할 계획이다. 공급자가 비활성이면 timer/network/scan 작업을 시작하지 않는다. 기능 선택지는 모두 제공한다.

단일 스케줄러·중복 요청 합치기·동시성 상한·증분 파일 읽기·제한된 cache/history를 사용한다. 버퍼/worker 제한이 원본 결과를 잘라먹지 않도록 출력 초과 오류와 재시도 계약을 보존한다. upstream의 전체 로그/캐시 의미를 검증하기 전 저장 엔진을 통째로 SQLite로 바꾸지 않는다.

미측정 제안 목표: Windows 11 x64, 4 logical cores/8GB, Release 빌드에서 3개 대표 공급자 활성·60초 기본 갱신·화면 닫힘·10분 안정화 후 30분 측정. 앱과 모든 자식의 합계 private working set p95 ≤100MiB, 총 CPU 시간/(관찰시간×logical cores) ≤0.5%, 열기 반응 p95 ≤200ms. 모든 공급자 등록/3개 활성과 69개 활성 부하를 따로 측정하고 후자 결과를 전자 예산으로 홍보하지 않는다.

창 열림/웹 인증 중 peak, 창 닫고 60초 뒤 잔류 프로세스·메모리, 8시간 추세, 절전 복귀, 대형 로그 catch-up을 별도 측정한다. 목표 미달 시 trace로 원인→수명/캐시/복사 최적화→같은 fixture 결과/부하 재측정. 기능·정확도 삭제로 예산을 맞추지 않는다. 숫자는 측정 결과나 보장값이 아니다.

## 7. 실행 순서와 완료 판정

1. 기준 고정·기존 후보 이관·delta 검토 → 모든 변경 파일의 영향과 미검토 항목 기록.
2. G1~G7 중 기술 위험을 작은 prototype으로 병렬 실증 → 성공/실패/대안/소유자 기록. 이 단계는 향후 구현 승인 후 실행.
3. Core/CLI 공유와 Host 어댑터 → 원본 parser/plugin/replay fixture를 양 OS에서 비교.
4. 앱 runtime 추출과 계정/갱신/비용 통합 → 기존 macOS 회귀 + Windows 상태/동시성 검증.
5. W01~W16 화면·통합을 구현 → 각 기능 ID의 정상/오류/빈 상태·설정 저장·실사용 증거 연결.
6. 독립 기능 검토·Windows 전체 회귀·성능·설치/업데이트 → 남은 BLOCKED를 공개하고 full parity 여부 판정.

단계는 우선순위이며 기능을 버리는 MVP 범위가 아니다. 날짜/주수는 G1~G7 결과와 작업량 검증 후 산정한다.
계획 OK: 모든 추적 파일 검토/분류, 발견된 기능 계약의 실행 가능한 계획, 플랫폼 결정·선행 실증 절차, 독립 필수 수정 0. 제품 FULL_PARITY: 모든 필수 기능의 Windows 증거와 동등 UX 결정, 회귀/성능/배포 검증까지 통과. 두 판정을 구분한다.

현재: 포크 확인/계획 개정/기계적 후보 이관 완료. 전체 의미 검토·Windows 빌드·실계정·성능·독립 승인 미완료. 계획 판정은 NOT_OK를 유지한다. 이 문서 작성은 앱 구현이나 commit/push/PR 승인이 아니다.

## 8. 이번 기준 변경의 우선 회귀 대상

74개 변경 파일 중 CLI renderer의 unavailable percentage/막대 생략/Antigravity named quota lanes, Bedrock region 설정, Claude swap compact 계정 표시, MiniMax transport identity, MiMo local fallback, token account 갱신, 비용 whitespace/cache replacement·OpenCodex fan-out/overflow를 우선 추적한다. SubprocessRunner timeout의 정수 변환/overflow 의미도 Windows adapter에 보존한다. 관련 변경 테스트는 BASELINE-DELTA.json의 Tests 경로를 기준으로 연결한다.

플러그인 앱 연결에는 JavaScriptCore import 조건으로 감싼 경로도 있으므로 QuickJS 코어가 빌드된다고 설정·메뉴·갱신 연결까지 동작한다고 보지 않는다. UsageStore+UserPlugins.swift, PreferencesPluginsPane.swift, StatusItemController+UserPlugins.swift의 플랫폼 조건과 TestsPlugin을 함께 검증한다. CLI text/cards/JSON/TOON, HTTP Host allowlist/Bearer/timeout, hooks의 직접 실행 계약도 회귀 대상이다.

## 9. 추가 소스 검토에서 확인한 숨은 실패 경로

- Config/CodexBarConfig.swift의 provider instance 인식도 canImport(JavaScriptCore)에 묶인 경로를 점검한다. UI 가드만 바꿔서는 QuickJS-only 환경에서 사용자 플러그인 설정이 유지되지 않을 수 있다. config load/save/restart fixture를 G1/W14에 포함한다.
- CQuickJS/CQuickJSHost.c의 clock_gettime/CLOCK_MONOTONIC 기반 watchdog를 Windows 단조 시계로 대응한다. vendored QuickJS의 _WIN32 존재만으로 host가 빌드된다고 판정하지 않는다.
- SweetCookieKit는 Core의 무조건 의존성이다. Windows dependency resolution/compile을 따로 확인하고, 불가하면 macOS dependency로 한정하고 cookie host 인터페이스에 Windows 구현을 연결한다.
- BrowserDetection/BrowserCookieImportOrder/KeychainCacheStore의 비-macOS stub은 compile 성공 뒤 기능이 조용히 꺼질 수 있는 경로다. 지원 provider의 Windows capability가 false로 떨어지는 사례를 실패 fixture로 만든다.
- SQLite C modulemap/import library/runtime DLL, WAL lock·crash recovery, exe 상대 리소스, config/plugin approval 경로를 clean Windows/non-ASCII 사용자명에서 검사한다.

C ABI 단일 프로세스 설계와 별도 Swift backend + named-pipe 설계를 G1에서 비교한다. 기본안은 위의 C ABI이나, async 수명/패키징/크래시 격리 비용이 크면 UI→backend 요청·snapshot 구독을 버전 있는 named-pipe 계약으로 옮긴다. 후자도 코어 하나와 공유 캐시를 유지하고 사용자 ACL·메시지 크기·취소·재연결·버전 handshake를 검증한다. 기존 dashboard-v1 payload는 읽기 DTO 후보일 뿐 설정/계정/refresh 명령 API 전체를 대신하지 않는다. 비교 결과는 동일 기능 fixture, 전체 프로세스 메모리/CPU/시작시간/설치 크기로 결정하고 IPC가 무조건 무겁거나 DLL이 무조건 가볍다고 가정하지 않는다.

## 10. 아키텍처 검토 반영: G1의 결정 산출물

C ABI 선택 시 x64 calling convention, export symbol, ABI version/size, status/error code, UTF-8 buffer의 명시적 길이, Swift allocate/free 쌍을 고정한다. callback context 수명·재진입 규칙·cancel race·DLL unload 전 drain을 문서화하고 concurrent subscribe/cancel/shutdown stress를 수행한다. Swift trap은 동일 프로세스 UI도 종료시키므로 장애 격리가 필요하면 named-pipe backend를 선택한다. Swift runtime DLL 배포/업데이트 원자성도 실증한다. 1,000회 순차 호출 통과만으로 확정하지 않는다.

SQLite는 G1에서 pinned amalgamation 정적 링크와 pinned DLL/import-lib를 비교해 하나를 선택한다. 선택 결과에는 버전·라이선스·업데이트 방법·DLL 검색 경로·WAL 동시 app/CLI·한글 경로 증거를 남긴다.

Host 경계 후보: ProcessLauncher, ProcessTreeController, InteractiveTerminal, CredentialStore, BrowserProfileLocator, BrowserSecretDecryptor, SocketListener, ExecutableLocator, ApplicationDataPaths, WindowFocuser, PowerSignals, Notifier. 이는 생성 완료한 API가 아니라 실제 호출부를 묶을 책임 목록이다. 필요 없는 추상화는 만들지 않고 WinSDK 호출이 provider 파서 안으로 퍼지지 않도록 한다.

기본 데이터 경로 제안은 LOCALAPPDATA/CodexBar이며 portable config override를 보존한다. W02/W14의 APPDATA 표기는 Windows 사용자 데이터 경로 후보를 뜻한다. G1에서 최종 경로/마이그레이션/리소스 resolver를 확정하고 비밀 저장을 roaming에 의존시키지 않는다.

## 11. 계획 검토의 남은 작업과 실행 경계

현재 승인된 실행 범위는 분석 문서 수정이다. G1~G7 prototype도 아직 실행 승인이 없으며, 향후 구현 지시 후 시작한다. W01~W16의 본 구현 착수 조건은 해당 기능의 포크 기준 계약·의존성·실행 가능한 검증 계획 및 독립 필수 수정 종결이다. 전체 기능 계획이 OK라는 보고는 모든 기능과 전체 repo 검토 게이트가 통과한 후에만 한다.

다음 분석 담당은 영역별 원본 분석자(Core/providers, UI/runtime, CLI/integrations, build/dependencies)이며 통합 담당이 feature ID와 source coverage를 연결하고 별도 검토자가 판정한다. 산출물은 fork-parity 아래의 개별 기능 계약 ledger와 파일별 검토 ledger다. 기존 569행 각각에 entrypoint/settings/error/test/Windows adapter를 채우고 새 발견 기능은 새 ID로 추가한다. 74개 변경 파일은 직접 참조뿐 아니라 호출자·소비자·테스트에 대한 영향 연결을 남긴다. 미연결 entrypoint/설정/오류·미분류 tracked file·미해결 독립 필수 수정이 모두 0일 때 분석을 종결한다. 파일 수/후보 수 감소만으로 의미 검토를 통과시키지 않는다.

독립 검토 결과: 방향은 유효하나 실행 준비된 전체 이식 계획은 아직 NOT_OK. 경로 표기·프로세스 결정의 조건부 표현·실행 경계·다음 분석 산출물에 대한 지적을 반영했다. 나머지 전수 계약 검토는 미완료이며 이 개정본을 최종 승인으로 표시하지 않는다.

## 12. 사용자 실행 승인 및 검증 조건 변경 (2026-09-09)

사용자가 이 계획에 따른 구현을 명시적으로 승인했다. 앞선 분석 전용/착수 대기 문구는 현재 승인 범위를 제한하지 않는다. 기능 계약을 실제 구현과 함께 보강하며 진행한다. 다만 현재 macOS 환경에서는 실제 검증 없이 코드 비교만 수행하도록 요청했다. 따라서 빌드·테스트 실행·앱 실행·실계정·성능·원격 Windows 검증은 하지 않는다. 앞선 G1~G7 실행 실증은 향후 별도 검증 때의 체크리스트로 남기고, 현재는 해당 구현과 원본 계약의 정적 비교로만 판정한다. C ABI/프로세스 선택도 실측 확정으로 표현하지 않는다.

구현 및 반복 QA 상태는 IMPLEMENTATION-STATE.json에 기록한다. codexbar-windows-qa 루틴은 10분마다 구현을 이어가고, 구현 후보가 모두 갖춰지면 원본 고정 커밋과 Windows 코드의 전체 기능 비교 QA로 전환한다. 부족하면 다시 구현한다. 정적 비교 완료를 제품 실행/성능/실계정 동등성 증명으로 표현하지 않는다. commit/push/PR과 삭제는 이번 승인에 포함하지 않는다.
