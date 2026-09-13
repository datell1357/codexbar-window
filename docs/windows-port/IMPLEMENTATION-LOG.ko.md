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

## IMPL-006 — 세션 페이지와 원격 호스트 순환 조회

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·앱·실제 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-010/040/041의 목록 접근성 및 resource-bound 조회.

작성한 코드:

- `WindowsSessionPage.swift`: 세대가 포함된 page request, page index/count/범위와 이전·다음 요청을 추가했다. 결과가 줄어들면 페이지를 유효 범위로 맞춘다.
- 로컬 runtime은 수신한 세션을 32행씩 표시하며, 원격 runtime은 host 상태 행과 해당 host의 세션을 하나의 페이지 목록으로 제공한다. 기존 remote host별32/session전체128 화면 절단을 제거했다. 표시되는 페이지의 문자열만 생성한다.
- Remote refresh는 한 번에 최대32개 host를 조회하되 마지막 host ID cursor 다음부터 이어간다. 모든 catalog host를 순환하며 새 catalog에서도 cursor가 사라졌으면 처음부터 시작한다. 실제 SSH 동시성은 이전 최대4개를 유지한다.
- 아직 조회 전인 host와 cached host, unavailable host를 구분하고 마지막 성공 시각을 표시한다. 해당 순서에 포함되지 않은 host의 이전 결과를 보존하며, OS/CLI path가 달라진 target에는 이전 데이터·시각을 재사용하지 않는다. discovery 실패로 보존한 이전 host는 비활성화한다.
- `WindowsTrayHost`/`WindowsMain`: local/remote 이전·다음 명령과 페이지 정보를 연결했다. 페이지 변경은 조회를 실행하지 않으며 메뉴를 다시 열 때도 menu-open refresh를 생략한다. 오래된 설정 세대의 요청은 거부하고 submenu 부착 실패/닫기/종료 시 page command 표를 정리한다.

범위·남은 작업:

1. 페이지는 현재 받은 결과를 모두 볼 수 있게 한 것이다. 로컬 scanner의 원본 기본 maxProcessCount64·시간 예산이나 remote CLI 자체의 반환 한도를 늘린 것은 아니다. 그 한도 초과 수집을 위한 cursor/API 확장은 별도다.
2. 수동 host editor 최대32개 저장 제한과 256KiB 설정 크기는 유지한다. 발견된 tailnet host는 첫32개로 고정하지 않고 순환한다.
3. 순환 중 cached 결과는 오래될 수 있어 성공 시각을 표시한다. 원격 응답 cache의 대규모 메모리 사용·보존 정책과 실제 성능은 미검증이다.
4. native cwd·Claude/Codex correlation·Desktop/IDE·exact-tab focus, UI DPI/접근성/현지화는 여전히 미완료다.
5. 기존 query/scan/actor 종료와 page/메뉴 수명 모두 실행 검증하지 않았다. 전체 W03/W11 완료나 배포 가능 상태로 표시하지 않는다.

다음 구현: 로컬 cwd 제공 경계와 공급자별 session metadata correlation을 이어간다. 실제 native cwd가 없는 현재 explicit hint 범위를 전체 지원으로 오인하지 않는다.

## IMPL-007 — 실험적 native process cwd 읽기 (2026-09-13 KST)

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·앱·실제 프로세스/메모리·계정 조회·검증 스크립트는 실행하지 않았다. 구현에 필요한 공개 문서와 헤더 정의만 읽었다. 계약: WIN-040/042의 Windows cwd 기반.

작성한 코드:

- `WindowsProcessWorkingDirectory.swift`: 현재 사용자 SID와 PID 생성 시각을 확인하고 열린 process handle을 유지한다. IsWow64Process2/NtQueryInformationProcess를 동적으로 찾고 native64 x64/ARM64 조건에서만 작은 PEB/parameter 필드를 읽는 후보 구현을 추가했다. WOW64/에뮬레이션/32비트/권한 거부/API 부재는 unavailable이다.
- directory 문자열뿐 아니라 image/command-line anchor, normalized parameter flag, 길이·pointer 산술·UTF-16, 두 번의 descriptor/문자열 값, 최종 생존·생성 시각을 확인한다. 읽기 byte budget/deadline/cancel 조건을 갖는다. environment pointer/block, 메모리 전체 탐색, 쓰기/injection·SeDebugPrivilege는 사용하지 않는다. 읽은 메모리 버퍼를 로그나 파일로 저장하지 않는다.
- `WindowsAgentSessionScanner`: explicit provider cwd override를 우선하고 없을 때 native directory 결과를 사용한다. native read 실패는 partial 안내와 기존 path/PID fallback으로 처리한다. 기존 file-based metadata와 PID+creation ID를 유지한다.
- Windows 트레이에 `Read native directories (experimental, 64-bit)`를 추가했고 기본값은 false다. 설정 변경 시 기존 세션 보강 데이터를 즉시 비우고 진행 중 scan을 취소한다. 일반 local-session toggle과 별개로 선택해야 한다.
- Windows CLI sessions에 `--native-cwd` opt-in과 help를 추가했다. 기본 list/remote 실행에서는 이 flag를 자동 추가하지 않는다.

중요한 구현 경계:

1. CurrentDirectory는 공식 RTL_USER_PROCESS_PARAMETERS의 reserved 영역에 해당한다. 내부 native64 layout을 사용하는 실험 구현이며 Microsoft가 안정성을 보장하는 API로 표현하지 않는다. layout/anchor 검사는 Windows 실행 검증을 대신하지 않는다. 실제 Windows 검증 전 기본 활성화나 배포 가능 판정은 하지 않는다.
2. 현재 native directory 채택은 drive-absolute 경로 범위다. UNC·32비트/에뮬레이션 지원·상대 argv 해석·Claude/Codex transcript correlation은 미완료다.
3. Win32 프로세스가 내부 값을 바꾸는 race를 완전히 원자적으로 막는 것은 아니다. 읽기 중 값이 다르면 포기하며 알려지지 않은 layout에 임의 offset 탐색을 하지 않는다.
4. `ReadProcessMemory` 및 WinSDK signature·architecture/ABI·UI/CLI 설정·취소 동작은 실행하지 않았다. 새 코드는 미검증이다.

