# Windows 전용 CodexBar 구현 계획 — 2026-09-12 개정

**현재 실행 지시:** 사용자가 구현을 승인했다. 이 macOS 로컬에서는 구현만 하고 검증은 실행하지 않는다. 30분마다 보고하고 계속하는 heartbeat를 설정했다. 사용자는 매 구현 묶음의 commit/push도 승인했다. 현재 origin(main)은 datell1357/codexbar-window이며 강제 푸시 없이 게시하고 결과를 보고한다. 과거의 commit/push 금지 문구는 당시 작업 범위 기록으로만 해석한다. 진행은 [구현 로그](IMPLEMENTATION-LOG.ko.md)에 기록한다. 아래의 분석 전용 문구는 계획 작성 당시의 이력이며 이번 구현 승인을 제한하지 않는다.

상태: SOURCE_SCOPE_TERTIARY_REVIEWED / 구현·실행 검증 미완료. 1·2·3차에서 지정한 추출 범주·등록·동적 연결을 대조하고 발견한 계획/추적 결함을 보완했다. 전체 코드 의미 검증 또는 모든 암묵적 기능의 누락 부재를 뜻하지 않는다. 기준 원본 `928166f899471bbdcb72210641cdec91324d0154`, 조사한 Windows HEAD `80f6b484b0388877a3cf5f886aa0ad850c59779c`.

이 문서가 현재 계획이다. [9월 9일 계획](WINDOWS-PORT-PLAN-2026-09-09.archived.ko.md)은 이력으로 보존하며, macOS/Linux 제품 유지와 원본 코드 보존 자체를 목표로 삼았던 정책은 대체한다. 기존 QA의 좁은 범위 승인 기록은 유효한 참고 증거지만 새 제품 완료를 뜻하지 않는다.

## 1. 제품 목표와 필수 원칙

**Mac 원본에서 제공하는 기능 중 Windows에서 구현 가능한 기능을 모두 제공하는 Windows 전용 프로그램을 만든다.** 어려움·미구현·시간 부족을 OS 불가능으로 분류하지 않는다. 핵심 공급자만 제공하는 MVP로 완료 범위를 축소하지 않는다.

- Windows 설치·실행·업데이트에 Mac, Xcode, WSL, 사용자가 설치하는 Swift 개발 도구를 요구하지 않는다. 필요한 런타임은 배포물이 책임진다.
- Mac 화면의 픽셀 복제가 아닌 기능·계정 의미·설정·오류 복구·자동화 계약의 동등성이 목표다. 메뉴바 기능은 Windows 트레이/팝업/상시 표시 패널로 제공한다.
- Windows 배포물과 최종 활성 빌드 그래프에서 AppKit, SwiftUI, WidgetKit, Keychain, Sparkle, Mac helpers·entitlements·appcast·Homebrew 패키징을 제거한다.
- Swift는 OS가 아닌 구현 언어다. 기존 계산·파서·QuickJS host를 Windows에서 사용하는 것은 가능하다. **이번 개정은 전체 언어 재작성 승인이 아니며, Swift 공용 로직은 Windows 검증 조건부로 재사용한다.** 언어 파일 확장자를 이유로 기능을 버리지 않는다.
- Mac 소스는 기능 추출이 끝날 때까지 비교 자료다. 의존 소비자·리소스·테스트 이전이 끝난 단위만 활성 트리에서 제거한다. Git 원본 이력과 라이선스는 보존한다. 이번 작업에서는 제품 소스를 삭제하지 않았다.
- 사용자 목표의 “완벽”은 아래의 추적 가능한 완료 조건으로 다룬다. 무결함·미래 서비스 변경에도 영구 동작을 보장한다고 표현하지 않는다.

## 2. 전수 기능 표면 감사와 계획 책임 확정

[3차 검토·조치](TERTIARY-AUDIT-2026-09-12.ko.md)와 [입력/예상 결과 계약](BEHAVIOR-CONTRACTS-2026-09-12.ko.md)을 추가했다. [1차 감사 결과](FULL-COVERAGE-AUDIT-2026-09-12.ko.md)와 [추가 감사·조치](SECONDARY-AUDIT-2026-09-12.ko.md)가 판정 근거다. 추가 감사에서 mode 역참조, plugin optional/generic, 확장 JSON, alias 배열, runtime hook 추적을 보완했다. 최초 [소스 분석](SOURCE-ANALYSIS-2026-09-12.ko.md)은 이력으로 보존한다.

