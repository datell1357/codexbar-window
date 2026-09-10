# QA056 — Windows 세션 기록 조회 결과 구분

진행 중. agy_records_056 원본 비교 설계에 따라 사망과 접근 거부/불확실을 분리한다. 기존 optional identity는 호환용으로 유지하며 상세 lookup을 추가한다. 양성 PID의 OpenProcess ERROR_INVALID_PARAMETER는 사망, ACCESS_DENIED는 접근불가, 기타 실패는 불확실로 취급한다. 경로/생성 시각은 같은 핸들에서 읽는다.

Windows 기록 정리는 확실히 사망했거나 경로/생성 시각이 불일치한 항목만 기존 launch lock 범위에서 배열에서 제외한다. 접근불가/불확실/정확한 live identity는 보존한다. 저장 PID를 종료하지 않으며 실제 파일 삭제/이동을 실행하지 않는다. 수정은 agy_session_049, 테스트 소스 계약 조사는 record_fixtures_056 담당이다.

손상 JSON의 자동 복구는 원본과 아직 동등하지 않다. 현재 오류 진단과 바이트 보존만 있으며 이를 전체 동등성 완료로 세지 않는다. 종료 프로세스/접근거부 판별과 손상 복구의 남은 계약은 독립 재검토 대상이다. 빌드·테스트·실행 검증 미실시.

구현 갱신: 상세 조회와 Windows 기록 정리 소스를 추가했다. 독립 검토 및 Windows 전용 미실행 테스트 소스를 작성 중이다.

독립 검토 REQUEST CHANGES: 핸들을 조회할 수 있는 종료 프로세스도 running으로 분류하는 문제에 GetExitCodeProcess 확인을 추가한다. 손상 JSON 원본 복구 기대와 현재 Windows 보존 정책의 테스트 불일치도 수정 중이다. 6개 기록 정책 테스트 소스가 추가됐으나 실행하지 않았다. 원본 자동 복구 기능의 미완료 상태는 유지한다.
