# QA092 — 저전력 설정 메뉴

구현 진행 중. 기존 WindowsRefreshSettings의 off/on/automatic 및 backgroundWorkLowPowerModePreference 키를 메뉴에 연결한다. 설정 저장 후 기존 refreshSettingsDidChange 경로로 조회 없이 타이머를 재계산한다. WindowsPowerState의 자동 모드는 battery saver flag를 사용한다. Battery Saver 변경 알림 등록과 thermal/비용 작업 정책은 별도 미완료 항목이다. 독립 정적 검토 전 미승인, 실행 검증 없음.

092 메뉴 초안은 저장 키/직접 명령 매핑/기존 재예약 callback 및 submenu 해제 경로를 Root가 대조했다. 독립 094 검토 진행 중. 다음 Battery Saver 작업의 등록 API는 [Microsoft 문서](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerpowersettingnotification)로 HANDLE/LPCGUID/DWORD 및 실패 시 NULL 계약을 확인했다. Swift import 형태는 아직 미검증이며 등록 코드는 작성하지 않았다.

094 최종 정적 승인: 설정 매핑/저장/callback 및 submenu 소유권에 추가 필수 지적 없음. diff --check 통과, Actions 비활성 확인. Battery Saver 이벤트 등록은 별도 미완료. 실행 검증 없음.