원본 2,844개 Git 항목을 분류했고 Sources 코드 1,204개를 포함한 텍스트 2,554개를 스캔했다. 69개 공급자의 163개 source mode, 91개 SettingsDefaultsState 필드, 169개 CLI 옵션/인수 선언, 19개 메뉴 action, 6개 Hook 이벤트 및 위젯/플러그인/런타임/플랫폼 경로를 추적했다. 기존 54개 기능군은 **72개**로 보완했다. 파일의 계획 책임 미분류는 0개다.

상세 계약은 [기능군](FEATURE-CONTRACTS-2026-09-12.ko.md), [설정](SETTINGS-COVERAGE-2026-09-12.ko.md), [CLI](CLI-COVERAGE-2026-09-12.ko.md), [공급자](PROVIDER-MATRIX-2026-09-12.ko.md), `SURFACE-OBLIGATIONS-2026-09-12.jsonl` 및 `FILE-COVERAGE-2026-09-12.tsv`에 있다. 각 source obligation은 원본 blob/line, Windows 목적지, 수락 조건을 갖는다. 테스트 소스 1,052개의 참조 후보는 `TEST-TRACEABILITY-2026-09-12.json`에 연결했다.

범위 연결 완료를 모든 함수의 의미 검토/Windows 실행 성공으로 표현하지 않는다. 8,563개 source 의무 항목은 사용처/선언/분기의 중복을 포함하므로 기능 수나 완성률 분모가 아니다. 간접 생성/암묵적 경로가 구현 중 발견되면 같은 규칙으로 추가한다. 기존 569개 후보 ledger는 checkout에 없지만 이번 감사는 그 목록에 의존하지 않고 고정 원본에서 다시 추출했다. 향후 확보하면 historical crosswalk 자료로 사용한다.

## 3. 기술 구조 결정

계획 기본안은 **Windows 네이티브 UI + Windows용 Swift Core/Runtime + QuickJS**다. 기존 Win32 트레이는 유지·보강하고, 전체 설정/대시보드는 C# WinUI 3 프런트엔드를 기본안으로 둔다. 언어 재작성 비용보다 이미 축적된 도메인 계약 보존을 우선한다. WinUI 의존성 추가와 구현은 후속 작업이며 현재 설치하지 않는다.

공용 코어의 Windows 실증 실패가 지속될 경우에만 해당 모듈의 C#/Rust 대체를 비교한다. 대체 시 원본 fixture와 저장 schema·CLI·plugin 계약을 통과시켜야 하며 전체 재작성으로 조용히 범위를 바꾸지 않는다.

### 책임과 계획 디렉터리

기능별 세부 목적지는 FEATURE-CONTRACTS의 windows_destination이다. source obligation ID별로 Windows 파일/symbol·fixture·검증 결과를 작성하며, 기존 구현 코드는 QA의 실제 범위만 연결한다.

| 계층 | 책임 | 현재 근거 / 계획 목적지 |
|---|---|---|
| Windows host | 단일 인스턴스, 트레이, 메시지 루프, 전력, 알림, 종료 | `Sources/CodexBarWindows` 유지 후 host/runtime 분리 |
| Domain/Core | 공급자·계정 소유권·quota·cost·history·plugin·sync 모델 | `Sources/CodexBarCore`, `AdaptiveRefreshCore` |
| Windows runtime | Settings/UsageStore에 남은 상태·스케줄·계정·비용·hooks 연결 | 계획 `Sources/CodexBarRuntime` |
| Native UI | 설정, 계정, 상세 팝업, 차트, 진단, 접근성 | 계획 `Windows/App` |
| Widgets host | 6종 위젯, 선택/다중 인스턴스/갱신 | 계획 `Windows/Widgets` |
| 인증 helper | 필요한 동안만 WebView2, 로그인 취소·계정 분리 | 계획 `Windows/AuthHost` |
| CLI | 원본 명령·출력·종료 계약, GUI 없이 실행 | `Sources/CodexBarCLI` |
| 배포·검증 | MSIX/설치, 업데이트, fixtures, Windows 테스트 | 계획 `Windows/Packaging`, `TestsWindows` |

