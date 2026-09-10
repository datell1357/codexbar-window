# QA054 — Windows warm process identity

진행 중 / REQUEST CHANGES. native image 및 npm script 파일 ID 비교 후보를 연결했다. root 정적 검토에서 script 외 입력 경로의 절대 경로 확인 누락, CRT argv[0] 특수 규칙 및 인용부의 연속 쌍따옴표 처리 누락을 확인했다. warm_path_054 수정 및 warm_review_054 독립 검토를 진행한다. 049 전체 세션 동등성은 별도 미완료. 빌드·테스트·실행하지 않았고 현재 변경은 커밋/푸시하지 않았다.

후속 검토: 독립 검토가 BinaryLocator의 exe/com 제한으로 npm shim 분기에 도달하지 못함을 발견했다(055로 보완). root는 expected script 경로 검사 누락과 비정상 인용/NUL 및 UNC 빈 구성요소 처리를 추가 지적했다. 필수 항목 수정 전 커밋 보류. 049의 graceful 종료도 별도 보완 중이다.

054의 Swift split 인자 순서 오류를 root가 추가 발견하여 보정했다. 055는 agy에 한해 WindowsCommandResolver를 사용하도록 연결했으며 독립 검토 중이다. 049 정상 종료 대기의 취소 시 busy-loop도 수정 요청했다. 실행 검증 없음.

최종 해당 범위 정적 승인: warm_review_054가 matcher와 055 호출부 연결을 독립 검토했다. root가 실제 split 인자 순서 수정 및 diff --check를 확인했다. agy만 npm shim resolver를 사용하고 일반 실행 경로는 native-only를 유지한다. 이미지 및 script 파일 ID 비교는 원본 Windows 경로 대응으로 추가했다. Actions 비활성 확인. 049의 세션 구현은 미완료이며 이번 커밋에서 제외한다. 주입 FileManager 미전달, 상대 script/device 경로 재사용 제한 및 실제 Windows 실행 미검증은 남아 있다. 전체 기능 완료가 아니다.
