# 코드 비교 QA 009

008 독립 최종 검토 수신: timeout/cancellation/capture 경로 지적 0, 정적 APPROVE. 실제 Windows 빌드/실행은 하지 않았다.

Windows 환경 변수 이름의 대소문자 차이를 처리하도록 CodexBarPlatformPaths.environmentValue를 추가했다. exact key 우선, Windows만 정렬된 case-insensitive fallback; LOCALAPPDATA/CODEXBAR_CONFIG/XDG_CONFIG_HOME 조회에 적용. non-Windows 기존 동작과 config override 우선순위 유지. 독립 범위 검토 APPROVE.

RPC를 위한 WindowsProcess 증분 stdout/stderr API 구현 중. aggregate capture와 reader 동시 소유를 막고 bounded callback에 청크를 전달한다. detached async callback의 취소 수명 및 EOF/강제 drain 구분을 검토에서 지적해 보완 요청했다. RPC client에 아직 연결되지 않았다. 전체 기능 완료로 세지 않는다.

후속: stream API 독립 리뷰 후 Codex/Grok RPC의 BoundedLineBuffer/입력 Pipe/종료 및 오류 경로 연결. 원본 Process 기반 RPC와 /usr/bin/env 경유, 직접 POSIX 종료 호출 제거가 함께 필요하다. 원본 Browser 타입도 non-macOS empty struct 및 detection false stub인 것을 재확인했으며 브라우저 자동 인증은 여전히 미구현이다.

후속 소스 수정: callback을 synchronous bounded 처리 계약으로 바꾸고 StreamTermination eof/forcedStop/drainTimeout 결과를 분리했다. 반환 누락 및 drain timeout이 EOF로 보고되는 중간 초안 문제를 수정했다. stream_009_review 독립 리뷰는 진행 중이며 RPC caller 연결은 다음 작업이다.

009 독립 리뷰의 aggregate drainTimeout 오류 요구는 원본 ProcessPipeCapture.finish의 bounded Data 반환과 대조 후 철회되었다. 원본 계약을 유지한다. 새로운 stream EOF는 결과만으로 다른 pipe 종료를 기다릴 수 있어 010에서 개별 종료 callback을 추가했다.
