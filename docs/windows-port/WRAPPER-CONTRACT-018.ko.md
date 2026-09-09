# Windows wrapper 후속 구현 경계

독립 설계 검토 wrapper_contract_018: 현재 native exe/com resolver와 CRT argument encoder는 그대로 유지한다. cmd/bat를 CreateProcess의 native 이미지처럼 허용하거나 모든 명령을 cmd.exe로 보내면 인수 보존 계약이 깨진다. 일반 batch는 내용에 따라 % expansion, delayed expansion, %* 재해석이 발생하므로 임의 argv 동등성을 주장하지 않는다.

다음 구현은 Windows launch plan(applicationName, arguments, native/npm shim 종류)을 추가하고, 검증된 npm cmd-shim template만 구조적으로 인식해 node.exe + JS entry + 원래 arguments를 직접 실행하는 경로다. 임의 shell 평가를 하지 않는다. sibling node.exe 우선/PATH node 다음, 실제 JS entry regular file, 단일 literal target 확인이 필요하다. 모호하거나 다른 prelude/side effect가 있는 wrapper는 지원 완료로 세지 않는다.

실제 저장소/설치 shim template 근거를 먼저 확보하고 허용 문법을 고정해야 한다. Codex/Grok/Claude/Gemini availability/version/RPC가 같은 launch plan을 써야 한다. 일반 hook cmd/bat 기능은 원본 direct-exec 계약과 별도로 검토하며 전체 기능 분모에서 삭제하지 않는다. pnpm/Yarn/Bun 및 환경/cwd side effect는 미해결이다.

현재는 설계 근거만 기록했으며 wrapper 실행 구현·테스트 완료가 아니다.
