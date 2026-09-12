# 원본 기능·코드와 Windows 전용 제품 가능성 분석 — 최초 조사 이력

후속 전수 표면 감사와 누락 수정은 [FULL-COVERAGE-AUDIT](FULL-COVERAGE-AUDIT-2026-09-12.ko.md)를 따른다. 아래의 54개 기능군/미연결 상태 설명은 최초 조사 당시 기록이다.

조사일: 2026-09-12. 원본은 fork에 보존된 `928166f899471bbdcb72210641cdec91324d0154` Git tree이며 최신 upstream으로 임의 교체하지 않았다. Windows 구현 대조는 `80f6b484b0388877a3cf5f886aa0ad850c59779c` 기준이다. 이번 목표는 계획 수정이며 실행 검증을 하지 않았다.

## 결론

공급자 HTTP 조회, 비용/사용량 계산, 계정 관리, 차트, 트레이, 알림, 세션, CLI, Hooks, QuickJS 플러그인 등은 Windows 전용 제품의 구현 대상으로 유지할 수 있다. 원본의 상당 부분이 재사용 후보지만 **실제 Windows 빌드와 69개 공급자의 모든 인증 경로가 검증된 상태는 아니다.** 원본 iCloud container·암호화 필드 접근, 브라우저 기존 세션 import, 일부 외부 CLI/terminal은 별도 실증 조건이다. 따라서 모든 기능의 무조건적인 구현 성공이나 일정은 확약할 수 없다.

## 원본을 실제로 추적한 방법

- `git ls-tree -r <baseline>`와 `git cat-file --batch`로 원본 2,844개 항목의 경로/blob/내용을 읽어 기계적 inventory를 생성했다. 컴파일러나 package manifest는 실행하지 않았다.
- `Providers.swift` enum의 69개 ID와 각각의 descriptor 선언을 연결했다. descriptor가 공유 디렉터리에 있는 경우 경로 목록은 겹칠 수 있다. ID 등록은 Windows support 인증이 아니다.
- 실제 앱 entrypoint/설정 pane와 binding, UsageStore/StatusItemController 분할 파일, CLIEntry dispatch, Codex/Claude descriptor, CloudSyncEngine의 container/encryptedValues 사용, WindowsMain과 웹 설정/import 연결을 선택적으로 읽었다.
- 원본 기능 설명은 `docs/ui.md`, `providers.md`, `configuration.md`, `cli.md`, `widgets.md`, `plugins.md`, `agent-sessions-design.md`, 아키텍처 문서 및 기존 Windows 계획/QA와 대조했다.
- 모든 함수·설정 키·소비자에 대한 의미 검토는 미완료다. inventory의 semantic_review가 PENDING인 이유다. 54개 기능군은 구현 계획을 세분화할 시작점이며 54개가 전체 기능 수라는 뜻이 아니다.

## 코드별 판단

| 실제 근거 | 발견한 기능/경계 | Windows 계획에 반영한 내용 |
|---|---|---|
| `Sources/CodexBarCore/Providers/Providers.swift`, 각 `*ProviderDescriptor.swift` | 69개 ID, source·credential·cost·pace·branding capability가 별도 | provider×source×account 계약을 필수화; ID 개수만으로 완료 금지 |
| `CodexProviderDescriptor.swift`, `ClaudeProviderDescriptor.swift` | Codex PAT는 외부 auth 파일, Claude token은 OAuth/admin API/web cookie로 routing | 인증을 하나의 토큰 입력으로 평준화하지 않고 원본 선택·소유권 유지 |
| `Sources/CodexBar/PreferencesView.swift` | general/iCloudSync/usageSpend/notifications/menuBar/menu/advanced/hooks/plugins/about/debug/provider pane | Windows 전체 설정 화면과 하위 binding 목록 작성 필요 |
| `PreferencesGeneralPane.swift`, `PreferencesAdvancedPane.swift` | 언어·통화·PII·storage footprint·CLI 설치·credential 접근 정책 | 단순 조회/트레이 외 기능도 필수. Mac bin symlink는 Windows PATH/alias로 대체 |
| `UsageStore+*`, `Providers/Codex/UsageStore+*` | cost catch-up, historical pace, plan utilization, reset credits, weekly reset 확인, hooks, plugin publication이 앱 계층에 존재 | Core만 남기고 앱 폴더를 삭제하면 기능 유실. 로직→runtime 추출 후 Mac UI 제거 |
| `StatusItemController+*` | overview, fleet, 계정별 표시, layout, 상세 actions, storage/cost cards, session focus | Win32 초안 메뉴만으로 대체 완료 불가. 실제 모든 action과 표시 조건 이전 |
| `Sources/CodexBarCLI/CLIEntry.swift` | usage/cards/cost/sessions list·focus/dashboard/serve/config/hooks/cache clear/cookie refresh/diagnose/guard/plugins | GUI 독립 CLI와 모든 옵션·출력·종료 계약 유지 |
| `LocalAgentSessionScanner.swift`, `PiFamilySessionScanner.swift`, `SessionWindowFocuser.swift` | 프로세스+cwd+제한된 metadata 탐색, pi/OMP dialect, OS focus | Windows 탐색 어댑터와 terminal별 focus 필요. 광범위 프로세스 환경 수집은 추가하지 않음 |
| `Sync/CloudSyncEngine.swift:389`, `:678`, `:980` | 원본 container 고정, encryptedValues에 secrets와 fleet payload 저장 | 일반 웹 DB 교체만으로 iCloud 동등성 주장 금지. Windows sync와 기존 iCloud 호환 계약 분리 |
| `Sources/CodexBarWidget`, `docs/widgets.md` | 6종 위젯; Switcher 공유 선택과 Usage 개별 선택이 다름 | Windows 위젯도 다중 인스턴스/선택 의미 보존; 69개 전부를 원본 widget 지원이라고 오인하지 않음 |
| `Sources/CQuickJS`, `Core/Plugins`, `PreferencesPluginsPane.swift` | 엔진 외에 승인·설정·비밀·HTTP authority·native 관리 필요 | QuickJS 빌드와 plugin 제품 완성을 구분 |
| 현재 `Package.swift:73`, `:276` | Windows executable은 있으나 Mac 제품/테스트/리소스도 같은 repo에 존재; SQLite 배포는 미확정 | Windows-only manifest/build/packaging로 정리하는 별도 단계 필요 |
| 현재 `WindowsMain.swift`, `WindowsUsageRuntime.swift`, QA193/200/204–206 | host callback·account/history·수동/Firefox web 조회·settings 부분 연결 | 재사용 가능한 후보. DOM history/credit events/cache/native 전체 UI는 미완료 |

