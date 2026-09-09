# 코드 비교 QA 010

009 stream 리뷰에서 제기된 aggregate 1초 drain 후 prefix 반환은 원본과 동일하여 지적 철회. stream에 개별 onStdoutEnd/onStderrEnd callback을 추가해 stdout EOF가 stderr 종료 전에도 RPC continuation을 닫을 수 있게 했다. callback은 bounded synchronous 작업만 허용하는 계약을 명시했다.

GrokRPCClient WindowsProcess 연결 후보 작성 중: direct executable, 기존 stdin Pipe, BoundedLineBuffer 청크 처리, EOF/timeout/shutdown 종료. 중간 diff 검토에서 nonWindows stdin 중복 선언, streamTask 변경 race, timeout 오류가 EOF보다 먼저 반환돼야 하는 원본 계약, stream 오류 후 프로세스 정리를 지적해 수정 요청했다. 최종 독립 리뷰 진행 중.

PathBuilder.effectivePATH는 ':' 구분 및 /usr/bin fallback/login shell을 가정하므로 Windows 새 경로에서 호출하지 않도록 요청했다. BinaryLocator/TTY.which 자체의 Windows 탐색과 .cmd script 실행은 아직 미해결이다. 연결 코드만으로 Grok 기능 전체 완료로 세지 않는다.

빌드/테스트/컴파일러/앱/계정/키체인/성능/Windows 실행은 하지 않았다. 전체 기능 이식은 진행 중.
