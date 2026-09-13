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

## IMPL-028 — bounded title cache와 source 무효화

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 source/계정 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-040/042.

작성한 코드:

- runtime 소유 WindowsSessionTitleCache를 추가했다. 메모리만 사용하며64 entries/120초 TTL/8192-byte key/64 UUID 결과 한도를 두고 오래된 저장 항목부터 제거한다. NSLock으로 entry 접근을 보호한다.
- JSONL title reader는 provider/path/requested UUID 집합별로 완료된 names/seen/unresolved를 보관한다. 캐시 hit에도 파일을 열어 volume/file ID/size/creation/mtime과 pathname/retained handle identity를 비교하고 deadline을 확인한다. 오류/미완료 읽기는 캐시하지 않는다.
- runtime 설정 세대 변경과 roots 변경 시 cache 인스턴스를 교체한다. 이전 scan은 이전 인스턴스만 캡처하므로 늦은 작업이 새 source cache를 채우지 않는다. CLI 기본 호출은 cache nil이며 SQLite 결과는 캐시 대상에서 제외한다.

남은 범위:

1. 변경 없는 JSONL의 재파싱 회피이며 append-only 증분 파서는 아니다. file metadata가 바뀌면 suffix를 다시 읽는다. 같은 file identity/size/time을 의도적으로 보존한 내용 변경은 content hash 없이 감지하지 못할 수 있다.
2. TTL은 재사용 제한이며 background 메모리 청소 timer는 없다. 인스턴스 교체/용량 eviction으로 정리하고 process 종료 시 소멸한다. 실제 lock/actor/cancel 수명과 성능·메모리·Windows 동작은 미검증이다.
3. SQLite snapshot/WAL·source 소유권, 신규 추론 제목 및 전체 Windows 기능·배포 검증은 남아 있다.

다음 구현: session metadata의 캐시 사용 상태와 수동 새로고침 시 캐시 우회 경로를 연결한다. 기능 완료나 성능 개선을 측정 결과처럼 보고하지 않는다.

## IMPL-029 — 수동 새로고침 title cache 우회

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 source/계정 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-010/040/042.

작성한 코드:

- local session 수동 refresh callback을 refreshIgnoringTitleCache에 연결했다. 새 cache 인스턴스와 generation을 만들고 기존 scan/focus를 취소하며 이전 보강 행을 비운다. 진행 중 scan이 있으면 기존 queued/deferred 경로로 drain 후 교체 scan을 시작한다.
- 기존 주기적/메뉴 열기 refresh는 캐시 재사용 경로를 유지한다. 수동 명령 caption에 clear title cache를 명시했다. source 파일이나 SQLite DB를 변경하지 않는다.
- 성공/partial 상태에 메모리 cache 저장 entry 수와 수동 refresh의 효과를 추가했다. thread-safe count getter만 사용하며 hit rate/성능/검증 성공률로 해석하지 않는다. 만료됐으나 아직 접근하지 않은 항목도 저장 수에 포함될 수 있다.

남은 범위:

1. 반복 수동 요청과 queued scan/focus cancellation·actor 수명 및 Windows UI 동작은 미검증이다. cache를 비운 뒤에도 byte/time budget에 따라 제목이 미해결일 수 있다.
2. 증분 parsing·장기 공정성, SQLite snapshot/소유권 및 전체 Windows 기능·배포 검증은 남아 있다.

다음 구현: session 조회의 source별 처리량·미해결 정보를 데이터 모델로 분리해 현재 문자열 진단을 구조화한다. 전체 기능 완료와는 별도로 추적한다.

## IMPL-030 — 구조화된 provider session 진단 집계

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 source/프로세스 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-010/040/042.

작성한 코드:

- WindowsSessionDiagnostics 및 ProviderCounts Codable/Sendable 모델을 추가했다. 반환된 row만 대상으로 provider별 총수/cwd 보유/explicit metadata/inferred metadata/분류된 metadata 없음/이름 보유 수와 partial 여부를 집계한다. identity/path/title/error text는 저장하지 않는다.
- scan outcome에 diagnostics projection을 연결했다. complete/partial 결과만 반환하고 failed/cancelled는 nil이다. 실패를0개 성공 조회처럼 표현하지 않는다.
- Windows runtime은 구조화된 집계를 상태 요약/기존 상세 창에 설명 문구로 연결한다. 수치는 시스템 전체 process count나 source 소유권 검증률이 아니라 반환된 행 범위임을 명시한다. unknown/nil provenance는 실패 건수로 단정하지 않고 without classified metadata로 구분한다.

남은 범위:

1. source별 실제 시도/오류 code/소요시간/캐시 hit 통계 전체를 모델로 옮긴 것은 아니다. 현재 집계는 최종 반환 row의 projection이다. CLI의 기존 session JSON shape는 이번에 바꾸지 않았다.
2. 모델 합계·직렬화·UI 표시·partial 처리와 Windows 실행은 미검증이다. 증분 parsing, SQLite ownership, 나머지 Windows 기능/배포 검증은 남아 있다.

다음 구현: 구조화 진단을 CLI의 명시적 옵션으로 제공하되 기존 session JSON 소비자의 배열 계약을 유지한다.

## IMPL-031 — CLI diagnostics JSON opt-in

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·CLI 실행·실제 source 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-040/042.

작성한 코드:

- Windows sessions에 --diagnostics-json 옵션을 추가했다. schemaVersion1, scope=returned_session_rows, complete/partial/failed/cancelled status와 optional provider 집계만 출력한다. session 목록/identity/path/title/raw error는 포함하지 않는다.
- --json/--json-v2와 혼용하면 조회 전에 exit64로 거부한다. --pretty를 지원하고 기존 배열 출력/표/focus 명령의 경로는 유지한다. 공통 Windows outcome helper로 source 옵션 load와 실제 scan을 한 번만 수행하도록 구성했다.
- complete/partial은 JSON status를 출력하고 exit0, failed/cancelled는 집계 없이 status를 출력하고 exit1로 처리한다. 잘못된 옵션/absolute path 설정은 기존 stderr+exit64이며 diagnostics envelope를 보장하지 않는다.

남은 범위:

1. Commander option binding, JSON 직렬화/exit code와 실제 Windows CLI는 미검증이다. partial 집계는 반환된 행이며 시스템 전체 발견률/성공률이 아니다.
2. source별 attempt/error code metrics, 증분 parsing, SQLite ownership 및 전체 Windows 기능·배포 검증은 남아 있다.

다음 구현: session 기능 작업 기록을 정리하고 전체 계획의 다음 미구현 Windows 플랫폼 계약으로 넘어간다. 기존 세션의 미검증/미구현 경계는 그대로 추적한다.

## IMPL-032 — 전역 트레이 메뉴 단축키

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 키 등록/키 입력·검증 스크립트를 실행하지 않았다. 계약: WIN-011.

작성한 코드:

- Windows tray에 기본 off인 Ctrl+Alt+C 메뉴 단축키 설정을 추가했다. native RegisterHotKey/MOD_NOREPEAT와 WM_HOTKEY를 연결하고 앱 시작 시 저장 설정을 복원한다. 등록 실패는 체크 표시를 하지 않고 재시도 caption으로 표시한다.
- 새 활성화 설정은 등록 성공 후에만 저장한다. 비활성화는 unregister 성공 후 저장하고 종료 정리에서 등록된 hotkey를 해제한다. 다른 앱의 hotkey를 빼앗거나 대체 키를 자동 등록하지 않는다.
- popupIsOpen으로 재진입을 막고 hotkey가 열린 메뉴에 다시 전달되면 EndMenu를 요청한다. modal editor/quit 상태에서는 처리하지 않는다. 기존 popup의 메뉴 snapshot·focus/refresh 동작을 재사용한다.

남은 범위:

1. 사용자 지정 shortcut editor, 키 충돌 원인 상세·해제 실패 안내, 다중 모니터/DPI anchor, keyboard/scroll/focus 복원은 미구현 또는 미검증이다. 현재 popup 위치는 기존 커서 위치를 따른다.
2. native menu loop에서 WM_HOTKEY 전달과 EndMenu 동작, Register/Unregister 실패·종료 수명·AltGr/키보드 layout은 Windows 실행 검증이 필요하다. 전체 WIN-011 완료로 표시하지 않는다.
3. 기존 session cache/SQLite/ownership 및 전체 Windows 기능·배포 검증은 계속 남아 있다.

다음 구현: 전역 단축키 설정을 저장 가능한 modifier/key 모델과 사용자 선택 메뉴로 확장하며 등록 변경 실패 시 이전 등록을 보존한다.

## IMPL-033 — 전역 단축키 preset 선택과 등록 교체

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 hotkey 등록/입력·검증 스크립트는 실행하지 않았다. 계약: WIN-011/012.

작성한 코드:

- WindowsMenuShortcut 모델에 Ctrl+Alt+C/Ctrl+Shift+C/Ctrl+Alt+B/Ctrl+Shift+B 네 preset을 정의하고 저장/복원을 연결했다. 알 수 없는 저장값은 기존 Ctrl+Alt+C 기본값으로 해석한다. 활성화와 조합 선택은 별도 메뉴이며 비활성 상태에서 선택해도 자동 활성화하지 않는다.
- 활성 조합 변경은 다른 hotkey ID로 후보를 먼저 등록한다. 새 등록 실패는 이전 상태를 보존한다. 기존 해제 실패 시 후보 해제를 시도하며 성공 전에는 설정을 저장하지 않는다. 정리 실패 후보 ID도 owned set에 남겨 종료 시 재해제한다. handler는 active ID만 처리한다.
- 메뉴에 활성 여부·선택 조합·실패 안내를 표시한다. 하위 메뉴 부착 실패 시 미부착 handle을 정리한다. 기존 popup/quit/editor 경계를 유지한다.

남은 범위:

1. 임의 키 capture editor가 아닌 네 preset 범위다. 예약키/AltGr/layout, 변경·rollback/종료 cleanup·키 전달·DPI/접근성은 미검증이다.
2. unregister가 반복 실패한 비활성 후보는 종료까지 OS 예약이 남을 수 있다. 앱 handler는 무시하지만 사용자 알림/재시도 정리 UI는 후속 범위다. OS failure를 원자적 rollback 성공으로 주장하지 않는다.
3. 전체 WIN-011/012와 기존 session/SQLite·Windows 배포 검증은 미완료다.

다음 구현: hotkey 등록/해제 오류 상태와 rollback 잔여 등록 정리를 명시적으로 표시하고 재시도 경로를 연결한다.

## IMPL-034 — hotkey 실패 단계와 잔여 등록 정리

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 키 등록/입력·검증 스크립트는 실행하지 않았다. 계약: WIN-011/012.

작성한 코드:

- 등록·새 조합 등록·이전 등록 해제·후보 rollback·비활성화 실패를 다른 문구로 표시한다. 가능한 지점에서는 즉시 Win32 error code를 보관해 단계와 함께 안내한다. 실제 충돌 원인을 단정하지 않는다.
- inactive owned registration 수와 cleanup 재시도 명령을 추가했다. 현재 활성 ID를 제외하고 해제를 시도하며 실패 항목은 set에 남긴다. disable 실패는 기존 active 설정/체크를 유지하고 안내한다.
- 새 등록/조합 교체 전에 inactive 정리를 시도한다. 비활성 상태에서 잔여 등록이 정리되지 않으면 새 활성화/설정 변경을 중단해 예약된 키와 저장 설정의 불일치를 늘리지 않는다.

남은 범위:

1. native unregister가 계속 실패하면 예약이 종료까지 남을 수 있다. 재시도/종료 안내를 제공하며 원자적 OS rollback을 보장하지 않는다. 실제 실패 주입/입력/수명/UI 동작은 미검증이다.
2. 임의 shortcut capture, 다중 모니터 anchor·focus/scroll 복원과 전체 Windows 기능/배포 검증은 남아 있다.

다음 구현: 전역 단축키로 열린 트레이 메뉴를 현재 포커스 창의 모니터 작업 영역에 맞춰 배치하는 경로를 추가한다.

## IMPL-035 — keyboard popup의 foreground monitor 배치

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 모니터/키 입력·검증 스크립트를 실행하지 않았다. 계약: WIN-011.

작성한 코드:

- hotkey로 popup을 열 때 hidden tray owner 활성화 전에 foreground window monitor의 작업 영역을 읽고 우하단 안쪽 anchor를 만든다. monitor 정보 실패는 primary work area, 그것도 실패하면 기존 cursor 좌표로 fallback한다.
- keyboard anchor는 right/bottom alignment로 TrackPopupMenu에 전달한다. mouse 경로는 기존 cursor/정렬을 유지한다. 페이지 재열기는 keyboard anchor를 보존하며 가까운 monitor work area로 다시 clamp한다.
- 좌표는 기존 Win32 화면 좌표 체계를 그대로 사용하고 DPI 배율을 중복 적용하지 않는다. menu 크기/overflow 배치는 native menu에 맡긴다.

남은 범위:

1. 실제 다중 모니터/음수 좌표/혼합 DPI/작업표시줄 위치·해상도 변경과 Win32 menu 배치는 미검증이다. monitor 정보가 모두 실패한 경우 fallback cursor가 화면 안인지 추가 확인하지 않는다.
2. 키보드 focus/scroll 복원, 임의 shortcut capture·접근성 및 전체 Windows 기능/배포 검증은 남아 있다.

다음 구현: keyboard popup 취소 시 원래 foreground window로 포커스를 돌리는 경로를 제한적으로 연결하되 다른 창으로 의도적으로 이동한 상태를 덮어쓰지 않는다.

## IMPL-036 — keyboard popup 취소 포커스 복원

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 foreground/key 입력·검증 스크립트를 실행하지 않았다. 계약: WIN-011.

작성한 코드:

- hotkey popup 시작 시 현재 foreground HWND/process ID/thread ID를 기록한다. 마우스 진입은 기록하지 않고 페이지 재열기는 기존 복원 대상을 유지한다.
- 메뉴가 명령 선택 없이 끝났거나 좌표를 얻지 못해 중단되면, foreground가 여전히 tray owner인 경우에만 복원을 시도한다. 대상의 visible/enabled/non-minimized 상태와 process/thread identity가 유지되는지도 확인한다.
- 다른 창이 foreground이면 복원하지 않는다. session focus/설정 등 명령 선택 후에는 원래 창으로 돌리지 않는다. 페이지 명령 외 popup 종료 시 기록을 제거한다.
- SetForegroundWindow를 한 번 요청하는 best-effort 동작이며 input queue 연결·최소화 복원·반복 강제 포커스를 추가하지 않는다.

남은 범위:

1. HWND/process/thread 확인은 동일 thread 내 HWND 재사용을 완전히 식별하지 못한다. 포커스 판단과 호출 사이 race 및 Windows foreground 제한도 남아 있다. 실제 UI/key 입력·취소/페이지/Alt-Tab 동작은 미검증이다.
2. 중간 페이지 요청이 거부된 경우 복원 기록은 다음 새 진입에서 초기화된다. 메뉴 scroll/선택 복원·임의 shortcut editor와 전체 Windows 기능/배포 검증은 미완료다.

다음 구현: 키보드로 열린 메뉴의 초기 선택과 navigation 접근성을 보강한다. native 동작 검증은 사용자 승인 후 별도 진행한다.

## IMPL-037 — keyboard menu 초기 navigation과 mnemonic

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 키 입력·검증 스크립트를 실행하지 않았다. 계약: WIN-011.

작성한 코드:

- 키보드 popup의 local session submenu 위치를 메뉴 생성 시 기록하고 WM_INITMENUPOPUP에서 유효한 enabled submenu인 경우 한 번 highlight하도록 연결했다. command 실행/키 입력 주입은 하지 않는다. callback 전후 HMENU/position state를 지우고 파괴된 menu를 보관하지 않는다.
- Local/Remote/shortcut/Refresh/Quit의 정적 caption에 native mnemonic을 추가했다. 동적 session/provider 문자열의 기존 ampersand escaping은 유지한다. 선택 메뉴가 생성되지 않았으면 강제 초기 선택을 하지 않는다.

남은 범위:

1. HiliteMenuItem의 native tracking loop 초기 선택 동작과 screen reader/키보드 navigation은 미검증이다. 초기 highlight가 모든 Windows 환경에서 focus 이동을 보장하지 않는다.
2. 전체 메뉴 mnemonic 충돌/현지화·scroll/마지막 선택 복원·임의 shortcut capture와 전체 Windows 기능/배포 검증은 남아 있다.

다음 구현: 임의 shortcut 선택의 범위를 넓히되 예약 조합과 modifier 저장 모델을 명시적으로 다루는 설정 경로를 구현한다.

## IMPL-038 — modifier/key 모델과 확장 shortcut 선택

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 키 등록/입력·검증 스크립트를 실행하지 않았다. 계약: WIN-011/012.

작성한 코드:

- shortcut enum을 modifier/key 값 모델로 바꾸고 Ctrl+Alt 또는 Ctrl+Shift와 A–Z/0–9의72개 조합을 제공한다. failable initializer로 허용 범위를 검사하며 bare modifier/Win key/function/system key를 임의 채택하지 않는다.
- 저장값은 v1:modifier:key 형식이며 기존 네 preset 문자열을 계속 읽는다. 알 수 없는 값은 기존 기본값으로 해석한다. 선택 시 기존 staged registration/실패 보존 경로를 재사용한다.
- 선택 메뉴는 modifier별 A–M/N–Z/0–9 하위 메뉴로 나눠 그룹 최대13개 행으로 제한한다. 확장 command range는0x7900부터 사용해 기존 cleanup/local/remote 명령 범위와 분리한다. 부착 실패 그룹을 정리한다.

남은 범위:

1. 실제 키 capture editor와 모든 Windows virtual key 지원은 아니다. 모든72개 조합이 OS/다른 앱에서 비어 있다는 보장도 없다. 실제 등록 충돌/AltGr/layout/메뉴 keyboard 접근성은 미검증이다.
2. legacy/versioned 저장값과 command dispatch, group menu 수명은 미검증이며 전체 WIN-011/012·Windows 배포 완료로 표시하지 않는다.

다음 구현: 저장된 shortcut 값이 유효하지 않을 때 조용한 기본값 복귀 대신 비활성화와 명시적 재선택 안내를 연결한다.

## IMPL-039 — invalid shortcut 저장값 등록 차단

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 키 등록/입력·검증 스크립트를 실행하지 않았다. 계약: WIN-011/012/013.

작성한 코드:

- shortcut loader를 optional로 바꿔 미설정만 첫 실행 기본값을 사용한다. 존재하는 비문자열·잘못된 형식/범위·128-byte 초과 값은 nil로 처리한다. 기존 legacy 네 문자열은 계속 읽는다.
- invalid 저장값은 새 native 등록을 하지 않으며 활성화 저장 flag를 false로 바꾼다. 원래 잘못된 문자열은 사용자가 재선택하기 전까지 보존하고 이유를 메뉴에 표시한다. 등록이 없는 경우 활성화 항목은 재선택 전까지 비활성이다.
- invalid 값에서 새 조합을 선택해도 자동 활성화하지 않는다. 이미 실행 중인 유효 등록이 있고 외부에서 저장값만 바뀐 경우 현재 등록을 무조건 해제하지 않고, 메뉴에 현재 등록 유지 상태를 구분한다. 기존 active 교체 실패 보존 정책을 유지한다.

남은 범위:

1. defaults 외부 변경 즉시 관찰/등록 재조정은 미구현이다. 현재 load 시점의 상태로 대응하며 native 등록 상태와 저장값을 항상 실시간 동기화한다고 주장하지 않는다.
2. 잘못된 설정 복구·legacy parsing·메뉴 선택/등록과 Windows 동작은 미검증이다. 임의 key capture·전체 기능/배포 검증은 남아 있다.

다음 구현: 단축키 활성 등록과 저장된 선택값을 분리해 표시하고 외부 설정 변경 시 적용 요청 경로를 명시한다.

## IMPL-040 — active shortcut과 saved selection 분리

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 hotkey/설정 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-011/012/013.

작성한 코드:

- native 등록 성공 시 activeMenuShortcut을 별도로 보관하고 성공한 교체/해제/종료 시 갱신한다. 메뉴에 Active now와 Saved selection을 따로 표시해 외부 저장값 변경을 실제 적용 상태로 오인하지 않도록 했다.
- 활성 조합과 저장된 유효 조합이 다르면 Apply saved selection 명령을 제공한다. 기존 staged register/old unregister/rollback 경로를 재사용하며 실제 등록 변경을 사용자 선택에 연결한다.
- 선택 처리의 비교 기준을 보완했다. 저장값만 같고 실제 등록이 다르면 적용을 생략하지 않는다. 반대로 이미 활성 조합을 선택해 저장값만 맞출 때 동일 키를 중복 등록하지 않는다. 활성화 flag의 별도 의미는 유지한다.

남은 범위:

1. 외부 defaults 변경 즉시 감지와 OS 등록 전체 조회를 구현한 것은 아니다. Active now는 이 인스턴스에서 성공한 API 호출의 추적 상태다. 실제 OS/메뉴/재시작 동작은 미검증이다.
2. 별도 시작 시 활성화 flag의 외부 변경 적용, 임의 key capture, scroll/focus/accessibility 및 전체 Windows 기능/배포 검증은 남아 있다.

다음 구현: 전역 shortcut 작업의 남은 항목을 추적한 채 다음 Windows 전용 lifecycle/시작 설정 계약으로 넘어간다.

## IMPL-041 — Windows logoff/shutdown lifecycle

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 종료/로그오프·검증 스크립트를 실행하지 않았다. 계약: WIN-052.

작성한 코드:

- tray window의 WM_QUERYENDSESSION에 동의 응답만 하고 취소될 수 있는 단계에서 종료 정리를 시작하지 않는다. WM_ENDSESSION FALSE는 계속 실행하며 TRUE에서 system-session 종료 상태를 기록하고 열린 메뉴를 닫은 뒤 기존 invokeQuit 경로를 호출한다.
- 시스템 종료가 확정되면 keyboard foreground 복원 대상을 제거한다. 일반 quit/WM_CLOSE와 기존 native 자원 정리 경로를 재사용한다.
- WindowsMain은 동일한 session/remote/runtime helper shutdown을 요청한다. 시스템 종료의 경우 semaphore 대기를2초로 제한하고 초과 시 cleanup 미완료를 stderr에 남긴다. 일반 사용자 종료의 기존 drain 대기는 유지한다.

남은 범위:

1. Windows는 WM_ENDSESSION 처리 전후 프로세스를 강제 종료할 수 있어2초 정리나 persistent flush 완료를 보장하지 않는다. system 종료 중 실제 message 전달/modal loop/actor drain/timeout은 미검증이다.
2. ENDSESSION_CLOSEAPP 재시작 등록·installer restart manager·launch-at-login/PATH 설치와 전체 WIN-052는 미완료다. 저장 중 종료 복구도 별도 Windows 검증이 필요하다.

다음 구현: Windows 자동 시작 opt-in을 사용자별 설정과 실제 OS 등록 상태로 분리해 연결한다. 설치 방식에 따른 차이와 rollback을 명시한다.

## IMPL-042 — 사용자별 Windows sign-in 등록

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 registry/자동 시작 등록·검증 스크립트를 실행하지 않았다. 계약: WIN-052.

작성한 코드:

- unpackaged 앱용 HKCU Run/CodexBarWindows 등록 adapter를 추가했다. 현재 module executable의 quoted command만 사용하며260자 미만 경로와.exe를 요구한다. user 선택 없이 자동 등록하지 않는다.
- REG_SZ 읽기를1024-byte 한도로 제한하고 문자열/종단을 확인한다. 기존 value가 현재 executable command와 다르면 conflict로 남기고 덮어쓰기/삭제하지 않는다. 동일 command의 등록/해제만 user menu action으로 수행한다. HKLM/StartupApproved/정책은 수정하지 않는다.
- tray는 registry 기반 absent/registered/conflict/unavailable을 읽고 표시한다. registered가 실제 로그온 실행을 보장하지 않으므로 Windows 정책이 override할 수 있음을 표시한다. 변경 실패는 다음 메뉴에서 상태를 다시 읽도록 안내한다. 별도 defaults enabled flag를 성공으로 꾸미지 않는다.

남은 범위:

1. MSIX StartupTask 및 installer/uninstall/update 경로 이동은 미구현이다. 현재 구현은 unpackaged Run 방식이며 packaged 배포에서는 별도 경로가 필요하다.
2. registry 읽기와 set/delete 사이 외부 변경 race는 원자적 compare-and-swap이 아니다. value 단위 API 성공을 사용하며 실패 뒤 임의 rollback으로 다른 값을 복원하지 않는다. 실제 registry/로그온·권한·정책·긴 경로 동작은 미검증이다.
3. 파일 이동 시 이전 command가 conflict로 남는 복구 UI, 승인된 startup 정책 상태 표시 및 전체 Windows 기능/배포 검증은 남아 있다.

다음 구현: packaged 환경에서는 Run 등록을 하지 않도록 package identity 구분과 안내를 연결한다.

## IMPL-043 — package identity의 Run 등록 경계

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 package/registry 조회·검증 스크립트를 실행하지 않았다. 구현에 필요한 Microsoft API 문서만 읽었다. 계약: WIN-052.

작성한 코드:

- GetCurrentPackageFullName size query로 package identity 없음/있음/알 수 없음을 구분한다. APPMODEL_ERROR_NO_PACKAGE인 경우만 기존 Run source 경로를 진행한다. insufficient-buffer+양수 length는 packaged, 기타 결과는 unknown으로 처리한다. package 이름은 가져오거나 기록하지 않는다.
- state 조회와 실제 변경 양쪽이 공통 command 경계를 통과하도록 해 packaged/unknown에서는 registry open/create/query/write/delete를 진행하지 않는다. 메뉴는 packaged startup 연동이 아직 미구현임을 표시하고 Run action을 비활성화한다.
- package 등록 실패/미구현을 일반 exe 방식으로 조용히 대체하지 않는다. 기존 unpackaged opt-in/conflict 보호와 정책 override 안내는 유지한다.

근거: https://learn.microsoft.com/en-us/windows/win32/api/appmodel/nf-appmodel-getcurrentpackagefullname — size query 및 no-package/error 반환 계약.

남은 범위:

1. 실제 WinSDK binding/package identity 결과, packaged/unpackaged registry 경계와 UI는 미검증이다. StartupTask WinRT bridge·manifest 선언·사용자/정책 disabled 상태는 미구현이다.
2. 기존 unpackaged Run 값의 migration/uninstall, StartupApproved 상태와 전체 Windows 기능·배포 검증은 남아 있다.

다음 구현: Windows 자동 시작의 OS 설정 화면 진입을 연결해 정책/사용자 차단 상태를 확인할 수 있는 복구 경로를 제공한다. MSIX StartupTask 구현은 별도 필수 범위다.

## IMPL-044 — Windows 시작 앱 설정 이동

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 Settings/registry 접근·검증 스크립트를 실행하지 않았다. 계약: WIN-052.

작성한 코드:

- 트레이에 등록 상태와 독립된 Open Windows startup apps settings 명령을 추가했다. packaged/unknown/conflict에서도 OS 설정 이동을 선택할 수 있다.
- 사용자 선택 시 고정 ms-settings:startupapps만 ShellExecuteW에 전달한다. provider URL의 HTTP(S) 제한은 유지하고 외부 문자열을 OS scheme으로 전달하지 않는다.
- shell 반환값이 실패이면 즉시 기존 안내 dialog로 Windows Settings > Apps > Startup 수동 경로를 알려준다. 창/종료 상태를 확인하고 등록 값을 수정하지 않는다. shell 요청 수락을 실제 페이지 표시 또는 시작 활성화 성공으로 기록하지 않는다.

근거: https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-settings 의 Startup apps URI.

남은 범위:

1. Settings 페이지가 정책/Windows 버전에 따라 사용 불가하거나 앱 항목이 없을 수 있다. 이 이동은 MSIX StartupTask 구현이나 이전 executable 경로 충돌 복구를 대체하지 않는다.
2. 실제 shell 실패/성공·dialog·설정 페이지·접근성·지역화와 전체 Windows 빌드/배포 검증은 미실시다.

다음 구현: startup 상태별 상세 설명과 복구 안내를 연결한다. MSIX 등록과 경로 이동 복구는 별도 미완료로 유지한다.

## IMPL-045 — 자동 시작 상태별 상세·복구 안내

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·실제 registry/Settings 접근·검증 스크립트를 실행하지 않았다. 계약: WIN-052.

작성한 코드:

- absent/registered/conflict/unavailable/packaged 각각에 등록 범위와 가능한 다음 행동을 정의했다. 다른 시작 메커니즘 미조회, 정책에 의한 비활성화, 경로 이동 충돌 및 MSIX 미구현을 구분한다. 원시 executable/registry 값은 표시하지 않는다.
- 트레이 Startup registration details 선택 시 상태를 새로 읽고 전용 제목의 안내 dialog를 표시한다. No 기본값으로 OS 설정 이동 여부를 선택하며 Yes는 기존 고정 URI 경로에 연결한다. 상세 보기는 등록을 변경하지 않는다.
- 안내 작성 중 발견한 registry 첫 조회 실패의 분류를 보완했다. API 실패는 unavailable, 성공했지만 지원하지 않는 값 형식은 conflict로 구분한다. 접근 실패를 다른 실행 파일 소유라고 단정하지 않는다.

남은 범위:

1. 안내 dialog는 자동 복구가 아니다. MSIX StartupTask, 이전 설치 경로 migration/uninstall, 정책 상태 조회와 실제 Windows 검증은 남아 있다.
2. 상세 상태는 선택 시 snapshot이며 dialog가 열린 동안 외부 변경을 관찰하지 않는다. 지역화/접근성·화면 검증도 미실시다.

다음 구현: WIN-052의 Windows CLI 설치 위치 탐색 및 명시적 사용자 설정 안내로 이어간다. 자동 시작의 남은 구현 의무는 유지한다.

## IMPL-046 — Windows CLI 설치 위치·설정 안내

상태: CODE_WRITTEN_UNVERIFIED. 빌드·컴파일·테스트·lint·앱·CLI·실제 설치 경로 조회·검증 스크립트를 실행하지 않았다. 계약: WIN-052.

작성한 코드:

- WindowsCLISetup은 현재 module 폴더의 CodexBarCLI.exe 및 codexbar.exe 두 후보만 속성 조회하도록 작성했다. 없음·조회 실패·directory/reparse point·파일 존재를 구분하며 실행 가능/정품/의존성 충족으로 간주하지 않는다.
- 트레이 Command-line setup에 안내 dialog를 연결했다. hidePersonalInfo이면 폴더와 절대 경로 명령을 숨긴다. 일반 표시에는 apostrophe를 escape한 선택적 PowerShell --help 명령을 제공하지만 자동 실행/복사하지 않는다.
- 배포 라이브러리 동반 유지, 사용자 Path 수동 추가와 새 터미널, 다른 설치본 확인을 안내한다. 두 후보가 없으면 전체 Windows 배포물 필요 및 다른 폴더의 CLI 미조회임을 명시한다.

남은 범위:

1. PATH 탐색/중복 설치 탐지, installer/PATH 자동 등록·제거, MSIX execution alias 및 binary/의존성 검증은 미구현이다. file attribute 조회는 identity 검증이 아니며 상위 경로 link와 변경 race도 보장하지 않는다.
2. 실제 WinSDK/긴 경로/화면 크기/지역화/접근성 및 전체 Windows 실행·배포 검증은 미실시다.

다음 구현: bounded PATH 후보 탐색과 중복 설치 안내를 연결한다. 자동 설치/alias와 자동 시작의 남은 의무는 유지한다.

## IMPL-047 — process PATH의 CLI 후보 탐색

상태: CODE_WRITTEN_UNVERIFIED. 모든 빌드·컴파일·테스트·실행·실환경 조회·검증은 사용자 지시로 미실시. 계약: WIN-052.

- 현재 process PATH를 32768 UTF-16 buffer 한도로 읽고 최대64개 항목, 후보당 고정2개 이름을 조회하는 코드를 CLI 안내에 연결했다. 반복 사이200ms 경과 시 나머지를 미조회로 센다.
- drive-absolute fixed drive만 탐색하며 relative/UNC/device/미해결 변수/네트워크 drive는 제외한다. 대소문자 기준 중복 폴더를 줄이고 최대4개 후보만 경로240자 한도로 표시한다. 개인정보 숨김을 따른다.
- 후보 수·미조회 항목·접근/형식 실패를 구분하고 여러 후보 시 설치본 확인을 안내한다. shell resolution/실행 가능/전체 설치 탐지 성공으로 표시하지 않는다.

