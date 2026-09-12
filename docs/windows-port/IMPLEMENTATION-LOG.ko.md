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

## IMPL-003 — 로컬 세션 상태·주기·트레이 연결

상태: CODE_WRITTEN_UNVERIFIED. 사용자 지시에 따라 빌드·컴파일·테스트·앱·조회 실행·검증 스크립트를 실행하지 않았다. 계약: WIN-007/010 트레이 표면(W03), WIN-040/041, 세션 opt-in 및 설정/종료 수명.

작성한 코드:

- Core `WindowsSessionScanOutcome`: complete/partial/failed/cancelled와 목록/메시지를 분리했다. 열거 실패·timeout은 실패, 결과 수/시간 예산 초과는 부분 결과로 반환한다. 기존 list-only API는 호환 wrapper로 남긴다.
- CLI sessions/list/focus는 Windows에서 structured outcome을 사용하며 실패/취소 시 exit1, 부분 결과는 stderr 안내 후 기존 JSON/list 형식을 유지한다.
- `WindowsAgentSessionsRuntime.swift`: agentSessionsEnabled 기본 false, 활성화 시에만 30초 스케줄과 메뉴/수동 갱신, 한 번의 scan과 합쳐진 후속 요청, 세대 기반 늦은 결과 차단, 설정 off/종료 시 취소·drain과 데이터 제거를 추가했다. scan/focus task를 actor가 소유한다.
- `WindowsTrayHost.swift`: 고정된 popup snapshot에서 local CLI sessions submenu, 활성화 toggle, refresh, PID 기반 목록과 포커스 명령을 연결했다. 오류 시 이전 목록은 보존하되 actions를 비활성화하고 오류 메시지를 표시한다. popup의 명령표는 닫을 때 제거한다.
- `WindowsMain.swift`: 독립 세션 runtime의 publisher/메뉴/settings/focus/start/shutdown을 연결했다. provider quota refresh와 session discovery는 별도로 예약한다. 종료는 두 runtime에 취소/drain을 요청한다.
- Windows window focuser는 호출별 지역 상태만 사용하므로 main-dispatch queue hop 없이 worker에서 호출할 수 있게 했다. minimize 복원은 ShowWindowAsync를 사용하고 취소 검사 후 foreground 요청을 한다. Mac focuser의 MainActor 경로는 변경하지 않았다.

남은 범위:

1. 원격 세션 목록·host/OS/CLI 경로 editor·주기 갱신과 focus 결과의 native 통합. 현재 submenu는 로컬 CLI만 다룬다.
2. 프로젝트·대화명·cwd/metadata·실제 활동 시각, Desktop/IDE와 Windows Terminal의 정확한 tab 연결.
3. 개별 PID 접근 거부나 PE/argv 읽기 실패의 집계는 기존 열거기의 skip 동작을 유지한다. structured complete는 현재 식별 가능한 CLI 범위의 탐색 종료이며 모든 프로세스의 접근 성공을 뜻하지 않는다.
4. 상태/오류는 다음 popup snapshot에 표시한다. 닫힌 메뉴에 대한 즉시 toast/오류 내역 UI·현지화는 아직 연결하지 않았다.
5. 모든 WinSDK/API/actor 수명·사용자 설정·실행 동작은 미검증이다. 새 코드로 W03/W11 전체 완료를 주장하지 않는다.

다음 구현: 같은 actor와 snapshot 구조에 원격 host 설정/조회/실패를 연결하고, 로컬/원격 focus 요청을 구분한다. 그 다음 명시적 cwd와 제한된 metadata 기반 correlation을 구현한다.

## IMPL-004 — 원격 세션 설정·조회·트레이 통합

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·앱/UI·SSH/Tailscale·실계정·검증 스크립트를 실행하지 않았다. 계약: WIN-041 / BC-020~023, W03/W04의 원격 세션 native 표면.

작성한 코드:

- `RemoteSessionFetcher`: available/ unavailable/cancelled discovery API로 유효한 빈 tailnet과 탐색 실패를 구분한다. typed host 조회는 최대4개 SSH 작업으로 실행하고 취소 시 나머지를 drain한다. malformed peer hostname은 파서에서 제외한다.
- `WindowsRemoteSessionSettings`: remote enabled 기본false, discovery 선택, 수동 target/OS/선택 CLI path를 별도 버전 key로 저장한다. 최대32개 host·중복·path/OS·256KiB 저장 크기를 제한한다. 기존 agentSessionsManualHosts는 편집용으로 가져오며 unspecified OS는 명시적으로 지정해야 한다. 읽기 실패 시 저장 데이터를 덮어쓰지 않는다.
- `WindowsRemoteSessionSettingsDialog`: native host 목록과 추가/수정/삭제, OS 선택, CLI path, remote 활성화·Tailscale discovery checkbox를 추가했다. Save에서만 저장하며 Cancel/WM_QUIT는 적용하지 않는다. 다른 row 선택 전 편집 draft를 유지·반영하고 잘못된 입력은 표시한다.
- `WindowsRemoteSessionsRuntime`: opt-in, 60초 주기와 메뉴/수동 refresh, actor 소유 fetch/focus 작업, 세대별 late-result 차단·설정 변경/종료 취소, 호스트별 오류/이전 목록 비활성화, 원격 focus 요청을 연결했다. 최대32개 host를 새로 조회하고 popup은 최대128개 session을 표시하며 제한을 알린다. Windows/POSIX target을 focus까지 유지한다.
- `WindowsTrayHost`/`WindowsMain`: 별도 remote submenu, host settings dialog, 목록·오류·포커스 callback과 publisher/lifecycle을 연결했다. modal editor 동안 nested popup을 막고 닫힌 뒤 mailbox를 깨운다. hidePersonalInfo에서는 호스트/프로젝트명 대신 일반 label을 표시하고 raw SSH 오류는 메뉴에 노출하지 않는다.
- `Package.swift`: native editor font에 필요한 Windows Gdi32 링크를 추가했다. 새 외부 패키지는 없다.

