# Windows 전용 제품 작업 현황

IMPL-003: structured Windows scan outcome과 opt-in 로컬 세션 actor/30초 주기/트레이 목록·focus 연결을 작성했다. 오류 시 이전 목록을 비활성화하며 late-result/종료 처리를 추가했다. 미검증이고 원격 통합·metadata·정확한 tab focus는 남아 있다. [구현 로그](IMPLEMENTATION-LOG.ko.md) 참고.

IMPL-002: Windows live CLI PID/생성 시각 세션 및 보수적인 root/ancestor 창 활성화 코드를 연결했다. 미검증이며 cwd/대화 매칭·Desktop/IDE·정확한 탭 focus·트레이 session 통합은 남았다. 현재 구현 상태는 [로그](IMPLEMENTATION-LOG.ko.md)를 따른다.

구현 재개: IMPL-001에서 원격 OS별 세션 transport/Windows 실행 파일 경로 및 plugin nowMillis 타입을 작성했다. CODE_WRITTEN_UNVERIFIED이며 W11 전체 완료는 아니다. [구현 로그](IMPLEMENTATION-LOG.ko.md)를 우선 참고한다. 아래 표는 QA206 시점의 정적 현황이며 새 코드의 검증 결과로 승격하지 않는다.

2026-09-12 3차 검토: [추가 조치](TERTIARY-AUDIT-2026-09-12.ko.md)로 위젯 17개 선택지, Windows remote peer/명령 adapter, 출력·기본값·export 동작 조건을 보완했다. 72개 기능군은 유지하며 실제 구현 완료를 추가하지 않았다.

2026-09-12 계획 이차 감사: [추가 조치](SECONDARY-AUDIT-2026-09-12.ko.md)에서 발견한 mode 역참조·plugin 선언·동적 설정 추적 결함을 수정했다. 기능군 수는 유지하며 구현 완료를 추가하지 않는다.

2026-09-12 계획 개정: [현재 계획](WINDOWS-PORT-PLAN.ko.md)의 Windows 가능 기능 전부가 필수다. 아래 구현 상태는 `80f6b484b`/QA204–206 기준으로 유지한다. 계획 수정으로 코드 구현 상태를 승격하지 않는다. 전수 표면 감사로 72개 기능군·69개 공급자/163개 모드·91개 state·169개 CLI 옵션을 source obligation에 연결했다. 파일의 계획 책임 미분류는 0이며 Windows 구현·실행 증거는 여전히 미완료다. 기존 상태 JSON의 QA155/157 다음 작업은 오래된 기록으로 이동했다.

Mac/Linux 제품 유지를 위한 작업은 제품 범위에서 제외하되 공용 기능 추출·fixture 이관·라이선스 보존 후 Mac 전용 파일을 정리한다. 위젯·Sync/Fleet도 Windows에서 가능한 사용자 기능은 필수다. 외부 서비스 조건 미확정은 완료 또는 자동 제외가 아니다.

정적 코드 비교 기준. 기존 Swift 원본이 있는 것과 Windows 대응 완료를 구분한다. 현재 완료 판정된 작업 묶음은 없다. 기존 569개 후보는 전체 분모가 아니다. 새 원본 표면 추적표의 각 의무를 실제 Windows 구현·검증 증거와 연결하는 작업이 남았다.

