# QA 045 — tracked lease 진행 중

직접 생성한 suspended ConPTY 객체를 동일성으로 등록한 뒤 resume하는 lease를 구현 중이다. one-shot runner와 지속 세션은 동일 종료 registry를 공유해야 한다. 임의 PID 재연결은 하지 않는다.

초안의 persistentKey 재사용 cache는 actor의 계정·환경 소유 계약과 중복되어 제거 요청했다. Registry Sendable, WinSDK DWORD import 및 활성 자원을 버리는 debug reset도 정적 수정 대상이다. tracked_lease_045는 wrapper, lease_wire_045는 기존 runner 연결, lease_review_045는 독립 검토를 담당한다. 아직 커밋·빌드·테스트·실행하지 않았다.

## 범위 한정 정적 APPROVE

lease_review_045가 최신 wrapper와 one-shot 연결을 재대조했다. WinSDK 및 Sendable 보정, speculative cache/reset 제거, suspended 등록 후 resume, 종료 fence와 객체 동일성 해제가 반영됐다. one-shot과 후속 지속 세션이 동일 registry를 사용한다. git diff --check만 수행했다. 지속 세션 연결은 046 이후 미완료이며 Windows 컴파일·실행·성능은 검증하지 않았다.
