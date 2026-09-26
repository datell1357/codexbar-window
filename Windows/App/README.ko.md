# Windows 네이티브 앱

상태: **CODE_WRITTEN_UNVERIFIED**. IMPL-598은 WinUI 3 초기 화면과 기존 Windows 트레이
런타임 사이의 통신 경로를 작성한 단계다. 복원·빌드·테스트·실행·패키징은 수행하지 않았다.
전체 W03/W04/W07 기능 완료나 배포 가능한 설치 파일을 의미하지 않는다.

## 작성한 화면과 동작

- 트레이의 “CodexBar 열기”가 앱 창을 연다. 이미 실행 중이면 다음 응답의 activation 값으로
  기존 창의 활성화를 요청한다. 창을 닫으면 트레이는 계속 실행한다.
- Overview는 기존 provider presentation의 사용량 행과 검색을 제공한다.
- Usage & Spend는 IMPL-600에서 기간(7/30/90/수집된 전체, 최대 365일)·통화 그룹 선택,
  일별 비용 차트, 365일 토큰 활동 히트맵, 공급자/모델/프로젝트/세션별 40행 페이지를
  연결했다. 차트 click/hover와 이전·다음 날 버튼으로 날짜별 수치·누락 상태를 읽는다.
  새 데이터 수집 없이 기존 scan을 재집계한다. 창의 선택 저장은 IMPL-605에서 추가했다.
- IMPL-601은 일별 차트의 선택 날짜에 시간별 비용을, 프로젝트·세션 행에 모델 상세
  40행 페이지를 연결했다. 프로젝트 상세는 기간 내 일별 비용도 표시한다. 시간대 표시는
  UTC 오프셋으로 서머타임의 반복 시각을 구분하며, 누락된 시간과 확인된 0을 분리한다.
  모델·시간대 합계가 전체 청구액을 설명한다고 가정하지 않는다.
- IMPL-603은 Compare rolling periods로 7/30/90/365일 비용·토큰·수집 범위를 함께 표시한다.
  원본 비용 카드의 comparisonSummaries처럼 같은 수집 기준일에서 끝나는 겹치는 기간이다.
  각 행에서 해당 기간의 차트로 이동한다. 확인된0과 unknown을 구분하고 날짜/공급원 coverage가
  부족한 값에는 ~와 설명을 붙인다. 이는 인접한 이전 기간 대비 증감률이 아니다.
  한 actor turn에서 동일 scan/환율표를 사용하며 추가 기간은 합계 중심으로 투영한다.
  기간 비교 자체가 과거 데이터를 추가 수집하거나 트레이 설정을 변경하지 않는다.
- IMPL-604는 선택 기간·통화의 Share Stats 미리보기, 텍스트/이미지 복사, PNG 저장,
  비용 JSON 복사/저장을 기존 Windows 네이티브 경로에 연결했다. 365일 토큰 차트를 보고
  있더라도 출력 범위는 선택 기간이다. 공유 카드는 공개 공급자·모델 이름과 허용된 요금제
  이름만 사용한다. JSON은 PII 숨김 시 source ID·별칭·비공개 모델명·숨김 source ID도
  익명화한다. 끈 경우에는 원래 source ID/라벨을 포함하며 프로젝트/세션 원문은 제외한다.
  실패/수집 중인 데이터의 공유 카드는 거절한다. 부분 JSON에는 별도 수집 상태 안내를
  표시한다. 앱 응답은 요청 접수이며 실제 복사/저장 성공 증거가 아니다.
- Display settings는 PII 숨김, credits/extra 표시, 사용량 표시 방향, reset 시각 표시의
  네 키만 저장한다. 트레이와 같은 설정 저장소·렌더링 경로를 사용한다.
- IMPL-602의 Cost settings는 비용 수집·Codex ledger·OpenCodeX logs·OpenCodeX가 있을 때
  native Codex 숨김 토글, 원본 통화 유지/지원 통화 환산, 공급원별 및 전체 포함/제외를 제공한다.
  일반 설정은 수집 결과가 없어도 읽고 저장하며, 공급원 선택은 현재 수집이 준비됐을 때 제공한다.
  공급원은 40행씩 표시하고 전체 포함/제외는 모든 페이지에 적용한다. 현재 목록에 없는
  공급원의 기존 숨김 설정은 보존한다. PII 모드에서는 계정 별칭 대신 Source N으로 표시한다.