자료:
- Microsoft NtQueryInformationProcess: https://learn.microsoft.com/en-us/windows/win32/api/winternl/nf-winternl-ntqueryinformationprocess
- Microsoft RTL_USER_PROCESS_PARAMETERS: https://learn.microsoft.com/en-us/windows/win32/api/winternl/ns-winternl-rtl_user_process_parameters
- Microsoft ReadProcessMemory / IsWow64Process2 문서.
- System Informer phnt ntrtl.h의 CURDIR/RTL_USER_PROCESS_PARAMETERS 필드 정의: https://github.com/winsiderss/phnt/blob/master/ntrtl.h (참고만 했으며 소스/패키지를 vendoring하지 않음).

다음 구현: source 소유권과 실제/명시 cwd가 확인된 경우에 한정하여 Codex/Claude의 제한된 transcript metadata correlation을 연결한다. native-cwd 실험 옵션의 Windows 검증은 계속 별도 미완료로 유지한다.

## IMPL-008 — 명시적 Codex/Claude UUID metadata correlation

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·앱·실제 프로세스/파일/계정 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-040/042, W03/W04 session metadata source 설정.

작성한 코드:

- `WindowsSessionLaunchHints`: Codex resume UUID와 Claude --resume/-r/--session-id UUID를 추적한다. fork/continue/상충하는 selector는 기존 session metadata로 연결하지 않는다. unknown grammar는 보수적 fallback이다.
- `WindowsSessionMetadataRoots`/`WindowsSessionMetadataCorrelator`: 사용자가 지정한 Codex sessions 및 Claude projects root만 사용한다. known cwd와 explicit UUID가 없으면 연결하지 않는다. Codex는 depth/entry/time 예산 안에서 UUID 파일 후보를 찾고, 후보가 하나이며 header ID/cwd·source와 파일 identity/크기/mtime이 맞는 경우만 붙인다. Claude는 escaped project folder+명시 UUID 파일의 metadata만 읽고 본문은 읽지 않는다. 같은 provider/cwd/UUID에 여러 프로세스가 있으면 연결하지 않는다.
- `WindowsAgentSessionScanner`: metadata path/mtime/activity를 보강하면서 PID+생성 시각 ID를 그대로 유지한다. 미해결/모호/예산 초과는 partial 안내와 PID fallback으로 남긴다.
- GUI: `Match selected-session metadata`는 기본 off다. Codex/Claude 폴더 선택과 override 해제 메뉴를 추가했고, 설정 변경 시 기존 보강 데이터와 늦은 조회 결과를 차단한다. folder picker는 선택만 하며 기능을 자동으로 켜지 않는다.
- CLI: `--codex-session-root`, `--claude-project-root`를 추가했다. 앱 환경변수 `CODEXBAR_WINDOWS_CODEX_SESSIONS_ROOT`, `CODEXBAR_WINDOWS_CLAUDE_PROJECTS_ROOT`도 명시적 source로 사용할 수 있다. 대상 프로세스의 환경을 읽거나 default HOME을 빌려서 채우지 않는다.
- native folder picker의 COM 수명과 Ole32 링크를 추가했다. 새 외부 패키지는 없다.

범위·남은 작업:

1. 일반 신규 세션/ID 없는 resume·picker·fork/continue, 다중 profile/root 자동 발견과 full CLI grammar는 미완료다. 이번 matching은 known cwd+explicit UUID에 한정한다.
2. root는 사용자가 선언한 검색 범위다. 실제 target CODEX_HOME/CLAUDE_CONFIG_DIR을 자동으로 증명한 것이 아니다. 잘못된 root나 중복·모호한 후보는 연결하지 않으며 전체 계정/소스 동등성을 주장하지 않는다.
3. Codex directory depth3 및 공통 entry/time budget 때문에 큰/비표준 트리가 미해결일 수 있다. 불완전 enumeration에서 유일 후보라고 판정하지 않는다. 직접 UUID/cwd가 맞아도 헤더 읽기 중 파일이 바뀌면 보강을 생략한다.
4. Codex는 기존 bounded first-line reader를 재사용하고 전후 file identity를 비교한다. 전체 작업이 하나의 원자적 filesystem transaction은 아니며 ancestor junction/race 및 모든 file lifecycle 검증은 남아 있다.
5. Claude title, Codex thread-title DB, Desktop/IDE, exact tab focus, long-path folder-picker 지원, DPI/현지화/접근성은 미완료다. GUI folder picker는 현재 전통적 Windows 경로 API 범위이며 긴 root는 CLI/환경 설정 경로로 별도 다뤄야 한다.
6. native-cwd 실험 옵션과 새 parser/correlator/설정·UI·취소 모두 미검증이다.

다음 구현: explicit UUID에 한정된 경로를 source/cwd 기반의 새 세션 매칭으로 확장하되 ambiguity와 profile 소유권을 보존한다. thread title 및 non-live metadata 표시 범위는 별도 단계로 연결한다.

## IMPL-009 — 신규 세션 metadata 추론 opt-in

상태: CODE_WRITTEN_UNVERIFIED. 사용자 지시에 따라 빌드·컴파일·테스트·lint·앱·실제 프로세스/세션 파일 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-040/042 및 Windows session 설정.

작성한 코드:

- `WindowsSessionLaunchHints`: 인식 가능한 옵션만 있는 신규 호출 또는 명시적 `--` prompt 경계에 한정해 추론 후보를 표시한다. bare positional/알 수 없는 grammar, resume/fork/last/continue와 explicit selector는 신규 추론 후보에서 제외한다. 기존 explicit UUID 경로를 유지한다.
- `WindowsSessionMetadataCorrelator`: 사용자가 지정한 root에서만, 같은 provider의 모든 발견 프로세스가 known cwd이고 같은 cwd의 프로세스가 하나일 때 추론한다. Claude는 escaped project folder 키로 충돌도 묶는다. scanner가 partial이면 신규 추론 후보를 전달하지 않는다.
- 신규 파일은 process birth 이후의 creation/mtime을 요구한다. Codex는 제한된 전체 root 열거와 header UUID/cwd/source·전후 file identity를 사용하고, Claude는 정확한 project folder의 직접 UUID JSONL 파일 metadata만 사용한다. 후보 하나와 열거 완료·시간 예산이 충족될 때만 보강한다. 추론 중 reparse 항목/읽기 실패/불완전 후보 집합은 보수적으로 포기한다.
- GUI `Infer new-session metadata (experimental)` 및 CLI `--infer-new-sessions`를 추가했다. 기본값은 false이며 GUI에서는 metadata 전체 기능도 켜야 한다. runtime 설정 세대 비교에 새 옵션이 포함되어 변경 시 이전 보강 결과를 비우고 늦은 결과를 버린다.
- 실제 연결이 있으면 상태 문구에 추론이며 ownership 검증이 아님을 표시한다. session ID와 focus authority는 계속 PID+creation ticks다.

