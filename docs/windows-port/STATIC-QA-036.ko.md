# 코드 비교 QA 036

Dashboard --output에 Windows 파일 게시 경계를 연결했다. 부모 디렉터리가 없으면 생성하지 않고 기존 안내문과 함께 실패한다. 동일 디렉터리에 CREATE_NEW 임시 파일을 열어 부분 WriteFile 반복, FlushFileBuffers, CloseHandle 성공 후 MoveFileExW replace/write-through로 게시한다. 생성 실패 시 다른 파일을 정리하지 않으며 쓰기·flush·게시 실패에서는 기존 목적지 파일을 직접 덮어쓰지 않는다.

임시 파일 share mode는 0으로 제한했다. Windows 파일은 부모 디렉터리 ACL을 상속하며 POSIX 0644 권한을 모든 플랫폼에 강제하지 않는다. 웹서버 계정의 실제 읽기 권한은 상위 ACL 설정에 의존한다. 기존 테스트 소스의 0644 assertion은 비Windows로 한정하고 내용 교체/임시 파일 잔여 검사 및 부모 부재 계약은 유지했다.

독립 정적 리뷰와 통합 검토에서 중복 CloseHandle, delete sharing, 조건부 컴파일 함수 brace 위치를 보완했다. 정확한 Win32 오류와 0바이트 쓰기 오류를 구분하며 close 실패 시 publish하지 않는다. git diff --check만 수행했다. 빌드·테스트·실제 출력·ACL·원자성 검증은 하지 않았다.

Windows 전체 CLI 완료가 아니다. Winsock HTTP server, PathEnvironment 프로세스 및 공급자/native UI/설치/전수 기능 비교가 남아 있다.