| 계획 영역 | Windows 상태 | 남은 핵심 경계 |
|---|---|---|
| W01 공급자 | 부분 연결 (Windows descriptor/process 경계) | 69개 × 인증/조회 소스의 Windows 연결 및 오류 경로 (`Sources/CodexBarCore/Providers`, `STATIC-QA-021/024`) |
| W02 계정 | Credential Manager·browser profile·소유권 snapshot 일부 | 외부 CLI 계정 소유권·OAuth/browser import·전환 (`Sources/CodexBarCore/WindowsCredentialCacheStore.swift`, `STATIC-QA-177-180`) |
| W03 트레이 | native 메뉴·상세 사용량·표시 토글·publisher 연결 일부 | 모든 표시 모드와 native tray/popup 동작 (`Sources/CodexBarWindows/WindowsTrayHost.swift`, `STATIC-QA-061`) |
| W04 설정 | 경로·사용/잔여·리셋 시각·refresh/predictive/quota/web 설정 일부 | 전체 native UI·설정 상태·migration (`Sources/CodexBarWindows/Windows*Settings*.swift`, `STATIC-QA-173-174/204-206`) |
| W05 사용량/예측 | canonical 이력·학습 예측·근무일·계정 소유권·authorized dashboard 역채우기 소비자 일부 | 레거시 소유권 연속성, producer/역채우기 전체, 전체 표시 연결 (`Sources/CodexBarWindows/WindowsUsageRuntime.swift`, `STATIC-QA-163-164/172-175/187-188/193`) |
| W06 비용 | 원본 cost 경로 보존, Windows 전용 연결 미판정 | 파일/증분/회전/계정별 경로 (`Sources/CodexBarCore/Vendored/CostUsage`, `STATIC-QA-033`) |
| W07 대시보드 | HTTP client·authorized fetch·snapshot 게시 경계 일부 | native 표시·집계·export 및 web producer/cache 전체 (`Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardHTTPClient.swift`, `STATIC-QA-036/193/200`) |
| W08 갱신 | fixed/adaptive timer·power snapshot·AC/resume·Battery Saver 등록·reset boundary·시작 재시도 일부 | agent-aware scanner·thermal/cost 정책·전체 refresh 정책 (`Sources/CodexBarWindows/WindowsPowerState.swift`, `WindowsTrayHost.swift`, `STATIC-QA-071/074`) |
| W09 알림 | session reset/recovery·threshold·provider editor·predictive candidate·balloon/overlay/sound·FIFO publisher 일부 | hooks 포함 전체 전달 정책, 현지화·실행/중복 동작 (`Sources/CodexBarWindows/Windows*Notification*.swift`, `WindowsQuotaWarningOverlay.swift`, `STATIC-QA-163-164/165-167`) |
| W10 위젯 | 미연결 | Windows 표면과 snapshot 연결 (`Sources/CodexBarWidget`, Windows target 부재) |
| W11 세션 | Codex/Antigravity ConPTY·process identity 연결, Claude 일부 | Claude 지속 세션 완성, 프로세스/터미널/원격 전수 (`Sources/CodexBarCore/Host/PTY`, `STATIC-QA-039/046/049/069`) |
| W12 CLI/HTTP | Windows process·console·Winsock HTTP·dashboard output 일부 | 직접 POSIX/TTY/명령 계약 및 전체 CLI 표면 (`Sources/CodexBarCore/Host/Process`, `Sources/CodexBarCLI`, `STATIC-QA-034/036/037/039`) |
| W13 Hooks | native process/dispatch 경계 일부 | event runtime, Windows 시나리오 전수 대조 (`Sources/CodexBarCore/Hooks`, `STATIC-QA-005`) |
| W14 Plugins | QuickJS·승인된 plugin 조회/Windows resource 경계 일부 | 재검색·cookie·설치/승인/설정 UI (`Sources/CodexBarCore/Plugins`, `STATIC-QA-001/002`) |
| W15 Sync/Fleet | 미연결 | CloudKit 대응·충돌·계정·offline |
| W16 운영 | Windows target/startup/shutdown·native settings 연결 일부 | 설치/서명/update/접근성·배포 (`Sources/CodexBarWindows/WindowsMain.swift`, `STATIC-QA-061/204-206`) |

단계별 코드 리뷰 기록은 STATIC-QA 문서에서 확인한다. 전체 제품 완성률을 파일/커밋 수로 계산하지 않는다. 실행 검증은 사용자 지시로 전혀 하지 않으며 별도 승인 없는 상태에서 자동 CI도 재활성화하지 않는다.
과거 agent203이 금지된 `swiftc -parse`를 실행했다는 기록은 STATIC-QA-204-206에 적힌 대로 검증 근거에서 제외한다. 이를 근거로 컴파일러 실행 이력을 부정하지 않는다.
