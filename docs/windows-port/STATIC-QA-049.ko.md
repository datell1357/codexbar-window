# QA049 — Antigravity 지속 세션 Windows 연결 진행 중

agy_session_049가 기존 protocol/actor를 유지하는 owned ConPTY 연결을 구현하고 agy_enum_design_049가 별도 프로세스 열거·명령행·사용자 SID 계약을 분석한다.

중점: PID-only registry 대체, POSIX launch/identity/flock 조건부 경계, 현재 사용자 소유 확인, binary/start time 식별, auth 출력·idle reset·동시 launch lock 보존. Windows 임의 stale PID 종료나 중요한 의존성의 no-op을 완료로 세지 않는다.

아직 정적 승인 전이며 커밋·빌드·테스트·실행하지 않았다. Claude047 승인 대기와 별개로 진행한다.

통합 재검토 REQUEST CHANGES: 임시 Date/PID identity dictionary, 프로세스 내부 lock, 축약된 record store는 원본 계약 충족 증거가 아니다. 실제 kernel 시작시간/경로, cross-process lock, 원본 레코드 의미를 보완한다. Owner050은 전체 SID를 보존하는 타입과 토큰 조회 기반만 별도로 구현한다.

후속 정적 검토: 정상 종료 유예 및 sleep 취소 탈출, 저장 실패의 오류 타입만 기록하는 진단은 범위 내 승인됐다. root가 Windows 이미지 경로 디코딩의 UTF16.CodeUnit.self 오류를 발견해 UTF16.self로 수정 요청했다. 056은 nil identity의 사망/접근불가 구별 및 오래된 기록 처리 계약을 설계 중이다. 전체 049는 여전히 미완료이며 실행 검증하지 않았다.

최종 통합 정적 검토: agy_review_049가 049+056+057 및 테스트 소스 범위를 승인했다. 종료·출력 오류·기록 조회/정리·백업 복구·잠금 연결에서 필수 소스 차단 사항을 찾지 못했다. git diff --check 통과, Actions 비활성 확인. 빈 기록은 []로 남기며 살아 있는 고아 프로세스는 종료하지 않는 차이가 있다. 미사용 UID placeholder와 FileManager 추상화 제한을 기록한다. 전체 원본 기능 동등성이나 Windows 빌드/실행 통과를 의미하지 않는다. Claude 변경은 별도 미완료로 이번 커밋에서 제외한다.
