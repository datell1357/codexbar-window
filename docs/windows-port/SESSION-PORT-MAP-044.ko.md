# 지속 세션 Windows 이식 지도 044

상태: 미구현. 정적 소스 대조만 수행했으며 Windows 실행 증거가 아니다.

1. Host/PTY: suspended ConPTY 생성 전 launch reservation, owned 객체 등록 후 resume하는 tracked lease를 추가한다. unregister는 PID뿐 아니라 객체 동일성(===)까지 확인한다. 임의 PID OpenProcess 연결로 대체하지 않는다. 현재 WindowsTTYCommandRunner의 PID-only 등록 false는 미지원 상태를 명시하며 완료로 세지 않는다.
2. CodexCLISession.swift: 288–423의 openpty/setpgid/kill/FD read를 Windows actor의 owned lease로 전환한다. 기존 captureStatus/reset, binary·rows·cols·env·args·cwd 재사용 조건과 100–263의 상태 머신을 유지한다.
3. ClaudeCLISession.swift: 390–477, 564–680 POSIX 수명을 Windows actor로 분리한다. current/capture/reset/launchEnvironment와 accountScope 환경 분리 및 224–353의 idle·settle 동작을 보존한다.
4. AntigravityCLISession.swift: 12–30 프로토콜 경계를 활용하되 826–1111 launcher는 owned Windows 구현이 필요하다. 771–800의 stale PID 재종료 대신 현재 Job 소유 수명을 사용한다. AntigravityStatusProbe+PortDetection.swift의 Windows lsof/proc fallback은 GetExtendedTcpTable LISTEN 조회로 교체하고 Iphlpapi 링크를 추가한다.
5. KiroStatusProbe.swift: 798–844 PTY fallback은 공통 runner, 662–783 pipe는 WindowsProcess streaming/wait/terminate 소유 경로로 분리한다. stdout/stderr·idle·race 계약을 보존한다.

KiroStatusProbeTestSupport.swift와 KiroTransportRaceTests.swift의 기존 POSIX PID 주입, AntigravityCLISessionTests.swift의 수명 의존성 주입은 유지한다. Windows에는 별도 owned-object 주입 경계를 추가한다. ConPTY.close 이후 exitStatus는 nil이므로 종료 상태를 닫기 전에 보관해야 한다.

순서: tracked lease → Codex → Claude → Antigravity/포트 탐색 → Kiro pipe. 공급자별 독립 정적 리뷰를 수행한다. 현재 미완료 one-shot TTY 변경과 섞어 완료 처리하지 않는다.
