# 3차 검토 — 선택지·기본값·출력·Windows 원격 연결

고정 원본 `928166f899471bbdcb72210641cdec91324d0154`를 기준으로 앞선 1·2차 목록을 다시 대조했다. 이번에는 **원본 테스트가 고정한 행동, enum 선택지, 출력 DTO, OS 분기**를 추가로 확인했다. 기존 72개 기능군은 유지하며 아래 조건을 보강했다.

## 발견과 조치

| ID | 발견 | 계획 조치 |
|---|---|---|
| TA-01 | docs/widgets의 provider 목록은 12개지만 `ProviderChoice`와 실제 descriptor/test literal은 17개 | Windows 일반 위젯은 17개 전부 선택 가능하도록 확정. BurnDown은 Codex/Claude 별도, Metric 3종 및 6종 크기 매핑도 명시 |
| TA-02 | 이전 scanner는 위젯 parameter/control을 추적했지만 enum의 개별 선택지는 별도 계약이 아니었음 | 전체 Sources의 CaseIterable/AppEnum과 MenuBarLayoutToken 선언에서 412개 선택지 위치를 추가. 원본 범위가 내부/진단인 경우 그 범위를 유지하며 기능 수로 세지 않음 |
| TA-03 | Tailscale peer parser가 macOS/linux만 허용하며 remote 실행은 `sh -lc`와 Mac bundle fallback을 사용 | Windows→Windows 원격 session도 지원하도록 peer OS 정보·Windows CLI/SSH locator·원격 shell별 명령 adapter를 필수화. POSIX remote 호환과 v2→v1 데이터 계약은 별도 보존 |
| TA-04 | “CLI 출력 지원”만으로는 usage-only TOON, bootstrap parse-error 형식, format 우선순위가 불명확 | usage/implicit usage만 TOON. 마지막 --format 값 판정 및 비-usage fallback을 BC-011~013으로 고정 |
| TA-05 | guard의 일반 실패·한도 부족·조회 불가를 모두 exit1로 바꿀 위험 | >= 임계 판정, blocked1/unknown69/인수64/fail-open unknown0, synthetic window 거부, timeout0 의미를 BC-014~017로 고정 |
| TA-06 | “기본값 유지”라는 포괄 조건은 fresh/legacy/invalid state 차이를 숨김 | 신규 adaptive, 기존·잘못된 값 fiveMinutes, 저장 유효값 우선, scanner consent, legacy 저전력/알림 defaults를 입력별로 명시 |
| TA-07 | 대시보드 화면 model·Spend export JSON·dashboard-v1 JSON은 서로 다른 계약 | 원본 Spend export가 projects/sessions를 직렬화하지 않는다는 점을 명시. provider/model/통화/coverage DTO와 파일 취소·atomic write·기간 이름을 보존 |
| TA-08 | plugin costUsage의 366일/10000행 한도를 앱의 365일 scan이나 화면 차트 제한과 혼동 가능 | costUsage/JS-safe numeric 한도 및 오류 처리를 별도 fixture 조건으로 고정. 원본보다 조용히 줄이거나 초과를 잘라 성공시키지 않음 |

## Windows 원격 기능의 구체적인 구현 조건

현재 원본의 POSIX command builder를 그대로 공유하면 Windows remote는 탐색에서 빠지거나 `sh`를 실행하지 못한다. 이를 Windows OS에서 불가능한 기능으로 제외하지 않는다.