## 파일 처리 인벤토리

SOURCE-AUDIT-SUMMARY JSON 및 SOURCE-INVENTORY TSV의 분류는 **경로 규칙에 따른 제안**이다.

| 제안 분류 | 항목 수 | 해석 |
|---|---:|---|
| Core/Adaptive/QuickJS/SQLite 재사용·적응 후보 | 716 | 실제 순수 함수/OS 호출 분리 검토 필요 |
| Mac host에서 기능 추출 후 폐기 후보 | 568 | 리소스·테스트 계약을 옮긴 뒤 활성 트리에서 제거 |
| CLI 계약 이전 | 40 | 현재 Windows 추가 파일은 원본 분모에 포함하지 않음 |
| Tests/Scripts 플랫폼별 검토 | 1,184 | 테스트를 버리지 않고 Windows fixture로 이관; 도구는 선별 |
| 원본 문서 참고 | 260 | Mac 사용/배포 문서는 Windows 사용자 안내로 교체 |
| 나머지 build/resource/license 검토 | 76 | 생성물·아이콘·라이선스·metadata 개별 판단 |

Apple 계열 import 신호가 있는 Swift 파일은 443개다. 조건부 가드와 OS 비의존 로직을 함께 담은 파일도 포함하므로 “443개 삭제” 또는 “443개 컴파일 오류”로 해석하면 안 된다.

## 공식 자료로 확인한 플랫폼 경계

아래는 2026-09-12 확인한 공식 자료다. 이 자료는 플랫폼 능력의 근거이며 현재 프로젝트 성공의 증거는 아니다.

- Swift는 Windows 설치와 개발을 지원한다. 따라서 Swift 확장자 자체는 Mac 의존성이 아니다. 프로젝트 패키지들의 실제 호환성과 런타임 배포는 별도 검증한다. [Swift Windows 설치](https://www.swift.org/install/windows/), [Windows 도구체인 요구사항](https://www.swift.org/install/windows/manual/).
- Windows Widgets는 provider가 host 요청에 JSON template/data를 제공하는 방식이다. 원본 SwiftUI 위젯 코드를 그대로 실행할 수는 없지만 데이터·선택·차트 기능은 재구현 후보다. 등록·패키지·지원 build를 실증한다. [Microsoft Widgets providers](https://learn.microsoft.com/en-us/windows/apps/develop/widgets/widget-providers).
- Chrome의 Windows 쿠키는 App-Bound Encryption 보호를 사용할 수 있고, Edge도 관련 정책을 제공한다. 일반적인 DPAPI 처리만 추가하면 모든 프로필 import가 된다는 계획은 부정확하다. 보안 정책 해제를 지원 전제로 삼지 않는다. [Chrome 공식 설명](https://security.googleblog.com/2024/07/improving-security-of-chrome-cookies-on.html), [Edge 정책](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/applicationboundencryptionenabled).
- WebView2는 앱이 관리하는 user data folder에 데이터를 저장한다. 기존 브라우저 세션을 공유한다고 가정하지 않는다. 별도 로그인 경로의 provider 호환성은 확인해야 한다. [Microsoft WebView2 user data](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/user-data-folder).
- CloudKit JS는 기존 CloudKit 앱과 web services 활성화를 요구한다. 원본 container 권한과 private encryptedValues 상호운용이 자동 확보된다는 근거는 없다. [Apple CloudKit JS](https://developer.apple.com/documentation/cloudkitjs), [인증·요청 구성](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html).

## 계획을 바꾼 이유

이전 계획의 macOS/Linux 유지 의무를 제거했다. 대신 원본을 고정한 기능 계약과 비교 fixture를 보존한다. Windows UI/배포/인증/저장 수명주기를 제품 중심으로 명시했고, 작업 단계마다 삭제 가능한 Mac 코드와 아직 기능 추출이 필요한 코드를 구분한다. Windows에서 가능한 기능은 모두 필수로 두되 외부 서비스 접근 미확정을 불가능 또는 완료로 덮지 않는다.