남은 범위: 개별 OS 호출은 중단할 수 없고 fixed drive의 상위 reparse 경로가 network를 가리킬 수도 있어 wall-clock hard limit이 아니다. UI thread 밖 실행·취소·오래된 결과 처리, PATH 설치/제거, MSIX alias 및 Windows 검증은 남아 있다.

다음 구현: CLI 안내 탐색을 tray message thread 밖으로 옮기고 취소/오래된 결과 처리를 연결한다.

## IMPL-048 — CLI 탐색 worker와 취소

상태: CODE_WRITTEN_UNVERIFIED. 사용자 지시에 따라 빌드/컴파일/테스트/실행/검증 미실시. 계약 WIN-052.

- CLI file/PATH 조회를 detached Thread에서 실행하고 mailbox lock으로 단일 진행 요청과 결과를 보호한다. 반복 선택은 진행 요청의 협력 취소를 설정하며 worker 종료 전 새 worker를 만들지 않는다.
- sibling/PATH 반복에 취소 확인을 전달한다. quit은 취소 및 결과 제거를 수행하며 worker는 종료 뒤 UI 결과를 게시하지 않는다.
- wake message에서 UI thread dialog를 표시하고 privacy 값이 변경됐으면 결과를 버리고 새 설정으로 다시 수집한다. 열린 popup/editor 동안은 결과를 보류한다.

남은 범위: 개별 Win32 조회 중단은 불가하다. 모달 종료 뒤 보류 결과의 확실한 재전달 및 진행/취소 상태 UI 보강이 다음 작업이다. thread/종료/privacy 경쟁과 Windows 실행은 미검증이다. 자동 PATH 설치와 MSIX 등 전체 의무는 남아 있다.

## IMPL-049 — CLI 진행 표시와 모달 뒤 결과 전달

상태: CODE_WRITTEN_UNVERIFIED. 빌드/컴파일/테스트/실행/검증은 사용자 지시로 미실시. 계약 WIN-052.

- 메뉴에 조회 취소·취소 대기·결과 준비 상태를 표시하고 준비된 결과를 선택하면 새 조회로 덮지 않는다. popup 종료 시 보류 결과 wake를 다시 게시한다.
- 조회 시250ms native timer로 모달 뒤 전달을 재시도하고 idle 결과 소비/취소 종료/host teardown에서 제거한다. disabled owner, popup/editor 및 CLI dialog 재진입을 차단한다. timer 설치 실패 시에도 결과는 menu/wake 경로에 남는다.
- teardown은 mailbox lock 아래 worker 취소·결과 제거·window nil을 먼저 수행하고 그 뒤 DestroyWindow를 호출해 worker의 이전 HWND 게시 구간을 닫는다.

남은 범위: timer/중첩 모달/취소/privacy/teardown 실제 Windows 동작은 미검증이다. 개별 파일 조회 hard cancellation, PATH 자동 설치/제거, MSIX alias, 전체 기능 구현 및 배포 검증은 남아 있다.

다음 구현: Windows CLI 설치·환경 설정 계약을 계속 연결한다.

## IMPL-050 — 사용자 PATH 등록·제거 작업

상태: CODE_WRITTEN_UNVERIFIED. PowerShell/앱/빌드/컴파일/테스트/registry/검증 실행은 하지 않았다. 계약 WIN-052.

- Windows/PackagingAndOperations/Set-CodexBarUserPath.ps1에 명시적 Add/Remove와 Directory 입력을 받는 작업을 작성했다. Add는 regular CLI 후보를 요구하며, Remove는 사라진 설치 폴더도 literal PATH 항목으로 제거할 수 있다.
- 원래 PATH 문자열의 비대상 항목·순서·값 형식을 유지하고 동일 항목 추가를 생략한다. 환경 변수는 확장하지 않는다. Remove는 사용자가 지정한 동일 literal 항목을 모두 제거하며 파일을 삭제하지 않는다.
- ShouldProcess/WhatIf, 입력·크기·형식 제한, 쓰기 직전 외부 변경 감지, handle 정리를 추가했다. machine PATH와 process 환경은 변경하지 않고 로그아웃·로그인 안내를 제공한다. CLI 실행/신뢰 검증 성공으로 표현하지 않는다.
- CLI-SETUP.ko.md에 사용법·제거 의미·경쟁 조건과 미검증 범위를 기록했다. guidelines/COMMITS.md가 없어 제공된 핵심 커밋 규칙을 적용했다.

남은 범위: 앱 UI에서 설치 작업 연결, 배포물 동봉/서명, MSIX alias, 환경 변경 broadcast 및 전체 Windows 검증은 남아 있다. 재조회/쓰기는 atomic CAS가 아니며 기존 외부 writer race는 보장하지 않는다.

다음 구현: Windows host에서 명시적인 설치 작업 실행 및 결과 처리를 연결한다.

## IMPL-051 — 트레이 PATH 작업과 배포 리소스

상태: CODE_WRITTEN_UNVERIFIED. manifest 평가/빌드/컴파일/PowerShell/registry/테스트/앱 실행 및 검증 미실시. 계약 WIN-052.

- WindowsOperations SwiftPM target의 resource로 기존 단일 PATH script를 묶고 Windows host에 연결했다. script 복사본이나 외부 dependency는 추가하지 않았다.
- 트레이 Add/Remove 명령은 No 기본 확인 후 worker에서 실행한다. CLI discovery/다른 PATH mutation과 동시 실행을 막고 결과는 기존 modal-safe mailbox로 전달한다. privacy 변경 시 mutation을 재실행하지 않는다.
- system directory의 PowerShell을 명시적으로 선택하고 NoProfile/NonInteractive/File의 분리된 argument를 사용한다. execution policy를 우회하지 않는다. package identity 없음이 확인될 때만 helper를 시작한다.
- stdout/stderr를 수집하지 않고 exit 상태로 고정 안내를 표시한다. 30초 대기 뒤 종료 요청하며 변경 여부 불명 안내를 제공한다. 실패 시 rollback하지 않는다.

남은 범위: quit와 child process 소유권/drain 연결, 구조화된 상세 오류, script/배포 서명, 실제 SwiftPM resource 위치, MSIX alias, 환경 broadcast와 Windows 전체 검증이 남아 있다. 현재 parent 종료가 child 완료를 기다리지 않으며 timeout terminate 성공은 미확인이다.

다음 구현: PATH helper의 lifecycle 소유권과 종료 처리를 연결한다.

## IMPL-052 — PATH helper 소유권과 종료

상태: CODE_WRITTEN_UNVERIFIED. 빌드/컴파일/테스트/실행/검증 미실시. 계약 WIN-052.

- host가 PATH operation 인스턴스를 소유하며 condition으로 launch와 shutdown을 직렬화한다. stop 수락 뒤 launch를 차단하고, worker는 실행 중 stop을 관찰한다.
- timeout/stop 시 terminate 요청 후 최대1.5초 종료를 관찰한다. 여전히 실행 중인 Process를 보유하고 종료 확인 전 추가 mutation을 차단한다. 중단을 registry rollback으로 표현하지 않는다.
- invokeQuit은 stop을 요청하고 WindowsMain은 정상 종료 시 최대2초 helper drain을 시도한다. system-session 종료는 추가 대기를 하지 않고 미완료이면 stderr에 남긴다. 런타임 cleanup은 기존 경로를 유지한다.

남은 범위: Process.run 자체 지연과 condition 획득은 hard deadline이 아니며 OS 강제 종료 시 child 종료 보장은 없다. Job Object process-tree containment, 실제 프로세스 종료/registry 결과, 구조화 오류와 전체 Windows 검증은 남아 있다.

다음 구현: PATH helper 구조화 결과와 환경 변경 통지를 연결한다.

## IMPL-053 — PATH 결과 코드와 환경 변경 통지

상태: CODE_WRITTEN_UNVERIFIED. 코드/공식 API 문서 읽기와 편집만 수행했다. PowerShell/registry/앱/빌드/컴파일/테스트/검증 미실시. 계약 WIN-052.

- 내부 ResultProtocolV1에서20=쓰기 성공,21=이미 요청 상태,22=ShouldProcess 거부/미리보기로 반환한다. 일반 수동 호출의 출력은 유지한다. 앱은0/알 수 없는 exit를 성공으로 처리하지 않는다.
-20에서만 worker가 WM_SETTINGCHANGE/Environment를 synchronous SendMessageTimeoutW로 통지한다. UTF-16 pointer lifetime을 호출 끝까지 유지하며 실패/timeout과 통지 요청 성공을 구분한다. shutdown이면 통지를 생략한다.
- 기존 프로세스 환경 교체/수신 앱 반영을 보장하지 않고 로그아웃·로그인 복구 안내를 유지한다. 원시 PATH/오류 출력은 수집하지 않는다.

근거: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendmessagetimeoutw 및 WM_SETTINGCHANGE 계약.

남은 범위:100ms는 수신 창별 timeout이므로 전체 broadcast hard limit이 아니다. 상세 실패 코드, child process-tree containment, resource 서명/MSIX 및 Windows 실행·배포 검증은 남아 있다.

## IMPL-054 — Windows 배포물 명시적 조립

상태: CODE_WRITTEN_UNVERIFIED. PowerShell/패키징/빌드/컴파일/테스트/검증 실행 미실시.

- Windows/Packaging/New-CodexBarDistribution.ps1은 입력 JSON의 명시적 file 목록을 받아 새 출력 폴더에만 복사한다. app/CLI/runtime DLL/license/operation resource 범주를 요구하고 파일 목적지 중복·상위 탈출·파일/폴더 충돌을 제한한다.
- source regular file만 복사하고 원본 경로를 제외한 relative path/kind/size/hash 인벤토리를 작성하도록 했다. status는 STAGED_UNVERIFIED이며 hash를 실행/서명/의존성 검증으로 표현하지 않는다.
- WhatIf/ShouldProcess, 기존 출력 거절, 실패 부분 출력 보존을 구현하고 README에 실제 bundle 경로 유지와 입력 책임을 명시했다.

남은 범위: 정확한 DLL closure/resource 입력 자동 생성, PE architecture 일치, source/output 동시 변경과 상위 reparse, 서명·MSIX·installer/update 및 Windows 실행 검증이 남아 있다. 현재 조립 스크립트는 배포 완료가 아니다.

다음 구현: 의존성/리소스 목록 생성과 서명 인계 작업을 연결한다.

## IMPL-055 — 배포 입력 목록 생성과 PE machine 경계

상태: CODE_WRITTEN_UNVERIFIED. PowerShell/PE 파일 조회/패키징/빌드/컴파일/테스트/검증 미실시.

- 빌드 app/CLI와 명시적으로 선택한 runtime DLL, resource root, license tree를 기존 조립 입력 schema로 생성하는 New-CodexBarDistributionManifest.ps1을 작성했다.
- PE signature/machine을 제한된 header 범위로 읽고 x64/ARM64 불일치를 거절한다. binary 실행·서명 검증은 하지 않는다. duplicate destination과 tree depth/entry/file 한도에서 중단한다.
- resource root 이름을 보존하며 link를 거절하고 stable destination 정렬 및 CreateNew 출력을 사용한다. source 절대 경로가 있는 입력은 게시용이 아님을 문서화했다.

남은 범위: import/delay-load closure, 서명/라이선스 목록 완전성, 상위 reparse/동시 변경, empty-directory 의무와 Windows 실행·패키징 검증은 남아 있다. dependencyClosure는 NOT_VERIFIED다.

다음 구현: PE import 의존성 closure 계산을 연결한다.

## IMPL-056 — PE import 의존성 그래프

상태: CODE_WRITTEN_UNVERIFIED. 공식 PE 문서 및 소스 읽기/편집만 수행했다. PowerShell/바이너리 읽기/컴파일/빌드/테스트/검증 미실시.

- PE32+ section RVA 매핑과 정적/지연 import DLL 이름 파서를 작성했다. 파일 범위·모호한 매핑·section/descriptor/string 한도 및 null terminator를 요구한다. delay descriptor는 RVA 방식만 지원하고 기타 형식은 중단한다.
- 입력 생성기가 각 app/CLI/runtime import를 dependencies edge로 기록한다. 포함 DLL은 included, 나머지는 external_unclassified로 남겨 시스템 DLL이라 추측해 면제하지 않는다.
- 전체 closure로 표시하지 않고 IMPORT_GRAPH_ONLY_UNVERIFIED로 기록한다. 동적 LoadLibrary/forwarded export/API-set 매핑과 외부 DLL 해석은 다음 범위다.

근거: https://learn.microsoft.com/en-us/windows/win32/debug/pe-format

남은 범위: 후보 폴더 기반 재귀 DLL 해석·시스템 정책, 서명/리소스 전체 계약 및 모든 Windows 검증.

## IMPL-057 — 지정 runtime 폴더의 재귀 DLL 해석

상태: CODE_WRITTEN_UNVERIFIED. 소스 편집만 수행했다. PowerShell/실제 DLL 조회/빌드/컴파일/테스트/검증 미실시.

- RuntimeSearchDirectories 최대32개를 입력받고 선택되지 않은 import 이름을 해당 폴더에서만 조회한다. 단일 regular candidate를 기존 PE machine gate로 포함한 뒤 queue에서 재귀 처리한다.
- 명시적 RuntimeFiles 선택을 우선하고 다중 후보는 모호성 오류로 중단한다. 동일 이름 negative lookup을 cache하며1024 PE/100000 edge/file 한도에서 중단한다. 접근 오류와 link를 누락으로 숨기지 않는다.
- unresolvedLibraries를 기록하고 RECURSIVE_IMPORT_GRAPH_UNVERIFIED 상태를 사용한다. process PATH/system 폴더 검색 및 이름 기반 시스템 면제를 하지 않는다.

남은 범위: system/API-set 지원 정책, 미해결 release/staging gate, dynamic imports/forwarders, 파일 경쟁/서명/라이선스와 Windows 실행 검증.

다음 구현: 명시적 시스템 의존성 정책과 미해결 배포 차단을 연결한다.

## IMPL-058 — 명시적 시스템 정책과 미해결 조립 차단

상태: CODE_WRITTEN_UNVERIFIED. 모든 PowerShell/바이너리/빌드/컴파일/테스트/패키징/검증 실행 미실시.

- 아키텍처·Windows minimum·정확한 DLL 이름·분류·이유·HTTPS 근거를 요구하는 공유 정책 schema를 작성했다. wildcard/중복/형식 불일치를 거절하고 declared_system으로만 표시한다. 검증된 기본 정책을 추정해 추가하지 않았다.
- 생성기는 정책 DLL 검색을 생략하며 정책을 manifest에 보존한다. 조립기는 원본 바이너리 import를 다시 읽어 포함 runtime 또는 정책으로 분류되지 않으면 출력 생성 전에 중단한다.
- 정책과 import 범위를 배포 인벤토리에 기록한다. dependency 상태 문자열을 통과 증거로 신뢰하지 않는다.

남은 범위: 실제 지원 OS 정책 근거 확정, 복사 바이트와 분석 일치, dynamic imports/forwarders/API symbols, 서명/MSIX 및 Windows 실행 검증.

## IMPL-059 — 대상 바이트와 분석·해시 연결

상태: CODE_WRITTEN_UNVERIFIED. 코드 편집만 수행. 파일 공유/PE 조회/PowerShell/패키징/빌드/컴파일/테스트/검증 실행 미실시.

- 복사한 각 파일의 read-sharing handle을 인벤토리 기록까지 유지하도록 작성했다. staged app/CLI/runtime의 machine과 import를 다시 읽고 미해결·아키텍처 불일치에서 중단한다.
- held stream에서 SHA-256을 계산하고 staged dependencies와 analysisSource=HELD_STAGED_FILES를 기록한다. 성공·실패 모두 finally에서 핸들을 닫고 부분 출력을 보존한다.
- 원본 preflight만으로 대상 바이트 분석을 대신하지 않는다. 실제 file-sharing 보장/상위 폴더 교체/서명 후 변경과 동적 의존성은 여전히 미검증이다.

다음 구현: Windows 서명 인계와 배포 출처 기록을 연결한다.

## IMPL-060 — 출처 기록과 서명 요청 인계

상태 CODE_WRITTEN_UNVERIFIED. 소스 편집만 수행. PowerShell/파일 대조/빌드/컴파일/테스트/인증서/서명/검증 미실시.

- repository/revision/version 선언을 생성 입력과 조립 인벤토리에 전달한다. 형식만 제한하며 DECLARED_NOT_ATTESTED로 실제 빌드 증명과 구분한다.
- 인벤토리와 대상 파일 크기/hash를 대조한 후 app/CLI/PATH resource3개만 서명 요청으로 내보내는 스크립트를 작성했다. vendor DLL 재서명·키 접근·실제 서명은 하지 않는다.
- request 경로는 distribution 밖, CreateNew, status SIGNING_REQUEST_ONLY이며 서명 후 인벤토리 갱신 의무를 기록한다.

남은 범위: 실제 signer 입력 재대조·인증서 명시 선택·timestamp/AuthentiCode 결과·서명 후 인벤토리, provenance attestation 및 모든 Windows 검증.

## IMPL-061 — 명시적 Authenticode 서명과 새 인벤토리

상태 CODE_WRITTEN_UNVERIFIED. 공식 API 문서와 소스 읽기/편집만 수행. PowerShell/인증서/서명/파일 대조/빌드/컴파일/테스트/검증 미실시.

- 서명 요청·인벤토리·출처·대상 hash를 대조한 뒤 새 output에 복사해 지정 CurrentUser/My 인증서로 first-party3개를 서명하는 스크립트를 작성했다. 원본과 vendor 파일은 보존한다.
- 인증서 유효기간/코드서명 용도/private key, SHA256, 지정 timestamp, Valid/signer/timeStamper 확인을 코드에 연결했다. WhatIf는 인증서 접근 전에 중단한다.
- 서명 후 새 파일 크기/hash/signer를 기록하고 SIGNED_RUNTIME_UNVERIFIED/releaseApproved=false로 출력한다. 실패 partial output을 삭제/복원하지 않는다.

근거: Microsoft Set-AuthenticodeSignature 및 Get-AuthenticodeSignature 공식 문서.

남은 범위: 최종 signed bytes/의존성 재분석 결합, 동시 변경, 실제 cert/timestamp chain, OS 정책/installer/MSIX/릴리스 및 모든 Windows 검증.

## IMPL-062 — 서명된 최종 바이트 분석

상태 CODE_WRITTEN_UNVERIFIED. 소스 편집만 수행. 서명/인증서/파일 공유/PE/PowerShell/빌드/컴파일/테스트/검증 실행 미실시.

- 서명 뒤 파일을 read-sharing handle로 유지한 후 Authenticode/signer/timestamp 확인과 machine/import 분석·hash 계산을 수행하도록 연결했다.
- 비서명 vendor/resource도 최종 hash를 원본과 대조하고 모든 handle을 인벤토리 기록까지 유지한다. 최종 dependencies를 다시 계산해 이전 pre-sign graph를 대체한다.
- 실패 시 성공 인벤토리를 작성하지 않고 partial output을 보존한다. SIGNED_RUNTIME_UNVERIFIED/releaseApproved=false 유지.

남은 범위: 실제 공유/AuthentiCode 동작, 상위 경로 경쟁, 동적 import/forwarder, OS 지원 정책 근거, installer/upgrade/MSIX 및 전체 Windows 검증.

다음 구현: Windows 설치·업그레이드·제거 lifecycle을 연결한다.

## IMPL-063 — 사용자별 버전 payload 설치

상태 CODE_WRITTEN_UNVERIFIED. PowerShell/인증서/설치/파일/빌드/컴파일/테스트/검증 실행 미실시.

- signed payload와 명시적 signer를 받아 LocalAppData Programs의 version/architecture/revision별 새 폴더에만 복사하는 코드를 작성했다. runtime-unverified 개발 설치 opt-in을 요구한다.
- source/target hash, first-party Authenticode/signer/timestamp를 확인하고 read-sharing handle을 receipt 기록까지 유지한다. operations.lock 독점 열기와 완료 receipt-last를 연결했다.
- 기존 version·부분 출력·사용자 데이터를 보존하고 활성화/PATH/startup 변경을 하지 않는다. receipt는 INSTALLED_INACTIVE_RUNTIME_UNVERIFIED다.

남은 범위: active version/shortcut 전환·upgrade rollback·uninstall/OS 적합성·receipt 신뢰 및 모든 Windows 검증.

## IMPL-064 — 시작 메뉴 버전 선택

상태 CODE_WRITTEN_UNVERIFIED. PowerShell/COM/shortcut/파일/서명/빌드/컴파일/테스트/검증 실행 미실시.

- 설치 receipt의 app hash/signer와 VersionID를 확인하고 WScript.Shell로 사용자 시작 메뉴 링크를 작성하는 코드를 추가했다. 개발 설치 opt-in과 operations.lock을 유지한다.
- 기존 관리 경로/arguments 조건을 요구하고 준비 journal, 임시 link, 직전 hash 비교, File.Replace backup 또는 신규 Move를 연결했다. 선택된 버전으로 앱을 자동 실행하지 않는다.
- 실패 시 link는 이미 변경됐을 수 있음을 안내하며 journal/backup/기존 version을 보존한다. 이전 VersionID 재선택 경로는 동일하다.

남은 범위: interrupted journal recovery, 상위 경로/동시 변경, 전체 installed payload 재확인, PATH/startup migration, uninstall/OS 적합성과 Windows 검증.

## IMPL-065 — 기록에 결합한 shortcut 복구

상태 CODE_WRITTEN_UNVERIFIED. PowerShell/바로가기/파일/설치/빌드/컴파일/테스트/검증 실행 미실시.

- 교체 전 candidateHash를 selection journal에 기록한다. Restore-CodexBarActivation은 관리 TransactionID 경로만 사용하고 현재/previous/candidate hash로 이미 복원됨·복구 가능·외부 변경을 구분한다.
- 이전 backup을 복사해 replace하며 현재 link를 displaced backup으로 보존한다. 첫 선택의 rollback은 link를 보존 위치로 move한다. 기존 version/user data를 삭제하지 않는다.
- operations.lock/ShouldProcess/별도 recovery 기록과 부분 실패 안내를 연결한다. old/incomplete journal은 추측해 복원하지 않는다.

남은 범위: journal 원자적 쓰기, compare/replace race, managed uninstall/부분 설치 복구, 설정/프로세스/PATH/startup migration과 Windows 검증.

## IMPL-066 — 복구 가능한 버전 제거 경로

상태 CODE_WRITTEN_UNVERIFIED. PowerShell/프로세스/레지스트리/바로가기/파일 이동/빌드/컴파일/테스트/검증 실행 미실시. guidelines/COMMITS.md는 없어 제공된 커밋 핵심 규칙을 적용한다.

- Remove-CodexBarVersion.ps1에 명시적 VersionID·개발 opt-in·설치 receipt 경로 제한·operations.lock·ShouldProcess를 연결했다. 시작 메뉴/PATH/Run·RunOnce/실행 중 CodexBar 참조를 만나면 제거를 거절하도록 작성했다.
- receipt의 경로/hash를 받아 일치한 파일만 별도 removed transaction의 payload로 이동한다. 수정/링크/디렉터리는 보존하고 없는 파일은 ALREADY_ABSENT로 기록한다. 임의 파일은 제거 대상으로 열거하지 않으며 기존 receipt/디렉터리/설정은 남긴다.
- 파일별 journal과 부분 완료 상태를 작성한다. 이동 직후 hash가 달라지면 바이트를 복구 폴더에 보존한 채 중단한다. 실제 삭제/이동은 실행하지 않았다.

남은 범위: 영구 삭제 및 공간 회수, 자동 removal rollback/부분 설치 복구, 원자적 journal, 경로/프로세스/참조 변경 race, 다른 registry view/작업 스케줄러/별도 shortcut 참조, Apps 제거 등록 및 Windows 검증. 이 변경은 전체 제거 기능 완료가 아니다.

## IMPL-067 — 제거 payload 복원과 journal 교체

상태 CODE_WRITTEN_UNVERIFIED. PowerShell/파일 복사·교체/설치/빌드/컴파일/테스트/검증 실행 미실시. guidelines/COMMITS.md 부재로 제공된 핵심 커밋 규칙을 따른다.

- Restore-CodexBarRemovedVersion.ps1은 고정된 removed transaction 폴더의 receipt와 원래 version receipt의 일치를 요구한다. 기록된 상대 경로만 사용하고 원래 디렉터리가 보존됐을 때만 빈 목적지에 복사한다. 기존 목적지/변경된 사본을 덮지 않으며 recovery 사본도 남긴다.
- removal journal의 마지막 저장 성공을 전제하지 않고 실제 receipt-owned payload 존재/hash를 사용한다. 이미 복원됨·다른 transaction에 있음/없음·충돌을 구분하고 부분 결과를 기록한다.
- Write-CodexBarJournal 공통 함수를 작성해 removal/restore/activation journal에 연결했다. 새 임시 파일에 UTF-8 JSON을 쓰고 Flush(true) 후 Move 또는 File.Replace로 교체하며 이전 generation과 실패한 임시 파일을 보존한다.

남은 범위: 전원 차단/파일시스템별 교체 내구성 검증, previous generation 자동 선택·정리, 상위 경로 및 외부 writer race, 복원 중 새 프로세스, incomplete-install 복구·Apps 등록·PATH/startup migration·전체 Windows 검증. 복구는 payload 파일에 한정하며 런타임/서명 재승인이나 자동 활성화를 의미하지 않는다.

## IMPL-068 — 기록된 중단 설치 재개

상태 CODE_WRITTEN_UNVERIFIED. PowerShell/서명/파일 복사·설치·복구/빌드/테스트/컴파일/검증 실행 미실시. guidelines/COMMITS.md 부재로 제공된 핵심 커밋 규칙을 적용한다.

- Install-CodexBarVersion.ps1에 ResumeIncomplete를 추가했다. version 폴더 생성 전에 설치 의도 기록을 저장하고 inventory 원본 바이트 SHA256·VersionID·signer를 결합한다. 같은 기록의 PREPARED/COPYING 상태만 재개한다.
- 기존 목적지 파일은 덮어쓰지 않고 새 파일과 동일하게 read-sharing handle을 유지하면서 전체 해시와 first-party 서명/timestamp를 확인한다. 부모 디렉터리를 순서대로 확인하며 링크/파일 충돌을 거절한다. 새로 누락된 파일만 복사한다.
- 완료 receipt와 설치 단계 기록에 공통 journal 저장 함수를 연결했다. receipt가 이미 있으면 재설치/활성화하지 않으며 마지막 단계 기록 실패는 receipt 게시 후일 수도 있음을 안내한다.

남은 범위: 복사 도중 끊겨 바이트가 일부만 기록된 파일의 자동 복구, 옛 기록 없는 부분 설치, 완료 receipt와 미완료 journal의 조정, unknown 파일 혼재 및 외부 동시 변경/경로 race, Apps 등록·PATH/startup migration·Windows 검증. 현재 재개는 일치한 파일 재사용과 없는 파일 추가에 한정한다.

## IMPL-069 — 설치 파일 게시와 완료 기록 조정

상태 CODE_WRITTEN_UNVERIFIED. PowerShell/파일 복사·교체/서명/설치/빌드/컴파일/테스트/검증 실행 미실시. guidelines/COMMITS.md 부재로 제공된 핵심 커밋 규칙을 따른다.

- 새 payload 파일을 version 밖의 install-staging transaction 폴더에 복사하고 Flush(true) 및 크기/hash/first-party 서명 확인 후 Move로 최종 경로에 게시하도록 작성했다. 이미 존재한 목적지는 덮어쓰지 않는다. 게시 후 파일을 다시 대조하고 완료 receipt까지 handle을 유지한다.
- COPY 단계 기록이 남았으나 receipt가 게시된 경우, ResumeIncomplete에서 같은 배포/서명자와 receipt의 버전·출처·파일 목록을 대조한다. 최종 파일이 모두 그대로 있을 때만 진행 기록을 마무리하고 receipt/파일은 교체하지 않는다.
- receipt가 있는데 파일/부모 폴더가 누락되면 수리나 재설치로 간주하지 않고 중단한다. 새 설치 실패 시 임시 사본은 보존되며 다음 재개는 새 임시 위치를 쓴다.

남은 범위: 옛 최종 경로의 불완전 파일/수정 파일 처리, staging·journal 이전 세대 공간 정리, 서명 확인과 Move 사이 및 상위 경로 외부 변경, receipt 자체 동시 변경, 파일시스템/전원 손실 내구성, Apps 등록·참조 migration·전체 Windows 검증.

## IMPL-070 — 설치 도구 배포 및 전체 서명 계약

상태 CODE_WRITTEN_UNVERIFIED. manifest/PowerShell/패키징/인증서/서명/설치/빌드/컴파일/테스트/검증 실행 미실시. guidelines/COMMITS.md 부재로 제공된 핵심 커밋 규칙을 따른다.

- 설치된 앱 등록의 선행 조건으로 설치·선택·제거·복구 도구가 배포물에 실제 포함되도록 manifest producer를 연결했다. tools 아래에 8개 명시적 스크립트를 넣고 중복 목적지는 기존 규칙대로 거절한다.
- Read-CodexBarFirstPartyFiles.ps1에 앱/CLI/단일 PATH resource/8개 tools의 공통 계약을 작성했다. producer·stager·signing request·signer·installer에서 동일 목록의 누락과 서명 대상 개수를 처리한다.
- installer는 tools를 포함한 모든 first-party 파일에 서명자/timestamp 확인을 적용하도록 작성했다. 기존 3개만 서명하는 인벤토리는 새 계약으로 다시 조립·서명해야 하며 실제 서명 작업은 하지 않았다.

남은 범위: Apps 등록 및 버전 제거 중에도 유지되는 invocation 위치, installer bootstrap trust, 제거가 실행 중인 helper에 미치는 영향, staging/backup 공간 회수·PATH/startup migration·전체 Windows 검증. 도구 배포가 완전한 설치 프로그램/UI 통합을 의미하지 않는다.

## IMPL-071 — 개발 설치 등록과 제거 진입점

상태 CODE_WRITTEN_UNVERIFIED. PowerShell/레지스트리/WinForms/파일 복사·서명/설치·제거/빌드/테스트/검증 실행 미실시. guidelines/COMMITS.md 부재로 제공된 핵심 커밋 규칙을 따른다.

- Register-CodexBarInstallation.ps1은 VersionID·signer·개발 opt-in을 받아 tools를 version 밖 management-ID 폴더에 복사하고 receipt hash 및 서명/timestamp를 확인하도록 작성했다. 관리 잠금과 준비 journal을 사용하며 현재 사용자 Registry64의 버전별 Uninstall 항목에 표시 이름/버전/설치 위치/제거 명령을 쓴다. 기존 등록은 덮어쓰지 않는다.
- Invoke-CodexBarUninstall.ps1은 관리 폴더 위치 확인·기본 No 확인 대화상자·기존 제거 도구 호출을 연결한다. 제거 도구에 PassThru 결과 계약을 추가해 완전한 receipt payload retirement일 때만 등록 해제를 시도한다. 부분 결과/등록 소유권 변경/추가 데이터는 등록을 보존한다.
- 등록용 도구 2개도 공통 배포/서명 목록에 포함했다. 필수 lifecycle tools는 10개, 앱·CLI·PATH resource 포함 서명 대상은 13개다. 실행 명령은 시스템 PowerShell과 AllSigned 정책을 사용한다.

남은 범위: 선택 중인 version의 shortcut/PATH/startup 자동 전환, registry 생성·비교·삭제 race 및 제거 후 복원 동시 실행, 부분 등록 재개/등록 상태 journal 조정, management/staging/복구 사본 정리, 완전한 uninstall UI/localization·bootstrap trust·전체 Windows 검증. 현재는 개발 표시 등록이며 영구 삭제/공간 회수나 일반 출시 완료가 아니다.

## IMPL-072 — 중단된 앱 등록 재개