1. 발견한 peer의 OS를 host record에 유지하고 online/local/duplicate 조건을 적용한다. Windows도 대상에 포함한다. 수동 host는 OS/shell/CLI 경로를 설정하거나 확인할 수 있어야 한다. 불명확한 host에 POSIX shell을 추측해 실행하지 않는다.
2. 로컬 Windows에서 SSH/Tailscale 실행 파일과 PATH/설정 override를 Windows 방식으로 찾는다. `/usr/bin/ssh`나 Mac app bundle을 필수 전제로 삼지 않는다.
3. remote OS/shell별 list/focus 명령 adapter를 사용한다. Windows shell 인수 인코딩과 POSIX shellQuote를 구분한다. host/session 문자열을 임의 명령으로 실행하지 않으며 원본 host 검증·timeout/cancel을 유지한다.
4. 원격 JSON은 기존 v2/v1 array 형식을 유지한다. peer OS 선택은 transport metadata/config에서 해결하며 기존 array를 임의의 새 envelope로 바꾸지 않는다. CLI 구버전/미설치·접속 거부·focus 실패는 구별해 표시한다.
5. Windows↔Windows 및 Windows→POSIX의 실행·focus fixture를 따로 만든다. 기존 macOS/Linux 원격 프로토콜을 지원한다는 이유로 Windows 설치물에 Mac UI/런타임 파일을 포함하지 않는다.

## 위젯 공급자와 표시 계약

일반 provider 위젯의 원본 선택지는 **Codex, Claude, Gemini, Alibaba Coding Plan, Alibaba Token Plan, Qwen Cloud, Antigravity, Cursor, z.ai, Copilot, Devin, MiniMax, Kilo, OpenCode, OpenCode Go, Mistral, Kimi — 17개**다. 69개 전체를 원본 위젯 지원이라고 표현하지도 않고, 오래된 문서대로 12개로 줄이지도 않는다.

Switcher/Usage는 small·medium·large, History는 medium·large, Metric은 small, BurnDown/Combined는 medium이다. Windows 크기 API 명칭을 복제하는 것이 아니라 각 크기에서 제공하는 정보·선택·행동에 대응한다. Switcher 공유 선택과 Usage 인스턴스별 선택은 별개다. BurnDown provider는 Codex/Claude, window는 session/weekly이며 Metric은 credits/todayCost/last30DaysCost다.

## 입력·예상 결과 계약

[BEHAVIOR-CONTRACTS](BEHAVIOR-CONTRACTS-2026-09-12.ko.md)에 **25개** 사례를 추가했다. 각각 입력, 기대 결과, 원본 blob/줄/anchor, 참고할 기존 테스트 파일과 원본 보존/Windows 적응 여부를 담았다. 이는 전체 테스트 수가 아니며, 실행한 테스트 결과도 아니다. 기존 포괄 조건을 실제 Windows fixture로 옮길 수 있도록 구체화한 것이다.

412개 enum 선택지 추가 후 source 의무 항목은 **8,563개**다. 이전 8,151개 ID는 유지한다. 중복 사용처와 지원 코드를 포함하므로 기능 수 또는 완성률로 해석하지 않는다.

## 검사 결과와 남은 범위

`validate_tertiary_audit.py`는 원본 소스를 읽어 다음을 대조한다.

- ProviderChoice 17개 = descriptor의 widgetSelectable(default 포함) = 원본 test literal.
- 6종 위젯의 family 목록, 18개 조건부 layout metric과 선택지 의무 연결.
- usage-only TOON, guard 코드/비교/placeholder, refresh 기본값 분기, Spend export DTO 경계.
- 원본 Windows peer 제외/POSIX shell 전제를 확인하고 Windows 적응 계약에 연결.
- 행동 계약 25개의 원본 anchor/줄/blob·test 파일 존재와 NOT_RUN 상태.

1·2차 검사와 원본 경로·schema·역참조·재생성 검사를 함께 재실행한다. 모든 검사는 Python 문서/소스 대조이며 Swift 코드, 앱, provider, 실계정, 원격 접속, Windows runtime을 실행하지 않는다.

이번에 확인한 계획 보완은 반영했지만 Windows remote adapter 등 실제 기능 구현은 남아 있다. 테스트 파일을 읽었다는 이유로 해당 테스트 통과를 주장하지 않는다. 원본 전체의 모든 암묵적 실행 경로를 완전히 증명했다는 의미도 아니다.
