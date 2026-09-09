# 코드 비교 QA 038 — Windows 경로 계층 부분 대응

BinaryLocator는 Windows에서 주입된 PATH/PATHEXT와 override를 대소문자 구분 없이 조회하고 세미콜론으로 경로를 분리한다. 정규 파일인 exe/com만 반환하며 기존 launch filter를 적용한다. POSIX 경로와 로그인 셸 fallback은 실행하지 않는다.

PathBuilder는 Windows 드라이브 문자를 보존하고 세미콜론으로 결합한다. PATH가 없으면 빈 문자열을 반환하며 현재 디렉터리나 Unix 경로를 추가하지 않는다. ShellCommandLocator의 pipe/fcntl/posix_spawn 코드는 Windows 컴파일에서 제외한다. LoginShellPathCapturer는 Windows에서 nil을 반환한다. 캐시 current getter는 잠금과 읽기만 수행한다.

독립 정적 리뷰로 환경 변수 대소문자, PATH 구분자, POSIX 컴파일 경계와 존재하지 않는 home 바인딩을 보완했다. git diff --check만 수행했으며 빌드·테스트·실제 실행은 하지 않았다.

미완료: BinaryLocator의 String 계약은 WindowsLaunchTarget 인자 prefix를 전달하지 못하므로 npm cmd shim은 이 경로에서 아직 지원하지 않는다. 일반 PATHEXT 스크립트·PowerShell alias/profile·설치 위치 전수 탐색도 미완료다. TTYCommandRunner의 POSIX 코드와 공급자 연결은 별도 039 단계에서 검토한다. 전체 경로 기능 또는 Windows 제품 완료로 판정하지 않는다.