상태 CODE_WRITTEN_UNVERIFIED. PowerShell/레지스트리/파일 복사·서명/앱 등록/빌드/테스트/컴파일/검증 실행 미실시. guidelines/COMMITS.md 부재로 제공된 핵심 커밋 규칙을 따른다.

- Register-CodexBarInstallation에 ResumeRegistrationID를 추가하고 schema 2 기록을 tool 복사 전에 저장하도록 변경했다. receipt 원본 해시·VersionID·signer·등록 ID가 같은 PREPARING_TOOLS/PREPARED/REGISTERED 상태만 재개한다.
- 기존 관리 파일을 덮어쓰지 않고 hash/서명/timestamp를 다시 확인한다. 누락된 tool만 복사하며 기존 명령 문자열이 달라지면 등록을 갱신하지 않는다.
- registry의 동일 소유권 ID와 허용 값 이름/자료형/값을 사전 대조한 뒤 누락된 값만 채운다. 이미 완성된 동일 등록은 유지하고 journal을 완료 상태로 마무리할 수 있다. 추가 데이터/다른 값/owner 없는 항목은 보존한다.

남은 범위: CreateSubKey 및 값 읽기/쓰기 사이 외부 race, owner 기록 전 중단된 빈 key, schema 1 및 기록 없는 관리 폴더, 일부만 복사된 tool의 자동 수리, receipt 동시 변경, reference migration/backup 정리/전체 Windows 검증. 실제 복구나 registry 동작을 검증하지 않았다.

## IMPL-073 — 버전 참조 전환 및 제거 연결

상태 CODE_WRITTEN_UNVERIFIED. PowerShell/COM/registry/환경 변수/서명/설치·제거/빌드/테스트/검증 실행 미실시. guidelines/COMMITS.md 부재로 제공된 핵심 커밋 규칙을 따른다.

- Set-CodexBarVersionReferences는 FromVersionID를 받아 지정 버전의 literal 사용자 PATH 항목, 정확한 CodexBarWindows Run 명령, arguments 없는 관리 시작 메뉴 링크를 처리한다. ToVersionID와 signer가 있으면 대상 앱/CLI receipt/hash/서명을 대조한 뒤 기존 참조만 전환하고, 생략하면 해제한다. 없는 참조를 새로 활성화하지 않는다.
- PATH 원래 값/형식을 보존하고 unrelated 항목은 유지한다. 변경 전 journal과 shortcut backup을 남기며 registry/shortcut 현재 값을 쓰기 직전에 다시 대조한다. 현재 PowerShell 프로세스의 PATH도 같은 literal 규칙으로 바꾼다.
- 제거 launcher의 확인 문구와 실행 순서를 연결해 동의 후 known user references를 해제하고 기존 payload 제거를 호출한다. 사용자 정의/머신 참조 및 실행 프로세스는 기존 제거 gate가 차단한다. 새 helper도 배포/서명 대상에 포함했다.

남은 범위: 참조 transaction 자동 rollback/재개, environment broadcast, 새 프로세스·외부 registry/shortcut/receipt 변경 race, 머신/간접 PATH/다른 startup 참조, 실패 시 이미 해제된 참조 복구, management/backup 정리와 Windows 검증. payload 제거 실패 시 참조만 먼저 해제될 수 있으며 자동 rollback을 주장하지 않는다.

## IMPL-074 — 버전 참조 복구

상태 CODE_WRITTEN_UNVERIFIED. PowerShell/파일·서명/registry/shortcut/빌드/컴파일/테스트/검증 실행 미실시. guidelines/COMMITS.md 부재로 제공된 핵심 커밋 규칙을 따른다.

- Set-CodexBarVersionReferences의 기록을 schema 2로 바꾸고 changePath/changeRun 및 새 shortcut hash를 저장하도록 작성했다. 교체 전에 candidate hash를 게시하고 현재 shortcut도 다시 대조한다.
- Restore-CodexBarVersionReferences는 TransactionID·signer·개발 opt-in을 받아 원래 버전 receipt와 앱/CLI hash·서명을 먼저 대조한다. payload가 제거됐으면 먼저 payload를 복원해야 한다.
- 변경 대상의 현재 값/자료형이 기록된 before 또는 after와 맞는지 전체 사전 대조한다. 이미 before면 유지하며 after에 해당하는 항목만 복원한다. 현재 shortcut과 backup hash를 결합하고 기존 shortcut은 displaced 사본으로 보존한다. 별도 recovery journal을 작성한다.

남은 범위: schema 1 자동 전환 복구, 환경 broadcast 및 프로세스 PATH 처리, journal 진위/동시 변경, 여러 쓰기 atomicity, 제거 실패 자동 복구 orchestrator·보존 파일 정리·전체 Windows 검증. 복구 중 실패해도 앞선 쓰기는 적용됐을 수 있다.

## IMPL-075 — 참조 PATH 변경 통지

상태 CODE_WRITTEN_UNVERIFIED. PowerShell/Add-Type/C# 컴파일/native call/registry/환경 통지/빌드/테스트/검증 실행 미실시. guidelines/COMMITS.md 부재로 제공된 핵심 커밋 규칙을 따른다.

- Send-CodexBarEnvironmentChange helper에 동기 WM_SETTINGCHANGE/Environment broadcast를 작성했다. 100ms per-recipient와 BLOCK/ABORTIFHUNG을 사용하며 string marshalling을 호출 동안 유지한다. Add-Type 및 native call은 코드로만 작성했고 실행하지 않았다.
- 참조 변경/복구에서 실제 PATH 쓰기 직후 통지하고 environmentNotification을 기록한다. 통지 실패/정책 차단은 이미 성공한 PATH 쓰기의 rollback으로 처리하지 않으며 재로그인 안내를 남긴다.
- helper도 배포·서명 목록에 포함했다. 필수 tools는 13개, 전체 first-party 서명 대상은 16개다.

남은 범위: 모든 창을 포함한 통지 전체 시간 상한, 사용자 프로세스별 실제 환경 갱신, 통지 직후 기록 실패, lifecycle 실패 ID 인계/UI 안내·보존 파일 정리·Windows 검증. 성공 반환도 모든 앱의 환경 재로드를 보장하지 않는다.

## IMPL-076 — 제거 실패 복구 정보 인계

상태 CODE_WRITTEN_UNVERIFIED. PowerShell/WinForms/예외 전달/파일·registry/빌드/테스트/컴파일/검증 실행 미실시. guidelines/COMMITS.md 부재로 제공된 핵심 커밋 규칙을 따른다.

- 참조 변경 도구에 PassThru 결과를 추가하고 참조/제거 도구 예외 Data에 생성된 transaction ID를 전달하도록 작성했다. ID 생성 이전 오류에는 임의 ID를 만들지 않는다.
- 제거 launcher가 management 폴더에 uninstall-ID.json을 작성하고 참조 해제·파일 이동·등록 해제 단계를 기록한다. 반환된 transaction ID/상태/환경 통지 결과를 연결한다.
- 실패 시 제한된 exception chain에서 형식이 맞는 ID만 수집해 오류창에 단계·관리 ID·파일/참조 복구 ID·복구 순서를 표시한다. 마지막 journal 저장이 실패해도 원래 오류를 유지하고 화면 ID 보관을 안내한다.

남은 범위: 비정상 프로세스 종료 시 호출자 기록과 실제 child journal 사이 공백, ID 생성 후 journal 생성 실패 구분, 자동 recovery orchestrator·UI 접근성/localization·동시 변경·공간 회수·전체 Windows 검증. 기록은 복구 근거이며 변경의 원자성/완료 증명이 아니다.

## IMPL-077 — 제거 하위 작업 ID 사전 기록

상태 CODE_WRITTEN_UNVERIFIED. PowerShell/강제 종료/파일·registry/빌드/컴파일/테스트/검증 실행 미실시. guidelines/COMMITS.md 부재로 제공된 핵심 커밋 규칙을 따른다.

- 제거 handoff를 schema 2로 바꾸고 참조/파일 제거 ID를 하위 호출 전에 PLANNED 상태로 저장한다. child 작업이 실제 변경 후 응답 전에 중단돼도 호출자 기록에서 고정된 경로를 찾을 수 있도록 작성했다.
- 참조/제거 스크립트에 선택적 OperationID를 추가했다. ID 생략 시 새 GUID를 쓰며 기존 journal/shortcut/제거 폴더에 해당 ID가 있으면 재사용하지 않는다. 관리 잠금 안에서 충돌을 확인한다.
- launcher는 성공 응답의 ID가 사전 기록 ID와 같아야 수용한다. 예외에서 예상 밖 ID가 나와도 원래 ID를 덮지 않고 별도 표시한다. 사전 예약은 실행/완료 증거가 아님을 안내한다.

남은 범위: journal 게시와 payload 변경의 원자성, 외부 경로 race, 비정상 종료 후 자동 상태 조정/통합 복구, 예약됐지만 실행되지 않은 작업의 판별 UI, 보존 파일 정리와 전체 Windows 검증. OperationID는 기존 작업 재개 옵션이 아니다.

## IMPL-078 — 기록 기반 제거 복구 실행

상태 CODE_WRITTEN_UNVERIFIED. PowerShell/파일 복구/registry/서명/빌드/테스트/검증 실행 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- Restore-CodexBarUninstall이 명시적 RegistrationID/UninstallID/signer로 schema 2 handoff와 연결된 제거/참조 기록을 읽고 버전을 대조하도록 작성했다.
- 파일 복구에 PassThru 결과를 추가하고 전체 receipt payload 복원 결과에서만 참조 복구로 진행한다. 단계별 journal을 남기며 부분 복구/누락된 완료 기록은 중단한다.
- 새 도구를 배포·서명 계약에 포함했다. tools 14개, 전체 first-party 대상 17개다.

남은 범위: 전체 단계 통합 잠금, 기록 조회 후 동시 변경, PLANNED 기록 누락의 원인 판별, Apps 등록 복구 통합, 실패 후 UI 재진입·보존 파일 정리·Windows 검증. child별 잠금만 사용하며 자동 전체 rollback이나 런타임 정상 상태를 보장하지 않는다.

## IMPL-079 — 통합 복구의 앱 등록 연결

상태 CODE_WRITTEN_UNVERIFIED. PowerShell/파일·서명/registry/복구/빌드/컴파일/테스트/검증 실행 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- Restore-CodexBarUninstall에 RestoreRegistration opt-in을 추가했다. schema 2 등록 기록의 ID/버전/signer를 사전 대조하고 파일·참조 복구 후 같은 등록 ID로 등록 재개를 호출한다.
- 참조 복구와 앱 등록에 PassThru 결과를 추가해 버전/ID/완료 상태가 일치해야 다음 단계 및 최종 결과를 수용한다. 등록 단계와 결과를 recovery journal에 저장한다.
- 앱 등록 시 앱·CLI의 크기/hash/서명/timestamp를 확인하고 읽기 handle을 등록 완료까지 유지한다. 관리 tool만 남은 제거 상태의 재등록을 방지하도록 작성했다.

남은 범위: 전체 단계 통합 잠금, 단계 사이 외부 변경/등록 정책 변경, dependency/resource 전체 설치 신뢰, legacy 등록 복구, UI 통합/보존 파일 정리/전체 Windows 검증. 미지정 시 기존처럼 Apps 등록은 변경하지 않는다.

## IMPL-080 — 트레이 요약 복사

상태 CODE_WRITTEN_UNVERIFIED. Swift 컴파일/빌드/테스트/Win32 clipboard/UI/검증 실행 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 원본 StatusItemController의 copyError와 WIN-010 복사 action 요구를 참고해 Windows 트레이의 표시 요약 복사 경로를 작성했다. 현재 메뉴 행 snapshot만 사용하고 LogRedactor를 적용하며 NUL을 제거한다. 행/UTF-16 크기 상한을 두고 메뉴 종료 시 사본을 해제한다.
- Copy redacted summary 메뉴와 개인정보 설정 변경 시 재열기 안내를 연결했다. clipboard 기존 내용을 읽지 않으며 사용자 선택에서만 Unicode text를 쓴다.
- GMEM_MOVEABLE/GlobalLock/OpenClipboard(owner)/EmptyClipboard/SetClipboardData 소유권 이전 및 실패 경로를 작성했다. 전송 성공 시 시스템 소유 메모리를 해제하지 않으며 실패 시 오류를 표시한다.

남은 범위: 공급자별 상세 오류/카드 선택 복사, Share Stats 이미지/export, redactor의 실제 데이터별 비밀 처리 범위, 접근성/키보드/UI 및 Windows clipboard ABI 검증. 이 변경은 원본 copy action 전체 또는 WIN-010 완료를 의미하지 않는다.

API 참고: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setclipboarddata

## IMPL-081 — 공급자별 오류 복사

상태 CODE_WRITTEN_UNVERIFIED. Swift 컴파일/빌드/테스트/UI/clipboard/검증 실행 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 현재 새로고침의 first-party fetch 실패를 provider ID별 redacted copy text로 저장하고 최종 menu entry에 연결했다. 새 fetch 묶음 시작 시 이전 오류를 비우고 초기 action projection에는 과거 오류를 싣지 않는다.
- Copy provider error 하위 메뉴에 실패 공급자만 표시하며 popup별 command/text 사본을 유지한다. 최대 128개, 메뉴 생성 실패 시 명령을 등록하지 않고 종료 시 사본을 제거한다.
- 기존 clipboard 크기/필터/실패 처리와 privacy 설정 변경 guard를 재사용한다. 자동 clipboard 접근은 하지 않는다.

남은 범위: plugin 오류, 개별 계정 동시 표시 오류 선택, config/account resolution 단계 오류, 상세 카드와 copy action 전체 계약, redaction 완전성 및 Windows ABI/UI 검증. WIN-010 완료를 의미하지 않는다.

## IMPL-082 — 플러그인 오류 복사

상태 CODE_WRITTEN_UNVERIFIED. Swift 컴파일/빌드/테스트/plugin 실행/UI/clipboard/검증 실행 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- plugin fetch 실패 및 등록되지 않은 설정상 plugin의 오류를 ProviderInstanceID.rawValue로 저장하고 현재 refresh의 copy action으로 전달하도록 작성했다. 취소는 오류 복사 대상으로 만들지 않는다.
- 플러그인 이름과 인스턴스 ID를 함께 표시해 같은 이름의 항목을 구분한다. 제목에 LogRedactor/NUL 제거/길이 상한을 적용하고 기존 popup escape와 clipboard 필터를 사용한다.
- WindowsTrayMenuEntry에 statusVisible을 추가해 오류 전용 plugin entry가 허위 상태 페이지/대시보드 메뉴를 만들지 않도록 분리했다. 기본 first-party 상태 항목은 기존 동작을 유지한다.

남은 범위: 계정별 동시 오류 선택, plugin별 dashboard/status 선언 연결, 제목·오류 redaction 범위, 상세 카드/UI 계약 및 전체 Windows 검증. plugin 기능 전체 또는 WIN-010 완료를 의미하지 않는다.

## IMPL-083 — 공급자별 사용량 복사

상태 CODE_WRITTEN_UNVERIFIED. Swift 컴파일/빌드/테스트/UI/clipboard/plugin/검증 실행 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- plugin manifest를 읽은 결과 dashboard/status URL 선언이 없어 추정 링크를 추가하지 않았다. 대신 WIN-010의 공급자별 usage copy를 연결했다.
- 표시 행을 다시 렌더링하는 지점에서 현재 privacy/optional usage/used-or-remaining/reset 설정을 적용한 instance별 copy text를 작성한다. first-party 및 성공한 plugin의 menu entry에 연결하며 오류-only 항목은 사용량으로 복사하지 않는다.
- Copy provider usage 하위 메뉴를 추가하고 기존 popup-bound 명령/clipboard 실패/개인정보 변경 guard를 재사용한다. 오류 복사와 별도 명령 범위를 쓰며 메뉴 종료 때 함께 정리한다.

남은 범위: 계정별 동시 상세 선택, rich card/Share Stats 이미지 내보내기, plugin link 계약이 추가되는 경우의 별도 지원, 전체 Windows UI/ABI/redaction 검증. WIN-010 완료로 판정하지 않는다.

## IMPL-084 — 공급자 상세 텍스트 보기

상태 CODE_WRITTEN_UNVERIFIED. Swift 컴파일/빌드/테스트/Win32 메뉴·대화상자/clipboard/검증 실행 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- Provider details 하위 메뉴에서 현재 popup의 redacted 사용량/오류를 분리해 표시하도록 작성했다. 최대 128개 action과 12,000자 표시 상한을 두고 긴 내용은 복사 메뉴 안내를 붙인다.
- 개인정보 설정이 달라지면 메뉴 재열기를 안내하며 popup 종료 시 detail 사본을 제거한다. 정보 창을 열면서 provider fetch나 계정 변경을 자동 실행하지 않는다.
- 일반 메시지와 세션 전용 설명을 분리해 clipboard 오류에 세션 새로고침 안내가 붙지 않도록 수정했다.

남은 범위: 스크롤/선택 가능한 full detail card, 계정 선택·그래프·개별 action 통합, 접근성/DPI/localization 및 Windows UI/ABI 검증. 텍스트 대화상자는 전체 상세 카드 완료를 의미하지 않는다.

## IMPL-085 — 스크롤·선택 가능한 공급자 상세 창

상태 CODE_WRITTEN_UNVERIFIED. 빌드/컴파일/테스트/Win32/UI/clipboard 검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- WindowsProviderDetailsDialog에 크기 조절 가능한 소유 창과 읽기 전용 multiline EDIT, 수직 스크롤, 텍스트 선택, Ctrl+A, Close/Escape 동작을 작성했다. 표준 EDIT의 선택 복사 동작을 사용하며 내용을 편집하거나 자동으로 clipboard에 쓰지 않는다.
- popup 시점의 redacted 사본을 전달하며 12,000자 표시 잘림을 제거했다. 입력은 기존 공급자별 copy text 크기 제한을 따르고 줄바꿈을 CRLF로 통일한다.
- 창 닫힘 시 owner 활성 상태 복원, WM_QUIT 재전달, 메시지 루프/컨트롤 생성 실패 처리, 기존 editor 중복 진입 차단을 연결했다.

남은 범위: rich detail card/그래프/계정 선택과 개별 action 통합, DPI별 배치·최소 창 크기·접근성·지역화, 선택 복사/긴 텍스트/메시지 루프의 Windows ABI 및 런타임 검증. WIN-010 또는 전체 제품 완료를 의미하지 않는다.

## IMPL-086 — 공급자 상세 창 링크 동작

상태 CODE_WRITTEN_UNVERIFIED. 빌드/컴파일/테스트/UI/브라우저 열기/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 상세 snapshot에 같은 공급자의 dashboard/status/changelog 링크를 함께 보관하고 최대 세 개의 버튼을 작성했다. 링크가 없는 공급자에는 추정 목적지를 추가하지 않으며 release notes는 기존 providerChangelogLinksEnabled 설정을 따른다.
- 버튼 선택 시 선택 URL을 반환하고 상세 창이 닫혀 owner가 복구된 다음 기존 HTTP(S)/host/credentials/control-character 검사 경로로 전달한다. 단순 창 열기·닫기로 URL을 실행하지 않는다.
- 상세 창을 연 동안 privacy가 변경되면 링크 실행 대신 재열기 안내를 표시한다. 버튼 행과 Close가 겹치지 않도록 최소 창 크기를 작성했다.

남은 범위: rich card/계정 선택·refresh 통합, 링크 열기 실패의 사용자 표시 개선, DPI별 크기와 접근성/지역화, Windows ABI·실행 검증. WIN-010 완료를 의미하지 않는다.

## IMPL-087 — 공급자 링크 실패 안내와 URL 로그 보호

상태 CODE_WRITTEN_UNVERIFIED. 빌드/컴파일/테스트/UI/ShellExecute/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- status/dashboard/changelog 및 상세 창 링크가 공유하는 열기 함수를 openProviderPage로 정리했다. 종료 중 실행을 막고 owner 창을 전달하며 URL 길이 상한을 기존 HTTP(S)/host/credentials/control-character 검사와 함께 적용했다.
- 잘못된 주소와 Windows shell 거절을 구분해 사용자 메시지를 작성했다. shell 실패 시 기본 브라우저 설정 확인과 수동 웹사이트 열기를 안내하며 자동 재시도·설정 변경은 하지 않는다.
- 오류 로그에서 원본 URL을 제거했다. 계정 식별자가 포함될 수 있는 path/query/fragment를 출력하지 않고 실패 종류와 shell 반환값만 기록한다. shell 수락을 웹페이지 로드나 인증 성공으로 판정하지 않는다.

남은 범위: rich card/계정 선택·refresh 통합, DPI·접근성·지역화, Windows 실제 링크 열기/실패 대화상자 검증. WIN-010 완료를 의미하지 않는다.

## IMPL-088 — 상세 창의 명시적 전체 새로고침

상태 CODE_WRITTEN_UNVERIFIED. 빌드/컴파일/테스트/UI/실제 수집/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 상세 창 결과를 closed/openURL/refreshAll enum으로 분리하고 Refresh all & close 버튼을 작성했다. 선택 후 창과 modal owner를 정리한 다음 기존 onRefresh 콜백을 한 번 호출한다.
- 기존 콜백은 usage/local sessions/remote sessions를 요청하므로 공급자 전용 갱신으로 오인하지 않도록 전체 새로고침과 창 닫힘을 버튼 및 안내에 명시했다. 별도 fetch 루프를 만들지 않으며 usage runtime의 진행 중 요청 합치기 경로를 재사용한다.
- Close/Escape/창 닫기는 새로고침을 요청하지 않는다. 업데이트 완료를 기다리거나 최신 데이터를 받았다고 표시하지 않으며, 업데이트 뒤 상세 창을 다시 여는 안내를 작성했다.

남은 범위: 상세 창을 유지하는 live refresh/로딩·실패 상태, 공급자·계정별 갱신과 rich card, DPI/접근성/지역화 및 Windows 런타임 검증. WIN-010 완료를 의미하지 않는다.

## IMPL-089 — 상세 창 DPI 배치와 글꼴

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/DPI/글꼴/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 상세 창의 초기 client 크기·최소 크기·버튼·여백을 96 DPI 기준에서 현재 창 DPI로 환산하도록 작성했다. 프레임 크기는 AdjustWindowRectExForDpi를 사용한다.
- WM_DPICHANGED에서 새 DPI와 제안 RECT를 적용하고 컨트롤 배치를 다시 계산한다. 배율 변경과 시스템 설정 변경 때 SystemParametersInfoForDpi의 message font로 교체하며 기존 폰트는 컨트롤 교체 후 해제한다. 조회 실패 시 기존 글꼴을 유지한다.
- Context가 소유한 글꼴은 창 메시지 루프 정리 이후 해제한다. 기본 stock font는 소유하거나 해제하지 않는다.

남은 범위: 앱/스레드 전체 DPI awareness 통합, 실제 다중 모니터·배율·작업 영역 초과·접근성 텍스트 크기, 지역화 및 WinSDK ABI 검증. 이번 상세 창 코드만으로 전체 DPI 지원 완료를 주장하지 않는다.

API 참고: https://learn.microsoft.com/en-us/windows/win32/hidpi/wm-dpichanged , https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfofordpi

## IMPL-090 — 상세 창 작업 영역 배치와 버튼 줄바꿈

상태 CODE_WRITTEN_UNVERIFIED. 빌드/컴파일/테스트/UI/모니터/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- owner 모니터의 작업 영역 내에서 상세 창 초기 크기를 제한하고 중앙 배치하도록 작성했다. 조회 실패 시 기존 기본 위치를 유지한다.
- 최소 창 크기가 현재 모니터 작업 영역보다 커지지 않도록 제한한다. 버튼은 실제 사용 가능한 client 폭에 맞춰 줄바꿈하고 필요한 footer 높이만큼 텍스트 영역을 조절한다.

남은 범위: 극단적으로 작은 작업 영역에서 전체 footer 스크롤, DPI awareness 통합, monitor 변경 중 실제 배치·키보드 순서·접근성·지역화 검증. rich card 및 전체 Windows 기능 완료를 의미하지 않는다.

## IMPL-091 — 저장된 토큰 계정 선택 backend

상태 CODE_WRITTEN_UNVERIFIED. 빌드/컴파일/테스트/설정 접근 실행/계정 수집/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- credential/organization/workspace를 제외한 계정 UUID·제목·선택 ID projection을 작성했다. privacy 활성 시 순번 이름을 사용하고 일반 제목에도 redaction을 적용한다.
- UUID로 저장된 계정을 다시 찾고 기존 선택 ID를 비교해 stale 요청을 거절한다. 중복 UUID, 삭제된 계정, 비활성 공급자, 미지원 공급자를 분리하고 refresh 진행 중에는 전환하지 않는다.
- 저장 시 계정 목록·토큰을 보존하고 activeIndex와 catalog가 요구하는 manual cookie source만 갱신한다. 성공 후 이전 표시·복사·dashboard 캐시를 철회하고 caller가 refresh를 요청하는 계약이다. 예외 내용에 credential이 포함될 가능성을 피하도록 외부에는 일반 failed 결과만 반환한다.

남은 범위: UI/콜백 연결 및 성공 후 refresh, process 간 설정 동시 쓰기, account 추가·삭제·수정, Codex visible OAuth account 선택 및 계정별 동시 표시, 실제 provider side-effect 계약·Windows 검증. 이번 backend는 아직 UI에서 호출되지 않으며 다중 계정 기능 완료가 아니다.

## IMPL-092 — 저장된 토큰 계정 트레이 선택 연결

상태 CODE_WRITTEN_UNVERIFIED. 빌드/컴파일/테스트/UI/설정 실행/계정 수집/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- refresh의 provider config snapshot에서 credential 없는 선택 목록을 menu entry로 전달하고 Saved accounts > provider > account 메뉴를 작성했다. 저장된 선택은 체크 표시, manual source 전환을 요구하는 공급자는 제목에 표시한다. 전체 popup 최대 128개 선택 command, 메뉴 생성 실패 시 command 미등록, 종료 시 사본 제거를 적용했다.
- privacy 변경 시 재열기를 요구하고 요청 UUID를 mailbox 결과와 대응시킨다. 하나의 저장 요청만 허용하며 성공·동일 선택·진행 중 수집·stale·미지원·실패를 별도로 안내한다.
- WindowsMain에서 runtime 저장과 성공 후 refresh를 연결했다. 이전 계정 표시 철회 시 No providers 메시지 대신 계정 변경 후 갱신 중 안내를 표시한다. 결과 안내는 요청 사실만 알리고 수집 성공을 주장하지 않는다.

남은 범위: 128개 초과 목록 페이지, 신규 계정 추가·삭제·수정, Codex visible OAuth 계정 전환, 동시 계정 표시·자동 소스 전환 의미, 저장 프로세스 간 동시성, 전체 Windows UI·수집·privacy 검증. 원본 다중 계정 기능 전체 완료가 아니다.

## IMPL-093 — 저장된 계정 메뉴 페이지 이동

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/계정/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 전체 계정을 128개씩 표시하고 Previous/Next 및 현재 페이지 정보를 작성했다. 공급자별 계정 구간과 현재 페이지의 교집합만 생성해 기존 공급자 하위 메뉴와 UUID 선택 계약을 유지한다.
- 페이지 이동은 기존 popup 재열기 메시지를 사용하며 설정 저장이나 수집을 호출하지 않는다. 계정 UUID 목록/순서가 변경되면 첫 페이지로 돌아간다. 메뉴 종료 시 이동 command를 제거하고 메뉴 생성 실패 때 목적지를 등록하지 않는다.

남은 범위: 페이지 이동 후 Saved accounts 하위 메뉴 자동 포커스, provider/계정 검색, 계정 lifecycle·Codex OAuth·동시 표시, 전체 Windows 검증. 새 페이지를 표시했다는 실행 증거는 없다.

## IMPL-094 — 계정 페이지 키보드 이동 맥락 보존

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/키보드/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 계정 페이지 재열기 시 Saved accounts 항목의 실제 메뉴 위치를 기록하고 기존 WM_INITMENUPOPUP/HiliteMenuItem 경로로 선택 표시하도록 작성했다. 항목 자동 실행이나 키 입력 주입은 하지 않는다.
- 기존 continuingPage가 세션 페이지에만 적용되어 계정 페이지 이동 때 keyboard return target을 잃던 부분을 연결했다. 계정 페이지 종료 후 취소 시 원래 키보드 호출 대상 복원 경로를 유지한다.
- PostMessage 실패 시 페이지 번호를 복구하고 사용자 안내를 작성했다. 일반 메뉴 열기에서는 이전 페이지 포커스 요청을 소비·초기화한다.

남은 범위: 하위 메뉴 자체의 자동 펼침·현재 계정 포커스, 키보드/마우스 혼합 및 Windows 실행 검증, 계정 lifecycle·OAuth·동시 표시. 포커스 동작 검증 완료를 주장하지 않는다.

## IMPL-095 — 계정 이름 전용 수정 backend

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/설정 쓰기 실행/계정/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- UUID와 편집 시작 시 원래 label을 비교하는 rename 요청/결과 계약과 runtime 저장 경로를 작성했다. 순서 변경은 UUID로 처리하며 기존 이름이 바뀌었거나 삭제된 경우 stale 결과를 반환한다.
- 빈 이름·제어 문자·UTF16 160단위 초과를 거절하고 양끝 공백을 정리한다. 계정 payload의 ID/token/시간/외부 ID/scope/조직/workspace 및 activeIndex는 그대로 복사한다.
- Mac의 통합 credential 편집 함수와 달리 이번 전용 이름 수정은 API key 삭제나 source 변경을 수행하지 않는다. 인증 수정이 아닌 표시 이름 수정이라는 계약이며 이름만 바꾸는 경우 기존 자격증명과 선택을 보존한다.
- 수집 중에는 저장하지 않으며 성공 후 현재 표시 설정으로 메뉴 이름을 다시 투영한다. 입력이나 예외 내용을 로그에 출력하지 않는다.

남은 범위: 편집 UI와 원래 이름 snapshot 로드/결과 연결(현재 UI 미연결), process 간 config 동시성, 계정 추가·삭제·자격증명 수정, Windows 검증. 이름 수정 UI 완료를 주장하지 않는다.

## IMPL-096 — 계정 이름 입력 UI와 저장 연결

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/설정 쓰기 실행/계정/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- Saved accounts의 현재 페이지 각 계정 옆에 Rename 명령을 추가하고 native EDIT 입력·Save/Cancel·Enter/Escape·오류 안내 창을 작성했다. 입력은 빈 값으로 시작해 redacted 메뉴 제목을 원래 이름으로 저장하지 않는다.
- 기존 원본 label 비교를 SHA256 revision 비교로 변경해 UI에 원본 label을 추가 전달하지 않는다. revision은 충돌 검사용이며 인증용 비밀값으로 취급하지 않는다. 이름 외 계정 정보는 전달하지 않는다.
- 이름 변경과 계정 선택이 같은 pending request 슬롯을 사용하고 UUID로 결과를 연결한다. 성공·변경 없음·잘못된 입력·stale·진행 중 수집·실패를 구분해 안내한다. 이름 저장 후 메뉴 재투영을 사용하며 인증 수집은 추가로 요청하지 않는다.
- 창 생성 실패·메시지 루프 오류·WM_QUIT·owner 활성 상태 복원 경로를 작성했다. 취소는 저장 요청을 보내지 않는다.

남은 범위: 이름 창 DPI/작업 영역/접근성·지역화 개선, account 목록의 rename action 배치, 추가·삭제·credential 편집·Codex OAuth·동시 표시, 실제 Windows UI/설정/ABI 검증. 전체 계정 관리 완료가 아니다.

## IMPL-097 — 계정 이름 창 배율·초기 배치

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/DPI/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 이름 창 client 크기/여백/입력칸/안내/버튼을 DPI로 환산하고 WM_SIZE 및 WM_DPICHANGED 배치를 작성했다. 현재 모니터 DPI의 system message font를 적용하며 교체 후 이전 소유 font를 해제한다.
- owner 모니터 작업 영역 안으로 초기 창 크기를 제한하고 중앙에 배치한다. 모니터 정보 조회 실패 시 기본 위치와 계산된 크기를 사용한다. 안내 영역을 넓혀 입력 오류 문구를 위한 높이를 확보한다.
- DPI/글꼴 변경이 입력 내용이나 저장 요청을 변경하지 않도록 기존 control을 유지한다.

