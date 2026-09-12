# 원본 기능 전수 표면 감사와 계획 보완 결과 — 1차 기록

**후속 상태:** [2차 감사](SECONDARY-AUDIT-2026-09-12.ko.md)에서 추가 추적 결함을 발견하고 수정했다. 아래 6,943개/71개 schema 등은 1차 시점의 기록이다. 현재 계수와 조치는 2차 문서·SURFACE-AUDIT-SUMMARY를 따른다.

기준: fork에 보존된 원본 `928166f899471bbdcb72210641cdec91324d0154`. Windows 코드/이전 QA 기준은 `80f6b484b0388877a3cf5f886aa0ad850c59779c`다. 최신 upstream 기능을 섞지 않았다. 2026-09-12의 앞선 54개 기능군 계획을 재검토한 후 **72개 기능군**으로 보완했다.

## 판정

**고정 원본의 명시적 기능 표면을 목록화하고, 발견한 계획 누락·잘못된 연결·문서 해석 차이를 수정했다.** 원본 파일의 계획 책임 미분류는 0개이며, 69개 공급자의 모든 선언된 source mode, 설정 state 필드, CLI 옵션 선언, 메뉴 action 및 위젯/Hook 등록에 대응 계획을 연결했다.

이 판정은 **계획의 범위 추적성**에 대한 것이다. 모든 함수의 의미·모든 동적 경로를 형식적으로 검증했다는 인증, Windows 구현 성공, 무결함 보장이 아니다. 텍스트 자동 추출 후 중요한 누락과 경계는 소스를 읽어 재대조했다. `all_files_semantically_verified`를 true로 바꾸지 않았으며 자동 스캔을 독립 전문가 전수 리뷰라고 표현하지 않는다. 실행 검증은 하지 않았다.

## 확인 범위와 계수의 뜻

| 항목 | 확인 결과 | 해석 |
|---|---:|---|
| 원본 Git 항목 | 2,844 | 모두 blob과 계획 책임 분류; binary는 파일/소비 영역 분류 |
| 텍스트 파일 스캔 | 2,554 | 문서·코드·테스트·빌드 포함 |
| Sources 코드 파일 | 1,204 | Swift/C/H/TS/JS; 플랫폼 가드 포함 lexical scan |
| 필수 기능군 | 72 | 사용자 기능과 내부 지원/개발 도구 구분; 18개 세분화 항목 추가 |
| 공급자 ID | 69 | descriptor와 app-side 코드 연결 |
| provider×source mode | 163 | auto 포함, 앱/CLI 조건부 분기는 별도 하위 경로 |
| SettingsDefaultsState | 91 | 상태 필드 전부; UI 옵션 개수와는 다름 |
| CLI 옵션/인수 선언 | 169 | 명령별 중복 포함; 전역 help/version 별도 |
| 메뉴 action enum | 19 | enum 외 native action/selector/UI callback도 추가 추적 |
| UI 생성 지점 | 431 | 생성 코드 위치 수이며 독립 기능 수가 아님 |
| provider editor ID 선언 | 206 | field/toggle/action ID 후보; 동적 manifest 설정은 별도 schema |
| Hooks 이벤트 | 6 | 원본 stable raw value 전부 |
| 테스트 소스 | 1,052 | source symbol 참조 후보 연결; 실행하지 않음 |

자동 추출된 총 6,943개 의무 항목은 선언·사용처·분기·저장키가 중복되는 **코드 위치별 추적 단위**다. 제품 기능 수나 구현 완료율로 사용하지 않는다. source mode 개수를 API endpoint 개수로 오인하지 않는다. count는 SURFACE-AUDIT-SUMMARY JSON에 기록된다.

## 실제 누락·부정확성을 수정한 내역

