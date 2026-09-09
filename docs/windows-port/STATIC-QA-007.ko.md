# 코드 비교 QA 007

SubprocessRunner.run에 Windows 조건부 dispatch와 WindowsSubprocessRunner를 연결했다. 원본 runToCompletion detached 경로는 유지했다. explicit limit+1/nil 1MiB prefix, 동시 wait/capture, 취소 Job 종료, 오류 시 group cancel을 추가했다. WindowsProcess.wait는 50ms 대기와 취소 플래그로 waiter 자체가 취소될 수 있도록 수정했다. timer는 root 상태 확인 후 종료 요청을 분류한다.

독립 리뷰에서 timer의 TerminateJobObject 실패 시 error만 저장하고 task group을 깨우지 않아 root가 계속 실행되면 무기한 대기 가능함을 확인했다. 다음 수정에서 별도 timeout/error event로 기다림을 깨우고 reader/wait 취소 및 정리를 보장해야 한다. 연결 후보는 부분 구현이며 이 지적으로 정적 QA 통과 처리하지 않는다.

리뷰의 출력 overflow 불가 지적은 normalizedMax=10→captureMax=11→read 최대11→11>10 예로 반박했다. read가 정확한 전달 budget을 보존하므로 +1을 다시 적용하면 오히려 중복된다. 취소 wait 개선도 최종 소스 기준 재검토 요청했다.

legacy terminateProcess를 Windows에서 제외했으나 RPC/Gemini 직접 호출부와 나머지 POSIX/PTY는 남아 있어 전체 Core Windows 호환 완료가 아니다. RPC-CONTRACT-007.ko.md에 두 RPC client의 full-duplex/NDJSON/timeout/실행 경로 계약과 문서 timeout 불일치를 기록했다.

빌드·테스트·컴파일러·앱·실계정·성능·Windows 실행을 하지 않았다. 모든 변경은 코드 비교 대상이다. 전체 기능 완료 아님, 루틴 유지.
