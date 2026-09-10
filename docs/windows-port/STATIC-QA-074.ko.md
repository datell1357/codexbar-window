# QA074/075 — Windows 전력 신호 연결

074 초안: GetSystemPowerStatus 단일 조회에서 AC 상태와 battery saver 신호를 구분하고, 실패 코드 및 off/on/automatic 원본 설정/legacy bool 복원을 연결했다. 독립 정적 리뷰 075 진행 중.

Root는 전원 조회 오류 필드가 소비되지 않는 것을 확인해 트레이 상태 행에 오류 코드를 표시하도록 연결했다. 실제 OS 알림/thermal 이벤트와 cost catch-up 전력 정책은 미완료다. 실행·컴파일러·빌드·테스트·성능 측정은 하지 않았다.

## 이벤트 연결 076

AC/배터리 상태 변경 및 자동 resume broadcast에서 runtime의 현재 fixed/adaptive sleep을 취소하고 기한을 재계산한다. fetch 중 변경은 다음 fixed tick 계산 직전 power 재조회로 반영한다. battery-saver 전용 GUID 등록은 아직 미구현이며, 등록 없이 PBT_POWERSETTINGCHANGE를 받는다고 주장하지 않는다. 075 통합 재검토 중.

## 075 최종 재검토

전력 snapshot/설정 복원 및 AC·resume 이벤트 범위에서 새 차단 오류 없음. 조회 중 변경은 다음 주기 계산 전 재조회하며 종료 후 이벤트는 무시한다. 부분 범위 게시 가능. Battery Saver 전용 설정 알림 등록, thermal 및 비용 작업 전력 정책은 미완료. 실제 Windows 검증은 하지 않았다.