- 연결 실패 시 이전 데이터를 내리고 컨트롤을 잠근다. 저장 응답이 유실된 변경은 자동
  재전송하지 않고, 재연결 후 현재 설정을 다시 받는다.
- IMPL-605는 마지막 탭, 비용 기간/통화/차트/분류/비교 여부, 선택 날짜를 앱 재개 시
  복원한다. backend의 별도 versioned view key에 저장하며 수집/환산 설정이나 계정 선택을
  바꾸지 않는다. 프로젝트·세션 raw ID/행 번호·일시적인 상세 revision은 저장하지 않는다.
  지정 통화가 사라지면 빈 상태와 재선택 안내를 유지한다. Automatic을 직접 선택한 경우에만
  현재 첫 통화 그룹을 사용한다. 날짜는 현지화된 문자열이나 차트 index 대신 yyyy-MM-dd로
  저장하며, 현재 차트에 없는 날짜를 다른 날로 조용히 바꾸지 않는다.
  UI에는 저장 상태와 Retry save/Restore saved view를 제공한다. 불확실한 저장은 자동
  재전송하지 않으며, 명시적 재시도는 현재 revision을 읽고 다시 flush한다.
- IMPL-606은 Codex model changes and service tiers 패널을 추가했다. 선택 통화·포함 공급원
  중 native Codex만 집계하며, 같은 수집/환율표에서 현재 기간과 바로 앞의 같은 경과시간
  기간을 비교한다. 40행씩 모든 모델의 비용/토큰, New/Ended/Unchanged/증감률,
  기록된 standard/priority 비용·토큰과 토큰 구성을 표시한다. 다른 공급자와 OpenCodeX는
  이 패널의 대상이 아니므로 상위 전체 비용과 범위가 다르다.
  양 기간의 공급원·모델·합계가 완전할 때만 증감을 제공한다. 가격/이력이 없으면 unknown,
  일부 알려진 값에는 ~를 표시한다. DST로 이전 기간이 하루 중간에서 시작하면 일별 자료로
  경계를 추정하지 않고 온전한 날짜의 값만 표시하며 증감률은 보류한다. 별도 과거 수집은 없다.
  PII 숨김은 분석·기본 모델 표·프로젝트/세션 모델 상세에 공개 모델 계열 또는 Model N을
  사용한다. 분석 토글/페이지는 이번 창에서만 유지한다.
- IMPL-608은 같은 모델 패널에 현재/이전 기간의 기록된 effort별 토큰과 고유 세션 참조 수·
  증감을 연결했다. 모델마다 같은 세션은 기간 내 한 번 세며 여러 모델을 사용한 세션은
  각 모델에 나타날 수 있다. 요청 수를 세션 수로 대신하지 않는다. effort가 없는 사용량은
  Unrecorded로 표시하며 명시적 none과 구분한다. 서버 적용 effort를 증명하는 수치는 아니다.
  이벤트 집계와 일별 모델 합계가 맞는 경우만 사용하며, 구형 자료·한도 초과·누락·stale은
  Unknown/~ 및 증감 보류로 표시한다. 세션 ID/경로는 보고서별 번호로 치환해 내부에서만 쓰고
  화면/pipe에는 집계 숫자만 전달한다. PII 숨김은 사용자 정의 effort를 Custom으로 묶는다.
  최대12개 effort 라벨을 표시하며 그보다 많으면 추가 라벨 수를 알린다.
  effort별 비용·세션 탐색·모델 필터·일/주/월 타임라인은 남아 있으며 WIN-057 전체 완료가 아니다.

## 프로세스와 통신 규약

기존 `CodexBarWindows.exe`가 단일 런타임과 credential/config 소유자다.
WinUI 프로세스는 공급자에 직접 접속하거나 두 번째 백엔드를 시작하지 않는다.

1. 트레이가 새 UUID pipe 이름과 자신의 PID를 인자로 지정하여 절대 경로의 UI를 시작한다.
   handle을 상속하지 않으며, 자식 환경은 Windows·사용자 폴더 관련 키만 허용한다.