UI↔backend는 사용자 ACL이 제한된 **버전 있는 named pipe**를 계획 기본안으로 정한다. 기존 Swift 트레이/backend 프로세스 하나가 코어·스케줄러·캐시를 소유하고, 창은 필요할 때 시작한다. 직접 Swift 객체를 C#에 노출하지 않는다. G1에서 시작 시간·배포 비용을 확인한다. C ABI는 그 결과가 부적합할 때 검토할 대안이며 동시 구현하지 않는다.

IPC 계약: protocolVersion, requestID, generation, method, payload, structured error; 크기·동시 요청 상한, handshake, 사용자 확인, 취소·재연결·역순 응답 처리, 종료 drain. 화면 snapshot에는 비밀 원문을 싣지 않는다. 비밀 교체 요청은 로그/진단에서 배제하고 저장 결과만 반환한다. 창을 닫아도 backend가 중복 생성되지 않게 한다. Widgets는 비밀 없는 원자적 snapshot을 읽는다. CLI는 독립 실행을 유지하며 앱과 계정별 저장 lock을 공유한다.

기본 저장 위치는 LOCALAPPDATA/CodexBar. 일반 설정·캐시·이력·로그를 구분하고 앱 소유 비밀은 Credential Manager 또는 사용자 DPAPI 보호 파일로 분리한다. 기존 config의 평문 비밀은 버전 migration으로 이전하며 실패 시 기존 데이터 보존, 성공 확인 후 명시된 정리 절차를 적용한다. 외부 CLI 소유 auth 파일은 그 도구의 계약을 따르고 앱 마음대로 형식을 바꾸지 않는다.

## 4. 기능 범위: 모두 필수

W01~W16은 작업 묶음이다. 세부 수락 항목은 FEATURE-CONTRACTS의 ID를 기준으로 분할한다. 원본에서 지원하지 않는 provider×기능 조합을 새 요구로 만들어 부풀리지 않는다. 반대로 원본이 지원하는 조합은 조용히 생략하지 않는다.

| ID | 필수 결과 | 작업·수락 조건 |
|---|---|---|
| W01 | 69개 공급자 전부 | provider×source×account×org/region×outcome 행. API/OAuth/CLI/RPC/PTY/web/local의 설정 노출·선택·fallback·버전·오류까지 대응 |
| W02 | 계정 추가/수정/삭제/선택/동시 표시/재인증 | Codex managed/system/profile/workspace/PAT, Claude swap, token 계정, 외부 credential 소유권, 계정별 cache/history 격리 |
| W03 | 트레이·Overview·상세·표시 레이아웃 | 개별/통합, 최고 사용량, quota 선택, 두 줄/token/조건식/override, reorder, shortcut, 계정/플랜/status/credits/details·actions |
| W04 | 모든 설정과 Windows 기본 UX | general/providers/display/menu/notifications/advanced/hooks/plugins/sync/about/debug/spend, 검색·언어·통화·PII·저장·migration |
| W05 | 사용량·예측·리셋 | raw/표시 quota 구분, 0/nil/stale, 학습 이력·workday·ETA·신뢰도·소유권·authorized backfill, reset credit 확인·사용·만료 알림, routines/model weekly/Spark 필터, 프로젝트/모델 내부 분석 API |
| W06 | 원본이 제공하는 비용·스토리지 조회 | descriptor의 12개 cost capability와 OpenCodex/Pi/OMP를 포함한 모든 원본 cost source, 증분·회전·중복·fan-out·가격·통화·시간대·재시작·catch-up·저장 용량 |
| W07 | Usage & Spend + 웹 quota 대시보드 | 서로 다른 데이터 모델 유지; 기간/모델/프로젝트/세션/heatmap/비교/coverage/공유/내보내기, web enrichment/크레딧/이력, Buy Credits 사용자 결제 창, Share Stats 카드 |
| W08 | 전체 refresh 정책 | manual/fixed/adaptive/agent-aware, opt-in scanner, menu wake, reset boundary, 저전력·절전 복귀·취소·중복·startup retry |
| W09 | 상태·quota·예측 알림과 celebration | source/account/reset-cycle별 중복 억제, sound/overlay/Windows 알림, click/설정/언어/권한·집중 모드/실패 정책 |
| W10 | 6종 위젯 | Switcher/Usage/History/Metric/Burn Down/Combined, 일반 provider 17개·BurnDown 2개 선택 범위·공유 선택/독립 인스턴스·stale/empty·snapshot |
| W11 | 세션 탐색·상태·focus·원격 | Codex/Claude/pi/OMP, PID 생명주기, metadata budget/privacy, terminal/editor별 focus, SSH/Tailscale v2→v1 협상·Windows peer 탐색·상대 OS별 실행 adapter |
| W12 | CLI/HTTP 전체 | usage/cards/cost/dashboard/serve/sessions/guard/config/cache/cookie/hooks/plugins/diagnose와 모든 하위 옵션·JSON/TOON/text/exit·Host/Bearer·cancel |
| W13 | Hooks 전체 | 이벤트 발생→규칙→조건→실행→결과, stdin JSON/env/timeout/process tree, 기본 shell 없는 실행, PowerShell/cmd/선택 WSL 구분 |
| W14 | Plugins 전체 | JS/TS 설치·검증·승인·설정·재승인·갱신·재검색·비활성·삭제, QuickJS 제한·HTTP/secret/cookie·generic UI·CLI 정책 |
| W15 | 동기화·fleet 사용자 기능 | opt-in 설정·선택 비밀·장치/계정 snapshot, schema·충돌·삭제·offline·장치 해제; 원본 iCloud 상호운용은 별도 조건부 계약 |
| W16 | Windows 제품 운영 | 설치·자동 시작·CLI PATH·stable/beta·서명·업데이트·실패 복구·삭제·진단·라이선스·DPI/키보드/screenreader |

