# QA071/072 — 자동 갱신 통합 검토

현재 REQUEST CHANGES. 원본의 주기 raw 값과 AdaptiveRefreshCore 정책을 재사용하는 초안을 작성했으나 통합 정적 검토에서 다음 문제를 발견했다.

- public 신호 타입이 package 내부 열 상태 타입을 노출한다. 같은 패키지에서 Core 접근은 가능하므로 Core를 public으로 확대하지 않고 경계를 수정한다.
- 스케줄 Task의 Optional Void 반환형, start 재진입, schedule 대기 전 refresh 취소 누락.
- Main의 중복 shutdown 호출이 완료 전 semaphore를 신호할 수 있어 단일 종료 경로로 복원한다.
- 활동 스캐너가 없는데 consent allowed만으로 agent-aware를 활성화하는 오류.
- 비문자열 잘못된 defaults 값을 신규 설치로 오인하는 오류.
- 메뉴 열기 timestamp는 기록하지만 이미 잠든 타이머를 앞당기지 않는 누락.

071 수정 및 072 독립 리뷰 중. 빌드/컴파일러/테스트/실행 미실시. 전원/열 OS 연결, 활동 스캐너, 리셋 경계/설정 UI는 별도 미완료다.

## 독립 리뷰 072 후속

메뉴 열기 시 잠든 타이머를 앞당기는 경로와 고정 주기 저전력 보정이 남았다. 스케줄 전체를 중복 생성하지 않고 sleep task만 취소해 새 기한을 반영하는 방식으로 071 수정 중. 활동 감지는 동의와 무관하게 Windows 스캐너 자체가 미구현이므로 자동 실행하지 않으며 안내 문구를 정확히 고친다. 전체 계정 표시 미구현은 별도 범위로 계속 남긴다. 073에서 원본 전력 정책/설정 경계를 대조한다.

## 타이머 경로 추가 대조

adaptive 일반 sleep 전에 scheduledDeadline을 저장하지 않아 정상 timeout을 wake로 오인하는 결함과 첫 fixed tick에 저전력 clamp가 반영되지 않는 결함을 발견했다. 071 수정 후 072 재검토. 전력 설정 off/on/automatic 및 Windows OS 신호 연결은 073 조사로 경계를 확인했고 아직 구현되지 않았다.

## 부분 범위 최종 재검토

072 재검토: 정상 adaptive tick, 메뉴 조기 wake, 시작/종료 취소, 고정 주기 하한의 정적 경로에 새 차단 결함 없음. 고정/일반 adaptive 주기 구현 부분 범위 게시 가능. 실제 OS 저전력/열 신호와 설정 UI, agent-aware scanner, 리셋 경계는 미완료. 런타임 검증 미실시.