| 발견 | 기존 계획의 문제 | 수정된 계획/근거 |
|---|---|---|
| Codex 시스템 계정 승격 | 일반 계정 전환으로 묶여 displaced live 계정 보존·repair·거부 조건이 불명확 | WIN-055. `CodexAccountPromotionPlanning/Preparation/Execution/Service`의 보존·충돌·실패를 별도 수락 조건으로 지정 |
| reset credit 만료 알림 | reset 사용/복구 알림만 명시하고 expiry notifier 누락 | WIN-058. `CodexResetCreditExpiryNotifier`의 3일 창, fingerprint, 최대64개 기억과 다중 계정 교대 |
| Buy Credits 창 | 일반 dashboard link로는 구매 flow·창 수명·로그인/결제 redirect를 대체하지 못함 | WIN-059. `OpenAICreditsPurchaseWindowController`를 Windows 인증/구매 host로 대응. 사용자 최종 결제 동작 유지 |
| 추가 quota 표시 | Claude routines/model weekly, Codex Spark 설정의 각각 기본값·필터 추적 부족 | WIN-060, 91개 state matrix. source snapshot과 화면 필터를 분리 |
| 로컬 프로젝트/모델 분석 | Core root의 indexer/thread catalog/sidecar/CSV 등이 기존 경로 목록에서 빠짐 | WIN-056/057. 내부 API와 실제 노출 UI를 구분해 이관 |
| Workspaces 출시 범위 과장 위험 | 이름만 보고 완성된 프로젝트 분석 창이 있다고 해석할 수 있음 | `CodexWorkspacesMenuAvailability`: DEBUG+환경변수에서만 켜지고 release는 false. `CodexWorkspacesNavigation`은 No data yet 빈 창. 원본 완성 UI로 세지 않음 |
| OpenCodex 집계 설명 차이 | docs/providers의 “항상 별도 행” 요약이 실제 코드와 다름 | WIN-061. `SpendDashboardSource+OpenCodex`의 preferredMergeIndex, provider별 mergeSnapshots, hide-native 설정 시 별도 Codex 행 규칙을 기준으로 계획 |
| 비용 source 과소 목록 | 설명 문서의 대표 목록만 사용하면 일부 provider 누락 | WIN-062. descriptor상 12개: Codex/OpenAI/Claude/Cursor/OpenCode Go/Antigravity/Vertex AI/OpenRouter/Mistral/Bedrock/Grok/xAI |
| DeepSeek/Groq/Doubao 등 추가 조회 | 문서 요약만으로 API-only로 축소할 위험 | provider matrix: DeepSeek platform web, Groq console web, Doubao arkcli와 configured credential 분기 필수 |
| Antigravity/Grok OAuth·local fallback | PTY/local probe만 이식하면 selected account와 token history 누락 | provider mode/operation ledger로 app/CLI/IDE/OAuth/offline 경로와 계정 불일치 정책 추적 |
| localStorage·cURL·브라우저 선택 로그인 | cookie adapter만 만들면 Devin/Factory/Windsurf/ZoomMate 등 기능 불충분 | WIN-063. login runner/router·localStorage·cURL·session refresh·permission retry를 별도화 |
| 공급자 native 설정·조직 | descriptor만 연결하고 app `ProviderImplementation/SettingsStore` 경로가 빠짐 | WIN-064. Kilo org·Copilot budget·z.ai team·Notion workspace·region/endpoint 등 206개 editor ID 후보 연결 |
| pipeline 부수 계약 | source 이름만으로 isAvailable/fallback/retry/optional completeness 불명확 | WIN-065. 원본 planner·isAvailable·shouldFallback·취소·선택 요청 대기 정책을 코드 위치로 연결 |
| Claude 복구 경로 | 단순 OAuth→CLI 순서로는 history fallback·owner CLI recovery·version recovery 보존 불가 | WIN-066, 해당 UsageStore와 Claude Core 경로 포함 |
| replay/진단/로그 | 앱 기능 표에 묻혀 CLI replay와 packaged resource smoke가 누락 가능 | WIN-067/068/071. replay options·hang watchdog·Windows log path·resource smoke·generated parser hash 이전 |
| 모든 설정과 잔류 상태 | SettingsDefaultsState 밖에 expiry/선택/배치/usage state 저장키가 있음 | WIN-069와 persistent_or_codable_key 추적. 응답 CodingKey와 persisted preference를 구분해 구현 |
| 공유 카드와 차트 | 첫 Share 패턴이 Providers/Shared까지 잘못 매칭됨 | WIN-027 근거를 실제 ShareStats 파일로 교체. WIN-070에 source hide/환율/partial overflow/redaction 추가 |
| 위젯/앱 entrypoint 예시 오류 | Switcher 예시에 BurnDown, 앱 시작 예시에 Scripts 경로가 나옴 | 실제 `CodexBarWidgetBundle`, `CodexbarApp.swift`로 수정. 스크립트는 검증·배포 지원으로 분리 |
| Sync 기능 확대/약화 위험 | Windows backend 대체 시 hooks/history/로컬 경로까지 동기화하거나 암호화를 약화할 수 있음 | WIN-072. portable subset·encrypted fleet·newer-schema pause·echo suppression·dirty state·삭제/offline 계약 유지 |

## 단계별 산출물과 책임

