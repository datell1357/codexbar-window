# 코드 비교 QA 020

고정 npm cmd-shim 7667c245e7d9259b5f88b77fb71b497ffcc26976 lib/index.js 61–119행을 직접 읽었다. no-args/no-env node template 전체 일치 recognizer, 64KiB bounded read, sibling node.exe/PATH 선택, literal JS prefix 및 PATHEXT 치환을 후보로 구현했다. Codex RPC/version/CLI availability에 같은 resolver를 연결했다. 다른 공급자와 임의 batch는 아직 미지원이다.

통합 검토에서 Swift multiline prefix의 불필요한 dropLast를 수정했다. reviewer의 directory node.exe→PATH fallback 요구는 원본 IF EXIST 분기와 다르므로 채택하지 않았다. ../ 금지 요구도 generator의 relative(dirname(to), from) 계약상 링크된 패키지를 배제하므로 채택하지 않았다. CLI executable 선택은 sandbox 경계가 아니며 unknown batch는 전체 template 비교로 거부한다. reviewer 재판정 대기.

Windows native PATH만 쓰므로 원본 cmd PATHEXT 임의 확장/현재 디렉터리 검색과 완전 동일하지 않다. 실제 compiler/test/shim 실행 없이 정적 비교만 진행한다. 전체 기능/모든 npm 버전 지원 완료가 아니다.

최종 독립 재검토에서 두 지적 철회 및 scoped 확정 결함 없음 확인. 실행 검증은 하지 않았다.