범위·남은 작업:

1. 파일 생성/수정 시각과 cwd의 유일성은 target 프로세스의 파일 소유권 증명이 아니다. 다른 종료된 프로세스/수동 복사/동일 프로젝트의 다른 profile이 생성한 파일도 가능하므로 실험 옵션이며 실제 source/profile 소유권 확인은 미완료다.
2. 프로세스 유일성은 현재 scanner가 인식·발견한 CLI 집합에 한정한다. 발견되지 않은 프로세스·Desktop/IDE·전체 CLI grammar는 포함하지 않는다. bare prompt는 의도적으로 추론 대상에서 제외한다.
3. 기존 explicit UUID matching과 신규 inference는 같은 directory entry/time budget을 공유한다. 큰 Codex tree, 변경 중 header, unknown cwd peer, 반복 생성된 복수 파일에서는 연결이 생략될 수 있다. 신규 추론의 매칭률/성능은 측정하지 않았다.
4. filesystem 열거와 file info/header 읽기는 원자적 snapshot이 아니다. 마지막 metadata 비교 이후 변경이나 ancestor junction/race 등은 Windows 구현/검증에서 추가로 다룰 범위다.
5. thread-title DB, Claude title, file-only 세션, exact-tab focus, long-path picker, UI DPI/접근성/현지화 및 모든 Windows 빌드·실행 검증은 남아 있다. 전체 기능/배포 완료로 계산하지 않는다.

다음 구현: metadata/title의 출처와 표시 경계를 이어서 구현한다. 각 구현 묶음은 검증 없이 소스·진행 문서를 함께 커밋하고 origin/main에 푸시한다.

## IMPL-010 — Codex 헤더 역할 이름과 bounded Windows reader

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·프로세스/계정/세션 파일 조회·검증 스크립트는 실행하지 않았다. 계약: WIN-040/042 및 session label 표시.

작성한 코드:

- Windows Codex explicit UUID 및 신규 추론 경로에서 원본 `CodexRolloutMetadata.descriptiveName`을 연결했다. 이미 매칭된 같은 Codex 헤더의 persisted agent path/guardian 역할만 sessionName에 넣고 기존 Windows label style과 개인정보 숨김 설정으로 표시한다. 역할 정보가 없으면 기존 project/PID fallback을 유지한다.
- `WindowsSessionMetadataCorrelator`의 Codex 헤더 읽기를 Windows retained handle 방식으로 교체했다. disk/non-reparse 파일에 한정하고, 첫 JSONL 레코드를 최대256KiB 및 deadline/cancel 범위에서 읽는다. 크기 한도에서 잘린 레코드는 채택하지 않는다.
- 파일 ID/volume/size/creation/mtime을 같은 핸들에서 전후 비교하며, 호출부의 경로 기반 전후 비교도 유지한다. 읽은 파일 정보와 호출부의 사전 정보가 다르면 보강하지 않는다. process PID+creation focus ID는 유지한다.

남은 범위:

1. 이 이름은 헤더에 저장된 역할/agent path 표시다. 사용자 지정 Codex thread title DB/session_index 및 Claude 제목 읽기는 아직 연결하지 않았다. 임의 HOME이나 다른 profile의 title을 빌리지 않는다.
2. native ReadFile은 동기 호출이므로 deadline 확인이 개별 OS read를 강제로 중단하는 것은 아니다. 실제 취소 지연/WinSDK signature/파일 수명/표시 동작은 미검증이다.
3. 단일 핸들 비교가 전체 pathname 열거를 원자적 snapshot으로 만들지는 않는다. ancestor junction, 경로 재연결 및 source/profile 소유권 경계는 남는다. IMPL-009의 신규 연결은 계속 기본 off인 추론이다.
4. 전체 기능 완성이나 배포 가능 판정은 하지 않는다. Windows 빌드·실행 검증은 사용자 승인 후 별도로 진행해야 한다.

다음 구현: 명시적으로 지정한 Codex title source를 UUID에 연결하고 출처를 유지하는 경로를 구현한다. Claude 제목과 나머지 session UI/platform 계약도 남아 있다.

## IMPL-011 — 명시적 Codex 제목 인덱스 연결

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 세션 파일/프로세스/계정 조회 및 검증 스크립트를 실행하지 않았다. 계약: WIN-040/042의 session title 및 CLI source 설정.

작성한 코드:

- `WindowsSessionMetadataRoots`에 optional title index 경로를 추가했다. CLI `--codex-title-index` 또는 앱 환경변수 `CODEXBAR_WINDOWS_CODEX_TITLE_INDEX`로 지정한다. 기본값은 nil이고 target HOME/profile/config를 자동 탐색하지 않는다. GUI runtime도 기존 roots loader를 통해 환경 설정을 읽고 설정 snapshot 비교에 경로를 포함한다.
- Codex root/cwd/header의 explicit UUID matching에 성공한 세션만 index의 동일 UUID 제목으로 보강한다. 먼저 기존 역할 이름을 만든 뒤 제목 조회를 수행하며 실패하면 그 이름을 유지한다. 원본 descriptiveName 조합과 Windows label/privacy 설정을 재사용한다. Claude/Pi와 신규 추론 세션에는 해당 제목을 붙이지 않는다.
- 제목 index는 local drive의 disk/non-reparse handle로 최대1MiB 전체를 읽고, JSONL 각 행 최대64KiB 및 공통 metadata deadline/cancel 조건을 적용한다. 전체 EOF와 stable file identity/size/creation/mtime 및 최종 pathname identity를 요구한다. 이후 행의 rename을 놓칠 수 있는 prefix 결과는 사용하지 않는다.
- id/thread_name schema가 맞는 행을 순서대로 적용한다. 같은 UUID의 마지막 항목을 사용하며 빈 마지막 이름은 이전 이름을 제거한다. 읽기 실패·크기/시간 초과·변경 중인 파일은 안내와 기존 label fallback이다. 세션 focus ID와 활동 시각을 title index로 바꾸지 않는다.

남은 범위:

1. 별도의 GUI title 파일 선택/해제 UI는 아직 없다. GUI 사용자는 현재 앱 시작 환경으로 경로를 지정하며 metadata 전체 기능과 Codex sessions root 설정이 필요하다.
2. SQLite thread DB fallback, 큰 index의 안전한 증분 cache, 신규 추론 세션 제목, Claude 제목은 미구현이다. 전체 index가 schema와 크기 한도를 만족하지 않으면 제목 전체를 생략하는 보수적 구현이다.
3. 지정한 title source가 실제 target profile에 속한다는 증명은 아니다. source 선택은 사용자 선언이며 파일 UUID 연결만 수행한다. 파일 열거/경로 전체 원자성과 동기 ReadFile 취소 지연 및 Windows 동작은 미검증이다.
4. 공통 metadata 시간 예산을 공유하므로 base matching 이후 여유가 없으면 제목 조회를 생략한다. 전체 기능/배포 완료로 계산하지 않는다.

다음 구현: Windows GUI의 title source 선택·해제와 명시적 source 표시를 연결한다. SQLite/Claude 제목 및 나머지 platform 계약은 후속 필수 범위로 유지한다.

## IMPL-012 — GUI Codex 제목 소스 선택·해제·표시

상태: CODE_WRITTEN_UNVERIFIED. 사용자 지시에 따라 빌드·컴파일·테스트·lint·앱·실제 파일/계정/프로세스 조회 및 검증 스크립트를 실행하지 않았다. 계약: WIN-010/012/040/042.

작성한 코드:

- Windows 트레이 local session 메뉴에 Codex `session_index.jsonl`이 있는 폴더 선택 명령을 추가했다. 기존 native folder picker를 재사용하며 선택한 폴더에 고정 파일명을 붙여 absolute path 설정으로 저장한다. 선택 자체로 metadata 전체 기능을 켜거나 파일을 읽지 않는다.
- `Disable Codex indexed titles`는 빈 explicit override를 저장해 환경변수 fallback까지 막는다. `Use title source from environment`는 override만 제거한다. 두 동작 모두 원본 파일을 삭제/변경하지 않는다.
- 메뉴는 선택 폴더/환경변수/비활성화/미설정 상태를 구분한다. 경로는 제어문자 제거·길이 제한·Win32 mnemonic escaping을 적용하고 hidePersonalInfo가 켜져 있으면 표시하지 않는다. source 표시는 설정 출처이며 파일 존재나 매칭 성공을 주장하지 않는다.
- runtime roots load에 GUI override를 전달했다. 기존 설정 변경 처리로 캐시 보강값을 비우고 scan을 취소하며 roots snapshot 비교로 이전 source의 늦은 결과를 차단한다. 선택 창은 기존 modal/quit 상태 경계를 사용한다.

남은 범위:

1. GUI는 고정 이름 `session_index.jsonl`의 부모 폴더를 선택한다. 임의 파일명과 긴 경로는 기존 CLI/환경 설정 범위이며 현대적 long-path file picker는 미구현이다.
2. 제목 표시에는 local sessions/metadata 기능과 Codex sessions root, explicit UUID 매칭이 필요하다. 설정만으로 데이터가 연결된 것은 아니다.
3. SQLite fallback, Claude 제목, 신규 추론 세션의 제목, 큰 index cache와 source/profile 소유권 검증은 남아 있다. GUI DPI/접근성/현지화 및 Windows 실행 검증도 미완료다.

다음 구현: Claude의 명시적으로 매칭된 transcript에서 제목 metadata를 읽는 경로와 별도 opt-in 설정을 연결한다. 대화 본문을 제목으로 추정하는 동작은 별도 계약 없이 추가하지 않는다.

## IMPL-013 — opt-in Claude custom-title metadata

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 세션 파일/계정/프로세스 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-010/012/040/042.

작성한 코드:

- GUI `Read Claude transcript titles (experimental)`와 CLI `--claude-titles`를 추가했다. 기본 false이고 metadata roots snapshot에 포함한다. GUI 옵션 변경은 기존 scan 취소·보강값 제거·늦은 결과 차단 경로를 사용한다.
- declared Claude root+known cwd+explicit UUID에 성공한 세션만 대상으로 한다. 신규 추론 결과는 제목 읽기에 포함하지 않는다. UUID가 같은 type=custom-title/sessionId/customTitle 레코드의 마지막 이름을 사용하며 빈 이름은 기존 이름을 제거한다.
- Codex stable title index reader를 공통 title reader로 확장했다. 파일 전체 최대1MiB, 행 최대64KiB, 동일 handle 전후 파일 정보와 최종 pathname 정보, deadline/cancel 범위를 유지한다. read 이후 base matching 파일 정보와도 비교한다.
- opt-in 시 transcript bytes에 대화 레코드가 포함될 수 있다. 제목 타입 외 레코드는 제목으로 사용하지 않고 저장/로그로 내보내지 않는다. prompt/assistant/tool output/summary로 이름을 추정하지 않는다. 실패하면 프로젝트 이름을 유지하고 상태 문구로 알린다.

형식 근거와 한계:

- 원본 fork의 source 검색에는 Claude custom-title reader가 없었다. Anthropic Claude Code 공식 저장소의 사용자 재현 보고 #67189에 기재된 JSONL 예시를 참고했다: https://github.com/anthropics/claude-code/issues/67189 . 이는 공식 안정 schema 보장이 아닌 관찰된 형식이며 실험 옵션으로 유지한다.
- 큰 transcript/긴 JSONL 행/형식 변경/진행 중 파일 변경/시간 예산 소진은 제목을 생략한다. 실제 지원률과 Windows 동작은 미검증이다.
- source/profile 소유권, filesystem 전체 원자성, 동기 ReadFile 취소 지연, 큰 파일의 안전한 tail/incremental 처리, 자동 제목/summary fallback, SQLite와 신규 추론 제목은 남아 있다. 전체 기능 또는 배포 완료로 판정하지 않는다.

다음 구현: session metadata의 큰 파일 처리와 source 진단을 보강하되 부분 읽기로 오래된 제목을 확정하지 않는 경계를 유지한다. 나머지 Windows platform 계약도 계속 필수 범위로 추적한다.

## IMPL-014 — 제목 source 실패 원인별 진단

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실계정/세션 파일 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-010/040/042.

작성한 코드:

- 공통 stable title reader의 nil 실패를 typed error로 분리했다. source 접근/파일 유형, 전체1MiB 제한, 행64KiB 제한, 형식 오류, 읽는 동안 변경, 시간 예산, 취소를 구분한다.
- Codex와 Claude 제목 안내를 공급자별 원인 메시지로 연결했다. Claude에서 여러 세션에 같은 실패가 발생하면 Set과 고정 case 순서로 한 번만 표시한다. 경로·제목·대화 내용·raw OS error를 메시지에 넣지 않는다.
- 제목 보강에 실패하면 기존 역할/프로젝트 label을 유지한다. 큰 파일에는 현재 지원 제한임을 명시하며 파일 삭제/수정이나 강제 읽기를 권하지 않는다. 기존 전체 EOF/identity 확인 및 크기 한도를 유지한다.