2. UI가 native named-pipe listener를 만든다. 현재 사용자 SID의 protected DACL,
   첫 인스턴스 전용, 원격 클라이언트 거절, overlapped I/O를 요청한다.
3. 양측은 native API로 얻은 peer PID를 비교한다. Swift 측은 자신이 시작한 프로세스
   handle과 세션·사용자 identity를, UI 측은 기존 백엔드 handle·경로·세션을 사용한다.
   pipe 이름이나 클라이언트가 보낸 문자열만으로 신뢰하지 않는다.
4. JSON 앞에 4바이트 little-endian 길이를 붙인다. 요청은 최대 4 KiB, 응답은 최대
   1 MiB다. Overview 문자열은 96 KiB, spend의 상위 화면과 상세 화면을 합친 문자열은
   128 KiB UTF-8 예산을 적용하고 초과 시 truncation을 표시한다. 모델 분석도 이 예산을 공유한다. Overview에는 최대
   256개 카드·1024개 행 예산과 카드당 64개 상세 행 제한이 있다. spend는 상위/상세
   각각 최대 40행, 모델 분석도 최대 40행, 차트 각각 최대 365개 지점이다.
5. 연결 첫 요청은 `hello`다. protocolVersion 1, requestID, backend generation을
   확인한다. 연결당 중복 requestID는 거절하고 4096개 뒤 재연결한다.
6. 허용 메서드는 `hello`, `snapshot`, `refresh`, `setSetting`, `spend`,
   `spendPreferences`, `setSpendPreference`, `spendAction`,
   `viewPreferences`, `setViewPreferences`이다.
   snapshot은 2초 간격으로 요청한다. 설정 쓰기는 네 키의 고정 순서 boolean SHA-256
   revision을 대조한다. 이는 오래된 화면의 저장을 감지하는 낙관적 대조이며, 트레이와
   별도 스레드에서 발생하는 모든 설정 쓰기의 원자적 직렬화를 보장하지 않는다.
   `spend`는 bounded query(days/currency/section/chart/page/detail/comparePeriods/codexModelsPage)를 받아 일반 snapshot과
   별도의 응답으로 보낸다. controller await 전후 collection/generation/publication/settings를
   대조하고, PII·문자열 예산을 적용한 표·차트만 전송한다. 내부 source/account 키는
   전송하지 않는다. 통화 그룹이 사라지면 다른 통화로 자동 합산하지 않는다.
   상세 선택은 수집 세대·통화·기간·privacy·프로젝트/세션 순서를 묶은 프로세스 키 기반
   HMAC revision과 행 번호/날짜를 보낸다. 원문 소유자 ID·프로젝트 경로는 전송하지 않는다.
   수집이나 행 순서가 바뀌면 이전 상세 요청을 거절한다. 시간별 projection은 controller
   옵션을 저장하거나 source를 다시 수집하지 않고, await 후 publication/설정을 다시 대조한다.
   비용 설정은 별도 응답이며 전체 설정·현재 공급원 순서·PII·수집 세대를 HMAC revision으로
   묶는다. 공급원 쓰기는 raw ID가 아닌 그 revision의 행 번호만 받는다. 저장 직전 값 비교와
   변경 필드 쓰기를 backend 프로세스의 동일 잠금 아래 수행하고 트레이의 비용 설정/공급원
   저장도 이 경로를 사용한다. 외부 프로세스의 설정 편집까지 원자적으로 직렬화하지는 않는다.
   저장 응답은 설정 저장 여부이며 수집 완료를 의미하지 않는다. 기존 runtime이 이후
   재집계/환율 fetch/필요한 재수집을 처리한다. 실패·응답 유실은 현재 값을 다시 읽고 자동
   재전송하지 않는다. 앱의 표시 설정과 비용 설정 저장도 동시에 시작하지 않는다.
   기간 비교는 같은 publication/generation·수집일·source catalog·통화·시간대·날짜 경계의
   결과만 사용한다. 별도 FX fetch 없이 rate table을 한 번 캡처하며 시간별 상세에도 같은
   table을 전달한다. 누락/비정상 환율은 기존 원본 통화 그룹으로 유지한다.
   비교의 최대4행도 spend의 공유128 KiB 문자열/1 MiB 응답 예산 안에 포함한다.
   `spendAction`은 허용된 6개 동작과 현재 view revision만 추가로 받는다. revision은
   환율표에도 묶인다. 생성된 PNG/DIB/JSON bytes·저장 경로·HWND는 pipe로 전송하지 않는다.
   backend 내부 단일 UI mailbox가 트레이 UI 스레드의 미리보기/클립보드/저장 대화상자에
   전달하고, 실행 직전과 대화상자 동안 수집 무효화·설정·PII·환율 변화를 대조한다.
   진행 중인 native action이나 pending action이 있으면 중복 접수를 거절하며 modal loop
   재진입도 막는다. 응답 유실 시 자동 재전송하지 않는다. JSON/이미지 산출물은16 MiB,
   clipboard text는65,536 UTF-16 code units로 제한한다. 저장 취소를 성공으로 보고하지 않는다.
   view 설정은 `windowsNativeAppViewV1` Data key의 최대4 KiB JSON이다. 저장 직전
   raw data SHA-256 revision을 대조하고 read/compare/write를 같은 프로세스 잠금으로
   직렬화한다. 계정/source ID나 credential은 포함하지 않는다. 누락은 기본값, 손상/다른
   schema/읽기 실패는 보존·쓰기 거절로 처리한다. flush 후 읽은 값이 다르면 실패로 응답한다.
   in-memory 쓰기 이후 synchronize 실패도 성공으로 바꾸지 않는다.
   UI는400ms 동안 선택 변경을 합쳐 저장하며 저장 중 후속 선택은 성공 응답 뒤 이어 쓴다.
   `AppWindow.Closing`에서 close를 즉시 취소한 뒤 최대2초 동안 미전송 선택을 처리하고
   닫는다. backend 종료는 기다리지 않는다. 비정상 종료·시간초과의 마지막 선택 보존을
   보장하지 않으며 기존의 불확실한 저장을 닫기 과정에서 자동 재시도하지 않는다.
