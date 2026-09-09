# 코드 비교 QA 008

WindowsSubprocessRunner 타이머 종료 실패를 AsyncStream(bufferingNewest:1)으로 전달하고 task group의 별도 monitor가 오류를 throw하도록 수정했다. 타이머가 monitor 시작 전에 실패해도 이벤트를 보존한다. 오류는 group.cancelAll로 wait/capture를 취소하고 기존 Job 정리를 거쳐 반환한다. 정상 pair가 모이면 TimeoutState.finish와 group.cancelAll로 무기한 idle monitor를 종료한다. defer에서 timer와 stream을 최종 해제한다.

원본 subprocess 로그 start/timeout/overflow/failure/exit/error와 label/binary basename/status/duration 메타데이터를 Windows 경로에 추가했다. 독립 로그 비교는 원본과 일치하며 args/env/stdout/stderr를 새로 기록하지 않음을 확인했다. 원본처럼 launch 자체 오류는 start 이후 일반 error catch 밖이다. UTF8 손실 허용 prefix/바이트 limit 계약도 유지한다.

타임아웃 모니터 독립 정적 리뷰 요청 중. 실행·빌드·테스트·컴파일러·키체인·실계정·성능 검증은 하지 않았다. SDK 타입/전체 Core 호환, RPC/PTY/직접 POSIX 호출 대체와 전체 기능 이식은 미완료다.

최종 독립 리뷰 수신: timeout monitor/wait/capture 범위 APPROVE, 지적 0. 버퍼링된 사전 실패 전달, finish/trigger lock, 취소 후 poll 종료를 소스에서 확인했다. 해당 범위의 정적 리뷰이며 전체 기능 완료나 실행 검증을 뜻하지 않는다.
