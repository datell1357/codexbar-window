# 프로세스 코드 비교 003 — 미통합 초안

WindowsCommandLine.swift에 CRT 인자 quoting, UTF16/NUL/명령줄 길이, 환경 변수 중복/정렬/이중 NUL과 드라이브 항목 처리를 작성했다. 실제 실행은 하지 않았다.

WindowsProcess.swift 초안은 suspended launch/Job/handle list 흐름을 포함하지만 정적 비교에서 pipe 부분 실패 정리, buffer bound 이후 drain, stdin, 취소/출력 drain, WinSDK pointer 형태의 결함/미완료가 발견됐다. SubprocessRunner 연결에서 조건부 컴파일 종료 누락도 발견해 해당 연결을 철회하도록 요청했다. 초안은 연결 완료/기능 완료로 세지 않는다.

다음 작업은 초안 결함 수리 및 독립 정적 검토 후 caller를 연결하는 것이다. 원본 runner 및 PTY 기능을 no-op/unsupported 경로로 대체하지 않는다. 이번에는 컴파일러/manifest/빌드/테스트/실행을 호출하지 않았다.