7. UI는 15초, Swift I/O는 30초의 대기를 제한한다. Swift는 취소한 overlapped 작업의
   완료를 기다린 뒤 buffer/event를 해제한다. 백엔드 종료를 감지하면 UI도 닫힌다.

전달 데이터는 표시 문자열·상태·표시/비용 설정과 불투명한 revision/행 번호다. API 키, cookie, OAuth token, raw config,
파일 경로를 위한 필드는 없다. 실제 Win32 PID/ACL/취소·보안 동작은 Windows 검증이 필요하다.

## 배포 위치와 의존성

계획한 파일 배치는 다음과 같다. 앱 폴더 전체를 동일 버전으로 배치해야 한다.

```text
<version-root>/
  CodexBarWindows.exe
  CodexBarCLI.exe
  <Swift runtime and backend resources>
  App/
    CodexBarApp.exe
    CodexBarApp.dll
    CodexBarApp.deps.json
    CodexBarApp.runtimeconfig.json
    <.NET and Windows App SDK publish output, XAML/PRI/resources>
```

프로젝트는 Windows 11 최소 빌드 22000, Windows SDK 26100, .NET 10, WinUI 3,
x64/ARM64를 대상으로 한다. `Microsoft.WindowsAppSDK 2.2.0` 및
`Microsoft.Windows.SDK.BuildTools 10.0.26100.4654`를 지정하고, .NET/App SDK의
self-contained 파일 배포를 요청한다. single-file publish와 trimming은 끈다.
위젯 host의 SDK 파일과 UI의 SDK 파일은 폴더를 분리한다.

**IMPL-599에서 publish·조립·서명 연결 코드를 작성했으나 실행하지 않았다.**
`Publish-CodexBarApp.ps1`은 명시적인 dotnet.exe, 기존 lockfile, 검토된 라이선스
폴더, revision/version/architecture와 새 출력 폴더를 입력받는다. 실제 호출하면
locked restore와 self-contained publish를 수행하므로 현재 macOS 구현 단계에서는 실행하지 않는다.

- Windows에서 의존성을 restore하여 실제 `packages.lock.json`을 생성·검토하고
  `-PackageLockFile`로 지정해야 한다. 현재 저장소에는 lockfile이 없고 전이 의존성을
  확인하지 않았다. 스크립트는 전달받은 lockfile을 복사하여 locked mode로 사용한다.