남은 범위: 매우 작은 작업 영역에서 수직 스크롤, 앱 전체 DPI awareness, 실제 다중 모니터/텍스트 크기/접근성/지역화 검증. 계정 관리 전체 완료가 아니다.

## IMPL-098 — 새 토큰 계정 추가 backend

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/설정 쓰기/실계정/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 새 계정 UUID를 요청에서 고정해 동일 요청 재시도 시 기존 등록 여부를 확인하고 중복 추가하지 않는 backend를 작성했다. 다른 payload가 같은 UUID를 사용하면 충돌로 처리한다.
- 선택 ID가 바뀌거나 수집 중이면 추가하지 않는다. 기존 계정들을 유지하고 새 계정을 끝에 추가·선택하며 label/token/scope/organization/workspace를 정리한다. 입력 크기/NUL/label 제어 문자 제한을 적용하고 입력·예외를 로그에 출력하지 않는다.
- 원본 add 규칙의 빈 이름 fallback, catalog의 clearsAPIKeyOnMutation 및 requiresManualCookieSource를 반영했다. UUID/token/metadata 외부 검증이나 로그인 성공을 주장하지 않는다.
- 성공 후 이전 계정 표시를 철회하며 caller가 새로고침해야 한다. 현재 UI 미연결이다.

제한: 기존 CodexBarConfigStore는 JSON token 필드를 사용한다. 이 backend 자체에 Credential Manager/DPAPI 이전은 없으며 새 credential 입력 UI를 배포 가능한 기능으로 판정하기 전에 해당 보호 저장·마이그레이션/호환성 계약을 연결해야 한다. 추가 UI, provider별 credential 검증, 삭제·수정·OAuth·동시 계정 표시와 전체 Windows 검증도 남아 있다.

## IMPL-099 — Windows 사용자 범위 토큰 DPAPI codec

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/manifest 평가/테스트/DPAPI/실계정/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- WindowsTokenAccountProtection protect/unprotect 계층을 작성했다. 사용자 범위 DPAPI, UI_FORBIDDEN, provider+account UUID의 domain entropy와 versioned payload를 사용한다. machine-wide 보호 옵션은 사용하지 않는다.
- 입력·출력 크기를 제한하고 복원 시 payload version/공급자/계정/토큰 크기를 확인한다. 원문/암호문/OS 예외 내용을 로그에 출력하지 않으며 실패를 평문 반환으로 대체하지 않는다.
- Windows 시스템 Crypt32 링크를 Core에 추가했다. Native output은 LocalFree로 정리한다. Swift Data/String 복제 메모리의 완전한 zeroization은 구현되지 않았다.

남은 범위: config의 보호 token schema/읽기/쓰기 연결과 legacy migration, CLI/다른 호출부 호환성, 저장 실패·profile 변경·잘못된 암호문·복구 UX, Windows ABI 및 DPAPI 검증. 이 codec은 아직 저장 호출부에 연결되지 않아 기존 JSON token 저장을 변경하지 않는다.

API 참고: https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata , https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptunprotectdata

## IMPL-100 — 설정 token 보호 읽기·쓰기 연결

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/설정 읽기·쓰기 실행/DPAPI/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- Windows config load/saveEncodedData에 디스크 전용 변환을 연결했다. 저장 시 account.token을 제거하고 windowsProtectedToken(base64 DPAPI) 및 root windowsTokenProtectionVersion=1로 쓴다. 메모리 모델과 encodedData는 기존 resolved token 계약을 유지한다.
- 구형 평문 설정은 읽을 수 있으며 다음 정상 저장 때 token 계정을 모두 보호하도록 작성했다. 읽기만으로 파일을 수정하지 않는다. 모든 암호화를 마친 뒤 기존 atomic write를 호출하고 실패 시 평문 fallback을 하지 않는다.
- 보호 형식의 version/크기/UUID 중복, 보호·평문 혼합과 marker 누락을 거절한다. 다른 공급자/계정으로 바꾼 blob은 DPAPI binding 및 payload 확인 경로에서 거절하도록 연결했다.
- 비Windows 공통 저장소는 보호 marker를 가진 파일 읽기와 해당 기존 파일 덮어쓰기를 거절한다. 암호화/복원 예외에는 원문 데이터나 OS 상세를 포함하지 않는다.

제한: 실제 기존 파일 이전은 실행하지 않았다. tokenAccounts의 token만 보호하며 provider apiKey/cookieHeader/secretKey/pluginSecrets, 직접 JSONEncoder/파일 쓰기 경로, 구버전 바이너리 호환성·downgrade 및 백업 평문은 별도 대응이 필요하다. 기존 atomic write 이후 권한 적용 실패와 process 간 충돌도 남아 있다. 전체 credential 보관 또는 배포 준비 완료를 주장하지 않는다.

## IMPL-101 — 공급자 비밀 필드 보호 형식 v2

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/설정 읽기·쓰기/DPAPI/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- apiKey/secretKey/cookieHeader/pluginSecrets를 공급자별 DPAPI bundle에 넣고 원래 JSON 필드를 제거하도록 작성했다. token 계정과 별도 purpose entropy를 사용해 서로 바꾸어 넣을 수 없도록 분리한다.
- root 보호 형식 v2를 작성하고 legacy 평문 및 v1 token 보호 파일의 읽기를 유지한다. 다음 저장에서 v2로 변환하며 v2에 평문 비밀 필드나 보호·평문 중복이 있으면 거절한다.
- 복원 bundle은 허용된 필드명과 string/plugin string-map/null 타입만 허용한다. 암호화 실패는 기존 파일 교체 이전에 반환하며 원문 fallback은 없다.

제한: 실제 이전·암복호화는 실행하지 않았다. provider별 extension 내부 비밀 값, 직접 파일 쓰기·export 및 구버전 downgrade, 512KiB bundle 상한 안내·복구 UI·메모리 정리, Windows 검증은 남아 있다. 전체 비밀 저장 완성을 주장하지 않는다.

## IMPL-102 — 보호 설정 오류 종류와 복구 안내

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/설정/DPAPI/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 현재 provider config extension 정의를 읽었으며 추가 token 필드는 발견하지 않았다. CLI config 명령도 공통 store.save를 사용하는 것을 소스에서 확인했다. 이는 모든 직렬화 경로의 전수 검증이 아니다.
- 보호 설정의 잘못된/미지원 형식, DPAPI 복원 실패, 저장 이전 보호 실패를 구분하는 오류를 작성했다. 형식 오류를 사용자 프로필 문제로만 안내하지 않으며 원본 보존·호환 백업·작성 버전 사용을 안내한다.
- 저장 시 보호 변환 실패는 파일 교체 전 발생하므로 해당 경로에 한해 기존 설정 미교체를 명시한다. 일반 파일 쓰기/권한 적용 실패에는 이 결과를 사용하지 않는다. JSON 파서 세부 내용은 credential 입력이 섞일 수 있어 정해진 일반 오류로 변환한다.

남은 범위: 복구 전용 UI/백업 선택·프로필 이동·구버전 정책, 실제 오류 분류와 Windows 검증, 전체 계정 및 provider 기능 구현. 자동 복원·파일 삭제·실제 이전을 실행하지 않았다.

## IMPL-103 — 수동 계정 추가 UI와 보호 저장 연결

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/실계정/DPAPI/설정 쓰기/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 지원 공급자를 선택하는 Add saved account 메뉴와 이름/ES_PASSWORD credential 입력 창을 작성했다. catalog의 조직·team controls 지원에 따라 scope/organization/workspace 필드를 생성한다. 이름은 비워 두면 backend fallback을 사용한다.
- UI는 입력과 취소만 처리하며 계정 저장은 기존 actor backend와 보호 config 저장 경로를 사용한다. 공유 pending 슬롯·요청 ID로 계정 추가/선택/이름 변경 중복을 막고 결과를 대응한다.
- 저장 성공 뒤 사용량 refresh를 요청하고, 저장 성공을 인증 검증 완료로 표시하지 않는다. 지원 해제·stale 선택·수집 진행 중·입력 실패·보호 또는 저장 실패를 각각 안내한다.
- 기존 이름 창 구조의 DPI/system font/작업 영역/WM_QUIT/owner 복원 처리를 사용했다. 토큰이나 draft를 로그·결과 안내에 출력하지 않고 자동 clipboard 읽기나 로그인 probe도 추가하지 않았다.

남은 범위: credential 종류별 안내·OAuth 전용 플로우·입력 실패 시 draft 보존 UX, 매우 작은 화면 스크롤/접근성/지역화, credential 변경·계정 제거·동시 표시, Windows ABI/DPAPI/실제 계정 검증. 메모리 token 복사 완전 삭제를 보장하지 않으며 전체 계정 관리 완료가 아니다.

## IMPL-104 — 계정 입력 조건 공유와 필드별 안내

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/계정/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 추가 UI와 backend의 이름/토큰/scope/조직/workspace 입력 조건을 WindowsAccountInputRules로 공유한다. UI가 놓치던 optional 필드 제어 문자 및 길이 조건을 저장 요청 전에 안내한다.
- 잘못된 필드에 포커스를 옮기고 창과 입력을 유지한다. 오류에 실제 필드 값이나 토큰을 출력하지 않는다. 이는 형식 확인이며 인증 성공 확인은 아니다.

남은 범위: backend 저장 실패 시 draft 재편집, provider별 scope 의미·credential 종류 확인, 접근성/작은 화면·Windows 검증 및 전체 계정 관리 구현.

## IMPL-105 — 공급자별 추가 계정 metadata 규칙

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/API/계정/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- provider catalog의 조직/team 입력 지원과 실제 z.ai settings의 personal/team 및 필수 Organization/Project 계약을 shared input rules에 연결했다. UI와 backend 모두 사용한다.
- z.ai scope는 소문자로 정규화하고 빈 값은 기존 personal 기본값을 따른다. 잘못된 scope나 team의 조직/project 누락은 저장 전에 해당 필드에 안내한다. UI의 workspace 저장 필드를 실제 의미인 Project ID로 표시한다.
- 지원하지 않는 공급자에 scope/조직/workspace 값이 전달되면 거절한다. credential 유효성이나 조직 존재 여부를 원격 확인하지 않는다.

남은 범위: provider별 credential parsing/OAuth·scope 선택 control 개선·API region 안내·저장 실패 재편집, Windows UI와 실제 계정 검증, 전체 계정 관리 구현.

## IMPL-106 — z.ai personal/team 선택 control

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/실계정/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- z.ai scope 자유 입력을 Personal/Team 라디오 선택으로 바꾸고 기본 personal을 명시한다. 선택 변경은 입력 상태만 바꾸며 저장·수집을 실행하지 않는다.
- personal에서는 조직/project 입력을 비활성화하고 저장 payload에서 제외한다. 입력칸 자체 내용은 보존해 team으로 돌아갈 때 다시 편집할 수 있다. team에서는 두 필드가 필요하다는 안내를 표시하며 기존 shared rules를 유지한다.
- DPI 배치·system font 갱신에 새 control을 포함한다. 다른 공급자 입력 계약은 유지한다.

남은 범위: 키보드 라디오 그룹/스크린리더/높은 배율·작은 화면 실행 검증, region 안내·credential parsing/OAuth·계정 수정 및 전체 Windows 기능 구현.

## IMPL-107 — 선택 계정 변경 시 세션 baseline 분리

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/알림/계정/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 계정 선택 저장과 새 계정 추가 성공 경로에 공통 selected-account 상태 철회를 연결했다. 공급자 단위 session transition 상태를 제거해 다음 계정의 첫 관측을 이전 계정과 비교하지 않도록 작성했다.
- Codex 전환 시 관측 watermark를 갱신하고 현재 계정 전용 historical dataset과 owner key를 비운다. history generation도 증가시켜 과거 generation의 비동기 결과 재사용을 막는 기존 guard를 사용한다. 영구 history 파일은 삭제하지 않는다.
- 계정 discriminator가 이미 포함된 quota/pace 중복 방지 기록은 보존해 같은 계정으로 돌아왔을 때 경고가 반복되지 않도록 한다. 이름 변경은 이 경로를 호출하지 않는다.

남은 범위: 이미 host mailbox 또는 OS 알림에 전달된 이전 계정 알림의 owner/generation 필터, 실제 switch·historical race·Windows 검증. 이번 변경은 알림 전달 전체의 계정 격리 완료가 아니다.

## IMPL-108 — 계정 전환 후 공급자 알림 mailbox 철회

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/알림/실계정/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- runtime의 session/quota/pace 알림에 providerID를 전달한다. 기존 initializer 호출 호환성을 위해 optional 기본값을 유지하지만 runtime 경로는 ID를 지정한다.
- 계정 변경 성공 시 동기 invalidation publisher로 host mailbox의 해당 공급자 알림만 제거한다. 다른 공급자 알림은 보존한다. 알림 게시와 invalidation 어댑터는 같은 runtime actor에서 순서대로 직접 호출한다.
- WindowsMain 시작 시 publisher를 연결하고 mailboxLock 안에서 세 알림 대기열을 정리하도록 작성했다.

남은 범위: 이미 mailbox에서 꺼내 렌더링 중인 알림, 표시된 OS balloon/overlay 철회, 외부 config 변경·OAuth 전환 경로의 invalidation, 실제 계정/스레드 race/Windows 검증. 이번 변경은 대기열 단계만 다룬다.

## IMPL-109 — 외부 config 계정 변경 감지

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/설정·계정/알림/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- refresh에서 읽은 선택 계정 UUID/credential/조직·scope와 공급자 인증 source·region 등을 길이 구분 digest로 비교한다. 이전 refresh와 달라진 공급자 및 활성 목록에서 제거된 공급자에 기존 계정 상태/알림 mailbox 철회 경로를 적용한다.
- 이름과 계정 목록 순서는 비교값에 넣지 않아 이름 수정이나 비선택 계정 재정렬로 baseline을 불필요하게 초기화하지 않는다. 비교용 저장에는 digest만 남기며 출력하지 않는다.
- 최초 load는 baseline으로 받아들이고 shutdown 시 비교값을 비운다. historical generation snapshot은 계정 reconciliation 이후 잡아 이번 refresh의 새 계정 결과가 과거 generation으로 오인되지 않도록 작성했다.

남은 범위: config 밖 OAuth/CLI/browser identity 변화, Codex active-source/profile 설정의 별도 owner 비교, 이미 표시된 알림 철회, 실제 외부 config 변경과 Windows race 검증. digest는 내부 변화 감지용이며 보안 인증 수단이 아니다.

## IMPL-110 — Codex 실제 선택 소스와 계정 변경 감지

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/실계정/알림/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- refresh에서 이미 캡처한 Codex reconciliation snapshot으로 요청 source, 실제 표시 계정의 source, runtime identity, managed home 경로 및 store unreadable 상태를 비교한다. 추가 credential 읽기나 인증 probe는 실행하지 않는다.
- 이전 관측과 달라지면 기존 Codex session baseline·history generation/cache·host 알림 mailbox 철회 경로를 사용한다. 최초 관측은 baseline으로 기록하고 shutdown에서는 비운다.
- historical generation은 config 및 Codex owner reconciliation 이후 캡처한다. 표시 이름과 OAuth token rotation은 owner 비교에 포함하지 않는다. 비교값은 현재 선택 계정만 메모리에 보관하고 출력·영구 저장하지 않는다.

남은 범위: unresolved 상태끼리 식별 불가능한 외부 credential 교체, 다른 공급자의 ambient OAuth/browser identity, 이미 표시된 알림 철회, 실제 profile/managed/live 전환 및 Windows race 검증. 전체 계정 기능 완료를 의미하지 않는다.

## IMPL-111 — 저장 계정 credential 교체 backend

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/credential/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 기존 토큰을 UI에 전달하지 않는 단일 opaque UUID 편집 티켓 begin/cancel/save API를 작성했다. 현재 계정 전체 revision digest는 runtime 내부에만 유지하며 10분 만료와 새 편집 시작·shutdown 정리를 적용한다.
- 저장 시 config를 다시 읽어 account UUID·revision·활성 공급자·중복 UUID를 확인한다. refresh 중에는 변경을 거절한다. 기존 계정 ID/이름/metadata/선택 index를 유지하고 토큰만 교체한다.
- 현재 선택 계정 교체에만 공급자 manual source/API key 규칙과 기존 session/history/mailbox 상태 철회를 적용한다. 비선택 계정 교체는 활성 계정을 바꾸지 않는다. 저장은 Windows 보호 config 경로를 사용한다.

남은 범위: native 교체 UI/host/Main 연결, provider별 credential 구조 안내·정규화, scope/org 편집, 프로세스 간 동시 저장 및 원자 쓰기 후 권한 오류 처리, Windows 실행 검증. 이 batch는 사용자에게 노출되는 기능 완료가 아니다.

## IMPL-112 — 네이티브 credential 교체 입력

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/credential/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 이름 변경 대화상자의 window/message loop/DPI/font/keyboard 경로를 공유하는 credential 교체 모드를 추가했다. 입력은 항상 빈 값으로 시작하고 ES_PASSWORD로 가린다.
- credential 모드는 전체 토큰 또는 cookie header 교체 안내와 인증 검증을 의미하지 않는 저장 안내를 표시한다. 비어 있는 값·NUL·65536 UTF-8 bytes 초과를 거절하며 잘못된 입력은 창을 유지한다.
- 이름 변경의 입력 제한은 유지한다. UI는 기존 credential을 받지 않으며 결과 문자열은 저장 호출에만 전달해야 한다.

남은 범위: tray 메뉴 및 ticket begin/cancel/save의 host/Main 연결, 공급자별 문구, 작은 작업 영역과 접근성, 문자열 메모리 zeroization, Windows 실행 검증. 아직 사용자 메뉴에서 호출되지 않는다.

## IMPL-113 — credential 교체 메뉴·host·Main 연결

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/계정/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 페이지별 저장 계정 메뉴에 credential 교체 항목을 추가하고 provider/account UUID를 보존한다. privacy 변경과 다른 계정 저장 진행 중에는 편집 시작을 거절한다.
- host mailbox에서 begin 결과를 받은 후 UI thread에 masked 입력을 표시한다. 취소/열기 실패 및 늦게 도착해 거절된 load 결과의 ticket은 취소한다. modal/editor guard와 기존 wake 경로를 공유한다.
- WindowsMain이 runtime begin/replace/cancel을 호출한다. save 결과 후 ticket을 정리하고 성공 시 refresh를 요청한다. 성공 메시지는 인증 검증과 구분하며 오류 메시지에 credential을 포함하지 않는다.

남은 범위: 공급자별 credential parsing/안내, scope/org metadata 편집, 만료·refresh 경합·shutdown·접근성·작은 화면 Windows 검증, 실제 인증 성공 확인. 새 경로는 실행하지 않았다.

## IMPL-114 — 공급자별 credential 교체 안내

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/계정/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 원본 SettingsStore+TokenAccounts와 TokenAccountSupport를 읽고 저장 시 trim, 소비 시 공급자 credential routing을 유지한다. cookie header 일괄 변환으로 OAuth 등의 원본 입력 계약을 변경하지 않는다.
- 편집 begin 결과에 비밀정보 없는 UsageProvider를 전달하여 native 교체 화면에서 카탈로그 title/subtitle/placeholder와 공급자 표시 이름을 사용한다. 기존 credential은 전달하지 않는다.
- 설명 공간과 창 높이를 credential 모드에 맞게 늘리고 이름 편집 크기는 유지한다. 인증 성공 미검증 안내도 유지한다.

남은 범위: 긴 설명·작은 화면·고배율·접근성 동작, 공급자별 실제 credential 적용, scope/org 편집, 전체 Windows 기능 및 실행 검증.

## IMPL-115 — 계정 metadata patch backend

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/계정/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- scope/organization/workspace 각각 unchanged와 replace(nil 포함)를 구분하는 patch를 추가했다. 다른 필드를 수정할 때 기존 값을 암묵적으로 지우지 않는다.
- 기존 credential 편집 ticket·revision·만료·refresh guard·보호 저장 경로를 공통 update 함수로 공유한다. metadata-only 수정은 token을 runtime 내부에서 유지한다.
- 공급자 지원 필드와 z.ai team 필수 값을 기존 shared rules로 판정하며 선택 계정 변경에는 기존 상태 철회를 적용한다. provider credential 교체 호출 계약도 유지한다.

남은 범위: metadata snapshot·native 편집 UI/host/Main 연결, 공급자별 canonical scope 처리, Windows 입력·동시 저장 검증과 전체 계획 기능. backend만 작성되었으며 UI에는 노출되지 않는다.

## IMPL-116 — metadata 편집 snapshot 조회

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/계정/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- metadata 지원 공급자의 현재 scope/org/workspace와 edit ticket을 하나의 config read로 캡처하는 begin API를 추가했다. credential이나 digest는 UI snapshot에 넣지 않는다.
- 기존 단일 ticket을 공유해 새 편집 시작은 이전 편집을 대체하며 cancel/expiry/save revision 경로를 유지한다. 지원하지 않는 공급자·중복 UUID·사라진 계정은 unavailable 처리한다.
- snapshot에서 unchanged와 replace를 구분하는 patch 생성 API를 추가했다. scope가 실제 교체될 때만 소문자로 정규화하고 기존 미수정 값은 유지한다.

남은 범위: native metadata 입력 UI/host/Main 연결, 개인정보 표시 정책, legacy invalid metadata 편집 안내, Windows 실행 검증 및 전체 계획 기능.

## IMPL-117 — native metadata 편집 대화상자

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/계정/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 지원되는 scope/org/workspace만 현재 snapshot 값으로 채우고 unchanged/replace patch로 반환한다. credential은 입력·전달하지 않는다. 미변경 nil/empty 원본 구분을 유지한다.
- 기존 native modal/DPI/font/keyboard 경로를 바탕으로 별도 편집 대화상자를 작성했다. 512자를 넘거나 NUL을 포함한 기존 값은 자동 잘림 없이 열기 실패로 처리한다.
- 필드 오류와 z.ai team 필수 값을 inline 안내하고 입력을 유지한다. personal 전환 시 org/project를 암묵적으로 삭제하지 않으며 각 필드를 비우면 명시적 삭제로 처리한다.

남은 범위: tray/host/Main 연결, privacy 표시 가드, 오류 상세·legacy 긴 값 복구, scope 선택 UX, 고배율·작은 화면·접근성 및 Windows 실행 검증.

## IMPL-118 — account metadata 메뉴 및 저장 연결

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/계정/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 지원 공급자의 저장 계정 메뉴에 Edit scope를 추가하고 UUID를 통한 begin/snapshot/editor/patch/save 경로를 연결했다. 성공 후 Main에서 usage refresh를 요청한다.
- host mailbox와 기존 계정 변경 pending slot을 사용한다. 취소·열기 실패·늦은 load 거절·save 종료 시 opaque ticket을 정리한다. 오류 메시지에는 계정 metadata나 credential을 넣지 않는다.
- Hide personal info 활성 상태에서는 metadata 편집을 열지 않으며 command 및 비동기 load 완료 시점에 다시 확인한다. 이는 현재 값을 화면에 채우는 편집기의 개인정보 표시 가드다.

남은 범위: modal 열린 후 외부 privacy 변경 대응, scope 선택 UX, 긴 legacy 값 복구, refresh 경합·shutdown·작은 화면·접근성 및 Windows 실행 검증, 전체 기능 구현.

## IMPL-119 — 저장 계정 삭제 backend

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/계정 삭제/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 삭제 확인용 snapshot은 공급자, 활성 계정 여부, 남을 계정 수와 opaque ticket만 전달한다. 저장 시 대상 revision·전체 계정 UUID 순서·활성 계정·만료를 다시 확인한다.
- 원본의 선택 규칙대로 비선택 계정 삭제 시 활성 UUID를 보존하고, 선택 계정 삭제 시 같은 위치 또는 마지막 남은 계정을 선택한다. 마지막 계정이면 tokenAccounts를 nil로 저장한다.
- catalog API key 제거 규칙과 selected/source 변경의 session/history/mailbox 상태 철회를 연결한다. config 파일·history 파일은 삭제하지 않는다. 실제 계정 삭제는 실행하지 않았다.

남은 범위: 명시적 삭제 확인 UI/host/Main 연결, 마지막 계정 삭제 후 ambient source 안내, Antigravity shared OAuth cache 정리 parity, 동시 저장 및 Windows 검증. 이번 API는 config 계정 제거만 담당한다.

## IMPL-120 — 저장 계정 삭제 확인 및 메뉴 연결

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/실제 계정 삭제/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 저장 계정 메뉴 Remove 항목에서 impact ticket을 요청하고 UI thread의 기본 No 확인 창을 통과한 경우에만 삭제 API를 호출한다. 선택 계정 변경·남은 계정 수·마지막 계정 삭제 후 ambient source 가능성·복원 시 credential 재추가를 안내한다.
- 취소·확인 창 실패·늦은 load 거절·save 종료 시 removal ticket을 정리한다. 기존 pending slot/모달 가드/메일박스를 사용하고 성공 후 refresh를 요청한다.
- 원격 계정이나 토큰 취소와 로컬 config 제거를 구분한다. 실제 계정 삭제/인증 요청은 실행하지 않았다.

남은 범위: 확인 창의 대상 식별 UX, Antigravity shared OAuth cache 정리, 마지막 계정의 source parity, Windows 클릭/취소/동시 변경/종료 검증 및 전체 기능 구현.

## IMPL-121 — 삭제 대상 식별과 privacy-bound 확인

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/실제 삭제/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 삭제 ticket과 같은 config snapshot에서 계정 위치 및 privacy-filtered label을 캡처한다. 이름은 redactor와 길이 제한을 적용하고 제어 문자/방향 제어 문자를 공백으로 바꾼다. 숨김 모드에서는 Account N으로 표시한다.
- 확인 창에 공급자·계정 이름·목록 위치를 명시한다. runtime의 기존 account revision 및 목록 순서 비교는 확인 후 대상 변경을 거절한다.
- snapshot privacy 상태가 확인 창 열기 전 또는 Yes 후 현재 설정과 달라지면 ticket을 취소하며 삭제하지 않는다. 실제 계정 작업은 실행하지 않았다.

남은 범위: 이미 열린 native MessageBox의 외부 privacy 변경 시 즉시 닫기, provider shared credential cleanup, Windows 상호작용 검증 및 전체 계획 구현.

## IMPL-122 — Antigravity shared cache 제거 parity

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/인증 캐시 읽기·삭제/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 원본의 remaining-account 및 shared-token 일치 규칙을 Windows helper에 이식했다. 같은 계정이 남아 있으면 보존하고, 없을 때 store의 lock-scoped matching delete만 호출한다. 식별자가 모두 없는 두 항목은 동일 계정으로 간주하지 않는다.
- config 저장 성공 이후 캐시 정리를 수행한다. 실패는 별도 removedWithCacheCleanupFailure로 반환하고 UI에서 계정 삭제 성공과 캐시 정리 실패를 구분한다. 이 결과에서는 Main의 즉시 refresh를 요청하지 않는다.
- 삭제 확인에 일치 Antigravity cache 정리 영향을 추가했다. 실제 파일/계정/캐시는 읽거나 삭제하지 않았다.

남은 범위: 실패 후 재시도 UI, 외부 프로세스 동시 cache 교체, 자동 refresh의 잔여 cache 재사용 정책, shared cache 자체 보호 저장, Windows 실행 검증 및 전체 기능 구현.

## IMPL-123 — cache cleanup 재시도 및 fetch 보류

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/캐시 접근·삭제/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 이미 확인된 Antigravity 삭제의 cache cleanup 실패를 runtime 내부에 보관한다. refresh 시 최신 계정 목록으로 재시도하여 재추가된 동일 계정은 보존한다.
- 실패가 남아 있으면 해당 refresh에서 Antigravity fetch를 생략하고 generic 오류 행과 copy error를 표시한다. 다른 공급자 수집은 계속한다. 성공하거나 캐시가 이미 없으면 pending을 제거한다.
- UI 부분 실패 안내에 현재 앱 세션의 수집 보류와 refresh 재시도를 설명한다. pending credential은 출력·영구 저장하지 않고 shutdown에서 비운다.

남은 범위: 재시작 이후의 지속 가능한 차단/복구 기록, 프로세스 간 cache 교체 경합, shared cache 자체 보호 저장, 재시도 UI와 Windows 실행 검증. 현재 보호는 runtime 프로세스 수명에 한정된다.

## IMPL-124 — 암호화 삭제 복구 journal

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/DPAPI/파일·캐시 접근/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- config 경로의 .removal-recovery 파일에 Antigravity pending UUID와 사용자 범위 DPAPI 암호문을 저장하는 journal을 추가했다. 삭제 복구 전용 purpose를 사용하고 label/평문 token은 디스크에 쓰지 않는다. 최대 128개/16 MiB와 중복 UUID·형식·복호화 입력 한도를 적용한다.
- config 삭제 전에 intent를 원자 쓰기로 저장한다. config 저장 실패 시 남은 계정 비교가 cache를 보존한다. 정리 성공 후 journal 갱신이 실패하면 pending을 유지하여 다음 refresh/재시작에 재시도한다.
- 최초 refresh에서 journal을 복원하며 읽기 실패는 빈 목록으로 처리하지 않고 Antigravity 수집을 보류한다. 정상적인 파일 부재만 빈 기록으로 처리한다. 빈 journal은 파일 삭제 없이 저장한다.

남은 범위: 프로세스 간 동시 writer lock, 복구 journal ACL 및 내구성/크래시 검증, 손상 복구 UI, credential 캐시 자체 보호 저장과 전체 Windows 검증. 실제 journal 생성·DPAPI·삭제는 실행하지 않았다.

## IMPL-125 — recovery/config private ACL 저장

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/ACL·파일 접근/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 기존 WindowsCredentialFileWriter의 writePrivate만 public으로 노출해 Windows host의 recovery journal이 사용하도록 연결했다. 임시 파일 생성 시 current-user protected DACL, write/flush, publish 전 DACL 재적용, 동일 디렉터리 교체 경로를 재사용한다.
- Windows 암호화 config 저장도 같은 writer로 연결했다. 암호화를 먼저 완료하며 파일 권한 실패를 성공으로 처리하지 않는다. 다른 플랫폼의 저장 경로는 그대로 둔다.
- 기존 파일은 다음 성공적인 저장 때 교체되며 이번 작업에서 사용자 파일이나 ACL을 실제 변경하지 않았다.

남은 범위: 이미 존재하는 파일의 read-time ACL 보정 정책, 디렉터리/프로세스 간 동시 쓰기, ACL·교체 실패·강제 종료 Windows 검증 및 전체 구현.

## IMPL-126 — 기존 계정 Personal/Team 선택 UX

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- z.ai scope 자유 입력을 Personal/Team 라디오로 대체했다. scope를 실제 선택하지 않은 경우 원본 값을 그대로 patch에 사용하며 nil 기본 personal 표시가 불필요한 저장 변경을 만들지 않도록 한다.
- personal에서는 org/project를 비활성화하고 저장값을 보존한다. team에서 편집/비우기 후 personal로 이동하면 명시적 변경을 반영할 수 있다. team 저장은 기존 필수 값 규칙을 유지한다.
- 알 수 없는 기존 scope는 선택 없음과 안내로 표시한다. 새 control을 DPI 배치와 font 업데이트에 포함했다.

남은 범위: 실제 라디오 키보드/접근성 동작, 작은 화면·legacy 값 편집 검증과 전체 계획 구현.

## IMPL-127 — metadata editor 개인정보 변경 취소

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/설정 접근/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- metadata 창 진입·활성화·저장 시 개인정보 숨김 설정을 다시 읽는다. 열린 창에는 250ms native timer로 로컬 표시 설정만 확인하도록 작성했다. timer 설치 실패 시 편집 창을 열지 않는다.
- 숨김 활성화 감지 시 창을 먼저 숨기고 파괴하며 unsaved patch를 반환하지 않는다. host가 ticket을 취소하고 개인정보 변경으로 저장되지 않았음을 안내한다. 창 종료 시 timer를 제거한다.
- host의 save callback 호출 직전에도 숨김 상태를 확인한다. 실제 설정 또는 창은 실행하지 않았다.

