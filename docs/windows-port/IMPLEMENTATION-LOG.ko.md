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

## IMPL-002 — Windows CLI 프로세스 세션과 창 활성화

상태: CODE_WRITTEN_UNVERIFIED. 사용자 지시에 따라 빌드·컴파일·테스트·앱·프로세스 조회 실행·검증 스크립트를 수행하지 않았다. 계약: WIN-040/041/042, BC-020/021의 Windows 상대 CLI 기반.

작성한 코드:

- `WindowsProcessEnumerator.swift`: 기존 Antigravity scope는 기본값으로 유지하고 agentSessions scope를 추가했다. 세션 scope는 현재 사용자 소유 프로세스만 command line 조회에 넘기고, PID·parent PID·raw FILETIME 생성 시각을 snapshot에 담는다.
- `WindowsAgentSessionScanner.swift`: native CLI/알려진 Node/Bun package entrypoint를 식별한다. 한정된 PE header를 읽어 GUI executable을 제외하고 PID+생성 시각을 opaque session ID로 쓴다. 프로세스 환경이나 대화 본문은 읽지 않는다. `LocalAgentSessionScanner`의 Windows 진입점을 연결해 POSIX ps/lsof 경로로 빠지지 않게 했다.
- `WindowsSessionWindowFocuser.swift`: PID 생성 시각·현재 사용자·생존 상태를 확인하고 열린 process handle을 유지한다. 생성 시각이 자식보다 늦은 parent나 다른 사용자 parent는 거부한다. 살아 있는 프로세스/조상의 유일한 top-level visible window만 활성화하며, 조상 창은 application-only 결과로 구분한다. 여러 창이면 추측하지 않고 실패한다.
- `SessionWindowFocuser.swift`, `CLISessionsCommand.swift`: 공통 결과 타입과 Windows CLI focus 호출을 연결했다. 실제 OS가 foreground 전환을 거절하면 실패한다. 키 입력 합성·권한 우회는 추가하지 않았다.
- `Package.swift`: Core의 Windows Shell32/User32 링크를 추가했다. 새 외부 패키지는 추가하지 않았다.

미완료·제한:

1. 현재 Windows scanner는 live CLI의 PID identity만 반환한다. cwd/프로젝트/대화명/transcript·activity timestamp 매칭, Desktop/IDE app-server, runtime flags를 가진 Node/Bun 실행, 모든 Pi/OMP custom root는 아직 연결하지 않았다. lastActivityAt은 nil이며 기존 live-process state 규칙을 사용한다.
2. native 탐색 오류/timeout은 현재 빈 목록으로 돌아간다. 전체 Windows 런타임에서 unavailable과 empty를 구분하는 상태 전달을 후속 연결해야 한다.
3. Windows Terminal 등의 pseudoconsole가 ancestor tree 밖에 있는 경우와 개별 탭 선택은 미완료다. root/ancestor의 유일한 창이 없으면 실패하며 전역 창 제목으로 임의 선택하지 않는다.
4. Windows 트레이 session 메뉴·native 설정·원격 focus 오류 표시는 미완료다. 이번 코드로 W11 전체 완료 또는 실제 실행 성공을 주장하지 않는다.
5. Windows 툴체인에서 WinSDK signature·linker·PE/argv·process/window 수명을 검증하지 않았다. 기존 테스트도 실행하지 않았다.

다음 구현: Windows 세션의 structured scan outcome(성공/빈/조회 실패/부분 결과)과 runtime 설정/갱신 연결을 추가하고, 현재 Windows 트레이에 session 목록·오류·focus 명령을 연결한다. 이어서 명시적 cwd/metadata 기반의 provider별 correlation을 확장한다.
