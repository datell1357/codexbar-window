# QA089/090 — 갱신 주기 메뉴

구현 진행 중. 기존 WindowsRefreshSettings의 manual/고정 주기/adaptive 설정을 네이티브 메뉴에 연결한다. agent-aware는 탐색기 미구현으로 사용 가능 처리하지 않는다. 주기 변경 시 기존 timer를 교체하되 진행 중인 공급자 조회를 중단하지 않으며, 빠른 연속 변경과 종료 시 중복 scheduler/오래된 task의 새 handle 해제를 방지해야 한다. 메뉴 handle 소유권과 저장 키를 포함한 독립 정적 검토 전 미승인. 실행 검증 없음.

091 독립 검토: start 이전 주기 callback이 scheduleTask를 생성하면 start의 guard가 최초 조회를 건너뛰는 race 발견. 초기화 여부를 timer 존재와 분리하고 시작 전 callback은 예약하지 않도록 수정 중. 나머지 세대별 timer 교체와 메뉴 handle 소유권은 정적으로 확인됨. REQUEST CHANGES.

최종 091 재검토 APPROVE: started 분리로 최초 조회 누락 해결. 기존 조회 유지, 세대별 scheduler 교체, 종료 처리 및 메뉴 소유권에 추가 필수 정적 지적 없음. Actions 비활성 확인. 빌드·테스트·Windows 실행 검증 없음. 전체 동등성 미완료.
