# 코드 비교 QA 033

Windows 캐시 잠금 실패에 Win32 GetLastError 코드를 보존하도록 NSError 전달을 보완했다. 기존 일반 CocoaError보다 CreateFileW/LockFileEx 실패 원인을 구분할 수 있다. 실제 WinSDK 실행 검증은 하지 않았다.

Windows DEBUG 합성 테스트 소스에 복수 계정 범위의 동시 staged replacement 거부를 추가했다. commit summary가 staged=2/committed=0/failed=2이고 기존 두 쿠키가 보존되어야 한다. 서비스 UUID 및 명시적 메모리 자격증명 저장소를 사용하고 legacy 경로는 Windows temporaryDirectory 아래 UUID 경로로 격리했다. 테스트를 실행하면 임시 lock 파일은 사용하며 실제 사용자 자격증명은 사용하지 않는 설계다. 테스트는 실행하지 않았고 OS 저장 실패 주입 및 Amp fetcher 통합 커버리지는 여전히 남는다.

추가 정적 탐색에서 아래 Windows 경계를 확인했다. 이는 전체 분모가 아니라 다음 구현 후보 5건이다.

- Sources/CodexBarCore/CredentialFileWriter.swift: open/fchmod/rename의 Windows ACL 및 atomic publish 대응 필요.
- Sources/CodexBarCLI/CLIDashboardCommand.swift: writeDashboardSnapshotAtomically POSIX output 경계.
- Sources/CodexBarCLI/CLILocalHTTPServer.swift: socket/bind/listen/accept 및 Winsock 초기화·정리 필요.
- Sources/CodexBarCore/PathEnvironment.swift: makeCloseOnExecPipe/runShellCommand의 pipe/fcntl/posix_spawn 경계.
- Sources/CodexBarCLI/CLIHelpers.swift 및 CLICardsRenderer.swift: isatty/ioctl 기반 색상·터미널 폭 탐지의 Windows console 대응 필요.

다음 단계는 범위가 작은 console 감지 연결부터 진행하고 credentials/HTTP/process 경계로 확장한다. 전체 공급자·native UI·설치·전수 기능 QA는 계속 미완료다. 실행 검증 없이 소스 및 diff 공백 검토만 수행했다.
