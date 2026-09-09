# 코드 비교 QA 013

WindowsProcess.launch에 mergeStandardError 옵션을 추가했다(default false). true일 때 child stdout/stderr에 동일 stdout writer를 지정하고 상속 목록에 중복 handle을 넣지 않는다. 기존 별도 stderr pipe는 parent만 보유하고 launch 이후 writer close로 EOF를 받는다. 따라서 capture 문자열을 뒤에서 결합하지 않고 원본 pipe interleaving을 보존한다. 기존 handle별 close 경로는 유지했다.

ProviderVersionDetector.run의 Windows synchronous backend 구현 중. stdout bounded capture와 비병합 stderr drain, root timeout/exit status, .25초 drain/첫줄 decode를 구현하도록 작업 범위를 고정했다. Claude 전용 fingerprint/TTY 경로와 other provider resolver는 이 변경으로 완료되지 않는다. merge handle 및 sync helper 독립 정적 검토를 진행한다.

빌드·테스트·컴파일러·앱·실계정·키체인·성능·Windows 실행은 하지 않는다. 전체 이식은 미완료다.

merge launch 독립 리뷰에서 handle 상속/alias/실패 정리 확정 결함 없음 확인. sync helper 중간 초안의 무제한 내부 drain loop(타임아웃 검사 기아), strict UTF8, wall clock, 무한 drain 조건 문제를 직접 검토에서 발견해 보완 요청했다. 아직 sync helper 정적 리뷰 통과로 세지 않는다.

후속 후보는 monotonic tick, bounded poll, lossy UTF8, finite drain 조건으로 수정했고 ProviderVersionDetector.run에서 merge 옵션을 전달한다. merge 옵션이 미사용이라는 리뷰의 조건부 우려는 해당 caller 연결로 해소된다. forceExit Windows 제외 처리, sync 최종 독립 검토 대기.