남은 범위: 타이머/메시지 큐 지연과 OS 표시 race, 다른 detail/삭제 확인 창의 live privacy 대응, Windows 실행·접근성 검증 및 전체 계획 구현.

## IMPL-128 — provider 상세 창 privacy 변경 대응

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- host가 캡처한 privacy 상태를 상세 창에 전달하고 진입·메시지 처리·command에서 재확인한다. 250ms native timer가 유휴 중 설정 변경을 감지하도록 작성했다.
- 변경 시 창을 숨긴 후 닫고 link/refresh action 대신 privacyChanged 결과를 반환한다. host는 현재 표시 설정으로 다시 열도록 안내한다.
- timer 설치 실패는 창 열기 실패로 처리하고 종료 시 timer를 해제한다. 실제 설정·창·clipboard 접근은 실행하지 않았다.

남은 범위: 메시지 큐 지연 중 표시/clipboard race, 삭제 확인 등 다른 창 대응, Windows DPI/접근성/UI 검증 및 전체 기능 구현.

## IMPL-129 — Antigravity shared OAuth cache 보호

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/DPAPI·인증 캐시 접근/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- Windows shared cache 저장을 전용 DPAPI purpose와 current-user private ACL writer로 연결했다. versioned encrypted envelope로 저장하고 plaintext fallback은 하지 않는다.
- 기존 평문 cache는 읽고 다음 save에 보호 형식으로 교체한다. 보호 envelope의 버전·키·크기를 확인하며 복호화 오류를 호출부로 전달한다. matching delete도 동일 loadUnlocked를 사용한다.
- 다른 플랫폼에서는 Windows 보호 envelope를 읽거나 save로 덮어쓰지 않도록 오류를 반환한다. token account 값과 환경변수 JSON 형식은 변경하지 않는다.

남은 범위: 구버전 바이너리 호환 안내, store fileExists의 접근 오류 구분, multi-process 갱신/복구 UX, 실제 Windows DPAPI·cache migration·OAuth 검증 및 전체 계획 구현.

## IMPL-130 — cache 접근 실패 전파

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/파일·캐시 접근/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- Windows cache load에서 fileExists 선행 판정을 제거하고 Data 읽기의 명시적 file-not-found만 nil로 반환한다. 접근 권한 및 기타 I/O 오류는 cleanup recovery 호출부로 전파한다.
- Windows cache delete도 실제 remove 오류 중 파일 부재만 성공으로 취급한다. 권한 오류를 파일 부재로 숨기지 않는다. 다른 플랫폼 경로는 유지한다.
- 보호 envelope뿐 아니라 legacy plaintext도 JSON 파싱 전에 1 MiB 한도를 적용한다. 한도는 읽은 Data에 적용되며 아직 스트리밍 메모리 제한은 아니다.

남은 범위: Windows Foundation 오류 매핑 검증, 경로/reparse·외부 프로세스 교체 경합, bounded file read, 전체 계획 및 Windows 실행 검증.

## IMPL-131 — 제한된 credential/recovery 파일 읽기

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/파일 접근/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- WindowsBoundedFileReader를 추가해 64 KiB 청크와 한도 초과 확인 1 byte로 읽는다. 정상 EOF까지 short read를 반복하고 한도 초과·읽기·close 오류를 전파한다. 명시적 파일 부재만 nil이다.
- Antigravity shared cache 1 MiB 및 removal journal 16 MiB 읽기를 연결해 Data(contentsOf:) 전체 파일 적재를 대체했다. 형식·암호화 검사는 기존 경로를 유지한다.
- 파일 크기 사전 조회에 의존하지 않아 읽는 중 커져도 누적 한도를 넘기지 않도록 작성했다. 실제 파일은 읽지 않았다.

남은 범위: Windows FileHandle 오류·short read 검증, reparse/비정규 파일과 프로세스 간 경합, config 등 다른 파일 읽기 한도 및 전체 계획 검증.

## IMPL-132 — Windows config bounded read 및 쓰기 한도

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/설정·파일 접근/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- Windows config load를 32 MiB bounded reader에 연결한다. 명시적 파일 부재만 nil이며 권한·읽기 오류는 loadOrCreateDefault로부터 전파된다.
- 암호화/base64 확장 후 결과도 32 MiB 이하인지 확인하여 다음 load에서 읽을 수 없는 파일로 교체하지 않도록 작성했다. 실패는 기존 protected write 실패로 전달한다.
- 복호화 이후 model decoding 오류도 원본 값을 포함할 수 있는 localizedDescription 대신 generic 오류로 전달한다. 다른 플랫폼 load/save 계약은 유지한다.

남은 범위: Windows 실제 오류 mapping·동시 생성/교체·한도 경계 검증, config recovery UX 및 전체 계획 구현.

## IMPL-133 — Usage & Spend / Share Stats 모델 이식

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/이력 파일·수집·UI/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 원본 Foundation 기반 SpendDashboardModel을 WindowsSpendDashboardModel로 이식했다. currency grouping, provider/model 집계, activity coverage, incomplete/overflow 규칙을 유지하기 위해 원본 모델 본문을 사용한다.
- ShareStats payload/subscription/sanitizer/builder/formatting을 Windows 이름으로 이식했다. 원본의 불완전 토큰·비용 및 모델 계열 집계 의미를 Windows 공유 화면의 입력으로 사용한다.
- 원본 controller의 365일 scan/activity horizon을 WindowsSpendHistoryPolicy로 분리했다. Mac controller·SwiftUI/AppKit은 Windows 소스에 넣지 않았다. 기존 원본 파일은 보존한다.

남은 범위: Windows cost snapshot/controller 연결, 기간·모델·프로젝트 등 native dashboard, Share Stats 카드 renderer/preview/export/clipboard, 통화·누락 데이터 의미 및 전체 Windows 검증. 이번 모델은 아직 사용자 메뉴에서 사용되지 않는다.

## IMPL-134 — spend scan lifecycle controller

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/scan·이력·UI/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- typed loader/publisher를 받는 actor controller를 작성했다. 365일 scan 요청 결과를 보관하고 기간·통화·source filter·선택 날짜는 보관된 데이터에서 다시 투영한다.
- refresh 중복 요청을 합치고 generation으로 오래된 결과를 거절한다. 계정/source 변경 invalidate API는 이전 model과 share 데이터를 즉시 비우고 작업을 취소한다.
- 실패 시 이전 model은 stale로 유지하며 generic 실패 enum을 게시한다. refreshing/failed 상태에는 share payload를 제공하지 않는다. 중복 source ID는 성공 데이터로 받아들이지 않는다.

남은 범위: 실제 비용 snapshot loader·account invalidation·Main/host 연결, native dashboard와 share renderer/export, 통화 데이터 availability·Windows 실행 검증 및 전체 기능 구현. 아직 실행 경로에서 인스턴스화되지 않는다.

## IMPL-135 — Core 비용 snapshot loader adapter

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/비용 scan·인증·파일/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 캡처된 source별 provider/환경/home/cache/cookie 옵션을 받아 CostUsageFetcher.loadTokenSnapshot을 호출하는 controller loader adapter를 작성했다. source ID 중복/빈 값은 거절한다.
- Codex는 명시적 home을 요구하고 scoped environment를 사용한다. 동일 시각/calendar/historyDays의 optional cached activity를 순차로 읽어 partial coverage 모델에 전달한다.
- 취소를 각 scan/optional activity 이후 확인하며 required scan 실패는 controller의 실패 상태로 전달한다. 환경/cookie는 출력하지 않는다. provider 지원 여부는 Core의 계약을 따르며 가짜 결과를 만들지 않는다.

남은 범위: config/managed/live/profile에서 Source를 만드는 resolver, 캐시 소유권 경로·provider cost 설정·OpenCodeX 입력, Main/host/dashboard/share 화면, per-source 부분 실패 표현, Windows 실행 검증. 실제 수집은 실행하지 않았다.

## IMPL-136 — 비용 수집 source별 부분 실패

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/수집/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- loader는 개별 source 실패 시 비밀정보 없는 source ID/provider만 기록하고 다음 source 수집을 계속하도록 작성했다. task 취소는 부분 실패로 삼키지 않고 전체 generation을 취소한다.
- controller snapshot에 sourceFailures와 partial phase를 추가했다. 성공 결과는 최신 데이터로 집계하며 실패 source를 0 사용량 데이터로 만들지 않는다. 성공/실패 목록을 합쳐 중복 source ID를 거절한다.
- partial 상태에서는 share payload를 제공하지 않아 일부 공급자가 빠진 통계를 전체 수집 결과처럼 공유하지 않는다. 전체 loader 실패에서 이전 데이터 stale 보존은 유지한다.

남은 범위: source resolver·Main/host 연결, 실패 행과 재시도 UI, 사용자 선택에 따른 부분 공유 정책, 실제 수집·Windows 실행 검증 및 전체 계획 구현.

## IMPL-137 — 설정 기반 native spend source resolver

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/계정·환경·파일 수집/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 전달된 config와 cost-enabled provider 집합의 교집합에서 source를 만든다. 기존 ProviderAccountContext의 선택 계정 환경 주입 및 cookie settings 규칙을 재사용하고 중복 provider/account UUID를 거절한다.
- Codex live/managed/profile home을 전달된 reconciliation snapshot에서 선택하며 context 부재/unreadable managed store를 오류로 처리한다. 실제 계정 파일을 다시 읽지 않는다.
- provider/account UUID/home의 길이 구분 digest로 opaque source ID와 개별 cache root를 만든다. 표시에는 공급자 이름만 사용하고 구독 이름은 미확정 nil로 둔다.

남은 범위: cost enabled 설정 resolver·Main/controller lifecycle 연결, 여러 visible Codex source 동시 집계 및 ledger/cache ownership parity, OpenCodeX 입력·구독 정보·native dashboard/share UI, Windows 실행 검증. 현재는 공급자별 선택 계정의 native source 구성 단계다.

## IMPL-138 — Windows 비용 설정 및 capability gating

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/defaults 접근·수집/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- Windows 전용 suite에 전체 비용 수집 opt-in, Codex local ledger, 기간·통화·source 숨김 옵션을 읽고 쓰는 설정 모델을 작성했다. 원본처럼 수집 기본값은 off이며 지원 여부는 tokenCost.supportsTokenCost를 사용한다.
- 활성 provider와 비용 수집 설정의 교집합을 source resolver로 전달한다. 대시보드 기간은 1...365로 제한하고 통화/source 식별자 형식을 정리한다. 통화 변환 지원 여부는 기존 집계 모델이 판단한다.
- 옵션은 controller 입력으로 변환하며 설정을 읽는 것만으로 scan을 실행하지 않는다. 실제 설정 변경은 실행하지 않았다.

남은 범위: native 설정 UI와 Main/host lifecycle 연결, ledger 수집 정책·timezone pinning·OpenCodeX source, 전체 비용/공유 UI와 Windows 검증. UserDefaults save는 OS durable write 검증을 의미하지 않는다.

## IMPL-139 — 비용 이력 bucket timezone

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/설정·scan/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- Core CostUsageBucketTimeZone 규칙으로 Windows 설정의 시간대 식별자를 읽고 설정 save 시 수집 활성화보다 먼저 저장한다. 설정 load 자체는 저장하지 않는다.
- 동일 설정의 bucketCalendar를 loader factory에 전달하는 overload와 dashboard Options 시간대 필드를 추가했다. 집계 build에서도 해당 Gregorian calendar를 사용한다.
- 잘못된/없는 저장 식별자는 현재 시간대로 대체한다. 아직 Main에서 설정을 저장·loader 생성하는 흐름을 연결하지 않았으므로 초기 pin의 실제 지속성은 그 연결이 필요하다.

남은 범위: Main/설정 UI 연결, 시간대 변경 시 기존 scan 무효화와 재수집 정책, DST·경계·Windows 검증 및 전체 계획 구현.

## IMPL-140 — 비용 수집 구성 교체와 표시 옵션 분리

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/수집/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- controller의 loader와 옵션을 한 actor operation으로 교체하는 API를 작성했다. 교체 시 generation을 갱신하고 작업 취소·이전 scan/share/오류 제거 후 idle snapshot을 게시한다.
- 기간·통화·필터 변경은 보관된 데이터에서 재집계하되 bucket 시간대 변경은 requiresCollectionReconfiguration으로 거절한다. 생성 시 옵션을 받을 수 있으며 유효 시간대 식별자를 고정한다.
- refresh task가 시작 당시 loader를 캡처하고 실행 전에도 generation/취소를 확인하도록 작성했다. 이미 진행 중인 이전 수집의 결과는 generation으로 거절한다.

남은 범위: Main/설정 UI에서 같은 calendar의 loader/옵션 생성 및 교체 연결, 실제 native dashboard/share 화면, 취소된 수집의 캐시 쓰기 종료 보장·Windows 검증 및 전체 계획 구현. 아직 controller는 앱 실행 경로에 연결되지 않았다.

## IMPL-141 — Windows runtime 비용 수집 연결

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/설정·로그 수집/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 기존 provider 사용량 refresh 게시 후 같은 config/Codex reconciliation capture로 비용 source를 만들고 controller를 생성·수집하도록 연결했다. 비용 설정이 off이거나 지원 provider가 없으면 disabled 상태로 끝내며 수집하지 않는다.
- 활성 수집 전 설정의 bucket timezone을 저장하고 provider/account별 spend-cache 하위 경로를 사용한다. 비용 실패는 별도 상태로 보관해 사용량 표시를 덮어쓰지 않는다. source별 partial 오류는 controller snapshot을 유지한다.
- runtime 소유 snapshot 조회 API를 작성했다. 새 refresh/계정 변경은 이전 snapshot을 즉시 제거하고 generation으로 이전 결과를 거절한다. 스캔 중 외부 비용 설정이 바뀌면 결과를 폐기한다. shutdown은 controller를 중지한다.

남은 범위: native 비용 설정/대시보드/공유 UI, 표시 옵션만 변경하는 재집계 연결, refresh마다 controller 재생성에 따른 stale/캐시 최적화, 외부 계정 파일 변경 실시간 감지, 여러 Codex source/OpenCodeX parity 및 Windows 검증. 실제 앱이나 비용 수집은 실행하지 않았다.

## IMPL-142 — 비용 설정 트레이 메뉴

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/앱·UI·설정 실행/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- Cost collection 하위 메뉴에 지원 공급자 비용 수집, Codex local ledger, 7/14/30/90/180/365일 표시 기간 선택을 추가했다. 현재 설정에 체크를 표시하고 저장 실패 시 일반 오류만 안내한다.
- host 설정 변경 콜백을 Main에서 runtime으로 연결했다. runtime은 기존 snapshot을 지우고 수집 controller를 중지한다. 사용량 refresh 중 변경이면 후속 refresh 플래그를 남겨 기존 coalescing으로 요청이 사라지지 않도록 작성했다.
- shutdown은 비용 설정 재갱신 플래그를 지운다. 비용 수집과 ledger 기본값 off는 유지한다.

남은 범위: 비용 대시보드/차트/공유 화면, 통화/시간대/source 세부 설정, 기간 변경 시 보관 scan 재집계 최적화, provider/account/OpenCodeX 완전 집계 및 Windows 검증. 기간 메뉴는 표시 기간을 선택하며 scan 정책은 기존 365일이다.

## IMPL-143 — 비용 요약 화면 연결

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI·수집/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- Cost collection 메뉴의 Open cost summary 요청을 Main/runtime으로 전달하고 UUID mailbox로 응답을 UI thread의 기존 읽기 전용 상세 창에 연결했다. 새 요청은 이전 대기 응답을 대체한다.
- 통화별 합계·토큰·공급자·모델·covered days·bucket 시간대를 표시하는 projection을 작성했다. 부분 수집 실패와 모델 이력 불완전을 명시하며 nil은 Unknown으로 구분한다. 모델 100개 초과는 생략 수를 표시한다.
- 수집 비활성/진행/실패/종료 상태는 각각 안내하며 이름은 redaction 및 제어문자 제거를 적용한다. 프로젝트 경로나 세션 내용은 요약에 포함하지 않는다.

남은 범위: 전체 차트/토큰 heatmap/프로젝트/세션 탐색 및 필터, native share preview/export, 표시 중 계정 변경에 따른 snapshot 갱신·요청 취소, Windows 검증. 기존 상세 창을 재사용한 요약이며 완전한 비용 대시보드 구현 완료를 의미하지 않는다.

## IMPL-144 — Share Stats 텍스트 복사

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/클립보드·UI·수집/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- Copy Share Stats 메뉴 요청을 Main/runtime으로 연결했다. ready snapshot, stale 아님, 공유 payload 존재, 수집 당시와 현재 설정 일치를 모두 요구한다. 부분 실패/갱신/빈 공유 데이터는 복사하지 않고 안내한다.
- 원본 ShareStatsFormatting.text와 sanitizer를 재사용하고 data-through 날짜는 수집 bucket calendar로 표시한다. 기존 bounded/redacted clipboard helper를 거친다.
- UUID/개인정보 표시 상태를 저장한 mailbox에서 UI thread만 클립보드에 쓴다. 계정 무효화와 트레이 비용 설정 변경은 대기 요청을 취소한다. 복사는 명시적인 메뉴 선택으로만 시작한다.

남은 범위: 이미지 Share Stats 미리보기/저장, 전체 비용 차트·필터, 외부 설정 변경 및 이미 표시된 snapshot의 즉시 갱신, Windows 클립보드/동시성 검증 및 전체 계획 구현. 실제 클립보드에는 쓰지 않았다.

## IMPL-145 — 비용 표시 통화 선택

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI·환율 요청/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- Cost collection의 Display currency 하위 메뉴에 Original currencies(auto)와 Core CurrencyExchange.supportedCurrencies를 연결했다. 현재 통화에 체크하고 기존 설정 저장/수집 갱신/대기 공유 취소 흐름을 재사용한다.
- 활성 비용 수집의 집계 전에 원본 CurrencyExchange.fetchLatestRatesIfNeeded 호출을 연결했다. USD/auto는 요청하지 않으며 나머지는 원본의 일 단위 갱신 및 실패 시 기존 환율 유지 정책을 따른다. await 이후 generation/취소/종료를 확인한다.
- 요약에 캐시 또는 근사 fallback 환율을 사용할 수 있음을 표시한다. 원본 통화 선택은 서로 다른 통화를 합산하지 않는 기존 그룹 집계를 따른다.

남은 범위: 환율 freshness/출처 상세 표시, 표시 옵션만 재집계하는 경로, 전체 차트·source 필터·이미지 공유 및 Windows 검증. 실제 네트워크 환율 요청은 실행하지 않았다.

## IMPL-146 — 표시 옵션 변경 시 비용 scan 재사용

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/옵션·환율·로그 수집/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 비용 설정에서 수집 활성화/ledger/timezone과 기간/통화/source 표시 옵션을 구분했다. 사용량 refresh가 없고 보관된 비용 snapshot이 있으면 controller.setOptions로 다시 집계한다.
- 통화 변경에만 원본 환율 갱신을 호출하고 완료 후 최신 generation/설정 일치를 확인한다. 집계 기준 시각은 이전 수집 시각을 유지하며 요약과 share payload를 동일 snapshot에서 교체한다.
- 재집계 중 기존 공개 snapshot을 비우며 계정 변경·새 refresh·종료가 generation을 바꾸면 결과를 게시하지 않는다. 수집 구성 변경/데이터 없음/controller 중지 시 기존 재수집 흐름을 사용한다.

남은 범위: 외부 계정/설정 파일 변경 즉시 감지, 네이티브 차트/source 필터/이미지 공유, 반복 설정 변경·자정·취소·Windows 검증 및 전체 계획 구현. partial scan 재집계는 partial 상태와 공유 금지를 유지한다.

## IMPL-147 — 비용 소스 포함 선택

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI·설정·수집/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 실제 수집 model.availableSources에서 stable ID/표시 이름/포함 상태를 가져오는 runtime API를 작성했다. 수집 generation과 현재 설정 일치 여부를 저장 전에 다시 확인하고 존재하지 않는 source ID를 거절한다.
- 트레이 Choose included cost sources 메뉴를 Main과 runtime에 연결했다. native popup에서 전체 포함/전체 제외/개별 토글을 제공하며 40개 초과는 하위 페이지로 나눈다. 빈 목록/4096개 초과/중복 ID는 안내한다.
- 숨김 설정 저장 후 기존 scan 재집계를 호출한다. 표시 제외는 수집을 끄는 설정이 아니며 원본 availableSources 목록을 유지해 전체 제외 후에도 다시 포함할 수 있다. 선택 시 대기 중인 Share Stats 복사를 취소한다.

남은 범위: 실패 소스의 선택/진단, 여러 Codex 계정과 OpenCodeX 입력 전체 parity, 키보드 popup 위치·DPI·접근성·동시성 검증, 전체 비용 차트·이미지 공유 및 계획 구현. UI와 실제 설정 저장은 실행하지 않았다.

## IMPL-148 — Share Stats PNG 저장

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/이미지 생성·PNG 파싱·저장 대화상자·파일 저장/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 원본 크기 1200×630의 GDI DIB 공유 카드 renderer를 작성했다. sanitized share payload의 토큰·통화·공급자·모델·coverage·data-through를 그리며 표시 한도 초과 공급자/통화는 안내한다. GDI 자원을 정리하고 BGRA를 RGB로 변환한다.
- 외부 codec 패키지 없이 bounded RGB raster를 PNG로 인코딩하는 작은 encoder를 작성했다. None 필터·stored DEFLATE·Adler32·PNG chunk CRC를 사용하며 2048×2048 크기 상한을 둔다. 인코딩 결과는 아직 생성/검증하지 않았다.
- Save Share Stats PNG 메뉴를 runtime의 ready/settings 검사를 거쳐 기존 UUID 공유 mailbox로 연결했다. native GetSaveFileNameW와 .png 확장자/덮어쓰기 확인 후 atomic write를 사용하며 개인정보 표시 상태를 저장 전후 확인한다. Windows OS Comdlg32 linker library를 추가했으며 외부 dependency는 추가하지 않았다.

남은 범위: PNG 디코딩·픽셀/텍스트/Unicode/DPI 검증, 원본 카드 세부 시각 parity, 이미지 preview·이미지 클립보드 복사, 대화상자 중 계정 변경/종료 처리, 전체 비용 차트 및 전체 계획 구현. 미검증 encoder/WinSDK 호출이므로 생성 가능한 이미지나 배포 품질을 보장하지 않는다.

## IMPL-149 — Share Stats 이미지 클립보드

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/렌더링·클립보드·붙여넣기/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- renderer가 동일 raster에서 PNG와 CF_DIB용 40-byte BITMAPINFOHEADER/bottom-up 32-bit BGRX를 함께 반환하도록 작성했다. 저장 경로는 PNG만 사용한다.
- Copy Share Stats image 메뉴를 runtime ready/설정 확인 및 UUID/개인정보 상태 확인 mailbox에 연결했다. 기존 계정/설정 변경 대기 요청 취소를 재사용한다.
- clipboard helper는 registered PNG와 CF_DIB 메모리를 모두 준비한 다음 클립보드를 열고 교체한다. 전달한 핸들은 Windows에 소유권을 넘기며 전달하지 못한 메모리는 해제한다. PNG만 복사된 부분 실패와 전체 실패를 구분해 안내한다.

남은 범위: DIB 방향·색상·PNG 디코딩·Office/그림판/브라우저 붙여넣기 검증, 이미지 미리보기/원본 디자인 상세 parity, 전체 비용 차트와 나머지 계획 구현. 실제 클립보드는 읽거나 쓰지 않았다.

## IMPL-150 — Share Stats 미리보기 창

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/이미지·UI·저장·클립보드/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- Preview Share Stats 메뉴를 기존 ready/settings/UUID mailbox에 연결했다. 동일 renderer의 PNG/DIB와 redacted 공유 텍스트를 하나의 캡처로 전달한다.
- native modal preview를 작성했다. DIB를 창 영역에 비율 유지로 표시하고 읽기 전용 텍스트 영역, PNG 저장/이미지 복사/텍스트 복사/닫기 버튼을 제공한다. 저장과 복사는 표시된 raster를 사용하며 새 데이터를 섞지 않는다.
- monitor work area와 DPI 변경에 맞춰 창/컨트롤 위치를 조정하고 Tab/Escape/종료 message loop 및 owner 활성 상태 복원을 작성했다. 개인정보 표시 설정이 바뀌면 timer/message/command 경로에서 창을 숨기고 닫는다.

남은 범위: native preview 렌더링·텍스트 접근성·DPI font·작은 화면·키보드·dialog 중 종료 검증, 계정 변경 시 캡처 취소 정책, 원본 카드 시각 상세 parity, 전체 비용 차트 및 나머지 계획 구현. 미리보기는 실행하지 않았다.

## IMPL-151 — Windows 일별 비용 이력 차트

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/차트·UI·수집/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 기존 SpendDashboardModel의 currency group/daily stack point를 native 화면용 snapshot으로 변환했다. bucket calendar로 모든 기간 날짜를 배치하고 알려진 비용 contribution만 막대로 표시한다. 누락 날짜와 실제 0 값은 구분한다.
- Open cost history chart 메뉴를 runtime 상태/설정 검사 및 UUID mailbox에 연결했다. GDI로 누적 막대를 그리는 resizable 창, 통화 전환, 클릭 날짜의 공급자별 비용/known subtotal, 읽기 전용 coverage/부분 실패 안내, refresh-and-close를 작성했다.
- 비활성/데이터 없음은 안내하고 부분 수집은 실패 source 수와 불완전한 일별 합계 가능성을 표시한다. 개인정보 표시 변경 시 창을 닫는 기존 패턴과 monitor/DPI 위치 처리를 재사용한다.

남은 범위: 시간별 drilldown·키보드 날짜 탐색·색상 legend/접근성·토큰 heatmap·프로젝트/세션 탐색·축과 tooltip 상세 디자인, 실제 GDI/Windows 검증 및 전체 계획 구현. 이 일별 차트가 전체 dashboard parity 완료를 의미하지 않는다.

## IMPL-152 — 비용 차트 날짜 탐색 및 범례

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/키보드·차트·UI/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 이전/다음 날짜·All days 버튼과 Alt mnemonic을 추가하고 날짜 경계에서는 해당 버튼을 비활성화한다. 편집 영역 밖의 Left/Right/Home/End로 날짜를 선택하고 읽기 전용 텍스트의 Ctrl+A는 전체 선택으로 처리한다.
- 차트에 source palette index와 동일한 색상 범례를 추가했다. 6개 색상 그룹에 포함된 공급자 이름을 대응시키며 긴 이름은 화면에서 말줄임하고 전체 대응은 통계 텍스트에 남긴다. 여러 소스의 색상 공유를 명시한다.
- 선택 날짜는 강조 테두리와 공급자별 비용 텍스트를 함께 갱신한다. 날짜 탐색 행 및 범례에 맞춰 plot 영역을 조정했다.

남은 범위: DPI font/작은 화면/스크린리더/키보드 실제 검증, 시간별 drilldown·토큰 heatmap·프로젝트/세션 탐색·원본 chart 디자인 parity 및 전체 계획 구현. 동작이나 접근성 완료를 주장하지 않는다.

## IMPL-153 — 토큰 활동 히트맵

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/히트맵·키보드·UI·수집/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 원본 model.tokenActivity의 isScanned/optional totalTokens를 주/요일 셀로 변환했다. bucket calendar와 월요일 시작 정렬을 사용하고 미수집/알 수 없음/확인된 0/양수 4단계를 구분한다. 양수 색상은 최대 알려진 날짜 대비 로그 스케일이며 정확한 정수는 상세 텍스트에 표시한다.
- 기존 native history dialog의 공통 modal/날짜 선택/개인정보 변경 처리를 재사용하고 chart series를 비용/토큰 종류로 구분했다. 토큰 화면에서는 통화 전환 버튼을 숨기며 행은 월~일, 열은 주 단위로 표시한다.
- Open token activity heatmap 메뉴를 runtime 설정/수집 상태 검사에 연결했다. 미수집 소스는 count에 없을 수 있음을 안내하고 부분 실패 상태도 표시한다.

남은 범위: 원본 heatmap 강도/레이아웃 세부 parity, DST/연도/밀집 셀/색상 접근성/키보드 실제 검증, 시간별 비용 상세·프로젝트/세션 탐색 및 전체 계획 구현. 실제 화면이나 수집은 실행하지 않았다.

## IMPL-154 — 프로젝트 및 최근 세션 비용 요약

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/UI·프로젝트/세션 수집/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- currency group의 프로젝트별 비용/토큰과 최근 session 비용/토큰/모델/활동 시각을 기존 비용 요약에 연결했다. 프로젝트 100개 제한 초과는 생략 수를 표시하며 sessions는 원본 모델의 최근 12개 범위를 따른다. 불완전 breakdown이 전체 합계와 일치하지 않을 수 있음을 안내한다.
- 개인정보 숨김 상태에서는 프로젝트 이름을 번호로 바꾼다. 파일 경로와 session ID는 출력하지 않으며 문자열 redaction/control 문자 제거를 유지한다.
- runtime이 요약 텍스트와 생성 당시 privacy 값을 함께 전달하도록 변경했다. host는 현재 설정과 다르면 표시를 거절하며 상세 창에도 캡처 값을 전달해 창 생성 직전/표시 중 변경 검사에 사용한다. 계정 무효화 시 대기 중 요약 요청을 취소한다.

남은 범위: 전체 프로젝트/세션 탐색·정렬·검색·선택 액션, 시간별 drilldown, 이미 열린 창의 계정 변경 처리, Windows 개인정보/UI 검증 및 전체 계획 구현. 이번 요약은 완전한 프로젝트/세션 탐색 UI를 대체하지 않는다.

## IMPL-155 — 선택 날짜 시간별 비용 상세

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/시간대·DST·차트·UI·수집/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- controller에 기존 옵션을 변경하지 않는 특정 날짜 snapshot projection을 추가했다. 보관된 scan과 수집 시각으로 원본 모델의 selectedDay/hourlyPoints를 계산하며 공유 설정은 유지한다.
- 일별 차트의 선택 날짜에 Hourly details 버튼을 연결했다. runtime은 차트의 generation, 현재 설정, 요청 통화/날짜 범위를 확인하고 await 이후에도 변경 여부를 검사한다.
- 시간별 chart series는 calendar의 실제 하루 경계를 따라 시간 구간을 만든다. 원본 시간 sample을 구간에 집계하고 nil/누락을 0으로 채우지 않는다. label에 UTC offset을 포함해 반복 시각을 구분하며 이전/다음 시간·통화 전환을 제공한다.

남은 범위: DST/비정수 오프셋/시간 sample 분포/overflow/반복 키보드/원본 tooltip 시각 parity 검증, 세션·프로젝트 전체 탐색, 추가 공급자/source 이식 및 전체 계획 구현. 시간별 값의 분포나 실제 화면을 검증하지 않았다.

## IMPL-156 — OpenCodeX 로그 Windows 파일 식별자

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/OpenCodeX 로그·파일 핸들·캐시/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 원본 OpenCodexUsageStore.statLog와 Parser의 fstat 경로가 POSIX에 의존하므로 Windows 분기를 작성했다. CreateFileW/GetFileInformationByHandle로 volume serial/file index/size를 같은 핸들에서 얻는다.
- parser의 이미 열린 FileHandle은 기존 WindowsProcess와 같은 ucrt._get_osfhandle 변환을 사용한다. 소유권은 FileHandle에 유지하며 경로 검사에서 연 핸들만 직접 닫는다.
- 경로 부재 ERROR_FILE_NOT_FOUND/PATH_NOT_FOUND만 nil로 반환하고 다른 접근/조회 오류는 전파한다. 파일 시스템 파일만 허용하며 디렉터리/크기 변환 실패를 거절한다. POSIX 경로 및 prefix digest/cursor 계약은 유지한다.

남은 범위: Windows OpenCodeX opt-in 설정/원본 subscription fan-out 병합/runtime 연결, 파일 rotation/공유 잠금/캐시·SQLite portability 검증 및 전체 계획 구현. 아직 OpenCodeX 소스가 앱 수집 흐름에 연결된 상태는 아니다.

