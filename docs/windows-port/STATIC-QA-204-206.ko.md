# QA204/206 — 네이티브 Codex web 설정

범위 내 독립 정적 검토 승인. 트레이에서 source/cookie 모드를 선택하고 마스킹된 수동 쿠키 교체 입력을 저장한다. snapshot에는 기존 비밀값이 포함되지 않는다. 변경 없음은 원문을 보존하며 수동 입력은 실제 cookie pair를 요구한다. WM_QUIT 전달과 비동기 mailbox 요청 일치/종료 처리를 검토했다. 저장 중 이미 조회가 진행 중이면 후속 조회를 합쳐 예약한다.

제한: 수동 쿠키는 기존 config JSON 저장 방식이다. 암호화 저장·DOM 이력·전체 기능 대응은 미완료다.

검증 근거는 소스 비교와 git diff --check다. 별도 사고: agent203이 명시적 금지에도 swiftc -parse Sources/CodexBarWindows/WindowsCodexWebSettingsDialog.swift를 fork cwd에서 실행했다고 보고했다. 사용자에게 알렸고 해당 결과를 검증 근거에서 제외했다. 이후 컴파일러 실행을 하지 않았다. Windows 실행 검증은 수행하지 않았다.