## 5. Windows 가능성 판정과 예외 규칙

판정은 REQUIRED_PORT / REQUIRED_WINDOWS_EQUIVALENT / EXTERNAL_DEPENDENCY_UNRESOLVED / PROVEN_OS_ONLY로 구분한다. UNRESOLVED는 미완료이며 분모에서 빼지 않는다. PROVEN_OS_ONLY에는 원본 동작, 공식 플랫폼 근거, 검토한 대안, 사용자 가치 보존 여부를 반드시 남긴다. 예외·대체 UX는 사용자 결정 전까지 승인된 것으로 표시하지 않는다.

- **메뉴바/위젯:** 원본 기능은 Windows에서 구현할 수 있는 UI 기능이다. 트레이에 가변폭 텍스트를 억지로 삽입하지 않고 상세 팝업·고정 패널에서 전체 token layout을 제공한다. Windows Widgets API로 6종을 구현한다. OS가 허용하는 크기·갱신 주기는 실제 검증하고 동등 UX 결정 기록을 남긴다.
- **브라우저 인증:** Chrome/Edge 자동 import는 App-Bound Encryption 및 세션 바인딩에 따라 제약될 수 있다. 보호 해제·관리자 권한 요구·브라우저 보안 우회를 제품 전제로 삼지 않는다. 지원되는 API/OAuth/device login, 앱 소유 WebView2 로그인, 허용된 profile import를 provider별로 평가한다. WebView2는 기존 Edge 로그인과 별도 저장소다. 수동 쿠키만 제공하고 자동 import 완료라고 표시하지 않는다. 대체 로그인 성공과 기존 브라우저 세션 가져오기 성공은 별도 계약이다.
- **Sync/Fleet:** Windows 장치 간 설정·snapshot 동기화 기능은 구현 대상으로 유지한다. 기본 조사안은 앱 소유 서비스/사용자 지정 endpoint와 명시적 장치 pairing 및 종단간 비밀 보호다. 서버 운영·인증·비용·키 복구 정책은 D03 결정 사항이며 이번에 서비스 개설하지 않는다. 파일 동기화만으로 실시간 fleet 완료라 하지 않는다.
- **기존 iCloud 연동:** 원본 `iCloud.com.steipete.codexbar` private DB와 `encryptedValues`를 사용한다. CloudKit 웹 API가 있다는 사실만으로 같은 container나 암호화 필드 접근이 되는 것은 아니다. container 권한·web services·사용자 auth·암호화 의미를 확인한다. 새 backend가 동기화 가치를 제공하더라도 원본 iCloud 데이터와 상호운용 완료를 주장하지 않는다.
- **Mac 도구/OS 표현:** Safari 자동 가져오기, Mac terminal focus, AppKit/WidgetKit·Keychain·Sparkle 구현 자체는 Windows에 그대로 제공할 대상이 아니다. 해당 사용자 기능은 Windows 브라우저·터미널·저장·알림·업데이트 대응으로 남긴다. 서비스가 Windows용 로컬 앱을 제공하지 않으면 원격/API 가능성을 먼저 조사한다.