남은 범위:

1. Windows Terminal exact-tab focus, Desktop/IDE·cwd/대화/project/activity metadata 매칭. Remote CLI 성공은 요청 수락으로 표시하며 실제 tab 선택을 보장하지 않는다.
2. 32개 초과 peer/128개 초과 session의 전체 탐색 UI·pagination. 현재 제한 안내와 수동 host 선택만 제공한다.
3. 호스트별 새 SSH 인증 설정·키 설치·자동 로그인은 추가하지 않았다. 기존 SSH batch-mode 환경을 사용하며 인증 실패는 unavailable이다.
4. malformed 저장 데이터의 native 복구 editor, per-host scan progress, 즉시 오류 toast/접근성/고DPI/현지화 확장은 미완료다.
5. 설정 저장, Win32 dialog/메뉴, actor 종료, SSH 동시성 및 실제 Windows/POSIX 실행 모두 미검증이다.

다음 구현: Windows 로컬 session의 명시적 cwd/경로 옵션과 제한된 metadata를 연결해 PID-only 표시를 보강한다. 원격 대형 목록의 pagination과 native 표시 범위는 별도 단계로 진행한다.

## IMPL-005 — 명시적 launch 경로·선택 세션 헤더와 label 설정

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·앱·실제 프로세스/파일/계정 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-040/042의 부분 correlation, W03/W04 session label 설정.

작성한 코드:

- `WindowsSessionLaunchHints.swift`: target argv에서 Codex 절대 `--cd`/`-C`와 Pi/OMP 절대 `--session` 파일 경로를 추출한다. 알려진 옵션만 소비하고 prompt/`--` 뒤를 경로로 해석하지 않는다. 상대경로·환경변수·scanner cwd로 보완하지 않는다. 미지 옵션이나 상충하는 session selector는 PID fallback으로 남긴다.
- 선택된 Pi/OMP JSONL의 session header와 선택적 OMP title slot을 최대32KiB 안에서 읽는 native reader를 추가했다. 하나의 file handle에서 identity/크기/mtime을 읽고 변경 중인 파일이나 최종 reparse point·비정상 header는 보강에 사용하지 않는다. file 내용은 저장하지 않는다. 임의의 최근 session 디렉터리 탐색은 추가하지 않았다.
- `WindowsAgentSessionScanner.swift`: explicit Codex launch cwd를 project에 연결하고 Pi/OMP의 선택 파일에서 project/title/activity/transcript 정보를 부분 보강한다. Pi/OMP의 저장된 cwd는 project label용이며 live process cwd 필드에는 넣지 않는다. 기존 PID+생성 시각 ID를 유지해 native focus 수명 판정을 깨뜨리지 않는다. 읽을 수 없는 explicit header는 partial 안내와 PID fallback을 반환한다.
- `WindowsSessionLabelStyle.swift`: 원본 persisted key의 project/descriptive/descriptiveAndProject를 제공한다. hidePersonalInfo가 우선하며 local/remote label에 같은 규칙을 사용한다.
- `WindowsTrayHost`와 local/remote runtime: 3개 label 선택 메뉴, project/title 표시와 PID 구분을 연결했다. 기존의 “metadata 미연결” 고정 메시지를 explicit-path/selected-header 범위에 맞게 수정했다.

남은 범위:

1. 실제 프로세스 cwd 조회, 상대경로, UNC/직접 network drive, CLI의 모든 옵션 문법과 resumed-ID-only 세션. 현재는 명시적 drive-absolute 경로만 다룬다.
2. Codex rollout 및 Claude transcript와 native cwd의 전수 correlation, Desktop/IDE, Pi/OMP session-dir/profile/custom root 및 최신 session_info title 갱신.
3. selected file의 내용이 변하면 이번 보강을 생략한다. 실제 파일 write time의 안정성/활동 의미와 모든 Windows 파일 경로/ancestor junction 상황은 별도 검증이 필요하다. direct network drive와 최종 reparse 파일은 제외하지만 완전한 파일시스템 격리 경계라고 주장하지 않는다.
4. Windows Terminal의 exact-tab focus, local/remote 대형 목록 전체 탐색, 오류 UI·현지화·DPI/접근성.
5. 새 WinSDK/argv/header parser와 설정 변경/표시 동작 모두 미검증이다. W11 전체 또는 live-cwd 지원 완료가 아니다.

다음 구현: Windows native cwd 제공 경계와 provider별 correlation을 이어서 구현한다. 안전하게 source 소유권을 확인할 수 없는 경로는 임의의 recent-file fallback으로 연결하지 않는다. remote/local 목록 pagination도 별도 구현 묶음으로 이어간다.
