# QA050/051 — Windows 사용자 SID 기반 및 연결

050은 POSIX UID/Windows SID를 손실 없이 구분하는 ProcessOwnerIdentity와 TokenUser 조회를 구현한다. 초기 포인터 경계 문제를 수정해 TOKEN_USER 최소 크기·unaligned load, SID 시작 위치·8바이트 헤더·15개 sub-authority 상한·전체 길이를 native SID 함수 호출 전에 검사한다. 최종 독립 재검토 중이다.

051은 Antigravity warm reuse의 UInt32 UID 주입 경계를 이 타입으로 연결한다. 알 수 없는 소유자를 동일 사용자로 처리하지 않는다. 테스트 소스는 계약 변경에 맞춰 수정하되 실행하지 않는다. Windows 실행 경로/npm shim 비교는 별도 미완료 사항이다.

아직 커밋하지 않았고 빌드·테스트·실행은 하지 않았다.

최종 범위 한정 승인: owner_review_050은 SID 기반 메모리 경계/핸들 수명을 승인했고 owner_wire_review_051은 descriptor의 양수 PID 및 DWORD(exactly:) 가드, 핸들 닫기, 알 수 없는 소유자 제외, POSIX UID 래핑과 fixture 19개 호출부를 대조했다. 테스트 소스는 수정했지만 실행하지 않았다. 049 세션 PID/저장소 의견은 별도 미완료로 유지하며 이 커밋에서 제외한다. 전체 Windows 프로세스 검색·경로 비교는 미완료다.
