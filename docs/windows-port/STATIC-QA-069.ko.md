# QA069 — Claude Windows 세션 부분 범위 재검토

Windows 조건부 분기 및 tracked ConPTY API 호출을 독립 대조했다. 종료된 프로세스 감지 시 lease/handle이 다음 조회까지 남는 지적에 따라 Windows cleanup 후 processExited 오류를 반환하도록 수정했다. 해당 cleanup은 프로세스/메모리 정리이며 probe artifact 삭제 호출을 추가하지 않는다. 수정 후 독립 재검토 069: 부분 범위 승인. 추가 차단 사항 없음. 전체 parity 승인은 아님.

전체 parity 미완료: private probe 디렉터리 ACL, Windows watchdog 대응, 기존 승인 거절로 보류된 probe artifact 정리. QA047의 거절된 삭제 동작은 재시도하지 않았다. 빌드/컴파일러/테스트/실행을 하지 않았다.
