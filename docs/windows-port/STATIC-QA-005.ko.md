# 코드 비교 QA 005

진행 중이며 알림이 필요한 전체 완료/외부 결정은 없다. 구현·검토 루틴 유지.

WindowsProcess 후보에 Pipe/FileHandle/상속 stdin 입력 분기와 DuplicateHandle, 자식 handle list 포함을 추가했다. caller 소유 handle은 닫지 않고 복제본을 닫는다. UpdateProcThreadAttribute와 CreateProcessW가 같은 inherited buffer closure 안에 있도록 수정 요청했고 소스에서 확인했다. 중간 후보의 @_silgen_name CRT 선언은 ABI 위험으로 거부하고 ucrt import로 수정 요청했다. nil stdin에 콘솔이 없는 GUI 조건, SDK imported type 적합성, 독립 재검토는 후속 과제다.

HookRunner Windows 환경에는 SystemRoot/경로/사용자 및 임시 디렉터리의 좁은 allowlist를 추가했다. 독립 리뷰는 현재 이벤트 키 기준 변경부의 직접 보안 결함을 발견하지 않았다. Windows backend는 아직 SubprocessRunner에 연결되지 않아 hook 실행 기능 완료가 아니다. Pipe 선작성 4096바이트의 Windows 용량 전제도 미해결로 기록했다.

PROCESS-INTEGRATION-005.ko.md에 호출부 nil/nullDevice/Pipe 구분, legacy 출력 prefix와 max+1 차이, reader 오류 종료, 직접 POSIX 종료 호출의 계약을 추가했다. 전체 기능 ledger 분모/완료 수를 늘리지 않았다. 빌드/컴파일러/테스트/앱/provider/키체인/성능/Windows 실행은 하지 않았다.