남은 범위:

1. 이번 묶음은 진단 개선이며 큰 파일 읽기 지원을 구현한 것은 아니다. 제한된 tail/incremental reader와 변경·rename 처리 설계/구현이 남아 있다.
2. 실제 Windows 오류 분류, 취소 지연, 트레이 메시지 길이·접근성·현지화는 미검증이다. 취소된 전체 scan은 기존 scanner/runtime의 취소 처리로 결과가 폐기될 수 있다.
3. SQLite, 신규 추론 제목, source/profile 소유권과 전체 Windows 기능·배포 검증은 계속 미완료다.

다음 구현: 큰 파일 제목 읽기를 위한 bounded suffix 처리와 완전한 레코드 경계를 연결한다. 부분 데이터에서 발견되지 않은 제목을 확정하지 않는 정책을 유지한다.

## IMPL-015 — 큰 제목 파일의 bounded suffix 읽기

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 파일/프로세스/계정 조회·검증 스크립트는 실행하지 않았다. 계약: WIN-040/042.

작성한 코드:

- 공통 title reader에서1MiB보다 큰 파일은 같은 Windows handle의 SetFilePointerEx로 마지막1MiB 위치로 이동한다. 읽기 시작 offset의 Int64 변환을 확인하고, EOF까지 예상 suffix 길이와 전후 file identity를 유지한다. 작은 파일은 전체 읽기를 유지한다.
- suffix의 첫 줄은 UTF-8/JSON 중간 조각일 수 있으므로 첫 newline까지 항상 버린다. 이후 레코드에만 기존64KiB 행/JSON schema/UUID 검사를 적용한다. 시작점이 우연히 완전한 행 경계여도 첫 행은 보수적으로 버린다.
- title 결과에 unresolved UUID 집합을 추가했다. suffix에서 찾은 UUID는 마지막 제목을 사용하고, 빈 마지막 제목은 clear로 취급한다. 발견하지 못한 UUID는 제목 없음으로 확정하지 않고 범위 밖 미해결 안내와 기존 역할/프로젝트 fallback을 유지한다. Codex의 일부 UUID가 미해결이어도 발견한 다른 UUID 제목은 표시한다.
- CLI 도움말의 title index 읽기 범위를 갱신했다. PID focus ID/활동 시각, 기본 off Claude opt-in, source 설정과 개인정보 표시 정책은 유지한다.

남은 범위:

1. 전체 transcript 검색이나 증분 cache가 아니다. 제목이 마지막1MiB보다 앞에 있으면 미해결이다. suffix에64KiB 초과 행 또는 잘못된 JSON이 있으면 해당 읽기의 제목을 생략한다.
2. 파일 변경/동기 read 취소 지연, SetFilePointerEx/WinSDK signature 및 실제 Windows 동작은 미검증이다. EOF 레코드는 JSON 파싱에 성공해야 하며 전체 작업은 원자적 filesystem snapshot이 아니다.
3. SQLite fallback, 신규 추론 제목, source/profile 소유권, full Windows UI/플랫폼 및 배포 검증은 계속 미완료다.

다음 구현: 제목·파일 metadata의 세션별 출처 표시와 실제 source 설정 진단을 이어간다. 큰 파일의 cache/증분 처리 및 SQLite도 남은 필수 범위다.

## IMPL-016 — 세션별 metadata/title 출처 표시

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 source/계정/프로세스 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-010/040/041/042.

작성한 코드:

- AgentSession에 optional metadataMatch/metadataTitleSource 문자열을 추가했다. Windows scanner/correlator가 explicit_uuid, explicit_file, inferred_cwd_time 및 session_header/rollout_role/codex_title_index/claude_custom_title 출처를 성공 지점에서 기록한다. PID focus authority와 source/provider 필드는 바꾸지 않는다.
- 기존 Codable JSON 출력에 optional 출처를 전달한다. 필드가 없는 기존 데이터는 nil이며 문자열을 사용해 미래 source kind를 보존하도록 작성했다. 실제 구버전 클라이언트와 wire 호환성은 미검증이다.
- Windows 로컬/원격 행에 고정 출처 문구를 추가했다. 알 수 없는 값이나 nil은 표시하지 않고, 알려진 값만 사람이 읽는 문구로 바꾼다. 개인정보 숨김 상태에도 실제 경로·UUID·제목을 포함하지 않는 출처 종류만 표시한다.
- 제목 읽기 실패/기본 project fallback에는 제목 출처를 임의로 부여하지 않는다. 신규 추론은 행별로 Inferred metadata라고 명시한다. source 표시는 연결 방법이며 target profile 소유권 검증을 뜻하지 않는다.

남은 범위:

1. 원격 provenance는 원격 CLI가 선언한 정보다. 암호학적 소유권 증명이 아니며 포커스 권한 근거로 사용하지 않는다. 원격 긴 행은 기존 caption 길이 제한에 의해 잘릴 수 있다.
2. JSON 추가 필드와 기존 CLI 소비자 호환성, Win32 메뉴 폭/접근성/현지화/개인정보 표시 동작은 미검증이다.
3. 큰 파일 증분 cache, SQLite, 신규 추론 제목, source 설정 진단 및 Windows 전체 기능·실행/배포 검증은 남아 있다.

다음 구현: 세션 source 설정의 누락/비활성화 진단과 복구 경로를 보강한다. SQLite 및 나머지 Windows 기능 계약도 필수 범위로 유지한다.

## IMPL-017 — session source 설정 안내와 복구 메뉴

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 source/계정/프로세스 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-010/012/040/042.

작성한 코드:

- local session 메뉴에 설정 상태별 다음 조치 행을 추가했다. local 기능이 꺼져 있으면 활성화, metadata matching이 꺼져 있으면 matching 활성화를 안내하고 기존 toggle 명령에 연결한다. 자동 활성화하지 않는다.
- effective source를 GUI override 우선/환경변수 fallback/빈 override는 fallback 억제라는 기존 load 규칙으로 해석한다. Codex sessions/Claude projects 폴더 누락과 잘못된 absolute path, invalid title source를 해당 폴더 선택 명령으로 연결한다. Claude titles가 켜진 상태의 projects root 누락은 제목 전제 조건으로 설명한다.
- 메뉴 생성 시 파일 존재/내용/실계정 조회를 하지 않는다. path 형식 정규화만 사용하며 오류 행에 경로/계정 내용을 출력하지 않는다. 설정 변경 후 기존 scan 취소·보강 데이터 초기화 경로를 재사용한다.
- 폴더 override 해제 명령을 Use ... folder from environment로 바꿔 해제 후 환경변수로 복귀한다는 동작을 분명히 했다.