## IMPL-157 — OpenCodeX 비용 소스 앱 연결

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/로그·SQLite·가격표·UI·수집/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- WindowsOpenCodexSpendSource에 원본 SpendDashboardSource+OpenCodex의 subscription fan-out/선호 병합 대상/별도 Codex 행 규칙을 이식했다. 별도 opencodex-cache 경로를 사용하며 기본 소스 scan 시각/calendar/historyDays로 병합한다.
- OpenCodeX opt-in 설정과 native Codex 중복 비용 숨김 메뉴를 연결했다. 기본 소스가 없어도 OpenCodeX 활성화 시 수집하고, 원본 환경 변수/홈 경로 규칙을 사용한다. 설정과 root source 숨김/병합 topology 변경은 재수집을 요구한다.
- enabled/available/confirmedEmpty/unavailable 관찰 상태를 controller snapshot으로 전달했다. OpenCodeX unavailable은 partial phase로 만들고 공유를 금지하며 요약/이력/히트맵에도 안내한다. scan capture 시각을 loader에서 유지한다.
- source 포함 메뉴는 OpenCodeX 전체 로그 root 항목을 제공해 숨긴 로그를 다시 포함할 수 있게 했다. root 숨김은 원본처럼 OpenCodeX 전체 supplement 수집을 중지한다.

남은 범위: 여러 Codex visible source/계정 귀속 완전 parity, 원본 token activity cache와 supplement 결합 세부 의미, 로그 rotation/SQLite/권한/부분 실패/가격표 Windows 검증 및 전체 계획 구현. 실제 수집이나 이미지·공유는 실행하지 않았다.

## IMPL-158 — 여러 Codex 계정/프로필 비용 수집

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/계정·auth.json·홈·비용 로그/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 원본 visible-account projection을 따라 live/managed/profile 각각을 Windows 비용 source로 만든다. 계정 ID/source 종류 기반 opaque ID를 사용하고 표시에는 Codex 번호만 사용한다. 중복 visible ID/중복 정규화 Windows 홈은 거절한다.
- 캐시는 계정/source/home/캡처 지문/bucket timezone으로 구분한다. loader는 실제 수집 전 홈 디렉터리 접근과 auth fingerprint를 확인하고, 예상 지문이 있으면 일치를 요구한다. 실제 지문 하위 캐시를 사용하고 수집/optional activity 이후 지문이 바뀌면 결과를 게시하지 않는다.
- 홈이 없는 source는 loader의 개별 실패로 처리한다. 여러 Codex 행을 기존 filter/chart/share/OpenCodeX preferred-merge 규칙에 전달하며, Codex 행이 여러 개일 때 OpenCodeX를 임의의 하나에 병합하지 않는 원본 규칙을 따른다.

남은 범위: 원본 live ledger cache ownership/barrier/tombstone 세부 parity, auth 부재/읽기 실패 구분과 원격 managed-home 정책, 별칭/하드링크 홈 중복 방지, 외부 계정 변경 즉시 무효화 및 Windows 실행 검증, 전체 계획 구현. 실제 다중 계정 수집 성공을 주장하지 않는다.

## IMPL-159 — 인증 파일 부재와 읽기 실패 구분

상태 CODE_WRITTEN_UNVERIFIED. 컴파일/빌드/테스트/auth.json·파일·권한/검증 미실시. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- Windows용 CodexCredentialFileAccess.readIfPresent를 작성했다. 기존 fixture permits/testIO 경계를 유지하고 bounded reader로 최대 지정 바이트만 읽는다. 확인된 Cocoa 파일 부재만 nil이며 접근/크기/기타 실패는 전파한다.
- CodexAuthFingerprint.fingerprintIfPresent는 4 MiB auth.json 상한을 사용하고 데이터가 있으면 기존 SHA256 규칙을 따른다. 기존 optional 지문 API의 타 플랫폼 동작은 유지한다.
- Windows spend loader의 수집 전후 지문 검사를 throwing API로 연결했다. 양쪽 읽기가 실패해 nil==nil로 통과하는 대신 해당 소스의 실패로 처리한다. fixture 승인 실패도 인증 파일 부재로 삼키지 않는다.

남은 범위: 인증/로그 읽기 사이 atomic ownership barrier, live ledger ownership/tombstone/캐시 parity, 원격 managed-home 및 외부 변경 감지, Windows 검증과 전체 계획 구현. 실제 인증 파일은 읽지 않았다.

## IMPL-160 — 비용 산정 근거와 토큰 유형 표시

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실행·검증은 하지 않았다. guidelines/COMMITS.md 부재로 핵심 커밋 규칙을 적용한다.

- 원본 PreferencesSpendDashboardPane의 요약 항목을 기준으로 Windows 요약 및 일별/시간별 차트 상세에 list-price/vendor-metered/mixed/unknown 구분, 구독 수, plan metered 금액, priced/unpriced/unmetered/estimated coverage를 연결했다.
- 입력·출력·cache read/write·reasoning 토큰을 그룹과 모델별로 표시한다. 원래 집계된 값을 사용하며 nil은 Unknown, 0은 0으로 유지하고 정확한 정수값을 표시한다.
- coverage 요청/행 개수와 covered days를 구분하고 비용은 청구 영수증이 아님을 설명한다. 토큰 클래스는 중복/부분 집계를 포함할 수 있으므로 합산하여 전체 토큰으로 간주하지 않도록 안내한다.
- 수집/가격/통화 변환 로직은 기존 모델을 사용한다. 새로운 파일 수집이나 실계정 접근은 수행하지 않았다.

남은 범위: 프로젝트/세션 전체 탐색, 비교 및 전체 대시보드 UX, live ledger ownership/cache lifecycle, Windows 실행 검증과 전체 계획 구현. 화면 동작 또는 기능 parity 완료를 주장하지 않는다.

## IMPL-161 — 비용 모델·프로젝트 전체 행 펼치기

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실행·검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- 원본 프로젝트 패널의 8행 접기/전체 펼치기에 맞춰 Windows 비용 요약도 모델·프로젝트 8행 기본 표시와 전체 펼치기를 제공한다. 기존 100행 고정 생략을 제거하며 수집된 모델의 전체 행을 표시한다.
- 동일 runtime snapshot과 privacy 값으로 접은/펼친 텍스트를 만든다. native read-only dialog의 Show all rows/Show less 버튼, keyboard mnemonic, DPI font/layout, 상단 스크롤 이동을 연결한다. 전체 행이 없는 경우 버튼을 만들지 않는다.
- 기존 provider details 호출은 optional expandedText 기본값 nil을 유지한다. privacy 변경 차단/모달 생명주기는 기존 경로를 따른다. 최근 세션 12개는 원본 모델 범위를 유지한다.

남은 범위: 대용량 목록 virtualization/search/sort, 전체 dashboard UX/비교, 계정 외부 변경에 따른 열린 창 무효화, live ledger ownership/cache lifecycle, Windows 검증과 전체 계획 구현. 수집 원본 밖의 프로젝트/세션을 복원하거나 실제 화면 검증을 수행하지 않았다.

## IMPL-162 — 비용 목록 및 상세 스냅샷 검색

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실행·검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- 공용 native read-only 상세 창에 검색 입력과 다음 찾기를 추가해 전체로 펼친 비용 모델/프로젝트 이름 및 표시된 상세 내용을 탐색한다. 검색은 현재 표시된 스냅샷에 한정하며 접힌 행은 펼쳐서 검색한다.
- Ctrl+F는 입력으로 이동, 입력에서 Enter 또는 F3는 다음 일치 항목을 선택한다. 대소문자 무시, 끝에서 처음으로 순환, no match 표시를 포함한다. 검색어는 256 UTF-16 단위로 제한하며 저장/로그/외부 전송하지 않는다.
- NSString UTF-16 range를 Win32 EDIT 선택 위치에 사용하며 선택 항목으로 스크롤한다. 펼치기 변경 시 검색 위치를 초기화하고 기존 개인정보 변경 차단과 DPI font/layout을 적용한다.

남은 범위: 대용량 가상 목록, 구조화된 정렬/필터, 비교와 전체 dashboard UX, 열린 창의 계정 무효화, live ledger ownership/cache lifecycle, Windows 검증 및 전체 계획 구현. 실제 UI 입력 성공은 미검증이다.

## IMPL-163 — 열린 스냅샷 창 무효화

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실행·검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- NSLock으로 보호하는 UUID 세대의 WindowsSnapshotValidity를 작성했다. 계정 정보 없이 열릴 때의 세대만 캡처하고 기존 계정/비용 설정의 pending-share 취소 경로에서 무효화한다.
- 공용 상세 창, 비용 차트/heatmap/시간별 창, Share Stats 미리보기에 validity closure를 전달한다. 열기 전 및 기존 modal message/250ms timer/명령 처리 경계에서 확인하고 무효화되면 창을 숨기고 닫는다.
- 창 수명 동안 상태를 공유하며 타 스레드가 직접 HWND를 파괴하지 않는다. 기존 개인정보 변경 처리와 owner 복원을 유지한다.

남은 범위: 수집부터 mailbox 표시까지 동일 ownership ticket 유지, 별도 파일 저장 대화상자 도중 무효화와 최종 파일/클립보드 게시 경계, 외부 auth 변경 감지, live ledger/cache parity, Windows 검증 및 전체 계획 구현. 모든 계정 변경 경쟁 조건이 해결되었다고 주장하지 않는다.

## IMPL-164 — 공유 저장·복사 직전 유효성 확인

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실행·검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- PNG exporter에 캡처 유효성 closure를 전달하고 저장 대화상자 전/확인 후/파일 쓰기 직전에 확인한다. 대화상자에서 기다리는 동안 계정·비용 설정이 바뀌면 저장을 거절한다.
- PNG/DIB 및 텍스트 clipboard writer는 메모리를 준비하고 clipboard를 연 뒤 EmptyClipboard 직전에 확인한다. 실패 시 기존 클립보드를 비우지 않고 준비한 메모리를 반환한다.
- Share preview는 열린 창의 동일 validity closure를 저장/복사에 전달한다. 직접 저장/복사도 host의 캡처 유효성을 전달한다. 기존 호출부는 기본 closure로 호환한다.

남은 범위: 유효성 확인과 OS 게시 사이의 원자적 처리, 수집부터 mailbox까지 동일 소유권 ticket, 중첩 저장 dialog/owner 생명주기, 외부 auth 변경 감지, live ledger/cache parity와 Windows 검증 및 전체 계획 구현. 실제 파일 저장/클립보드 변경은 수행하지 않았다.

## IMPL-165 — 공유 미리보기 중첩 대화상자 종료 순서

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실행·검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- PNG save common dialog와 오류 MessageBox가 owner timer를 처리하는 동안 미리보기 HWND가 먼저 파괴되지 않도록 childDialogOpen/closePending 상태를 추가했다.
- 계정/개인정보 변경 또는 WM_CLOSE는 창을 숨기고 종료를 예약한다. 자식 대화상자가 반환된 뒤 유효성을 확인하고 owner를 닫는다. 중첩 대화상자 동안 미리보기 명령 재진입을 거절한다.
- 저장 대화상자 이후의 기존 exporter 유효성 확인은 유지한다. 이미 닫힌 context에 대한 반복 종료도 무시한다.

남은 범위: Windows common dialog의 실제 owner/timer 동작, 종료/취소 메시지 전수 처리, 수집부터 표시까지 소유권 ticket와 원자적 게시, 외부 auth 감지, live ledger/cache 및 전체 계획 구현. 실제 저장 대화상자는 열지 않았다.

## IMPL-166 — 누락된 모델별 집계 확장 이식

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·컴파일·실행 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- WindowsSpendDashboardModel은 modelSummary 및 부분 이력 판정 함수를 호출했으나 해당 구현이 원본 SpendDashboardModel+ModelBreakdown.swift에만 남아 있었다. Windows 모델 대상에 확장이 없어 이전 구현을 실행 가능한 것으로 볼 수 없는 소스 연결 누락을 발견했다.
- 원본 확장 전체를 WindowsSpendDashboardModel+ModelBreakdown.swift로 이식했다. Windows 조건부 컴파일과 확장 대상 이름만 바꾸고 provider/model별 집계, 토큰 유형, 비용/토큰 overflow 및 invalid 처리, 정렬/rank, completeness 판정 정책을 보존했다.
- Codex 부분 모델 이력 보존, 가격 없는 named model 보존, Codex/Cursor ledger의 unpriceable cost 구분, zero/missing 및 모델 합계 coverage 규칙을 포함한다. 원본 파일은 유지한다.

남은 범위: 컴파일 및 모델 집계 실제 검증, JSON 내보내기 등 전체 대시보드 기능, ownership/cache 처리와 전체 계획 구현. 이번 확장 추가만으로 다른 누락이 없거나 빌드가 성공한다고 주장하지 않는다.

## IMPL-167 — 원본 비용 JSON 복사·내보내기

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·인코더 실행·파일 저장·클립보드 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- 원본 SpendDashboardExportPayload 및 JSONEncoder 설정(prettyPrinted/sortedKeys/iso8601), 기간별 기본 파일명을 Windows로 이식했다. 원본 요청 기간/선택일/통화 그룹/서비스/모델/coverage/tokenMix/hiddenSourceIDs 범위를 유지하며 프로젝트·세션·일별 기록 등 필드는 추가하지 않는다.
- runtime에서 수집 완료/ready/non-stale/동일 설정을 요구하고 원본 DTO를 인코딩한다. 순서를 안정시키기 위해 hiddenSourceIDs를 정렬한다. 파일은 16 MiB, 복사는 기존 65536 UTF-16 단위 제한을 사용한다. 복사 한도 초과는 JSON 파일 내보내기를 안내하고 데이터 일부를 잘라 내보내지 않는다.
- 트레이 Copy cost JSON/Export cost JSON, request UUID mailbox, UTF-8 텍스트 clipboard와 Windows .json 저장 대화상자를 연결했다. 저장은 overwrite prompt와 atomic write, 개인정보/계정 유효성 재확인을 따른다. 인코딩 실패는 사용자 오류로 전달한다.

남은 범위: 원본 partial/stale 상태에서 export하는 정책 차이(현재 Windows는 완전한 수집만 허용), 전체 Windows 실행/스키마 검증, ownership ticket/원자적 게시, live ledger/cache 및 전체 계획 구현. 실제 JSON을 생성하거나 파일/클립보드를 변경하지 않았다.

## IMPL-168 — 부분 수집 비용 JSON 내보내기

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·인코더/파일/클립보드/실행 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- 원본의 groups 존재 기준에 맞춰 Windows export에서 ready/non-stale 강제를 제거했다. 현재 설정과 일치하는 available snapshot에 비용 그룹이 있으면 일부 소스 실패/OpenCodeX unavailable 상태도 내보낸다.
- 복사·저장의 공통 JSON 결과에 copy flag와 collection notice를 담는다. 제외된 실패 소스 수, OpenCodeX 읽기 실패, snapshot stale 여부를 알리고 원본 JSON에는 이러한 상태 필드가 없음을 설명한다. schema에 임의 필드를 추가하지 않는다.
- 안내 이후 개인정보/캡처 유효성/종료를 다시 확인하고 clipboard 또는 save dialog로 진행한다. 기존 크기 제한 및 인코딩 실패 처리를 유지한다.

남은 범위: runtime이 refresh 시작 시 이전 snapshot을 비우는 정책 때문에 수집 중/전체 실패 시 이전 데이터 내보내기는 아직 불가하다. 원본의 stale 유지 lifecycle, ownership/cache 및 Windows 실행/스키마 검증, 전체 계획 구현은 남아 있다.

## IMPL-169 — 비용 설정 키 호환

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·설정 접근/실행 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- 원본 SettingsStore가 쓰는 tokenCostUsageHistoryDays, spendDashboardHiddenSourceIDs, hideNativeCodexCostWhenOpenCodexPresent를 Windows 비용 설정의 우선 키로 사용한다.
- 우선 키가 없을 때만 이전 Windows costUsageHistoryDays/spendHiddenSourceIDs/spendHideNativeCodexWithOpenCodex를 읽는다. 명시적인 false/빈 배열은 기존 값보다 우선한다. 읽기 시 저장하거나 수집을 시작하지 않는다.
- 저장 시 정규화된 동일 값을 원본 이름과 기존 Windows 이름에 함께 저장해 구버전 읽기와 기존 사용자 설정을 보존한다. 기간 clamp/source ID validation은 유지한다. 실제 사용자 defaults에는 접근하지 않았다.

남은 범위: 다른 플랫폼의 설정 suite 자동 이관은 포함하지 않는다. 구버전에서 다시 수정한 legacy 값과 이미 있는 canonical 값의 충돌은 canonical 우선이다. 전체 sync/설정 호환과 Windows 실행 검증, stale lifecycle/ownership/cache 및 전체 계획 구현이 남아 있다.

## IMPL-170 — 동일 Codex 수집의 이전 결과 유지

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·인증/수집/실행 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- Source에 값 동등성을 추가해 기존 controller와 새 source 설정을 비교한다. secret/cookie/environment를 포함한 값은 이미 loader가 보유하는 메모리 범위에서만 비교하고 디스크/로그에 기록하지 않는다. 별도 digest는 만들지 않았다.
- 설정과 모든 source 필드가 같고, 모든 source가 verifyCodexOwner 및 예상 인증 지문을 가진 Codex이며 OpenCodeX가 꺼져 있으면 이전 controller를 재사용한다. 그 외는 기존 재생성 경로를 유지한다.
- controller의 이전 snapshot을 refreshing/stale로 복사해 비용 수집 중 summary와 JSON에서 사용할 수 있게 했다. sharePayload는 제거하며 완료된 공유 카드로 취급하지 않는다. 계정 무효화 시 비교용 source를 지우고 await 이후 generation을 재확인한다.
- JSON은 retained snapshot이 있는 collecting/failed 상태에서도 내보내며 기존 stale 안내를 사용한다. 비용 요약은 snapshot이 있으면 수집/실패 상태에서도 상세를 보여준다.

남은 범위: Codex 외 provider 및 OpenCodeX의 원본 stale 유지, native usage 조회 초기 구간의 이전 화면 유지, 실제 auth 변경의 원자적 경계, source별 실패 시 과거 행 보존, Windows 실행 검증과 전체 계획 구현. 이번 단계는 전체 stale lifecycle 완성이 아니다.

## IMPL-171 — 이전 비용 결과의 차트 탐색

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·화면/인증/실행 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- retained snapshot이 있는 collecting/failed/available 상태에서 일별/시간별/heatmap/JSON 조회를 허용하는 공통 조건을 작성했다. idle/disabled/stopped는 제외하며 각 경로의 동일 설정 확인은 유지한다.
- heatmap/시간별 상세에 stale 문구를 추가하고 일별 차트의 기존 stale 안내와 맞춘다. hourly projection은 원본 snapshot loadedAt과 반환된 projection/current snapshot loadedAt이 같은지 확인해 다른 수집 결과를 혼합하지 않는다.
- 수집 중 외부 설정 불일치를 발견하면 controller뿐 아니라 retained snapshot/source/settings도 비운다. 비용 요약도 현재 설정과 collected settings가 다르면 데이터를 표시하지 않는다.

남은 범위: retained 수집 자체는 IMPL-170의 Codex 전용 제한을 유지한다. 전체 source stale lifecycle, per-source failure 보존, 수집 세대/계정의 원자적 경계, Windows 검증 및 전체 계획 구현은 남아 있다.

## IMPL-172 — 부분 합계와 모델 순위 표시

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·화면/실행 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- 이미 이식된 hasPartialCost/hasPartialTokens를 실제 summary 및 일별 비용 합계 표시에 연결했다. 원본처럼 일부 구독 값이 없는 합계 앞에 ~를 표시한다.
- 공통 accounting detail에 비용/토큰을 보고한 구독 수와 누락 값은 zero가 아니라는 설명을 추가해 차트 상세에도 전달한다. source 수집 실패 표시는 별도로 유지한다.
- provider/project rank를 표시하고 모델은 complete breakdown일 때만 rank를 표시한다. 불완전한 모델 행은 Partial로 표시하며 빈 모델 리스트는 incomplete일 때 unavailable, complete일 때 no history로 구분한다.
- 집계 산식과 JSON schema는 바꾸지 않는다. 기존 partial flag의 구독 값 존재 여부 정의를 그대로 따른다.

남은 범위: 원본의 모든 표시/내보내기 정책, 전체 provider의 stale/ownership/cache 흐름 및 Windows 검증, 전체 계획 구현. 실제 화면에서 표식이나 정렬이 맞는지는 미검증이다.

## IMPL-173 — 비-Codex 비용 캐시 소유권 분리

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·인코더/인증/파일/실행 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- 원본 sourceOwnershipFingerprints 정책을 참고해 비-Codex source의 캐시 경로를 계정 ID뿐 아니라 현재 설정·선택 계정·scoped environment·Cursor cookie·bucket timezone으로 구분한다.
- config에서는 enabled/quotaWarnings/전체 tokenAccounts를 제외하고 선택 계정만 별도로 인코딩한다. JSON sortedKeys 및 길이 prefix로 구분한 바이트를 SHA256에 전달해 경로에는 digest만 사용한다. 비밀값은 메모리에서만 처리하고 기록하지 않는다. 인코딩 실패를 빈 scope로 삼키지 않고 전파한다.
- 사용자 filter source ID는 그대로 유지하고 cacheRoot에 scope digest 하위 경로를 추가한다. 같은 UUID의 인증 정보 변경이나 scope 변경은 이전 캐시를 재사용하지 않는다. 기존 캐시 파일은 삭제/이동하지 않는다.

남은 범위: OS/파일에 있는 ambient 인증 변경 감지, provider별 token snapshot publication scope, 비-Codex stale 재사용 정책, 기존 캐시 정리 정책 및 Windows 검증과 전체 계획 구현. 실제 캐시/인증 파일을 읽거나 삭제하지 않았다.

## IMPL-174 — Windows Cursor 원격 비용 이벤트 수집

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·HTTP/API·쿠키/실행 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- CursorUsageEventsFetcher의 HTTP/JSON/페이지 집계 코드가 macOS 조건에 갇혀 있고 loadRemoteTokenSnapshot의 Cursor 분기도 macOS에만 있음을 발견했다. Windows source가 쿠키를 전달해도 이 경로가 동작하지 않는 누락이었다.
- 이벤트 수집기와 모델을 Windows에도 포함하고, Windows remote cost 경로에서 명시적 normalized cookie를 사용해 fetchUsage를 호출한다. 기존 페이지 완결성/중복 검사, token/metered 비용 집계와 오류 처리를 재사용한다.
- 일 시작 경계/기간/오늘 session, metered/list-price provenance, credential fingerprint를 기존 token snapshot 변환에 연결한다. 반환 뒤 취소를 확인한다. 쿠키가 없으면 notLoggedIn이며 기존 Cursor local CSV fallback 정책을 유지한다.

남은 범위: Windows Cursor status/quota 전체 구현, 앱/브라우저/OAuth 로그인 경로, bucket calendar parity와 local CSV fallback 소유권, 실제 API/페이지네이션 검증 및 전체 계획 구현. 수동 쿠키 경로 연결을 자동 로그인 또는 전체 Cursor 완료로 집계하지 않는다.

## IMPL-175 — Cursor 비용 집계 달력 일치

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·HTTP/날짜/실행 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- CostUsageFetcher가 가진 resolved scanner calendar를 remote Cursor 호출까지 전달한다. Windows 분기는 이 달력으로 N일 조회 시작을 계산하고 첫날 00:00으로 맞춘다.
- 동일 달력을 CursorUsageEventsFetcher.fetchUsage의 일별 이벤트 집계와 tokenSnapshot의 오늘/이력 생성에 전달한다. 대시보드가 고정한 bucket timezone과 OS 현재 시간대가 달라도 같은 날짜 경계를 사용하도록 한다.
- Bedrock 및 macOS Cursor의 기존 분기는 유지한다. 공통 remote API의 새 인수는 기본 .current를 제공한다.

남은 범위: 실제 DST/자정 이벤트 경계와 Windows 시간대 데이터 검증, Cursor local CSV 계정/소유권과 status/login 전체 경로, 전체 stale/cache 처리 및 전체 계획 구현. 실제 API 또는 날짜 검증은 실행하지 않았다.

## IMPL-176 — Cursor 이전 결과 유지와 CSV 소유권 경계

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·쿠키/CSV/HTTP/실행 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- Windows에서 명시적 Cursor cookie가 전달된 수집이 실패하면 그 오류를 전파한다. ambient CSV는 선택 계정 소유권을 증명하지 않으므로 선택 계정의 성공 결과로 대신 게시하지 않는다. cookie가 없는 local CSV 경로는 유지한다.
- 원격 비용 수집 취소 시 local fallback으로 진행하지 않고 취소를 전파한다. 일반 오류는 기존 provider별 정책을 따른다.
- Source의 supportsRetainedCollection 정책을 Codex verified fingerprint 및 Cursor normalized explicit cookie로 구성했다. runtime은 전체 Source 동등성/설정 동일성/OpenCodeX off/비어 있지 않은 source 조건과 함께 사용한다. 같은 계정 cookie/scoped cache가 유지되면 Cursor 및 Codex+Cursor 구성도 stale summary/chart/JSON을 사용할 수 있다.

남은 범위: 계정 소유권이 확인된 CSV를 명시적 계정 fallback으로 제공하는 기능, 다른 provider/OpenCodeX retained lifecycle, per-source 실패 이력 보존, Cursor status/login 전체 흐름과 Windows 검증 및 전체 계획 구현. 현재 제한을 전체 Cursor parity 완료로 보지 않는다.

## IMPL-177 — Windows Cursor 상태·쿼터 수동 쿠키 경로

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·HTTP/인증/실행 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- macOS/Linux에만 포함되던 CursorStatusProbe의 실제 응답 모델, snapshot 변환, HTTP fetch 및 parse 로직을 Windows에도 포함했다. Windows는 빈 snapshot/notSupported stub 대신 원본 모델을 사용한다.
- Windows fetch는 명시적으로 전달된 normalized cookie만 사용해 fetchWithCookieHeader로 연결한다. 기존 CursorStatusFetchStrategy 호출이 required usage-summary 및 optional auth/me/Sand/legacy usage 조회와 원본 plan/request/extra window 변환을 사용한다.
- 조회 전후 취소를 확인하며 쿠키가 없으면 noSessionCookie를 반환한다. resolveSession/browser import/기존 session store 자동 조회로 연결하지 않는다. 필요한 순수 CursorSessionIdentity 모델만 Windows 조건에 포함하고 macOS 앱 인증 코드는 기존 조건을 유지한다.
- Windows usage-summary decode 오류에는 원본 JSON 조각을 포함하지 않는다. raw data 자체는 기존 snapshot 진단 구조를 따르므로 전체 개인정보 출력 경계는 후속 대상으로 유지한다.

남은 범위: API/필드/플랜별 Windows 동작 검증, 선택적 endpoint 실패/취소 세부 처리, 자동 로그인/브라우저/WebView2/DPAPI 세션 저장, 전체 Cursor 및 전체 계획 구현. 수동 경로 포함을 전체 provider 완료로 주장하지 않는다.

## IMPL-178 — Cursor Windows 공급자 capability 연결

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·CLI/API/실행 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- Cursor supportsTokenSnapshot/supportsCostCommand가 여전히 macOS-only였음을 발견했다. IMPL-174 이후 원격 수집 함수가 있어도 capability 검사에서 차단되는 누락을 Windows 조건 추가로 연결했다.
- Linux에만 있던 manual cookie browserSupportExemption을 Windows에도 적용했다. cookieSource가 manual이고 normalized cookie가 있을 때만 브라우저 지원 검사 예외를 허용한다. 자동 브라우저 import 지원으로 표시하지 않는다.
- Windows 비용 no-data 및 notLoggedIn/noSessionCookie 안내를 선택 계정의 수동 Cookie header 설정/갱신으로 연결했다. macOS 메뉴/Safari 안내나 Linux config 경로를 Windows에 표시하지 않는다.

남은 범위: 실제 CLI→fetch→snapshot 호출 및 API/플랜별 검증, 자동 로그인과 계정 소유권 CSV, 전체 provider capability 전수 및 전체 계획 구현. capability 플래그는 구현 경로 연결이며 검증 완료 인증이 아니다.

## IMPL-179 — Windows Cursor 세션 보호 저장

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·DPAPI/세션 파일/실행 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- CursorSessionStore가 Windows에도 포함되면서 plaintext JSON save 경로가 노출되는 것을 보완했다. CursorSession.v1 전용 DPAPI purpose와 Cursor provider 바인딩으로 암호화하고 기존 private credential writer로 기록한다.
- 파일 magic/version 확인 및 16 MiB bounded read 뒤 복호화한다. plaintext 또는 다른 형식은 자동 수용/변환하지 않는다. 파일을 삭제하거나 실제 세션을 읽지 않았다.
- 저장/읽기/JSON 형식 실패는 generic persistenceFailure 상태에 담는다. cookie/path/raw 오류는 이 상태에 포함하지 않는다. 기존 메모리 세션과 자동 로그인 경로는 확장하지 않는다.

남은 범위: persistenceFailure UI 연결 및 저장 실패 rollback/재시도/clear 실패 처리, 계정별 다중 세션 및 로그인→보호 저장→조회 연결, 명시적 legacy import 정책, DPAPI/ACL Windows 검증과 전체 계획 구현. 현재 Windows 수동 쿠키 fetch는 이 store를 자동 조회하지 않는다.

## IMPL-180 — Cursor 세션 저장 실패와 로그아웃 결과

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·DPAPI/파일/실행 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- Windows setCookiesPersisted는 기존 메모리 세션을 캡처하고 보호 저장이 실패하면 복원하며 false를 반환한다. 기존 setCookies는 Windows에서 이 경로를 사용하고 macOS/Linux 동작은 유지한다.
- clearCookiesPersisted는 메모리를 즉시 비우고 파일 삭제 성공/확인된 부재만 true로 반환한다. 권한 등 삭제 실패는 false와 generic persistenceFailure로 알린다. 프로세스 재시작 후 잔존 파일 가능성을 숨기지 않고 재시도를 안내한다.
- 일부 cookie의 속성 변환이 실패해 수가 줄거나 JSON 인코딩이 실패하면 저장 실패를 기록한다. 빈 세션은 명시적 clear 경로로 처리한다.

남은 범위: 로그인 UI가 반환값을 처리하는 연결, clear 실패의 영속 tombstone/재시작 차단, 다중 계정 및 세션 선택, 실제 DPAPI/ACL/실패 경로 검증, 전체 계획 구현. 파일 삭제/저장 또는 세션 조회는 실행하지 않았다.

## IMPL-181 — Cursor 세션의 영속 로그아웃

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·DPAPI/파일/실행 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- clearCookiesPersisted는 WindowsCursorSessionFile.revoke를 호출한다. 먼저 기존 파일을 암호화된 빈 JSON 배열로 private atomic write한 뒤 제거한다.
- 제거에 실패해도 빈 세션 교체가 성공했다면 persistent logout 성공이다. 정상 reader가 빈 배열을 읽으므로 다음 실행에서 기존 쿠키를 복원하지 않는다. 남은 파일에는 이전 인증 정보가 없다.
- 보호 교체가 실패해도 파일 제거 또는 확인된 부재로 로그아웃을 마칠 수 있다. 교체/제거가 모두 실패하면 기존 generic 실패를 반환하고 메모리는 비워 둔다.

남은 범위: 동시 프로세스의 세션 재기록 조정, 쓰기/삭제 모두 거절되는 환경의 사용자 복구 안내, UI 연결과 실제 DPAPI/ACL/crash/restart 검증, 전체 계획 구현. 실제 파일을 쓰거나 지우지 않았다.

## IMPL-182 — Cursor Firefox 세션 후보 백엔드

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·브라우저/SQLite/쿠키/API/실행 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- Windows의 기존 Firefox 프로필 cookie reader를 사용하는 명시적 discover backend를 작성했다. 프로필 간 쿠키를 합치지 않고 cursor.com 및 루트 경로의 유효 쿠키만 후보로 만든다. session cookie 또는 chunk 이름 존재와 64 KiB header 한도를 확인한다.
- 프로필 읽기 실패 수를 결과로 전달하고 취소/기한 초과는 전파한다. 동기 SQLite 읽기 도중 강제 취소는 불가하며 호출 전후 deadline을 확인한다. raw 오류/쿠키는 로그에 기록하지 않는다.
- validate는 기존 수동 쿠키 probe를 호출하고 비어 있지 않은 API accountID를 요구한다. expectedAccountID가 주어지면 일치해야 한다. 후보 검증이 자동 선택/저장을 뜻하지 않는다.

