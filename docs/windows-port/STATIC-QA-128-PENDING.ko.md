# 전역 임계값 UI128/129 — 검토130 REQUEST CHANGES

ID Int/Int32 변환, BM_GETCHECK/BM_SETCHECK 심볼, nonoptional owner optional binding, Enter/Escape/Tab 처리와 단일 default button 수정을 요청했다. 상위 검토는 client 크기 대비 Save/Cancel 잘림, hidden tray owner 중심 계산, 실패 시 Context 중복 해제 가능성, child 생성 실패 무시와 owner enabled 상태 보존도 추가했다.128이 수정한다.

129는 actor 내 await 없는 revision guard를 제거하고 config 중복 키 trap을 피하도록 정리한다. 실행 검증 없이 정적 소스 대조만 수행하며 미게시 상태다.

## 상위 직접 수정 후 재검토 요청

addEdit/addButton의 HWND? 반환을 실제 반영하고 Save1/Cancel2 표준 ID 및 Save 단일 default style을 적용했다. 메시지 loop에서 dialog/child 대상 Enter/Escape를 IsDialogMessage 전에 처리하며 Cancel focus의 Enter는 취소한다. 초기 focus와 Tab 경로를 명시했다.130 재검토 대기, 실제 UI 미실행.

## 최종 재검토130 — 해당 범위 APPROVE

반환 타입·표준 ID·BM 상수·단일 default button·Enter/Escape/Tab·owner 복구·child 생성 실패·monitor 배치의 수정본을 독립 소스 대조했다.130에서 추가 HIGH/CRITICAL 문제 없음. native UI 동작/배치·ABI·빌드·키보드 실제 검증은 미실시다. provider별 override 편집은 다음 범위이며 전체 기능 완료가 아니다.