남은 범위:

1. 형식상 유효한 경로의 존재·권한·실제 source 소유권은 이 설정 안내가 확인하지 않는다. 실제 reader 오류 안내와 구분한다.
2. GUI 행 중복/메뉴 높이·DPI·접근성·현지화와 클릭 동작은 미검증이다. 제목 source가 있어도 UUID/cwd 매칭 조건은 여전히 필요하다.
3. SQLite, 증분 cache, 신규 추론 제목 및 나머지 Windows 기능·실행/배포 검증은 미완료다.

다음 구현: session 메뉴의 설정/진단 행을 별도 submenu로 정리하여 세션 탐색 공간을 확보하고 기존 명령·설정 의미를 보존한다.

## IMPL-018 — 로컬 session 설정·source 하위 메뉴

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 계정/프로세스/source 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-010/012/040.

작성한 코드:

- local session의 native cwd, metadata/title/inference 옵션, source 선택·복귀·비활성화, source 설정 안내를 Session settings and sources 하위 메뉴로 이동했다. 최상위 local 목록에는 활성화·설정 진입·새로고침·조회 상태·세션 행·페이지 이동을 유지한다.
- 기존 command ID와 dispatch, defaults 키 및 설정 변경 처리 경로를 재사용한다. local 기능이 꺼져 있어도 설정 하위 메뉴에 접근할 수 있다.
- 설정 child menu를 별도 helper에서 생성한다. 부착 전 실패하면 child를 정리하고, 부착 성공 후에는 parent의 DestroyMenu 수명에 맡긴다. parent 생성 실패 경로의 기존 page command 정리를 유지한다.
- 제목 source privacy 값을 helper 내 defaults에서 읽도록 명시했다. 이동 전 함수에는 해당 지역 값 선언이 없어 이번 소스 편집에서 함께 보완했다. UI/컴파일 검증을 수행한 것은 아니다.

남은 범위:

1. 실제 Win32 메뉴 수명·키보드 탐색·화면 배치·고DPI·접근성·현지화는 미검증이다. 동적 명령/페이지/scan 취소 동작도 실행하지 않았다.
2. 조회 상태 메시지는 목록에 남으며 긴 진단 문구의 별도 상세 UI는 미구현이다. SQLite, 증분 cache 및 나머지 Windows 기능·배포 검증도 남아 있다.

다음 구현: session 조회 상태를 간단한 목록 요약과 별도 상세 안내로 나누어 긴 오류 문구가 세션 목록을 가리지 않게 연결한다.

## IMPL-019 — 짧은 세션 상태와 snapshot 상세 보기

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 계정/source/프로세스 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-010/040.

작성한 코드:

- 로컬 세션 상태 행을 최대90 Unicode scalar 요약으로 표시하고 생략 표시를 붙인다. 전체 메시지는 Session status details 명령에서 native MessageBox로 읽도록 연결했다.
- 상세 텍스트는 메뉴 생성 snapshot을 보관하며 메뉴가 열린 시점의 상태임을 안내한다. 조회를 새로 실행하거나 현재 mailbox 상태로 바꿔치기하지 않는다. 최대8192 scalar와 제어문자 제거를 적용하고 제한 초과는 표시한다.
- 부착에 성공한 메뉴만 상세 값을 게시한다. popup 종료/취소/커서 조회 실패/종료의 기존 command cleanup에서 함께 제거한다. 상세 창 진입 전 값을 소비하고 기존 modal/quit/editor 상태 경계를 사용한다.
- 원본 상태 메시지는 현재 runtime/scanner가 작성한 로컬 안내다. 세션 제목/경로/대화 본문을 상세 텍스트로 조립하지 않는다. 메뉴 요약에는 ampersand escaping을 적용한다.

남은 범위:

1. 원격 상세 보기, 구조화된 상태 severity와 필터, 긴 메시지용 스크롤 dialog는 미구현이다. MessageBox 표시/키보드/접근성·DPI 및 nested message loop 동작은 미검증이다.
2. 요약은 의미 재분류가 아닌 길이 제한이다. 같은 snapshot의 텍스트를 보여주며 실제 최신 조회 성공을 증명하지 않는다.
3. SQLite, 증분 cache와 전체 Windows 기능·실행/배포 검증은 남아 있다.

다음 구현: 원격 session 상태에도 snapshot 상세 보기와 host별 경계를 연결한다. source별 데이터 소유권과 기존 focus generation을 유지한다.

## IMPL-020 — 원격 host snapshot 상세 보기

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·원격 실행·실제 계정/source 조회·검증 스크립트는 실행하지 않았다. 계약: WIN-010/041.

작성한 코드:

- 원격 runtime의 host 상태 행에 optional statusDetails를 추가했다. host 표시명, 조회 대기/실패/성공 상태, 마지막 성공 UTC 시각, 저장된 세션 수와 다음 조치를 snapshot에서 구성한다. hidePersonalInfo가 켜져 있으면 기존 Remote host N 표기를 사용한다.
- 호스트 상태 행은 상세 보기로 선택 가능하게 하고 session focus request와 별도 map으로 분리했다. 실패한 host의 cached session 행은 기존대로 focus 비활성 상태다. 상세 조회 자체는 네트워크/원격 명령을 실행하지 않는다.
- 로컬 상태 dialog helper를 재사용한다. popup 부착 성공 시 상세 map을 게시하고 클릭 시 먼저 소비하며, popup 종료/실패/앱 종료 정리에서 제거한다. 열린 메뉴의 snapshot을 표시한다는 안내를 유지한다.
- raw remote error/stderr/세션 제목·경로·대화 내용은 상세 텍스트에 넣지 않는다. 표시 host는 제어문자 제거와160 scalar 제한을 적용한다.

남은 범위:

1. 상세는 현재 페이지에 host 상태 행이 있을 때 진입 가능하다. 페이지 중간의 세션에서 host 상세로 바로 이동하는 경로, 구조화된 오류 코드와 긴 메시지 스크롤 UI는 미구현이다.
2. 실제 native dialog·modal lifetime·키보드/접근성·개인정보 표시·원격 상태 정확성은 미검증이다. snapshot의 last-success는 실시간 연결 보증이 아니다.
3. SQLite, 증분 cache 및 전체 Windows 기능·실행/배포 검증은 계속 미완료다.