- output은 소스 프로젝트 밖의 새 디렉터리만 허용한다. publish/bin/obj/packages를 분리하고
  실패 결과도 보존한다. `LicenseDirectory`에는 실제 의존성 라이선스와
  `THIRD-PARTY-NOTICES.txt`가 필요하다. 내용의 법적 완전성을 자동 판정하지 않는다.
- 결과는 `publish/`와 별도 `build-receipt.json`이다. receipt에는 전체 App 파일의
  종류·크기·SHA-256, lock digest, 선언된 소스 revision/version이 들어간다.
  로컬 파일 일치 기록이며 서명된 빌드 attestation은 아니다.
- `New-CodexBarDistributionManifest.ps1`에 `-AppPublishDirectory`와
  `-AppBuildReceipt`를 함께 전달한다. 기존 Swift runtime/resource/license 입력도
  필요하다. App 파일을 RuntimeFiles나 ResourceDirectories로 중복 공급하지 않는다.
- producer/조립/서명은 App 파일을 별도 payload로 다루고 실제 파일 바이트·분류·누락을
  대조한다. App의 EXE와 `CodexBarApp.dll`을 first-party 서명 목록에 추가하며,
  서명 후 변경된 크기/해시로 App payload를 재작성한다.
- DLL 이름은 root 백엔드와 App 애플리케이션 디렉터리를 구분하여 해석한다. App에서 부족한
  DLL을 Swift/widget 검색 폴더에서 자동 보충하지 않는다. 관리 DLL의 PE32는 CLR 헤더,
  ILONLY, 32-bit/native 제약 등을 읽어 명시적으로 허용한 App DLL에만 수용한다.

기존 portable 설치와 MSIX pack은 인벤토리의 하위 파일을 포함하는 경로를 사용한다.
설치/갱신/rollback의 실제 동작, WinUI runtime/PRI/bootstrap, Windows x64/ARM64,
장시간 재연결·프로세스 종료·패키지 identity는 아직 검증하지 않았다.
PE import 검사는 .NET assembly reference, P/Invoke, 동적 LoadLibrary, XAML/PRI 로딩을
증명하지 않는다. 실제 publish 결과와 deps/runtimeconfig에 대한 후속 대조 및 Windows 실행이 필요하다.

## 남은 앱 구현

전체 설정 pane, 계정·인증·provider 편집, Codex effort 비용·세션 참조 탐색·모델 필터/일·주·월 타임라인,
작업별 action/copy/open/login,
레이아웃 편집, 전역 단축키·창 위치/스크롤 보존,
전체 현지화, 키보드/Narrator/고대비·다중 모니터 QA가 남아 있다.
현재 UI 문구는 영어이며, 트레이의 열기 항목만 기존 en/ko 사전에 연결했다.
`WIN-007/010/012/013/015/026`은 부분 구현 상태로 유지한다.