남은 범위: 후보 목록/계정 선택 UI, 사용자 선택 후 계정 저장 및 상태 반환, Firefox 실행·프로필·API 검증, Chrome/Edge/WebView2 로그인, 전체 계획 구현. 브라우저나 쿠키 파일을 실제로 읽지 않았다.

## IMPL-183 — Cursor 후보 선택 runtime

상태 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·브라우저/API/계정 저장/실행 검증 미실시. guidelines/COMMITS.md 부재로 핵심 규칙을 적용한다.

- runtime에 Firefox 후보 검증 및 opaque UUID 선택 목록 반환 경로를 작성했다. 쿠키는 pending state에만 보관하고 UI DTO에는 개인정보 설정을 적용한 이름과 ID만 담는다.
- 최대 16개 후보를 순차 검증하며 60초 경계를 후보 사이에서 확인한다(진행 중 HTTP 요청은 자체 timeout 적용). 읽기/검증 실패와 미시도 수를 분리한다.
- 선택 ticket은 5분 유효하고 provider config SHA256 revision/선택 계정/개인정보 상태를 캡처한다. commit에서 재확인하고 기존 addTokenAccount의 DPAPI config 저장 및 계정 무효화 경로를 사용한다. 재조회/취소/새 요청은 pending state를 교체한다.

남은 범위: 실제 트레이 후보 선택 UI/취소/진행 표시 연결, 동기 브라우저 읽기를 actor 밖으로 이동, 만료 후보 즉시 메모리 정리, API 오류 상세 분류와 Windows 실행 검증, 전체 계획 구현. 이번 단계에서 UI로 import를 실행할 수 있다고 주장하지 않는다.

## IMPL-184 — Cursor Firefox 가져오기 UI

- Add saved account 메뉴에 명시적인 Firefox Cursor 가져오기 액션과 진행 중 중복 실행 차단을 추가했다.
- 검증 후보 선택, 가져온 계정 전용 이름 대화상자, 보호 저장 결과 안내를 runtime에 연결했다. 쿠키는 UI로 전달하지 않는다.
- 취소 API에 선택 ticket을 적용해 이전 UI의 취소가 새 요청을 취소하지 않도록 했다. 저장 후 사용자가 Refresh로 사용량을 갱신한다.
- 남은 소요: Chrome/Edge/WebView2, 동일 계정 후보 중복 병합, 후보 탐색 actor 분리, 진행 취소/시간 초과 UX, 열린 네이티브 후보 메뉴의 외부 privacy 변경 즉시 닫기. 현재 privacy는 메뉴 열기 전과 선택/저장 시 다시 확인한다.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 브라우저/계정/API 검증은 사용자 요청으로 실행하지 않았다.

## IMPL-185 — Cursor 후보 탐색 작업 수명

- Firefox 프로필/SQLite 탐색을 utility detached task로 분리해 usage runtime actor를 점유하지 않도록 작성했다. 호출 task 취소, 새 가져오기, ticket 취소 및 shutdown에 탐색 취소를 연결했다.
- 탐색 후 및 각 HTTP 후보 검증 전에 요청/종료/설정/privacy 상태를 확인한다.
- 동일 cookie header의 SHA-256 지문으로 중복 세션 후보를 제거한다. 사용자 ID만으로는 팀 컨텍스트를 구분할 수 없어 서로 다른 세션은 같은 사용자여도 유지한다. 지문은 메모리에서만 사용한다.
- 남은 소요: 동기 브라우저 I/O 내부의 즉시 중단 보장, HTTP 진행 취소/전체 deadline, UI 취소 액션, 계정/팀 식별 기반 병합, Chrome/Edge/WebView2 및 나머지 계획.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 계정/브라우저/API 검증 미실행.

## IMPL-186 — Cursor 가져오기 진행 취소

- 진행 중 가져오기 메뉴를 Cancel 액션으로 바꾸고 request/mailbox를 폐기해 늦은 응답을 표시하지 않도록 작성했다.
- UI가 시작한 task를 동기 lock 소유자로 관리한다. actor 진입 전 취소도 전달하며 host/runtime ticket을 같은 UUID로 사용한다.
- 후보 HTTP 검증 task를 보관하고 부모 취소, runtime 취소/교체/종료에 cancel을 연결했다. 저장 완료를 되돌리는 취소 기능은 아니다.
- 남은 소요: 전체 HTTP deadline, 네이티브 I/O 취소 응답성, 열린 후보 메뉴 privacy 변경 대응, Chrome/Edge/WebView2 및 나머지 계획. 실제 transport의 취소 반응은 검증하지 않았다.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실행·브라우저/API 검증 미실행.

## IMPL-187 — Cursor 가져오기 전체 deadline

- 후보마다 새 제한 시간을 시작하지 않고 탐색 시작 시 정한 60초 deadline을 HTTP 검증에 전달한다.
- 검증과 deadline timer를 구조화된 task group으로 실행하고 먼저 끝난 결과 후 다른 작업을 취소한다. deadline 경계 뒤 결과는 선택 후보에 추가하지 않는다.
- timeout 후보는 실패로 기록하고 이후 후보 검증을 중단한다. 이미 확인한 후보가 있으면 선택 목록을 유지하며 나머지는 미확인 수로 안내한다. 확인 후보가 없고 deadline을 넘겼으면 시간 초과 안내를 표시한다.
- 취소는 cooperative이며 transport 및 동기 브라우저 I/O가 응답할 때까지 drain될 수 있다. 엄격한 벽시계 60초 반환 보장이나 실측 결과가 아니다.
- 남은 소요: privacy 변경 중 열린 후보 메뉴 처리, Chrome/Edge/WebView2, 계정/팀 모델 및 전체 계획의 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실행·실제 API 검증 미실행.

## IMPL-188 — Cursor 가져오기 화면 privacy 수명

- 후보 popup이 열려 있는 동안 250ms Win32 timer로 개인정보 표시 설정을 확인하고 달라지면 EndMenu로 선택을 취소한다. timer 등록 실패 시 후보를 표시하지 않는다.
- 가져온 계정 이름 대화상자에도 privacy snapshot을 전달하고 열기 전, timer, 저장 시점에 확인한다. 설정이 바뀌면 저장 없이 닫는다.
- 기존 이름 변경/credential 교체 호출의 동작은 optional privacy 기본값을 유지한다.
- 남은 소요: Windows 메뉴 modal loop의 timer 전달 및 DPI/키보드 동작 검증, 즉시 변경 이벤트 연동, Chrome/Edge/WebView2 및 나머지 계획. timer 간격 내의 즉각적인 화면 제거는 보장하지 않는다.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실행/UI 검증 미실행.

## IMPL-189 — 가져온 Cursor 계정의 외부 ID

- API에서 확인한 Cursor accountID를 기존 ProviderTokenAccount.externalIdentifier에 함께 저장한다. 새 스키마나 수동 ID 입력 UI는 추가하지 않았다.
- 내부 추가 경로만 검증된 ID를 받으며 길이/제어문자를 제한한다. 같은 UUID 재시도도 외부 ID가 일치해야 이미 추가한 계정으로 처리한다.
- Cursor credential이 다른 값으로 교체되면 이전 외부 ID를 제거한다. 이름 변경 또는 같은 credential 유지 시 기존 ID를 보존한다.
- 남은 소요: 갱신 응답 계정 ID 불일치 차단, 팀 ID 모델, 기존 계정 가져오기 중복 정책, 추가 브라우저 지원 및 전체 계획의 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 저장/API 검증 미실행.

## IMPL-190 — Cursor quota 계정 소유권 확인

- Windows runtime이 선택 계정의 externalIdentifier를 fetch context에 전달한다. 다른 provider나 ambient 계정에서 ID를 가져오지 않는다.
- Windows Cursor status strategy는 저장된 ID가 있으면 응답 ID를 확인한 뒤 usage snapshot으로 변환한다. ID가 없거나 다르면 식별자를 노출하지 않는 오류를 반환하고 fallback하지 않는다.
- ID가 없는 기존/수동 계정은 기존 경로를 유지한다. macOS 동작 변경 없이 context 새 인자는 nil 기본값이다.
- 남은 소요: Cursor 비용 수집의 별도 응답 소유권 확인, CLI context 전달, 팀 ID 모델, 추가 브라우저 지원 및 전체 계획의 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 계정/API 검증 미실행.

## IMPL-191 — CLI 선택 계정 ID 전달

- CLI usage, diagnose, guard, hooks watch의 fetch context에 같은 선택 계정의 externalIdentifier를 전달한다. Windows Cursor의 ID 확인 조건을 앱과 동일하게 적용하는 연결이다.
- guard/watch의 updater 없는 읽기 전용 계약을 유지한다. 외부 ID를 새 출력이나 로그로 노출하지 않는다.
- cookie refresh는 account:nil로 동작하는 별도 경로여서 특정 저장 계정 ID를 부착하지 않는다. 기존 수동 계정은 ID가 없으므로 기존 동작을 유지한다.
- 남은 소요: 비용 수집의 계정 응답 확인, 팀 모델, 추가 브라우저 지원 및 전체 계획의 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. CLI 실행·빌드·테스트·lint·실제 API 검증 미실행.

## IMPL-192 — Windows Cursor 비용 소스 소유권

- 비용 소스에 선택 Cursor 계정 externalIdentifier를 캡처한다. Source 동등성에도 포함되어 ID가 바뀌면 이전 collector를 재사용하지 않는다. 기존 scope digest에도 account 전체가 포함되어 ID별 캐시 범위를 유지한다.
- ID가 있는 계정은 비용 수집 전후 명시적 동일 쿠키로 계정 ID를 확인하고, 없거나 다르면 해당 수집을 소스 실패로 반환한다. cached/browser/app auth fallback은 사용하지 않는다.
- 추가 identity 요청 2회가 발생한다. ID가 없는 기존 수동 계정 동작은 유지한다.
- 제한: 비용 이벤트 자체에 ID가 포함된 증명은 아니며 사후 확인 전에 Core 캐시 쓰기가 발생할 수 있다. 사후 확인 실패 시 새 결과를 대시보드 입력에 넣지 않는다. CLI 비용 경로, 캐시 commit 시점의 소유권 및 기존 stale 결과 정책은 별도 작업이 남는다.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 API/비용 수집 검증 미실행.

## IMPL-193 — Core Cursor 비용 snapshot 생성 경계

- CostUsageFetcher의 public/static 비용 snapshot 경로에 optional cursorExpectedAccountID를 추가하고 재시도/remote 호출까지 전달한다.
- Windows Cursor 원격 비용 요청 전후에 동일 쿠키의 계정 ID를 확인하고 성공한 뒤에만 remote snapshot을 생성한다. 명시적 쿠키 실패의 CSV fallback 차단을 유지한다.
- Windows loader의 이전 전후 확인 helper를 공통 Core 경로로 옮겨 중복 네트워크 요청을 피한다. 추가 확인 요청 수는 기존 두 번을 유지한다.
- 남은 소요: CLI cost/dashboard/serve가 선택 ID를 전달하는 연결, 원격 이벤트 자체의 계정 증명 및 기존 stale 데이터 정책. 계정 조회와 비용 조회 간 서버 상태 변경을 원자적으로 막는 보장은 아니다.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 API/캐시 검증 미실행.

## IMPL-194 — CLI 비용 계정 컨텍스트

- Cursor 비용 자격 정보를 한 번 해석하여 settings와 externalIdentifier를 같은 선택 계정에서 얻는다. 기존 cookie settings helper는 이 공통 resolver에 위임한다.
- cost 명령 및 dashboard/serve의 공통 수집 callback에 ID를 전달하고 Core 비용 조회에 연결한다. 비-Cursor에는 nil을 전달한다.
- callback 인자가 추가된 기존 테스트 호출부만 맞췄으며 테스트를 실행하지 않았다. 출력 형식이나 ID 로그는 추가하지 않는다.
- 남은 소요: 기존 stale 비용 보존 정책의 소유권 실패 처리, 팀 컨텍스트, 추가 브라우저 지원 및 전체 계획 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. CLI 실행·빌드·테스트·lint·실제 API 검증 미실행.

## IMPL-195 — 비용 계정 확인 실패 안내

- Cursor ID 미확인/불일치를 일반 parse 오류에서 전용 typed error로 구분한다. 소스 실패에는 원문/계정 ID 대신 boolean 사유만 보관한다.
- 비용 요약과 JSON 내보내기 안내에 계정 재가져오기 필요 및 실패 소스 제외를 표시한다. JSON 데이터 스키마는 변경하지 않는다.
- 소스 실패는 새 scan에서 이미 제외되고 OpenCodeX 일반 읽기 오류도 내부에서 부분 실패로 처리되고 있어, 이전 결과 보존 정책을 추정으로 변경하지 않았다.
- 남은 소요: 팀/세션 소유권 모델, 추가 브라우저 지원 및 나머지 전체 계획. 네트워크 오류를 계정 불일치라고 오분류하지 않는다.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 API/UI 검증 미실행.

## IMPL-196 — 동일 Cursor 세션 재가져오기

- 저장된 검증 ID와 정규화된 cookie가 모두 같고 별도 scope/조직/프로젝트가 없는 기존 계정이면 새 계정을 추가하지 않고 기존 선택 API로 활성화한다.
- 기존 계정 UUID/이름/자격 정보는 덮어쓰지 않는다. 결과 안내에서 기존 이름 유지와 사용량 Refresh 필요를 표시한다.
- 같은 사용자 ID라도 cookie가 다르면 팀 컨텍스트를 단정할 수 없어 별도 후보로 유지한다. ID 없는 수동 계정 자동 병합도 수행하지 않는다.
- 남은 소요: 로그인 갱신 시 동일 계정 교체 UX, 팀 컨텍스트 모델, 추가 브라우저 지원 및 전체 계획 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 저장/API/UI 검증 미실행.

## IMPL-197 — Cursor ticket 만료 수명

- 후보 발급 후 5분 task를 예약해 해당 request가 아직 유효하면 후보/세션 참조를 해제한다. 새 요청·취소·저장·shutdown 시 만료 task도 취소하며 이전 task가 새 후보를 지우지 않도록 ticket을 비교한다.
- 결과에 만료 시각을 전달하고 후보 popup timer와 이름 대화상자의 열기/저장/timer 조건에 반영한다. runtime 저장 시 만료 확인도 유지한다.
- 해제는 Swift 객체 참조 해제이며 메모리 zeroization 보장이 아니다. 앱 suspend/actor 점유 및 timer 전달 지연으로 물리적 정리 시각은 늦어질 수 있지만 만료 ticket 저장은 거부한다.
- 남은 소요: 계정 교체 UX, 팀 컨텍스트, 추가 브라우저 지원 및 전체 계획 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 UI/시간 경과 검증 미실행.

## IMPL-198 — Firefox 컨테이너 세션 분리

- Windows Firefox reader가 originAttributes 열을 읽어 cookie record의 storagePartition에 보존한다. 구버전 열 미존재는 기본 partition으로 처리하고 NULL/과대 속성은 제외한다.
- query는 기본적으로 기본 partition만 읽는다. Cursor importer만 명시적으로 전체 partition을 요청하고 프로필 안에서도 partition별로 cookie header와 후보를 따로 생성한다.
- 저장소 속성은 HTTP cookie나 UI에 포함하지 않는다. 각 후보는 기존 API 계정 확인/최대 후보 수/deadline 경로를 거친다.
- 남은 소요: Firefox 컨테이너 이름 UX, partition의 인증 의미에 대한 Windows 실증, Chrome/Edge/WebView2 및 전체 계획 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 Firefox/SQLite/API 검증 미실행.

## IMPL-199 — Firefox SQLite 취소/deadline

- Windows cookie query에 optional deadline을 추가하고 Cursor 탐색의 공유 deadline을 전달한다.
- 소유한 read-only SQLite 연결에 progress handler를 등록해 VM 실행 중 취소/시간 초과를 확인한다. callback 객체는 조회 동안 유지하고 연결을 닫기 전에 handler를 해제한다.
- 행 읽기 전과 완료 후에도 확인하며 SQLITE_INTERRUPT가 단순 프로필 읽기 실패로 변환되지 않도록 취소/timeout을 우선 전달한다. 빌린 연결은 기존 progress handler를 덮어쓰지 않는다.
- SQLite open 및 OS 파일 I/O/잠금 대기는 progress callback 밖일 수 있으므로 엄격한 wall-clock 완료 보장은 아니다. 기존 250ms busy timeout을 유지한다.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 SQLite/취소/시간 경과 검증 미실행. 추가 브라우저 지원 및 전체 계획 나머지 항목은 계속 남아 있다.

## IMPL-200 — Cursor 쿠키 후보의 결정성

- Windows BrowserCookieClient에서 CancellationError 및 timedOut을 일반 loadFailed로 감싸지 않고 전달한다.
- Cursor partition별 header 생성 시 같은 이름/같은 값은 하나로 합치고 같은 이름/다른 값은 후보 실패로 처리한다. 이름 순으로 정렬하여 DB 반환 순서에 따른 후보/캐시 지문 변동을 줄인다.
- header 이름과 값의 허용 ASCII 바이트를 검사해 제어문자/구분자 혼입을 거부하고 기존 64KiB 제한을 유지한다. 원본 쿠키 값은 로그에 남기지 않는다.
- 남은 소요: 충돌 후보 재로그인 UX, 컨테이너 이름, Chrome/Edge/WebView2 및 전체 계획 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 Firefox/API 검증 미실행.

## IMPL-201 — Firefox cookie 읽기 크기 제한

- 조회에서 반환한 행은 최대 50,000개, 복사 대상 텍스트 합계는 8MiB, 개별 열은 256KiB로 제한한다. 만료/제외할 행도 비용에 포함하며 초과 시 전체 조회를 실패 처리해 잘린 세션을 후보로 사용하지 않는다.
- 소유한 읽기 전용 SQLite 연결에는 1MiB SQLITE_LIMIT_LENGTH도 적용한다. 브라우저 DB 파일이나 빌린 연결의 설정을 변경하지 않는다.
- 원문 쿠키는 오류에 포함하지 않고 기존 SQLite 오류 코드 경로를 사용한다. Swift 객체/SQLite 내부 전체 메모리를 8MiB로 보장하는 것은 아니다.
- 남은 소요: 대용량 실제 프로필 호환성 검증, 추가 브라우저 지원 및 전체 계획의 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 SQLite/메모리 측정 미실행.

## IMPL-202 — Cursor 후보 출처 표시

- 후보 메뉴에 계정 표시와 함께 Firefox 프로필 및 기본/컨테이너/격리 세션 구분을 표시한다. 경로형 프로필 이름은 번호로 대체하고 제어문자/길이를 제한한다.
- originAttributes 전체를 노출하지 않고 단일 유효 userContextId 숫자만 컨테이너 번호로 표시한다. 사용자 지정 컨테이너 이름을 읽었다고 표시하지 않는다.
- 개인정보 숨김 모드에서는 프로필/컨테이너 이름 대신 일반 세션 번호를 사용한다. 기존 개인정보 설정 변경 시 화면 닫기와 만료 처리를 유지한다.
- 남은 소요: 컨테이너 사용자 지정 이름, 추가 브라우저 지원 및 전체 계획 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 Firefox/UI 검증 미실행.

## IMPL-203 — Windsurf Windows 수동 웹 조회

- macOS 조건에 묶인 원본 수동 session bundle 파서와 GetPlanStatus HTTP/protobuf codec을 Windows에 포함한다. 기존 daily/weekly/plan snapshot 변환을 사용한다.
- Chromium localStorage 자동 importer는 macOS에 유지한다. Windows auto는 수동 계정 설정 안내를 반환하고, 명시적 수동 세션 실패는 다른 로컬 계정으로 fallback하지 않는다.
- Windows 입력 64KiB/header 문자 확인, 응답 4MiB 해석 제한과 취소 확인을 추가한다. Windows HTTP 오류에는 응답 본문을 포함하지 않는다. 응답 제한은 transport 수신 후 적용되며 스트리밍 메모리 상한은 아니다.
- 남은 소요: Windows 로컬 Windsurf 캐시 조회, browser localStorage 가져오기/앱 로그인, provider capability/UI 세부 연결 및 전체 계획 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 Windsurf API 검증 미실행.

## IMPL-204 — Windsurf Windows 로컬 캐시

- 원본 cachedPlanInfo SQLite/JSON/UTF-16 blob 읽기 및 daily/weekly/legacy quota 변환을 Windows에 포함하고 CSQLite3를 사용한다.
- 기본 경로는 플랫폼 Roaming AppData/Windsurf/User/globalStorage/state.vscdb이며 기존 dbPath 주입을 유지한다. 읽기 전용으로 열고 busy timeout, 취소 확인 및 Windows 4MiB SQLite/값 제한을 적용한다.
- Windows 오류에서 사용자 경로와 payload decode 원문을 노출하지 않는다. 선택된 수동 웹 계정은 로컬 편집기 캐시 소유권을 입증할 수 없어 로컬 strategy를 사용하지 않는다.
- 남은 소요: Windows 설치/프로필별 경로 실증, 로컬 cache freshness/소유권 UX, 브라우저 로그인 및 전체 계획 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 로컬 캐시/앱 검증 미실행.

## IMPL-205 — Windsurf 저장 계정/CLI 연결

- Windows Windsurf descriptor에 token account credential adapter를 추가해 기존 Add saved account/선택/이름/credential 변경 UI를 사용한다. 네 필드의 Devin session JSON을 입력하도록 안내하고 JSON 내용을 Cookie prefix 정규화로 바꾸지 않는다.
- 저장 계정은 manual source를 요구한다. CLI auto는 로컬 캐시를 사용할 수 있고 manual web은 browser importer가 필요하지 않으므로 플랫폼 browser 지원 검사 예외를 연결한다.
- Windows 설정의 Web API 표시는 수동 세션임을 명시한다. macOS credential adapter와 표시 기본값은 유지한다.
- 남은 소요: 저장 계정별 설정 투영/회귀 검증, 브라우저 localStorage/앱 로그인, 캐시 최신성 및 전체 계획 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 계정 저장/CLI/UI 검증 미실행.

## IMPL-206 — Windsurf 저장 계정 settings 투영

- Windows Windsurf settingsSection에 credentialSettings 변환을 추가해 config/선택 계정으로부터 해석한 cookie source와 세션 bundle을 fetch context로 전달한다. 기존 공통 resolver의 계정별 정규화 및 manual source 규칙을 사용한다.
- 설정의 source를 WindsurfUsageDataSource에 반영한다. Windows auto에서 수동 계정이 없으면 미구현 browser importer를 먼저 시도하지 않고 구현된 로컬 strategy를 선택한다. 수동 계정은 web strategy 및 로컬 혼용 차단을 유지한다.
- macOS settings 변환/전략 선택 동작은 유지한다. 향후 Windows 자동 로그인 구현 때 auto 전략을 확장해야 한다.
- 남은 소요: 저장 계정/CLI source 조합의 Windows 회귀 검증, 캐시 최신성 표시, 브라우저 로그인 및 전체 계획 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 설정/조회 검증 미실행.

## IMPL-207 — Windsurf 로컬 캐시 최신성

- 캐시 레코드에 갱신 시각이 없어 DB 파일 mtime을 사용량 갱신 시각으로 대체하지 않는다. Windows source label/diagnostic에 캐시 최신성 미확인 및 읽기 시각과 서버 갱신 시각의 차이를 명시한다.
- 만료된 billing endTimestamp는 local 조회 오류로 처리한다. 지난 daily/weekly reset 구간은 Windows snapshot에서 제외하며 같은 캐시의 legacy 필드로 되살리지 않는다. 유효한 사용량 구간이 없으면 noData를 반환한다.
- reset/billing 시각이 없는 데이터의 최신성은 추정하지 않는다. updatedAt은 읽기 시각으로 유지하며 live 검증으로 간주하지 않는다. macOS 변환 동작은 유지한다.
- 남은 소요: Windows UI에서 진단 표시/구간 경계 실증, 브라우저 로그인 및 전체 계획 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 캐시/UI 검증 미실행.

## IMPL-208 — Windsurf 세션 저장 전 형식 확인

- 네트워크 요청 없는 수동 세션 형식 확인 API를 분리하고 Windows 웹 조회도 같은 bounded parser를 사용한다.
- Windows 계정 추가와 credential 교체는 필수 네 필드/64KiB/HTTP header 문자 조건을 만족해야 저장한다. 실패는 기존 invalidInput 결과로 반환하며 기존 저장 계정을 덮어쓰지 않는다.
- 형식 확인은 로그인 성공이나 세션 유효성 확인이 아니다. 기존 잘못된 계정의 이름/metadata 수정까지 막지 않도록 credential을 실제 교체하는 경우에만 재확인한다.
- 남은 소요: 구체적 입력 오류 UI, 브라우저 로그인 및 전체 계획 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 실제 형식 확인 API 호출·빌드·테스트·lint·저장/API 검증 미실행.

## IMPL-209 — Windsurf 입력 오류 UI

- 계정 추가 및 credential 교체 대화상자는 수동 Windsurf 세션 형식을 확인한 뒤 제출한다. 실패 시 대화상자를 닫지 않고 credential 입력으로 focus를 돌린다.
- 고정된 필수 필드/문자/크기 안내만 표시하고 파서 원문 오류나 입력 세션은 안내에 포함하지 않는다. runtime의 저장 전 재확인도 유지한다.
- 형식 확인은 네트워크 없는 순수 파싱이다. 다른 제공자 및 이름 변경 동작은 유지한다.
- 남은 소요: 실제 Windows 대화상자 안내 레이아웃, 브라우저 로그인 및 전체 계획 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 UI/API 검증 미실행.

## IMPL-210 — Windsurf 로컬 조회 취소

- Windows local strategy는 동기 SQLite 작업을 utility detached task에서 수행하고 부모 취소를 전달한다. 결과 게시 전에도 취소를 확인한다.
- 소유 SQLite 연결에 progress handler를 등록하고 종료 전에 해제한다. prepare 실패 시 statement를 정리하고 취소를 우선 전달한다. JSON 해석 후 취소를 parse 오류로 감싸지 않는다.
- OS 파일 열기/잠금 및 JSON 해석 내부는 즉시 중단을 보장하지 않는다. 기존 크기 제한과 busy timeout을 유지한다.
- 남은 소요: 실제 Windows 취소 응답성, 브라우저 로그인 및 전체 계획 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·실제 SQLite/취소 검증 미실행.

## IMPL-211 — Windsurf 세션 필드 모호성

- Windows는 accountID/accountId/devin_account_id 등 같은 필드의 별칭이 여러 개 있으면 동일한 비어 있지 않은 문자열인지 확인한다. 서로 다른 값이나 다른 타입이 섞이면 거부한다.
- key/value 형식에서 같은 키에 서로 다른 값을 반복하면 거부한다. JSON처럼 시작한 입력이 JSON/필드 해석에 실패하면 key/value 형식으로 재해석하지 않는다.
- macOS 파서 선택 규칙은 유지한다. JSON 객체 안의 정확히 같은 키 반복은 Foundation JSONSerialization의 해석에 따르며 별도 중복 키 검출은 아직 구현하지 않았다.
- 남은 소요: JSON 동일 키 중복 검출, 브라우저 로그인 및 전체 계획 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 파서 실행·빌드·테스트·lint·실제 API 검증 미실행.

## IMPL-212 — Windsurf JSON 동일 키 중복

- Foundation JSON 구문 해석 이후 원본 UTF-8에서 root 객체의 키를 별도 추적한다. 키 문자열은 JSONDecoder로 이스케이프를 해석한 뒤 비교하므로 같은 키의 유니코드 escape 표기도 중복으로 처리한다.
- 같은 값이라도 root 키 중복은 거부하고 기존 고정 오류 경로를 사용한다. 중첩 객체/배열과 문자열 안 구분자는 root 키로 오인하지 않도록 depth와 문자열 escape를 추적한다.
- sessionAuth는 root의 네 인증 필드만 사용한다. 사용하지 않는 중첩 객체의 키에는 이 중복 정책을 적용하지 않는다. 입력은 기존 64KiB 상한을 유지한다.
- 남은 소요: 실제 파서 회귀 검증, 브라우저 로그인 및 전체 계획 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 파서 실행·빌드·테스트·lint·실제 API 검증 미실행.

## IMPL-213 — Windsurf localStorage 수동 입력 호환

- 원본 importer가 처리하던 JSON.stringify된 storage value를 Windows 수동 JSON 세션에서도 한 겹 해석한다. 잘못 닫힌 문자열은 임의 quote 제거 대신 거부한다.
- 같은 필드의 별칭은 storage 문자열 해석 후 비교하며 기존 네 필드/중복 키/문자/크기 제한을 유지한다. 안내는 같은 로그인 origin에서 네 값을 함께 옮기는 수동 작업임을 명시한다.
- 자동 탐색은 기존 macOS SweetCookieKit reader 의존 때문에 Windows에 아직 연결되지 않았다. 이 변경을 자동 로그인/브라우저 가져오기 완료로 간주하지 않는다.
- 남은 소요: Windows Chromium localStorage reader 및 프로필/origin별 후보 검증·저장 UI, 앱 로그인, 전체 계획 나머지 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 파서 실행·빌드·테스트·lint·실제 브라우저/API 검증 미실행.

## IMPL-214 — 비용 세션 전체 행 확장

- Windows 비용 모델은 선택 기간에 마지막 활동이 속하는 수집된 세션을 모두 보존한다. 기존 모델 단계의 12개 절단을 제거하고 기본 요약에서만 최근 12개를 표시한다.
- 기존 Show all rows 동작은 모델/프로젝트뿐 아니라 전체 세션으로 확장한다. 접힌 화면에서 숨겨진 세션 수와 확장 안내를 표시하며 기존 최신 활동/ID 정렬을 유지한다.
- 세션 합계는 마지막 활동으로 기간에 포함한 수집 세션의 합계이므로 기간 이전 활동을 포함할 수 있다는 설명을 추가한다. 기간 총액으로 오인하지 않도록 기존 불완전 breakdown 설명도 유지한다.
- 원본 스캐너가 제공하지 않은 세션을 복원하는 기능은 아니다. 개별 세션/프로젝트 탐색, Windsurf 브라우저 가져오기 및 전체 계획 나머지는 남아 있다.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·UI·실제 비용 로그 검증 미실행.

## IMPL-215 — 비용 세션별 모델 상세

- 수집된 CostUsageSessionBreakdown에서 요청 수, 입력/출력/캐시 읽기/추론 토큰과 전체 모델 breakdown을 Windows SessionRow로 전달한다.
- 전체 행 보기에서 각 세션의 요청 수와 토큰 유형, 모델별 비용/토큰 유형을 표시한다. 기본 요약은 기존 크기를 유지한다.
- 모델 비용에는 해당 소스의 기존 통화 배수를 적용한다. 음수 토큰/잘못된 비용은 기존 nonnegative/validCost를 거쳐 누락값으로 처리하고 누락된 요청 수/토큰은 Unknown으로 표시한다. 세션에 없는 캐시 쓰기 값을 추측하지 않는다.
- 원본 세션 ID/로그 경로는 화면에 추가하지 않으며 기존 privacy와 snapshot 유효성 처리를 유지한다. 모델 내역의 합계 일치나 전체 coverage를 주장하지 않는다.
- 남은 소요: 개별 세션/프로젝트 탐색 UI, Windsurf 브라우저 가져오기 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·UI·실제 로그 검증 미실행.

## IMPL-216 — 개별 프로젝트·세션 탐색 연결