각 기능군에는 Windows 목적지와 수락 조건이 있고 각 source obligation에는 원본 commit/blob/path/line/symbol이 있다. 실제 구현 시에는 원본 코드에서 해당 줄의 전체 block과 호출부를 읽어 적용하고, Windows 구현 symbol·fixture·QA 결과를 동일 ID에 연결한다. 코드를 생성하거나 붙였다는 사실만으로 완료 처리하지 않는다.

| 산출물 | 역할 |
|---|---|
| `FEATURE-CONTRACTS-2026-09-12.ko.md` / JSON | 72개 기능군, 원본 노출 범위, Windows 목적지, 수락 기준 |
| `SETTINGS-COVERAGE-2026-09-12.ko.md` | 91개 state 필드, 초기화/default 근거, Windows 처리 |
| `CLI-COVERAGE-2026-09-12.ko.md` | command hierarchy/default, 169개 옵션, HTTP/replay 표면 |
| `PROVIDER-MATRIX-2026-09-12.ko.md` / coverage JSON | 69×source modes, cost capability, Core+app 코드 연결 |
| `SURFACE-OBLIGATIONS-2026-09-12.jsonl` | 선언·사용처·분기·callback·저장·플랫폼 guard별 하위 의무 |
| `FILE-COVERAGE-2026-09-12.tsv` | 모든 원본 항목의 계획 책임과 source coverage |
| `TEST-TRACEABILITY-2026-09-12.json` | 1,052개 테스트 소스와 원본 symbol 참조 후보; 통과 증거 아님 |
| `audit-tools/build_surface_audit.py`, `render_audit_tables.py`, `validate_audit.py` | Git 원본만 읽어 inventory/표를 재생성하는 문서 도구 |

## 플랫폼 판단이 필요한 항목의 처리

다음은 빠진 요구사항이 아니라 **실행해야 할 계획된 실현 가능성 게이트**다. 실제 Windows/API 실증 없이 가능/불가능으로 확정하지 않는다.

- G-BROWSER: 브라우저별 보호 상태·profile·허용된 import 경로·WebView2 별도 로그인·provider 계정 검증. 수동 입력만 지원하고 자동 import 완료라 하지 않는다.
- G-SYNC: 원본 CloudKit container/암호화 필드 접근과 Windows 독립 Sync/Fleet를 분리. 원본 iCloud 호환 실패를 Windows 간 동기화 기능 생략 이유로 삼지 않는다. 원본 서비스와 상호운용하지 않는 새 backend는 명시한다.
- G-HOST: 실제 Windows CLI/editor/browser 버전별 실행·focus·종료·설치 경로. 외부 CLI가 Windows에서 지원되지 않을 때 원격/API 대응을 조사하고, 검증 전 WSL을 필수 전제로 하지 않는다.
- G-SURFACE: Windows Widgets와 가변폭 표시 대체 UX의 OS 한계. 원본 정보·선택·동작이 접근 가능한 native 표면을 만든다.

이 게이트에 blocked 항목이 남아 있으면 해당 기능이나 전체 제품을 완료라고 보고하지 않는다. 원본 기능 자체가 Windows OS에서 불가능하다는 판정은 근거와 대체안 검토를 갖춰 사용자에게 제시해야 한다. 이번 감사에서 임의로 제외 승인한 기능은 없다.

## 재검증 방법과 한계

원본 Git blob 집합·feature/provider ID의 유일성·모든 source 경로 존재·91 state/163 mode/19 action/6 hook의 대응·CLI 선언의 owner type·문서 링크·generator 재실행 결정성을 검사한다. `git diff --check`는 문서 공백 검사다. 프로젝트 build/compiler/test/live account/CI는 실행하지 않는다.

조건부 컴파일과 주석/문자열을 고려한 lexical 추출이지만 Swift AST 실행이나 완전한 call graph는 아니다. 간접 생성 control·암묵적 runtime 계약에 대한 누락 부재를 수학적으로 증명하지 않는다. 이번 결과는 **원본에 명시된 기능 표면의 계획 책임 연결을 완료하고 확인된 누락을 종결한 것**이며, 향후 구현 중 발견된 원본 기능도 scope에 추가해야 한다. 검토 불가능성을 기능 제외나 “원본 기능 없음”으로 바꾸지 않는다.


검증 실행 기록: 위 문서 도구 3종을 실행했다. 원본 blob/경로/ID/선언 수 및 source excerpt의 줄 위치 검사는 통과했다. generator 두 번 실행 결과의 해시 일치와 `git diff --check`도 확인한다. 이 기록의 실행 대상은 Python 문서 검사기이며 Swift 빌드·테스트·앱이 아니다.
