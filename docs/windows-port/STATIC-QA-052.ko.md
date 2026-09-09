# QA052–053 — Windows 프로세스 탐색 및 Antigravity 연결

판정: 해당 변경 범위 정적 검토 승인. 전체 기능 동등성 완료 아님.

Toolhelp로 후보 PID를 열거하고 동일한 열린 프로세스 핸들에서 이미지 경로, 소유자 SID, 생성 시각 및 명령줄을 수집한다. 명령줄은 NtQueryInformationProcess의 로컬 출력 버퍼 내부 범위를 확인한 뒤 UTF16으로 복사한다. 버퍼는 128 KiB, 재시도는 3회로 제한한다. 프로세스별 접근 실패는 건너뛰며 열거 기반 오류·취소·시간초과는 전파한다.

발견 및 수정: OpenProcess 이후 기한 검사 시 누수, if 내부 defer에 의한 조기 CloseHandle, Process32 호출 오류 코드의 늦은 읽기. 최종 코드는 유효 핸들 guard 다음 반복문 범위에 defer를 두고, 네이티브 오류 코드를 즉시 저장한다. 스냅샷 획득 이후에도 기한을 확인한다.

StatusProbe Windows 분기를 연결하고 소유자/생성 시각을 전달한다. warm CLI 후보는 스냅샷의 소유자 정보를 우선 사용한다. 기존 Darwin/POSIX 경로와 초기화 호출의 기본값을 유지한다.

검토: root 실제 소스 재확인 및 enum_review_052 독립 검토 승인. git diff --check 통과. 빌드·컴파일·테스트·앱 실행·실제 계정 조회는 사용자 지침에 따라 수행하지 않았다. GitHub Actions 비활성 상태 확인.

남은 범위: Windows 실행 파일 및 node/bun 스크립트 경로 매칭, 생성 시각을 활용한 이후 PID 재사용 재검증, 049 세션 수명/기록 동등성. 네이티브 API의 Swift 바인딩 및 실제 Windows 동작은 검증되지 않았다.
