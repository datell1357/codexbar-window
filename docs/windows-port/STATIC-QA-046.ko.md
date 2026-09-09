# QA046 — Codex Windows 지속 세션

범위 한정 정적 APPROVE. Windows ConPTY owned lease를 CodexCLISession에 연결했다. 상위 capture gate, reset 시 helper 분리와 generation 무효화, await 후 generation 검사, 취소 cleanup을 대조했다. 원본 POSIX 구현은 조건부 분기 내 유지한다.

업데이트 프롬프트 CR 및 120/150/300ms 순서, 최초 status 200ms, 재전송 220ms 및 lastEnter 초기화, 2초 settle cursor 응답을 보정했다. 큰 청크 전체와 이전 tail을 검색한 뒤 tail을 제한하고 최종 UTF8 변환·출력 한도를 보존한다.

독립 codex_review_046가 최종 파일을 다시 읽어 범위 내 필수 지적 없음으로 판정했다. git diff --check 통과. 빌드·테스트·실행·성능 검증은 사용자 지시에 따라 미실시다. 전체 기능 이식 완료가 아니며 다음은 Claude 지속 세션이다.
