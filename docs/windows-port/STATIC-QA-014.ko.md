# 코드 비교 QA 014

UsageFetcher.swift의 CodexRPCClient에 WindowsExecutableResolver와 WindowsProcess 직접 실행 경로를 연결했다. 기존 stdin Pipe, JSON-RPC 요청/알림, launch gate, bounded stdout/stderr, EOF/drain 오류와 timeout 종료를 연결했다. 독립 정적 검토 중이며 완료로 세지 않는다. .cmd/.bat 실행은 아직 미구현이다.

WindowsProcess.captureVersionSynchronously의 고정 Sleep(10)을 실제 읽은 바이트가 없는 poll에만 적용했다. 각 반복에서 읽기는 16KiB로 제한하고 timeout/drain deadline을 계속 검사한다. sync_013_review가 이 변경에서 구체적 결함을 발견하지 않았다고 보고했다. 이는 해당 소스 변경만의 정적 판정이다.

Claude 버전 탐색의 Unix 경로/TTY 의존을 Windows로 대응하는 후속 변경을 진행한다. 전체 기능 이식은 미완료다.

10분 heartbeat codexbar-windows-qa가 ACTIVE이며 구현 후 전체 원본 비교 QA, 부족하면 보완, 필수 누락 0 및 독립 재검토 후 정지 조건을 유지함을 확인했다.

허용된 확인: 소스 읽기, diff 비교, git diff --check. 빌드·테스트·컴파일러·앱·실계정·키체인·성능·Windows 실행은 수행하지 않았다.

독립 RPC 리뷰에서 Windows가 주입 resolver를 무시하는 중간 수준 지적을 발견했다. UsageFetcher는 다시 공통 주입 함수를 사용하고 CodexExecutableResolver.swift 내부에 Windows 기본 탐색 분기를 넣었다. 재검토 대기다. Claude Windows 경로 정규화·native 버전 실행 후보도 작성되어 독립 정적 검토 중이다. inode 0 fingerprint 및 출력 정규화 등 의미 차이는 전체 동등성 증거가 아니다.

최종 독립 검토에서 resolver 수정 및 Claude 후보의 중간 이상 확정 결함 0을 보고했다. 통합 검토는 별개로 Claude 원본 TTY 전체 출력과 Windows 첫 줄 출력의 차이, inode=0으로 인한 동일 크기/mtime 파일 교체 시 캐시 무효화 차이를 미해결로 유지한다. ANSI 제거는 원본에 맞춰 Windows 반환에도 적용했다. 따라서 Claude 버전 기능 전체 parity 승인은 아니다.