다음 구현: 원격 host 상태와 세션 페이지 사이의 탐색을 보강하고, session slice 이후 SQLite/title source의 남은 구현을 이어간다.

## IMPL-021 — 원격 session 연속 페이지의 host 상세

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·원격 실행·실제 source/계정 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-010/041.

작성한 코드:

- 원격 페이지가 한 host의 session 목록 중간에서 시작하면 해당 host 상태 행을 Continued 표시로 다시 제공한다. 이전 페이지로 돌아가지 않고 기존 상세 dialog에 접근할 수 있다.
- 상세 snapshot에 해당 페이지에서 보이는 host session의1-based 범위를 추가했다. host header만 페이지 마지막에 있고 session은 다음 페이지에 있는 경우 None on this page로 표시한다.
- 반복 header는 표시용 문맥 행이며 전체 항목 수/offset/page range에는 더하지 않는다. 원래32개 항목 페이지당 최대1개 문맥 행이 추가될 수 있다. 기존 실제 session focus request와 host 상세 map을 재사용하고 조회를 추가 실행하지 않는다.

남은 범위:

1. host가 아주 많을 때의 직접 검색/점프, 전체 페이지 navigation UI와 메뉴33행 표시·DPI/접근성은 미검증이다. focus generation과 snapshot 상세 동작도 실행하지 않았다.
2. SQLite title fallback, 증분 cache, source 소유권과 전체 Windows 기능·배포 검증은 남아 있다.

다음 구현: 명시적으로 지정한 SQLite title source를 Codex의 매칭된 UUID에 한정하여 연결하는 경로를 구현한다. index 제목 우선과 source 경계를 보존한다.

## IMPL-022 — 명시적 Codex SQLite title fallback

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 DB/계정/source 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-040/042.

작성한 코드:

- CLI --codex-title-database 및 앱 환경변수 CODEXBAR_WINDOWS_CODEX_TITLE_DATABASE로 선언한 absolute DB 경로만 사용한다. 자동 HOME/profile/DB version 탐색을 추가하지 않는다. roots snapshot에 포함하므로 GUI runtime도 환경 source 변경 비교 경로를 사용한다.
- declared root/cwd/explicit UUID로 이미 매칭된 Codex 세션만 조회한다. index가 미설정이거나 완전히 읽은 범위에서 해당 UUID 기록이 없을 때만 DB fallback한다. index 이름·명시적 빈 rename·범위 밖 미해결·읽기 실패는 DB로 덮어쓰지 않는다.
- 기존 SQLite 모듈이 있을 때 READONLY open, busy timeout0, SQL length limit64KiB, progress callback/deadline/cancel을 사용한다. UUID를 바인딩하고 title만 읽으며 duplicate UUID row는 거부한다. 경로 기반 전후 file metadata 비교를 유지하고 DB 제목 출처를 표시한다. 모듈이 없으면 안내와 기존 label fallback이다.

남은 범위:

1. Windows SQLite 모듈 배포/링크 및 WinSDK·SQLite signature/실행은 미검증이다. GUI 파일 선택·source 표시/해제 UI, agent_path DB 보강은 미구현이다.
2. SQLite는 별도 경로 open이므로 사전 Win32 handle과 동일 open을 보장하는 custom VFS가 아니다. ancestor junction/path race, WAL/shared-memory 동작과 DB snapshot·source 소유권은 추가 구현/검증 범위다. read-only는 SQL connection의 쓰기 금지이며 SQLite sidecar OS 동작 전체를 증명하지 않는다.
3. 동기 SQLite open/prepare와 OS I/O를 deadline이 강제로 중단하는 것은 아니다. progress callback과 행 사이 예산을 갖지만 실제 취소 지연은 미검증이다.
4. 증분 cache, 신규 추론 제목, 전체 Windows 기능/배포 검증은 남아 있다.

다음 구현: SQLite title source의 GUI 선택·해제/표시 및 읽기 실패 복구 안내를 연결한다. DB ownership와 Windows 검증은 별도 미완료로 유지한다.

## IMPL-023 — GUI SQLite title source controls

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 DB/source/계정 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-010/012/040/042.

작성한 코드:

- 기존 Shell browse picker에 파일 표시 옵션을 추가했다. SQLite source 선택은 absolute .sqlite/.db 파일을 대상으로 하며 실행 시 파일 attribute로 directory/reparse를 거부하도록 작성했다. 선택 실패/취소는 이전 설정을 유지하고 DB 내용 자체를 picker에서 읽지 않는다.
- settings submenu에 SQLite 선택·비활성화·환경 설정 복귀와 현재 source 표시를 연결했다. 빈 override는 환경변수 fallback을 억제하고 removeObject는 복귀한다. title source 표시 helper를 공유하며 개인정보 숨김 시 path를 표시하지 않는다.
- runtime roots load에 GUI SQLite override를 전달해 기존 설정 snapshot 비교·scan 취소·보강 결과 초기화 경로에 포함했다. invalid absolute DB 설정은 기존 선택 명령으로 복구하도록 안내한다.

남은 범위:

1. 기존 Shell picker의260자 API 경계가 유지된다. 현대적 long-path 파일 dialog와 임의 확장자 파일 선택은 미구현이다. CLI/환경 경로는 별도 제한을 따른다.
2. picker attribute 확인은 source 소유권/DB 형식/쿼리 가능성 증명이 아니다. 실제 Shell picker, callback 수명, Windows SQLite 배포/링크·WAL·path race·취소 지연 및 UI는 미검증이다.
3. 증분 cache, DB agent_path, 신규 추론 제목과 전체 Windows 기능·배포 검증은 남아 있다.

다음 구현: SQLite title source의 오류 원인을 구분해 사용자 설정 복구와 모듈 부재/잠금/형식/시간 초과를 다르게 안내한다.

## IMPL-024 — SQLite title 실패 원인별 안내

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 DB/source 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-010/040/042.

작성한 코드:

- SQLite title 실패를 module 부재, read-only 접근, busy/locked, query/schema, invalid DB, resource limit, duplicate UUID, interruption, 기타 query 실패로 나누었다. extended code는 기본 code로 분류하며 현재 취소/시간 초과를 우선한다.
- open/prepare/bind/step 결과를 해당 안내로 전달한다. missing module이면 index 사용/지원 build, busy이면 나중 refresh, invalid source이면 source 선택을 안내한다. raw sqlite errmsg/path/title을 출력하거나 DB repair/lock 우회를 실행하지 않는다.
- prepare 실패 시에도 반환된 statement가 있으면 finalize하도록 defer 수명을 보완했다. 한 UUID의 두 번째 row는 일반 query 오류와 별도로 ambiguous title로 처리한다. 기존 label fallback과 read-only/budget 정책을 유지한다.

남은 범위:

1. SQLite 기본 code만으로 구체적인 filesystem/ACL/DB version 원인을 확정할 수 없다. 실제 code mapping·Windows 모듈/링크·WAL/취소 동작은 미검증이다.
2. 증분 cache, DB agent_path 및 신규 추론 제목, 전체 Windows 기능·배포 검증은 계속 미완료다.

다음 구현: Codex DB의 agent_path 보강을 기존 rollout 역할과 title 우선순위에 맞춰 연결한다. SQLite/path ownership의 미검증 경계는 유지한다.

## IMPL-025 — Codex SQLite agent_path 역할 보강

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 DB/source 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-040/042.

작성한 코드:

- DB reader 결과를 title 문자열에서 CodexThreadMetadata로 확장했다. title과 agent_path를 조회하고 원본 descriptiveName 조합에 전달한다. guardian 이름 우선, DB agent_path와 rollout 역할 fallback 규칙은 원본 helper를 따른다.
- agent_path가 없는 이전 스키마를 위해 prepare의 SQLITE_ERROR일 때 title/NULL shape로 한 번 재시도한다. 실패 statement를 finalize하고 deadline·기존 readonly/row/length 제한을 유지한다. 재시도도 실패하면 기존 typed 진단으로 전달한다.
- agent_path는 비어 있거나 control character를 포함하거나4096 UTF-8 bytes를 넘으면 채택하지 않는다. 제목이 없고 DB 역할로 이름을 만든 경우 database role 출처로 표시한다.
- DB 보강 대상은 기존 databaseIDs에 한정한다. index 제목·명시적 clear·미해결/실패의 DB 대체 금지는 유지한다. 따라서 index 제목이 있는 세션에 DB 역할만 별도로 조회하는 확장은 이번 범위에 없다.

남은 범위:

1. SQLite schema fallback, 문자열 encoding·역할 formatter·provenance와 Windows 실행은 미검증이다. SQLITE_ERROR는 missing-column만 의미하지 않으므로 재시도 성공 여부로만 fallback을 처리한다.
2. index title+DB role 조합의 별도 provenance 정책, 증분 cache·신규 추론 제목, DB ownership/WAL·전체 Windows 기능/배포 검증은 남아 있다.

다음 구현: session metadata 읽기 예산을 제목 보강과 기본 세션 매칭 사이에서 분리하여 선택적 제목 조회가 다른 세션의 기본 연결을 방해하지 않도록 한다.

## IMPL-026 — 기본 매칭과 선택적 제목 예산 분리

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 source/DB 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-040/042.

작성한 코드:

- Claude 기본 UUID 매칭 중에는 file identity와 후속 title 작업 정보만 수집한다. 전체 기본 매칭 및 신규 추론을 마친 후 title 작업을 수행하도록 순서를 변경했다.
- title 추가 예산은 min(directoryScanBudget,0.25초)의 절반씩 Claude/Codex에 배정한다. 각 provider lane 시작 시 deadline을 만들고 Claude 여러 파일은 하나의 lane을 공유한다. Codex index/DB도 하나의 lane을 공유한다. 기본 매칭 entry/time budget은 기존값을 유지한다.
- Claude title을 늦게 읽는 만큼 저장된 base file identity와 최신 pathname identity를 계속 비교한다. 취소/시간 소진 시 Claude title loop를 끝내며 기본 행을 버리지 않는다. caller의 전체 scan 취소 정책은 유지한다.
- 소스 편집 중 발견한 DB 후보 계산 위치 오류를 함께 수정했다. databaseIDs/ids 계산이 Claude 분기에 들어가 있던 코드를 제거하고 Codex index 성공 뒤로 이동했다. 이 변경으로 선언 범위와 index seen/unresolved 제외 의도를 맞췄으며 컴파일 검증을 수행한 것은 아니다.

남은 범위:

1. 추가 title 예산으로 메타데이터 처리의 명목상 최대 시간이 기본1초+title0.25초가 될 수 있다. 동기 OS/SQLite I/O 강제 중단을 보장하지 않으며 실제 지연/성능은 미측정이다.
2. 같은 provider 내 여러 파일의 공정성/증분 cache 및 SQLite snapshot/소유권은 미완료다. Windows 빌드·실행·배포 검증도 남아 있다.

다음 구현: 제목 읽기에서 개별 Claude 파일이 provider 예산을 모두 소비하지 않도록 파일별 상한과 건너뛴 작업 안내를 연결한다.

## IMPL-027 — Claude 파일별 title 예산과 미시도 안내

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 파일/계정 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-040/042.

작성한 코드:

- Claude title lane의 남은 시간을 남은 파일 수로 나누어 개별 deadline을 배정하며 파일당 최대50ms로 제한한다. 파일 시작 전에 provider deadline/cancel을 확인하고 마지막 pathname 비교 뒤에도 파일 deadline을 확인한다.
- 파일별 시간 초과 횟수와 provider 예산 종료로 아예 시도하지 못한 파일 수를 구분해 안내한다. 기타 title 실패는 기존 원인별 중복 제거를 유지한다. 제목 실패/미시도는 기본 session 행·focus identity를 바꾸지 않는다.
- 전체 scan이 취소되면 미시도 예산 안내를 추가하지 않고 caller의 기존 취소 처리를 따른다. Codex 독립 title 예산과 기본 매칭 순서는 유지한다.

남은 범위:

1. 시간 분배는 시도 기회를 나누는 정책이며 모든 파일의 성공을 보장하지 않는다. 다수 파일이면 개별 시간이 짧아져 제목이 생략될 수 있다. 고정 순서·반복 실패의 장기 공정성과 증분 cache는 미완료다.
2. 동기 ReadFile이 deadline 내 반환함을 보장하지 않으며 실제 Windows 지연/성능·표시 동작은 미검증이다. SQLite/WAL·소유권 및 전체 기능/배포 검증은 남아 있다.

다음 구현: session metadata 구현에서 남은 증분 cache를 bounded 상태로 도입하고, 파일 변경·source 설정 변경 시 무효화 규칙을 연결한다.