`TestsWindows/WindowsAppProtocolTests.swift`에는 framing, JSON 키와 필수 필드,
설정 revision/allowlist, Unicode/escape byte 예산의 합성 fixture 11개를 작성했다.
실행하지 않았으며, native pipe·WinUI·실계정 기능의 동작 증거가 아니다.
IMPL-600의 `TestsWindows/WindowsAppSpendProjectionTests.swift`에는 query 경계·통화 분리,
0/누락·PII·paging·heatmap·stale/partial·응답 바이트 예산의 fixture 9개를 추가했다.
이 테스트와 UI 실행도 미실행이다. 비용 collection 활성화는 트레이와 Cost settings에서 설정한다.
IMPL-601은 `TestsWindows/WindowsAppSpendDetailTests.swift`에 상세 요청/날짜 경계,
수집·행 순서·privacy HMAC 결합, 모델 paging/PII, 프로젝트 누락/중복/0,
DST 23/25시간, 시간별 publication/페이지, 합산 바이트 예산의 합성 fixture 8개를
작성했다. 기존 controller fixture에도 선택 날짜가 공유 옵션을 바꾸지 않는 경우를 추가했다.
모든 fixture와 WinUI 상호작용은 미실행이다.
IMPL-602의 `WindowsAppSpendPreferencesTests.swift`에는 공급원 paging/PII,
수집 미완료 상태의 일반 설정, 잘못된 catalog 거절, revision 변경, 미수집 공급원 설정 보존,
허용된 설정 shape/통화, 큰 이름의 응답 상한, 요청 wire fixture 8개를 작성했다.
모두 미실행이며 UserDefaults 저장·동시성·UI·환율 fetch의 실제 동작 증거가 아니다.
IMPL-603의 `WindowsAppSpendComparisonTests.swift`에는 DST 날짜 경계, 누락/중복/통화,
partial/stale/0, 다른 수집·source·기간 거절, 주입 환율/원본 통화 fallback, 요약 집계,
추가 수집/공유 설정 변경 없음, wire/PII의 fixture 9개를 작성했다. 실행하지 않았다.
기존 controller fixture의 필수 publisher 인수도 보완했다. 컴파일·성능·UI 검증은 보류했다.
IMPL-604의 `WindowsAppSpendExportTests.swift`에는 action/wire, 기간/통화 범위,
PII와 로컬 JSON, 공유 alias 제거, 주입 renderer의 출력 전달, partial/stale 안내,
잘못된 선택/렌더 실패, clipboard 상한, 환율 revision, delivery 철회의 fixture10개를
작성했다. 모두 미실행이며 실제 클립보드·PNG·대화상자·저장 파일 품질은 검증하지 않았다.
IMPL-605의 `WindowsAppViewPreferencesTests.swift`에는 기본값/무쓰기, 값·날짜 allowlist,
저장 round trip, 손상/과대/newer schema 보존, revision 충돌, flush 전후 실패와 재시도,
readback 불일치, wire 경계, heatmap 날짜 키의 합성 fixture9개를 작성했다.
실제 defaults·WinUI 재개/닫기·debounce/동시 선택·다중 인스턴스·강제 종료는 검증하지 않았다.
IMPL-606의 `WindowsCodexModelAnalysisTests.swift`에는 인접 기간/증감, 미가격 모델,
불완전/빈 이력, service-tier 누락/불일치, 중복 날짜·합계·날짜 오류, overflow, DST,
주입 FX/통화 범위, stale, 공급원 숨김/재수집 없음, paging/PII/응답 예산의 합성 fixture12개를
작성했다. 기존 상세 fixture는 비공개 모델 이름의 익명화와 PII off 동작을 추가했다.
모두 미실행이다. 실제 수집 자료의 완전성, 컴파일, WinUI 배치·키보드·성능은 검증하지 않았다.
IMPL-607은 rollout의 기록된 effort를 이벤트/증분 캐시/sidecar/내부 fragment에 보관하고
기존 캐시를 수집 예산 안에서 이관하는 코드를 추가했다. 현재 thread 설정으로 과거 값을 채우지 않는다.
이 값의 Windows 집계·WinUI 표시는 다음 IMPL-608에서 연결했다.
`WindowsCodexEffortTests.swift`에 파서·context 경계·resume·legacy decode·재가격·캐시 교체·
sidecar migration/rollback 합성 fixture12개를 작성했다. 컴파일·테스트·실제 마이그레이션은 미실행이다.
IMPL-608의 WindowsCodexActivityTests.swift에는 세션 중복/익명 번호·legacy/none·집계 상한/overflow·
공개 JSON 제외/내부 보고서 보존·다른 자료 병합·기간별 집계·합계/날짜/누락 경계·privacy/stale
합성 fixture8개를 작성했다. 모두 미실행이며 실제 Windows 화면·성능·정확도를 검증하지 않았다.

## API 참고

- [CreateNamedPipeW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createnamedpipew)
- [GetNamedPipeServerProcessId](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeserverprocessid)
- [Windows App SDK self-contained 배포 문서](https://github.com/MicrosoftDocs/windows-dev-docs/blob/docs/hub/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps.md)
- [Windows App SDK 공식 릴리스](https://github.com/microsoft/WindowsAppSDK/releases)
- [Windows 앱 색상과 테마](https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/color)
- [AppWindowClosingEventArgs.Cancel](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.windowing.appwindowclosingeventargs.cancel?view=windows-app-sdk-2.0)
