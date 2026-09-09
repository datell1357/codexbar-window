# 코드 비교 QA 034

CLI의 POSIX isatty/ioctl 경계를 Windows console API로 분기했다. 텍스트 색상은 stdout GetConsoleMode 성공 후 기존 mode 비트를 보존하면서 ENABLE_PROCESSED_OUTPUT 및 ENABLE_VIRTUAL_TERMINAL_PROCESSING을 활성화할 수 있을 때만 허용한다. noColor/JSON/TERM=dumb 기존 차단 순서는 유지한다. 실패하거나 출력이 redirected stream이면 색상을 끈다.

카드 폭은 GetConsoleScreenBufferInfo의 visible window Right-Left+1을 사용한다. 감지 실패 시 기존 COLUMNS 및 80열 fallback을 유지한다. 플러그인 승인 대화는 stdin과 stderr 양쪽이 Windows console mode 조회에 성공해야 한다. 파이프 입력에서 승인 프롬프트를 열지 않으며 기존 typed origin/y 확인 흐름은 변경하지 않는다.

WinSDK BOOL을 명시적으로 0과 비교하고 ANSI 활성화 early-return은 두 필수 flag가 모두 있을 때로 보완했다. helper는 Windows 조건부 파일이며 기존 SwiftPM CLI source 디렉터리 자동 포함을 사용한다. 새 의존성은 없다. 정적 코드 및 공백 검토만 수행했다. 실제 콘솔/리디렉션/터미널 크기 변경·빌드·테스트 실행은 하지 않았다.

MSYS/mintty처럼 console handle 대신 pipe를 제공하는 환경은 색상/대화 감지 false fallback이다. ConPTY 지원은 handle 노출 형태에 의존하며 실제 검증되지 않았다. 콘솔 모드 설정은 CLI 프로세스에서 유지하고 원상복구 lifecycle은 별도 미검토다. 전체 CLI의 Winsock, atomic output, 프로세스 경계와 native 앱은 아직 미완료다.

다음: credential 파일 owner-only ACL 및 atomic publish Windows 대응, dashboard output와 Winsock server, PathEnvironment POSIX 호출 이식. 전수 기능 계약 비교는 계속 필요하다.