- 비용 summary 결과에 개인정보 표시 설정을 적용한 프로젝트/세션 section을 함께 전달한다. 네이티브 드롭다운 선택으로 개별 항목의 비용·토큰·세션 모델 상세를 열고 Summary 선택으로 기존 요약에 돌아간다.
- 현재 선택한 section에 Ctrl+F/F3 검색을 적용하며, 개별 section 선택 중 전체 행 확장 버튼은 비활성화한다. 요약 복귀 시 기존 확장 상태를 복원한다.
- 프로젝트 경로는 개인정보 숨김 해제 상태에서만 redactor/문자 제한을 거쳐 표시한다. 세션 ID/로그 경로는 추가하지 않는다. 각 항목은 통화/시간대/불완전 집계/토큰 중첩/세션 기간 설명을 포함하고 stale 및 실패 소스 안내를 전달한다.
- 기존 snapshot validity/개인정보 timer와 DPI/font/layout 경로를 사용한다. 목록 추가 실패는 창 생성 실패로 반환한다.
- IMPL-214/215 후에도 runtime의 확장 버튼 조건이 모델/프로젝트 개수에만 의존하던 누락을 수정했다. 세션이 있으면 상세 확장을 제공하고, 현재 설정과 일치하는 유지된 snapshot에도 동일한 section을 제공한다.
- 남은 소요: 프로젝트별 일별/모델별 심화 탐색, 대규모 목록 사용성, Windsurf 자동 가져오기 및 전체 계획 나머지. 개별 항목 선택 UI가 작성되었으나 동작 확인 증거는 없다.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·UI·실제 데이터 검증 미실행.

## IMPL-217 — 프로젝트 일별 내역

- 프로젝트 집계에서 기존 선택 기간과 소스 coverage 조건을 통과한 기록을 날짜별로도 보존한다. 같은 소스/프로젝트/날짜 기록은 합산하고 날짜 내 미확인 값/overflow가 있으면 해당 지표를 Unknown으로 유지한다.
- 프로젝트 선택 상세에 최신 날짜부터 일별 비용·토큰을 표시한다. 기존 소스 통화 배수와 표시 시간대를 사용한다. 기록이 없는 날짜를 0으로 채우지 않으며 이 제한을 화면에 설명한다.
- 활동 기록이 존재하지만 비용/토큰 합계가 모두 미확인인 프로젝트를 목록에서 제외하던 조건을 변경했다. 기간/coverage 안의 기록이 전혀 없는 프로젝트는 계속 제외한다.
- 남은 소요: 프로젝트별 모델 분석, 대규모 탐색 UX, Windsurf 자동 가져오기 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·UI·실제 로그 검증 미실행.

## IMPL-218 — 프로젝트별 모델 분석

- 프로젝트의 선택 기간/소스 coverage 조건을 통과한 WindowEntry를 모아 기존 modelSummary와 부분 Codex/미가격 모델 보존 정책으로 모델 내역을 만든다. 제공자 전체 entry나 total을 프로젝트 집계에 사용하지 않는다.
- 프로젝트 row에 모델 목록/completeness를 보존하고 상세 화면에 모델별 비용·토큰 유형을 표시한다. 불완전 내역에는 Partial과 누락 안내를 표시하며 모델 목록이 없으면 그 사실을 명시한다.
- 원래 소스의 통화 배수와 모델 집계의 unknown/overflow 규칙을 사용한다. 새 집계 정책을 별도로 도입하지 않는다.
- 남은 소요: 대규모 항목 탐색 UX, Windsurf 자동 가져오기 및 전체 계획의 다른 Windows parity 항목.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·UI·실제 데이터 검증 미실행.

## IMPL-219 — 프로젝트·세션 목록 필터

- 본문 Find와 별도로 Filter items 입력을 추가한다. 이미 개인정보 정책을 적용한 section 제목만 대소문자 무시 검색하며 원본 경로/세션 ID는 검색하지 않는다.
- 필터 결과의 원본 section 인덱스를 따로 보존한다. 선택 항목이 결과에 남으면 유지하고 제외되면 Summary로 복귀한다. 일치 수와 결과 없음 문구를 제공하며 필터를 지우면 전체 목록을 복원한다.
- 필터 입력은 256자로 제한하고 기존 DPI/font/layout과 개인정보/snapshot 취소 처리를 사용한다. 목록 갱신 실패 시 창을 종료한다.
- 남은 소요: 대규모 목록 성능/접근성 검증, Windsurf 자동 가져오기 및 전체 계획 나머지. 본 변경만으로 대규모 데이터 성능을 주장하지 않는다.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·UI·성능 검증 미실행.

## IMPL-220 — Augment 수동 웹 조회 Windows 포함

- macOS 한정 본문에서 Augment API 응답/스냅샷 변환/수동 쿠키 크레딧·구독 HTTP 경로를 Windows에도 포함한다. 브라우저 importer와 기존 파일 세션 저장은 macOS 한정으로 유지한다.
- Windows sourceModes에 web을 추가하고 수동 저장 계정 선택은 웹 경로만 사용하도록 연결한다. CLI/웹 명시 모드 분리와 수동 웹 CLI 지원 예외를 작성했다. 기존 Auggie CLI 본문은 macOS 전용으로 Windows CLI는 아직 미구현이다.
- Windows는 빈 쿠키/64KiB 초과/제어문자 입력을 거부하고 응답 수신 후 4MiB 크기를 제한한다. 응답 본문을 오류나 rawJSON에 보관하지 않는다. 수신 후와 optional subscription 완료 후 취소를 확인한다.
- 크레딧 필수/구독 선택의 원본 순서를 유지한다. Windows 자동 브라우저/앱 로그인과 보호 세션 저장은 본 변경에 포함하지 않았으며 없는 수동 세션은 명시적으로 실패한다.
- 남은 소요: Augment Windows CLI/브라우저 로그인·계정 소유권, Windsurf 자동 가져오기 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·API·실제 계정 검증 미실행.

## IMPL-221 — Auggie CLI Windows 경로

- Auggie account status 실행/원본 크레딧 파서를 Windows에도 포함한다. WindowsCommandResolver와 AUGGIE_CLI_PATH, target argumentPrefix/environment를 통해 공통 Windows subprocess backend에 연결한다.
- CLI 가용성도 같은 명령 해석기를 사용하고 auto/cli의 browser 지원 예외를 허용한다. 수동 웹 계정은 기존 CLI 우회 규칙을 유지한다.
- 실행 제한 15초, stdout/stderr capture 1MiB 명시 상한, 실행 후 취소 확인, ANSI/CRLF 정규화를 추가한다. Windows에서는 원본 stderr와 파싱 실패 출력 전체를 로그/오류에 남기지 않는다.
- CLI 배포 형태별 resolver 지원 및 실제 출력 호환성은 미확인이다. 로그인 실행/자동 브라우저 가져오기는 본 변경에 포함하지 않는다.
- 남은 소요: Windows CLI 설치 형태·동작 검증, Augment/Windsurf 자동 로그인 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·CLI 실행·실제 계정 검증 미실행.

## IMPL-222 — Auggie 설치 선택과 실패 보존

- 공통 Windows resolver의 npm/cmd-shim 정형 템플릿 처리 코드가 존재하므로 별도 batch 실행기를 추가하지 않는다. 실제 npm 설치 호환성은 미검증이다.
- Auggie의 명시 AUGGIE_CLI_PATH는 비어 있지 않은 절대 경로로 고정한다. 잘못된 경로를 PATH의 다른 설치로 대체하지 않는다. 가용성 검사에서는 명시 설정이 있으면 fetch에서 구체적인 설정 오류를 반환하게 한다.
- 자동 탐색 가용성과 실행에 같은 effective PATH 및 Auggie 전용 해석 함수를 사용한다.
- Windows CLI 실패 뒤 미구현 자동 웹 조회로 fallback하지 않아 원래 오류/취소를 보존한다. 수동 웹 계정은 기존 웹 전용 전략을 유지한다.
- 남은 소요: 설치 형태별 실제 Windows 검증, Augment/Windsurf 자동 로그인 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·CLI 실행 검증 미실행.

## IMPL-223 — Augment Firefox 가져오기 backend

- Windows Firefox 쿠키 reader로 Augment API host에 적용 가능한 쿠키만 선택한다. 부모 host-only 쿠키와 auth 전용 host는 제외하고 프로필/originAttributes partition을 분리한다.
- 알려진 세션 쿠키가 있는 후보만 만들며 같은 이름의 다른 값, 잘못된 헤더 문자, 64KiB 초과를 거부한다. 기존 Cursor backend의 deadline/취소/프로필 출처 표시 방식을 따른다.
- AugmentStatusProbe에 기본값이 기존 HTTP client인 transport 주입을 추가하고 후보의 수동 쿠키만으로 조회한다. 구독 응답에서 이메일이 확인되지 않으면 가져오기 확인은 실패한다. 이메일은 안정적인 서버 account ID로 간주하지 않는다.
- 실제 브라우저/API 접근이나 계정 저장을 실행하지 않았다. 후보 선택/만료 ticket/보호 저장 UI는 아직 미연결이며 자동 가져오기 완료로 간주하지 않는다.
- 남은 소요: Augment 가져오기 runtime/UI/보호 저장, Chromium 지원, Windsurf 자동 가져오기 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·브라우저·API 검증 미실행.

## IMPL-224 — Augment 가져오기 runtime과 저장

- Augment 전용 후보 DTO, 요청 상태, discovery/validation task, 만료 task와 취소 API를 WindowsUsageRuntime에 추가한다. SQLite 탐색을 utility task로 분리하고 상위 취소/종료를 전달한다.
- 전체 60초/최대 16개 후보 확인을 적용한다. 동일 쿠키 헤더는 중복 확인하지 않으며 실패/미확인 후보 수를 반환한다. 표시 이메일/프로필은 redactor와 개인정보 표시 설정을 적용한다.
- 선택 ticket은 5분이며 provider config 지문/선택 계정/개인정보 설정을 저장 전에 다시 확인한다. 동일 credential이고 별도 scope가 없는 저장 계정은 메타데이터를 덮지 않고 선택한다.
- 이메일을 stable external ID로 저장하지 않는다. 새 계정은 기존 보호 계정 추가 API에 수동 쿠키로 전달한다. 실패한 탐색의 request 상태를 정리하고 종료 시 task와 후보를 철회한다.
- 남은 소요: 트레이 시작/취소/후보 선택 UI 연결과 실제 동작 확인, Chromium/Windsurf 가져오기 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·브라우저·API·보호 저장 검증 미실행.

## IMPL-225 — Augment 가져오기 UI 연결

- Add saved account 메뉴에 Augment 활성 상태의 Import from Firefox/Cancel 동작을 추가한다. 독립 요청 ID/메일박스와 기존 취소 가능한 task holder를 사용해 runtime 발견·저장·취소 API를 연결한다.
- 확인된 후보 선택, 실패/미확인 수 안내, 이름 입력과 보호 저장 결과 표시를 연결한다. 저장 후 사용자가 Refresh로 조회하도록 안내한다.
- 후보 팝업의 250ms 만료/개인정보 감지 timer 및 이름 입력 dialog의 기존 만료 처리를 사용한다. 이름 입력 문구는 provider 인자를 받아 Cursor/Augment에 맞게 표시한다.
- 계정 저장 성공/같은 세션 재선택/설정 변경/실패를 구분하며 취소 후 늦게 도착한 결과는 요청 ID로 무시한다.
- 남은 소요: 실제 Windows 전체 가져오기/보호 저장 검증, Chromium 및 Windsurf 자동 가져오기와 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·UI·브라우저·API 검증 미실행.

## IMPL-226 — Augment 플랫폼 경계와 미확인 사용량

- 앞선 이식에서 Status Probe Error 주석에 잘못 삽입된 endif를 실제 Session Store 끝으로 옮긴다. Windows가 공유 모델/오류/조회 본문을 포함하고 macOS 전용 파일 세션 저장만 제외하도록 작성한다. 이전 이식은 이 누락이 있는 미검증 코드였다.
- Windows 크레딧 응답은 하나 이상의 유효한 비음수 수치를 요구한다. 한도와 사용/잔여량으로 비율을 계산할 수 없으면 primary를 nil로 유지하며 0%를 만들지 않는다.
- 구독 조회 가용성을 snapshot에 보존하고 Windows 웹 결과에 구독 정보 누락/비율 미확인 진단을 전달한다. Windows 날짜 표시는 Foundation DateFormatter로 분기한다.
- 남은 소요: 원시 크레딧 잔액 표시 확장, 실제 전체 가져오기 검증, Chromium/Windsurf 지원 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·UI·API 검증 미실행.

## IMPL-227 — Augment 원시 크레딧 상세

- Windows Augment snapshot의 details에 잔여 크레딧, 사용 크레딧, 한도와 결제 주기 종료를 추가한다. 기존 WindowsUsagePresentation의 generic detail 렌더링으로 전달하며 CLI/수동 웹/가져온 세션 조회에 공통 적용한다.
- 누락/음수/비유한 값은 Unknown으로 표시한다. 비율을 계산하지 못해 primary가 없어도 확인된 크레딧 금액은 상세에서 보존한다.
- 구독 조회가 실패한 경우 credit 조회와 구분해 안내하며 서버가 제공하지 않은 한도를 역산하지 않는다. macOS details는 기존 빈 배열을 유지한다.
- 남은 소요: 실제 Windows 렌더링 및 전체 가져오기 검증, Chromium/Windsurf 지원과 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·UI·API 검증 미실행.

## IMPL-228 — Zed Windows 수동 인증 조회

- Windows 전용 Zed 저장 계정 adapter를 추가한다. 입력은 숫자 user ID/공백 하나/access token이며 기존 환경 주입으로 CODEXBAR_ZED_AUTHORIZATION에 전달한다. 이는 CodexBar 수동 입력 계약이며 Zed 편집기의 환경 변수라고 주장하지 않는다.
- Windows credential reader는 64KiB/숫자 ID/토큰 문자 제한을 적용하고 production Zed service에만 자격증명을 반환한다. strategy는 로컬 editor settings를 읽지 않는 고정 production API를 사용한다.
- Windows 응답 user ID가 입력 ID와 일치해야 snapshot을 반환한다. 요청 15초/수신 후 4MiB/취소 확인을 추가하고 브라우저 없이 auto/api 사용이 가능하도록 CLI 지원 예외를 연결한다.
- 원본 Keychain 경로는 macOS에 유지한다. 편집기 자격증명 자동 가져오기, 사용자 서버 설정 및 입력 저장 전 validation UI는 남아 있다.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·API·저장 계정 검증 미실행.

## IMPL-229 — Zed 저장 전 입력 형식

- ZedManualCredentialInput에서 user ID/토큰 구문과 64KiB 제한을 처리하고 credential reader가 같은 파서를 사용한다. user ID 범위는 응답 모델의 Int와 맞춘다.
- Windows 계정 추가/credential 교체 dialog의 기존 credentialIssue 경로에 Zed를 연결한다. 오류 시 입력을 유지하고 비밀값 없는 형식 안내를 표시한다.
- runtime 저장 API도 공통 credentialIssue를 거쳐 우회 호출의 잘못된 입력을 거부한다. 이름/메타데이터만 변경할 때는 기존 토큰을 재검사하지 않는다. Windsurf의 기존 검사도 동일한 runtime 진입점을 사용한다.
- 구조 검사는 인증 성공을 뜻하지 않으며 실제 ID 일치 확인은 원본 API 조회 경로에 남아 있다.
- 남은 소요: Zed 편집기 자동 인증/서버 설정, Chromium/Windsurf 가져오기 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 파서 실행·빌드·테스트·lint·UI·API 검증 미실행.

## IMPL-230 — Zed 예측 횟수와 청구 상세

- Windows generic details에 실제 edit prediction 횟수, 제한/Unlimited, 연체 여부, 유효 청구 기간을 추가한다. 비율에 쓰는 clamp와 별개로 실제 사용 횟수를 보존한다.
- 음수 사용 횟수는 Unknown이며 primary를 만들지 않는다. 역전/길이 0인 청구 구간은 secondary/갱신 시각에서 제외하고 상세 안내를 제공한다.
- Windows 청구 경과율과 reset 문구는 snapshot.updatedAt을 사용한다. 상세에 이 막대가 경과 시간이지 사용량 비율이 아님을 표시한다.
- 남은 소요: 실제 Windows 렌더링 검증, Zed 자동 인증/서버 설정과 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·UI·API 검증 미실행.

## IMPL-231 — Zed 수동 계정의 서버 바인딩

- 기존 `userID accessToken`은 production Zed로 유지하고 `userID accessToken https://server`를 선택적 확장 입력으로 제공한다. 서버와 토큰은 동일 계정의 기존 보호 credential 저장에 포함된다.
- HTTPS origin만 허용하며 로그인 정보/쿼리/fragment/하위 경로/잘못된 port는 거부한다. scheme/host와 root slash를 정규화한다.
- reader가 같은 bundle에서 ZedClientSettings(credentialsURL/serverURL)를 만들고 loadCredentials 호출의 서비스 주소와 일치할 때만 토큰을 반환한다. 원본 cloudAPIURL 매핑과 응답 ID 검사를 사용한다.
- 계정 추가/교체 안내와 공통 구조 검사도 확장 형식을 사용한다. 로컬 편집기 설정이나 별도 서버 환경 변수가 저장된 토큰의 전송 대상을 바꾸지 않는다.
- 남은 소요: Zed 편집기 자동 인증, 사용자 서버 실제 호환성/전송 동작 검증, Chromium/Windsurf 지원과 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 파서·빌드·테스트·lint·UI·API 검증 미실행.

## IMPL-232 — 수동 계정 HTTP 격리

- WindowsManualAccountHTTPTransport는 ephemeral configuration에서 쿠키 저장/자동 첨부, URL credential storage 및 응답 캐시를 비활성화한다. 공통 동일 출처 HTTPS redirect guard를 유지한다.
- Zed/Augment 기본 Windows 조회는 전용 전송을 사용하며 호출자가 제공한 transport는 보존한다. macOS 기본 전송은 기존 shared client이다.
- Augment 브라우저 후보 확인 overload도 기본 transport를 강제로 shared로 넘기지 않아 동일 격리가 적용된다. 선택한 후보의 명시 헤더만으로 요청하도록 구성한다.
- Windows Zed 네트워크/파싱 실패는 원본 URL/서버 응답 문자열을 담는 오류 대신 고정 문구를 반환한다.
- 남은 소요: 실제 HTTP/리디렉션·계정 전환 검증, Zed 자동 인증/Chromium/Windsurf 지원 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·네트워크 검증 미실행.

## IMPL-233 — Cursor/Windsurf 수동 세션 전송 격리

- CursorStatusProbe initializer의 기본 전송을 선택적으로 받아 Windows에서는 WindowsManualAccountHTTPTransport, 다른 플랫폼에서는 기존 shared client를 선택한다. 주입된 transport는 변경하지 않는다.
- Cursor Firefox 후보 확인도 기본 shared transport를 강제로 전달하지 않아 같은 Windows 격리가 적용된다.
- Windsurf fetchUsage의 기본 Windows 전송 역시 명시 세션 헤더만 사용하도록 격리하며 기존 session: 호출 라벨과 macOS 기본 동작을 유지한다.
- 본 변경은 Cursor 별도 비용 이벤트 수집기의 전송까지 완료했다는 의미가 아니다. 비용 수집 및 다른 제공자 경로는 별도 소요로 남는다.
- 남은 소요: 실제 전송/계정 전환 검증, Zed 자동 인증/Chromium/Windsurf 가져오기 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·네트워크 검증 미실행.

## IMPL-234 — Cursor 비용 이벤트 전송 격리

- Windows 비용 이벤트 수집기는 명시 쿠키를 사용하는 전용 HTTP client를 기본으로 선택한다. 주입 transport와 다른 플랫폼 기본값은 유지한다.
- 수신 및 decode 뒤 취소를 확인하고 Windows 페이지는 수신 후 16MiB 상한을 적용한다. decode 실패는 응답값을 포함하지 않는 고정 URLError로 전달한다.
- 기존 전체 페이지/중복 경계/계정 ID 전후 확인 규칙은 유지한다. 크기 상한은 스트리밍 다운로드 제한이 아닌 decode 진입 제한이다.
- 남은 소요: 실제 비용 조회/계정 전환 검증, 자동 인증/Chromium/Windsurf 지원 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·네트워크 검증 미실행.

## IMPL-235 — Zed Windows 편집기 credential reader

- 원본 https://github.com/zed-industries/zed/blob/main/crates/gpui_windows/src/util.rs 의 target 함수와 platform.rs의 read_credentials를 읽어 `zed:url=<serviceURL>` / CRED_TYPE_GENERIC / UserName / 원본 byte blob 계약을 확인했다. client/src/client.rs는 username을 user ID, blob을 UTF-8 token으로 사용한다.
- exact target 하나만 CredReadW로 읽고 vault 열거/쓰기/삭제는 하지 않는 reader를 작성했다. service origin 검사, username/blob 크기 제한, UTF-8/ID/token 구문 검사, 취소 확인, CredFree 정리를 포함한다.
- 없는 항목은 nil, 읽기 실패와 잘못된 형식은 비밀값 없는 오류로 반환한다. 원본 조사만 수행했고 실제 Credential Manager를 읽거나 API를 호출하지 않았다.
- 원본 URL은 main 가변 참조이며 실제 설치 버전 호환성은 검증하지 않았다. reader는 기본 fetch/UI에 아직 연결하지 않았다.
- 남은 소요: 편집기 설정/계정 선택과 가져오기 UI 연결, 실제 Windows 검증 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·Credential Manager 검증 미실행.

## IMPL-236 — Zed 편집기 세션 가져오기 백엔드

- 명시적으로 호출하는 WindowsZedEditorSessionImporter를 추가했다. origin을 정규화하고 detached task에서 exact credential을 한 번 읽으며 부모 취소를 전달한다.
- 읽은 credential을 고정 reader에 주입하여 편집기가 계정을 바꾸더라도 API 확인과 반환 bundle이 같은 계정을 사용한다. 기존 probe의 응답 user ID 검사와 격리 HTTP 전송을 사용한다.
- 확인 결과는 user ID, snapshot, service origin과 보호 저장용 secret bundle을 반환한다. 자동 저장이나 계정 선택 변경은 하지 않는다.
- 남은 소요: runtime의 가져오기 ticket/만료/동시성 처리, 보호 저장 및 명시적 사용자 선택 UI, 편집기 custom server 설정 탐색과 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·Credential Manager·API 검증 미실행.

## IMPL-237 — Zed 가져오기 런타임과 계정 저장

- 명시적 discovery 호출은 actor 외부에서 편집기 계정을 확인하고 opaque request ID와 표시용 제목만 UI에 반환한다. secret bundle은 pending runtime state에 둔다.
- provider 설정 revision, 선택 계정, 개인정보 표시 모드를 캡처한다. 결과와 저장 시점에 변경 여부를 확인하고 5분 후 pending credential을 해제한다. 교체/부모 취소/종료 시 작업 취소를 전달한다.
- 저장은 기존 addTokenAccount 보호 저장 경로를 사용한다. exact bundle 및 scope가 같은 계정만 재사용하고 서버별 user ID를 전역 externalIdentifier로 오인하지 않는다.
- 남은 소요: 네이티브 가져오기 메뉴/확인/취소 UI, custom server 편집기 설정 탐색, 실제 Windows 동작 검증 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·저장소·Credential Manager·API 검증 미실행.

## IMPL-238 — Zed 편집기 가져오기 네이티브 UI

- Zed가 표시되는 트레이 계정 추가 메뉴에 편집기 가져오기와 진행 중 취소를 연결했다. 기본 production 서버 credential을 명시적 클릭으로 읽는다.
- Main은 독립 task holder에서 runtime discovery를 호출하고 request ID로 UI mailbox 결과를 제한한다. 계정 이름 확인 후 저장/취소를 runtime에 전달한다.
- 기존 계정 이름 dialog에 선택적 계정 제목을 추가했다. Zed 확인 제목은 runtime 개인정보 모드를 따르며 기존 dialog의 만료/개인정보 변경 감시를 사용한다. secret bundle은 UI에 전달하지 않는다.
- 남은 소요: custom server 설정 탐색/선택, 실제 Windows UI·인증·저장 검증 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·UI·Credential Manager·API 검증 미실행.

## IMPL-239 — Zed 사용자 지정 서버 선택

- 편집기 가져오기 클릭 후 HTTPS origin을 입력하는 창을 제공한다. 기본값은 https://zed.dev이며 Continue를 누른 뒤에만 credential 조회를 시작한다.
- 서버 입력은 2048 UTF-16 단위로 제한하고 기존 bundle origin 검사/정규화를 공통 public helper로 노출했다. 경로, login 정보, query/fragment 등은 기존 계약에 따라 거부한다.
- 선택 origin을 Main에서 runtime으로 전달하여 기본 production 외 서버도 exact target reader와 고정 credential API 확인을 사용한다. 서버 입력 도중 개인정보 모드 변경은 기존 dialog 감시로 취소한다.
- 남은 소요: 편집기 설정 자동 탐색, 실제 Windows UI/사용자 서버 호환성 검증 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·UI·Credential Manager·API 검증 미실행.

## IMPL-240 — Zed 편집기 설정 origin loader

- 원본 https://github.com/zed-industries/zed/blob/main/crates/paths/src/paths.rs 에서 Windows RoamingAppData/Zed/settings.json 경로와 custom data dir의 config 하위 경로를 확인했다. main 가변 참조이며 설치 버전 호환성은 미검증이다.
- 기본 APPDATA 경로와 명시 URL overload를 제공하고 최대 1MiB+1만 읽어 과대 파일을 거부한다. 파일 없음만 production 기본값이며 접근 실패/파싱 실패는 오류로 전달한다.
- 문자열 내부 URL/escape를 유지하면서 줄/블록 주석과 후행 쉼표를 처리한다. UTF-8 및 JSON object를 요구하고 서버 origin은 기존 공통 계약으로 검사한다.
- credentials_url과 server_url이 다르면 현재 단일 origin bundle로 잘못 가져오지 않도록 별도 오류를 반환한다. 이 구성의 완전한 지원은 남은 소요이다.
- 남은 소요: UI 추천 기본값 연결, custom data dir 발견, 분리된 credential/API origin 계약, 중복 key 정책 및 실제 Windows 검증과 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 파서·빌드·테스트·lint·설정 파일 실행 검증 미실행.

## IMPL-241 — Zed 서버 추천값의 UI 연결

- 트레이 가져오기 요청은 먼저 별도 task에서 설정 origin을 읽고 request ID가 같은 UI mailbox로 추천값을 전달한다. 부모 취소를 파일 읽기 task에 전달하고 취소된 결과는 게시하지 않는다.
- 서버 입력 창은 추천값을 기본으로 표시한다. loader 오류는 빈 입력과 고정 안내로 표시하며 실패를 production 기본값으로 숨기지 않는다. 파일 없음에 따른 기본값은 안내에 명시한다.
- 개인정보 모드 변경은 추천값 표시 전과 창 내부/확인 이후 검사한다. Continue 확인 이후에만 기존 credential reader/API 확인 흐름으로 진행한다.
- 남은 소요: custom data dir 탐색, 분리된 credential/API origin, 중복 JSON key 정책, 실제 Windows 검증 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·UI·실제 설정 조회/인증 검증 미실행.

## IMPL-242 — Zed 설정 중복 key 처리

- Foundation JSON object 변환에서 중복 key가 사라지기 전에 원본 정규화 JSON의 root key를 별도로 추적하도록 연결했다. 같은 root key가 두 번 나오면 설정을 invalid로 반환한다.
- 기존 Windsurf scanner를 WindowsJSONRootKeys로 공유하고 caller별 상한을 받도록 했다. Windsurf wrapper는 기존 65536 byte 제한을 유지하고 Zed는 1MiB 제한을 적용한다.
- key 문자열의 JSON escape를 decode하므로 server_url과 unicode escape로 쓴 동명 key도 동일하게 취급한다. 중첩 object key는 root 서버 선택과 구분한다.
- loader 실패는 기존 UI의 직접 서버 입력 안내로 전달된다. 중복 설정을 임의의 첫 값/마지막 값으로 선택하지 않는다.
- 남은 소요: custom data dir 탐색, 분리된 credential/API origin 계약, 실제 Windows 검증 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 파서·빌드·테스트·lint·실제 설정 조회 검증 미실행.

## IMPL-243 — Zed 사용자 지정 데이터 디렉터리 설정

- CodexBar 전용 CODEXBAR_ZED_DATA_DIR 절대 경로를 지원한다. IMPL-240에서 읽은 upstream paths.rs의 custom_dir/config 계약에 따라 settings.json을 찾는다.
- 빈 값/상대 경로/control 문자/과대 경로를 거부하고 명시한 파일이 없으면 production 기본값으로 대체하지 않는다. 설정 실패는 기존 서버 직접 입력 안내로 전달된다.
- 가져오기 사용법, 환경 변수 범위, 서버 단위 Credential Manager 저장과 데이터 디렉터리의 차이, 미구현 범위를 ZED-EDITOR-IMPORT.ko.md에 기록했다.
- 남은 소요: 실행 중 편집기 디렉터리 자동 발견, 분리된 credential/API origin 계약, Windows 실제 검증 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·설정 조회·인증 검증 미실행.

## IMPL-244 — Zed credential origin과 API server 분리

- importer와 runtime discovery에 선택적 credentialServiceURL을 추가했다. 기존 호출은 동일 origin을 유지한다.
- 공통 ZedClientSettings.cloudAPIURL 신뢰 규칙을 Credential Manager 조회 전에 적용한다. 지원하는 Zed 서버 조합 외 임의의 교차 서버 전송은 기존 규칙대로 거부한다.
- vault reader 및 고정 reader는 credential origin을 사용하고 API probe는 server origin을 사용한다. 저장 bundle은 확인한 API server를 유지하여 이후 조회가 다른 서버로 바뀌지 않는다. 결과에는 원본 credential origin도 포함한다.
- 기존 3-field 수동 bundle 계약을 변경하지 않는다. 가져오기 후 조회는 편집기 vault 재조회 없이 보호 저장한 token과 API server를 사용한다.
- 남은 소요: settings loader의 두 주소 모델/명시적 UI 확인 연결, 편집기 디렉터리 자동 발견, 실제 Windows 검증 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·Credential Manager·API 검증 미실행.

## IMPL-245 — Zed 설정의 두 origin 보존

- WindowsZedEditorSettings.Configuration은 정규화한 serverURL/credentialServiceURL을 보존하고 공통 ZedClientSettings 신뢰 규칙을 적용한다.
- 환경 경로/명시 URL 읽기와 JSON 파싱을 Configuration 반환 경로로 확장했다. 누락된 credentials_url은 선택 server로, 없는 기본 설정 파일은 production 설정으로 해석한다.
- 기존 suggestedOrigin/parseOrigin은 compatibility wrapper로 유지한다. 분리된 주소를 단일 문자열로 축소하지 않고 기존 오류를 반환한다.
- 남은 소요: Main/mailbox/서버 확인 창을 Configuration으로 전환해 두 주소 확인 후 전달, 실제 Windows 검증 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 파서·빌드·테스트·lint·설정 조회·인증 검증 미실행.

## IMPL-246 — Zed 두 주소 확인 UI 연결

- Main의 설정 읽기와 mailbox를 Configuration으로 전환해 두 주소를 보존한다.
- API 서버와 credential 저장 주소를 각각 확인하고 조합 검사 후 runtime으로 전달한다.
- 취소/실패/개인정보 모드 변경 시 credential 조회를 진행하지 않는다.
- 남은 소요: 편집기 디렉터리 자동 발견, 실제 Windows 검증 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·UI·인증 검증 미실행.
- 코드 커밋 a4b302318 게시 후 문서 편집 명령의 인코딩 오류를 복구하여 이 기록을 별도 커밋으로 추가했다.

## IMPL-247 — Zed 편집기 자동 조회 연결

- Windows Zed fetch strategy가 수동 환경 입력이나 selectedTokenAccountID가 있으면 기존 manual API 경로를 사용한다. 선택 계정 token 누락/오류는 편집기 계정으로 fallback하지 않는다.
- 둘 다 없으면 actor 밖에서 설정 Configuration을 읽고 두 origin을 editor importer에 전달하여 동일 credential로 API 응답 ID를 확인한다.
- 부모 취소를 설정 task에 전달하고 수신 전후 취소를 확인한다. editor API 출처 라벨을 제공하며 자동 저장/계정 선택은 하지 않는다.
- 설정/인증 오류의 다른 프로필 대체는 없고 기존 source mode 및 shouldFallback false 계약을 유지한다.
- 남은 소요: 실제 Windows 자동 조회/계정 전환 검증, 편집기 디렉터리 자동 발견 및 전체 계획 나머지.
- CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 빌드·테스트·lint·설정 조회·Credential Manager·API 검증 미실행.
