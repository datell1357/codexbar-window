# Windows 전용 구현 로그

## 실행 정책 — 2026-09-12 사용자 지시

현재 로컬은 macOS이며 **구현만 진행**한다. 소스 읽기·편집과 상태 기록은 수행하지만 빌드, 컴파일러/manifest 평가, 테스트, 앱·실계정/provider/키체인·원격 Windows 실행, 성능 측정, CI 및 별도 검증 스크립트는 실행하지 않는다. 코드 작성은 동작 검증 또는 기능 전체 완료를 뜻하지 않는다. 사용자가 매 구현 묶음의 commit/push를 명시적으로 승인했다. 구현과 관련 상태 기록을 커밋한 뒤 datell1357/codexbar-window의 작업 브랜치로 푸시한다. 검증 미실시·미완료 범위를 커밋 본문과 30분 보고에 남긴다. 변경이 없으면 빈 커밋을 만들지 않으며, 강제 푸시·hard reset·파괴적 정리는 하지 않는다. 실패한 푸시는 미게시로 보고하고 로컬 커밋을 보존한다.

30분 주기 heartbeat `codexbar-windows-30`를 현재 작업에 연결했다. 매 실행에서 진행 상황, 커밋 해시, 푸시 결과를 한국어로 보고하고 마지막 구현 지점부터 계속한다. 재고정 원본 분석을 처음부터 반복하지 않는다.

## IMPL-001 — 원격 OS별 세션 transport와 plugin type 보완

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·실행·검증 스크립트를 수행하지 않았다.

계약: WIN-041 / BC-020~023, WIN-047 / SA-04.

작성한 코드:

- `Sources/CodexBarCore/RemoteSessionTarget.swift`: Windows/POSIX/미지정 OS를 가진 host 모델, `windows://user@host`/`posix://user@host` 입력, host 중복 정리와 OS 보완, 원격 executable override, OS별 list/focus 명령 생성, 구조화된 focus 결과.
- Windows remote는 PowerShell UTF-16LE EncodedCommand로 고정 작업과 인수를 전달한다. exe override는 절대 `.exe` 경로로 제한한다. PATH의 `codexbar.exe`/`CodexBarCLI.exe` 후보와 list v2→v1을 사용한다. session/path 값은 script literal로 인코딩한다. 원본 JSON 배열을 PowerShell 객체로 재직렬화하지 않는다.
- `RemoteSessionFetcher.swift`: Tailscale Windows peer를 포함하고 OS를 보존하는 파서, typed target fetch/focus API, Windows SSH/OpenSSH·Tailscale 실행 파일 경로 처리, 취소 검사와 실패 결과 전달.
- `AgentSessionsStore.swift`: Windows remote 조회 결과의 target을 후속 focus에도 전달한다. 기존 Mac UI의 Void focus 호출 방식은 유지하며 새 Windows UI는 구조화된 결과를 소비해야 한다.
- `PreferencesMenuPane.swift`: 기존 host 입력 힌트에 OS prefix 표기.
- `codexbar-plugin.d.ts`: 이미 prelude에 존재하던 `date.nowMillis()` 선언 추가. runtime 구현 자체는 변경하지 않았다.

아직 남은 범위:

1. Windows local agent session scanner와 실제 terminal/window focus. 현재 CLI sessions focus의 Windows 경로는 아직 미구현이므로 remote focus 기능 전체 완료가 아니다.
2. Windows 트레이의 세션 표시·설정·주기 갱신과 구조화된 focus 오류 표시. 현재 Windows runtime에는 전체 AgentSessionsStore 대응이 없다.
3. remote executable 경로/OS 선택의 정식 native 설정 UI. 현재 문자열 prefix 및 typed API만 제공한다. Windows manual bare host는 OS를 알 수 없으면 실행하지 않고 명시 설정 안내를 반환한다.
4. 모든 Windows SSH 로그인 shell 및 PowerShell 인수/출력·명령 실패/취소/시간초과의 실제 검증. 수행하지 않았다.
5. 업데이트된 Tailscale peer 동작에 맞춘 기존 fixture 이관. 테스트 추가/실행도 이번 단계에서 하지 않았다.

다음 구현: Windows 세션 탐색의 기존 process identity/metadata 경계와 CLI focus 호출부를 읽고 Windows 전용 scanner/focus를 연결한다. 범위가 큰 UI 작업은 소스 계약을 유지한 런타임 모듈로 나눠 이어간다. 필요한 검증은 별도 허용 전까지 실행하지 않는다.
