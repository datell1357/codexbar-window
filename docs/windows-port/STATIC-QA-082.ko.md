# QA082/083 — 사용량 표시 설정

구현 진행 중. 원본 usageBarsShowUsed/resetTimesShowAbsolute 키는 기본값 false이고 Core UsageFormatter 및 ResetTimeDisplayStyle을 재사용한다. Windows 전용 defaults suite를 유지한다. Win32 체크 메뉴로 두 옵션을 제어하며 표시 변경에는 추가 공급자 조회 없이 보존된 snapshot을 다시 표시한다. 오류 행과 공급자 순서, 진행 중 조회와 설정 변경의 순서 보존은 독립 정적 리뷰 필수 항목이다. 아직 정적 승인되지 않았으며 빌드·테스트·Windows 실행은 하지 않는다.

초안 정적 점검: 메뉴 callback과 두 표시 옵션 전달은 구현됨. Root는 설정 로드 등의 최상위 오류 이후 이전 성공 cache가 남아 표시 토글 시 오류가 사라지는 문제를 발견했다. 오류를 cache에 반영하고 게시 함수를 통합하도록 수정 요청했다. 독립 리뷰 084 진행 중.

084 독립 검토: 오류 cache 교체와 추가 조회 없는 재표시, 순서 보존은 확인됨. 추가 지적: accountEmail이 실제로는 임의의 token account label일 수 있어 raw 제목을 이메일 정규식만으로 숨기면 개인정보 설정이 우회된다. 안전한 공급자 제목을 별도 보존해 숨김 상태에서 사용하도록 수정 중. 아직 REQUEST CHANGES.

최종 084: privacyTitle 보존과 숨김/복원 경로 확인, 추가 필수 정적 차단 사항 없음. Root는 새 초기화 인자의 선언/호출 순서도 수정했다. 082-084 부분 단계 정적 승인. Actions 비활성을 API로 확인했으며 빌드·테스트·Windows 실행 검증 없음. 전체 설정 UI/고급 표시 모드/기능 동등성은 미완료.