## 6. 실행 순서와 산출물

| 단계 | 선행 조건 | 작업 | 완료 산출물 |
|---|---|---|---|
| P0 원본 기능 표면 대조 | 지정한 1·2·3차 범주 대조 완료; 전체 의미 인증 아님 | 72개 기능군·69/163 provider mode·91 state·169 CLI 옵션과 source obligations 연결. 구현 중 새 발견은 하위 ID 추가 | FULL-COVERAGE-AUDIT 및 파일 책임 미분류 0; 실행 미완료 상태 보존 |
| P1 Windows 실행 기반 | 검증 허용 시 시작 | Windows Core/CLI/QuickJS/SQLite/Crypto/Commander 빌드, 설치 fixture, tray→fetch→UI→cancel→exit, IPC·WinUI 연결 | 재현 가능한 Windows 빌드/설치·실행 로그; 의존성 버전/배포 manifest |
| P2 런타임·인증·저장 | P0 관련 계약, P1 | Mac UsageStore/SettingsStore의 도메인 로직 추출, Windows 계정/lock/atomic write/credential migration, login와 ConPTY | 계정 혼선·취소·경합·복구 fixture 통과 |
| P3 모든 공급자와 비용 | P2 | 69 provider×source 계약, 모든 cost/local source·plugin·CLI/hook 연결 | 행별 Windows 구현/정적 QA/fixture/실계정 증거 |
| P4 모든 UI·위젯·세션·Sync | P2, 관련 P3 데이터 | 설정·트레이·전체 대시보드·접근성·위젯·원격·sync 구현 | UI action과 저장·조회 양방향 증거, 확정된 외부 제약 |
| P5 Windows 전용 정리 | 이전할 각 기능 증거 | Mac 제품 target/import/resource/helpers/scripts 제거, 테스트 이동, README·installer 재작성 | Windows-only build graph·package allowlist, 보존된 원본 비교 이력 |
| P6 정식 배포 판정 | 모든 필수 항목 | clean Windows·회귀·장시간·성능·보안 경계·업데이트/복구/삭제 | release checklist와 artifact hashes, 미완료 필수 0 |

P0에서 확인한 누락을 위 추적표에 반영했다. P1에서 발견한 위험을 뒤 단계까지 숨기지 않는다. 순서는 검증 가능한 작업 순서이지 기능 축소가 아니다. 실행 검증이 금지된 동안에는 P0와 정적 구현만 가능하며 P1 통과나 배포 가능 판정을 내리지 않는다.

현재 사용자는 **분석과 계획 수정**을 요청했다. 이번 변경은 문서·추적 자료이며 빌드/컴파일러/테스트/앱/실계정/원격 Windows 실행이나 CI 활성화, commit/push를 하지 않는다. 과거 자동화의 10분 간격은 이력이며 이번 계획을 실행하는 자동화를 새로 만들지 않는다.

## 7. 검증·배포 완료 게이트

- G0 범위: 69개 ID 포함, 모든 source/account/settings/action 계약 연결, 원본 기능 미분류 0. 파일 수만으로 통과하지 않는다.
- G1 도구체인: Windows에서 Core/CLI/host/UI/QuickJS/SQLite 및 런타임 배포 성공. macOS build 성공은 대체 증거가 아니다.
- G2 OS: 한글·공백·긴 경로, quoting, 자식/손자 종료, stdout/stderr 포화, ConPTY, Winsock, sleep/resume, multi-monitor/DPI, 비관리자 계정.
- G3 데이터·인증: 0/nil/초과/stale, DST/timezone, 계정 교체 중 응답, 만료/거부/429/timeout/cancel, atomic save·crash·회전, 평문 노출·로그 redaction, plugin 승인 경계.
- G4 제품: 모든 native 설정 저장/복원, UI→runtime→저장→재실행, 6종 위젯, 원격 focus, 동기화 충돌·삭제·offline·키 복구, 접근성/현지화.
- G5 운영: 개발 도구 없는 clean Windows에서 설치·실행·CLI PATH·자동 시작·signed update·중단/rollback·uninstall. 외부 데이터 삭제는 제품에서 사용자 선택으로 구분한다.
- G6 부하: 원본 100MiB/0.5% CPU/200ms 목표는 미측정 목표로 유지. 전체 프로세스 합계·3개 활성/69개 활성 구분, 8시간 이력·절전 복귀·대형 비용 로그·인증 창 종료 후 잔류를 측정한다. 기능 삭제로 목표를 맞추지 않는다.

