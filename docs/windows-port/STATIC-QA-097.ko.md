# QA097–098 — Windows 리셋 경계 갱신

기준 원본: `928166f899471bbdcb72210641cdec91324d0154`.

원본 `UsageStore+ResetBoundaryRefresh.swift`, `UsageStore+AdaptiveRefresh.swift`의 계약을 `Sources/CodexBarWindows/WindowsUsageRuntime.swift`에 연결했다. 모든 rate window의 reset+30초, 최소 5초 지연, snapshot 갱신 시각, 정상 갱신 주기 안의 후보, 저전력 1800초 하한을 비교한다. 시도 경계는 최대 64개로 제한하고 실행 중인 갱신에는 시도를 기록하지 않는다. 수동 및 아직 지원하지 않는 agent-aware 모드는 예약하지 않는다.

독립 검토 `reset_contract_098`의 초기 지적: 설정 변경 시 예약 marker 잔류, 전력 변경 시 기존 예약 미계산. 두 항목을 수정한 뒤 범위 한정 정적 승인. 한 번의 예약 판단에서 전력 snapshot도 한 번만 읽도록 정리했다. 설정 변경·오류·종료 시 취소와 성공한 현재 표시 snapshot의 소비 경로를 대조했다.

검사: 소스 읽기 및 `git diff --check`. 빌드·테스트·컴파일·실행·계정 접근·성능 측정은 하지 않았다. WinSDK ABI와 실제 timer/actor 실행 동작은 미검증이며 전체 기능 동등성 승인이 아니다. agent-aware 활동 감지 및 다른 전체 갱신 정책은 미완료다.
