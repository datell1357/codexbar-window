# 코드 비교 QA 011

010 독립 리뷰의 Unix binary resolver 지적에 대응해 WindowsExecutableResolver를 작성하고 Grok Windows 경로에 연결했다. valid override 우선, semicolon PATH, Windows case-insensitive 환경 조회, quoted PATH 항목, regular file 및 native 확장자 후보를 처리한다. filename 검사만으로 PE 실행 유효성이 검증되는 것은 아니다. cmd/bat wrapper 및 Windows 설치 위치 자동 탐색은 후속 미구현이다.

Windows Grok stream 오류를 lock으로 보관한 뒤 continuation을 finish하도록 수정했다. readNextMessage가 generic EOF 전에 보관된 원인을 requestFailed로 전달한다. 취소는 stream 오류로 기록하지 않는다. per-stream EOF와 동시에 다른 stream이 실패하는 경우의 진단 우선순위는 독립 검토 중이다.

resolver의 중간 초안 public/nonWindows 노출, drive-relative colon 및 script extension 처리 개선을 요청했다. 최종 resolver 및 Grok error 전달 독립 리뷰 진행 중. 전체 Grok parity/전체 Windows 빌드 완료로 세지 않는다. 모든 검증은 코드 비교만 수행했다.

Grok 독립 EOF를 stderr 종료까지 지연하라는 리뷰 제안은 원본 EOF 동작을 바꾸므로 그대로 채택하지 않았다. stdout 자체 read 실패는 callback 없이 catch로 전달한다. stdout 정상 EOF 이후 미래 stderr 오류는 이미 끝난 요청 결과를 변경하지 않는다. drainTimeout에는 명시 진단을 먼저 기록하고 종료하도록 보완했다. 후속 리뷰 요청 중.

최종 리뷰 수신: native resolver 범위에서 확정 결함 없음, Grok StreamFailure 원인 전달/독립 EOF 유지 타당. 남은 availability/version callsite 지적은 012에서 수정한다. native resolver가 .cmd를 지원한다거나 .com 실제 image가 검증됐다는 의미는 아니다.