Windows 11 x64를 첫 검증 대상으로 잡는다. 지원 최소 OS/build와 ARM64는 D01에서 명시적으로 확정하고 검증 전 지원을 주장하지 않는다. 테스트 코드는 기능 회귀 fixture를 이관한다. Mac-only tests가 제외됐다는 이유로 그 테스트가 지키던 기능까지 삭제하지 않는다.

FULL_WINDOWS_PRODUCT = G0~G6 통과 + Windows에서 가능한 필수 기능 전부 구현 + unresolved 항목의 근거/결정 종결 + 패키지에 Mac 의존 없음. 제한적 preview는 full completion과 다르며 최종 목표를 대신하지 않는다.

## 8. 진행률과 결정 대장

상태 축을 분리한다: contract / implementation / static_review / windows_fixture / live_integration / release. 좁은 QA APPROVE를 implementation 또는 release 완료로 자동 승격하지 않는다. 기능 분모 확정 전 백분율을 발표하지 않는다. 확정 후에도 각 축의 완료 수와 제외 근거를 별도로 표시한다.

| 결정 | 기본안 | 확정에 필요한 증거 |
|---|---|---|
| D01 지원 환경 | Windows 11 x64 우선 | 최소 build·ARM64·Widgets/SDK 조건 및 clean install 결과 |
| D02 UI/코어 연결 | WinUI 3 + Swift backend named pipe | toolchain, lifecycle, IPC 보안, 시작/메모리·패키징 G1 |
| D03 Sync/Fleet | Windows 독립 sync backend, iCloud 호환 별도 | 운영 주체/인증/비용/암호화·복구 및 CloudKit 권한 확인 |
| D04 browser login | provider별 허용된 자동 import 또는 별도 앱 로그인 | 브라우저 버전·보호 상태·provider auth 성공/실패, 대체 UX 결정 |
| D05 배포 | 서명 MSIX를 우선 평가 | Widgets identity, CLI alias/startup/update 제한; 필요 시 EXE + identity 대안 |
| D06 OS 표현 | tray + popup + 선택적 상시 패널, native Widgets | 원본 표시/action 모두 접근 가능, 키보드/DPI 및 사용자 동등 UX 판단 |

다음 구현은 source obligation을 작업 ID로 사용해 기존 Windows 코드/QA206의 충족 범위와 미완료 web history/auth/cache를 연결하는 것이다. 원본 표면을 다시 후보 목록부터 만드는 작업은 반복하지 않는다. Windows 실행 검증을 시작할 수 있을 때는 전체 코드 작성 완료를 기다리지 않고 P1부터 진행한다.

## 9. 전수 감사에서 추가로 고정한 구현 규칙

2차 상세 조건 SA-01~09는 [추가 감사 문서](SECONDARY-AUDIT-2026-09-12.ko.md)를 따른다. 기능군 72개는 유지하며 기존 계약의 누락을 보완했다.

- WIN-055~072의 18개 세분화 계약은 기존 W01~W16에 포함되는 필수 작업이다. 시스템 계정 승격 보존, 만료 알림, 구매 창, 추가 quota, OpenCodex 집계, 공급자 login/editor, 복구, replay/진단, 리소스와 Sync 제외 필드를 생략하지 않는다.
- 원본 `CodexWorkspacesMenuAvailability`는 DEBUG+환경변수에서만 켜지고 release는 false이며 창은 빈 shell이다. 내부 indexer/model/CSV API는 보존 대상으로 추적하되 이미 완성된 원본 출시 UI로 집계하지 않는다. 새 완성형 Workspaces 화면은 기존 기능 이식과 구분한다.
- CLI source의 `api/cli/web`는 transport와 같지 않다. 예를 들어 로컬 파일 조회가 cli 모드에 노출될 수 있다. 등록된 모드·실제 planner·app/CLI·선택 계정 분기를 함께 유지한다.
- 설정 비밀을 Windows 보호 저장소로 옮길 때 config schema/CLI dump·set-api-key·환경변수·plugin secret lookup을 깨뜨리지 않는다. `config dump --show-secrets` 같은 명시적 조회 계약은 별도 처리하고 기본 dump/로그/UI snapshot은 redaction을 유지한다.
- 로그는 Windows 사용자 데이터 경로로 옮기며 file logging·레벨·JSON stderr·크기 제한·redaction을 보존한다. packaged resource smoke는 개발 checkout을 사용할 수 없는 환경에서도 실행되도록 Windows에 대응한다. source fixture가 있는 Mac-only 테스트를 build exclusion만으로 지우지 않는다.
- docs/providers 같은 요약과 고정 소스가 다르면 원본 소스·호출부·테스트를 기준으로 판단하고 차이를 감사 기록에 남긴다. 새 provider/server 지원을 임의로 추측하거나 보호된 인증 경로를 우회하지 않는다.

## 10. 이차 감사에서 고정한 동적 계약과 판정

- provider ID, Core bootstrap, app implementation bootstrap의 69개 연결을 보존한다. 각 provider JSON은 자기 source mode 의무를 모두 역참조하고, 공유 폴더의 다른 provider 모드를 포함하지 않는다.
- plugin `?`는 응답 값 생략 가능성을 뜻한다. 해당 값이 있을 때의 기능까지 선택 구현으로 취급하지 않는다. generic HTTP/cache/JWT 메서드·costUsage·재생량·만료시각·identity-only 반환을 그대로 지원한다.
- `ctx.date.nowMillis()`는 원본 runtime에 있고 d.ts에는 없다. Windows 배포용 선언을 runtime과 일치시키는 작업을 포함한다. 현재 원본 코드가 수정됐거나 검증됐다고 보고하지 않는다.
- provider extension JSON은 고정 UI 필드 외의 unknown non-null 값도 보존한다. 14개 typed key·nil 제거·정수/실수 타입·null/충돌 처리를 fixture로 검증한다. `.secretWorkspace` binding의 비밀 로그 정책도 유지한다.
- 환경변수는 별칭 배열의 순서·상징 상수·소문자 지원·account injection/scrub까지 계약이다. Windows 환경의 casing 충돌/동시에 여러 alias/endpoint override 상황을 포함한다.
- provider의 settings observation, typed snapshot provider-ID/type 검사, protocol defaults, login capability, start/stop/failure/recovery callback을 runtime에 연결한다. 특히 Augment keepalive와 forceSessionRefresh를 macOS guard 제거만으로 완료하지 않는다.
- OpenRouter management-auth 예외는 원본의 first-party ID·secure key·GET·HTTPS·정확한 host/path·port/userinfo/fragment 거부 조건을 지킨다. authoring API 정리 중 일반 user plugin 권한으로 확대하지 않는다.
- 파일 책임 미분류 0은 파일 분류 결과다. 전수 기능 의미 검증 완료 boolean은 두지 않는다. 추출 범주 검사 통과, 원본 불일치, 구현 상태, Windows 실행 상태를 별도로 기록한다.

## 11. 3차 검토로 고정한 행동 및 OS 적응

[3차 검토](TERTIARY-AUDIT-2026-09-12.ko.md)와 BC-001~025를 P1~P4의 필수 fixture 입력으로 사용한다. 단순 source/옵션/선택 control 존재만으로 완료하지 않는다.

- 일반 위젯의 원본 선택지 17개, BurnDown provider 2개/window 2개, Metric 3개와 원본 정보 밀도에 대응한다.
- 원격 peer의 OS와 원격 shell/CLI 실행 경로를 보존·설정한다. Windows peer를 제외하거나 Windows remote에 `sh -lc`를 실행하는 구조로 완료하지 않는다. 데이터 프로토콜 v2/v1과 transport OS 선택은 분리한다.
- TOON은 usage 전용, guard의 blocked/unknown/invalid와 fail-open을 구분한다. 원본 출력 형식·종료 코드를 Windows 관행으로 임의 통합하지 않는다.
- 설정의 새 설치/이전 설치/잘못된 값·기존 값과 동의 상태를 구분한다. 초기화 함수 호출 위치만 연결하고 기본값 검증 완료라 하지 않는다.
- 화면 데이터, Spend export DTO, dashboard-v1 및 내부 CSV API의 범위를 분리한다. 기존 export에 없는 필드를 추가하려면 schema 확장으로 명시하며 원본 이식 완료의 근거로 소급하지 않는다.
