# QA095 — Battery Saver 변경 알림

구현 중. HWND 생성 뒤 GUID_POWER_SAVING_STATUS 등록, 창 파괴 전 등록 해제, PBT_POWERSETTINGCHANGE에서 기존 전력 snapshot 재조회 callback을 호출한다. 등록 실패와 해제 실패를 명시적으로 처리한다.

근거: [등록 API](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerpowersettingnotification), [GUID](https://learn.microsoft.com/en-us/windows/win32/power/power-setting-guids), [해제 API](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-unregisterpowersettingnotification). Microsoft C 계약을 문서로 확인했으며 Swift WinSDK ABI와 실제 이벤트 수신은 미검증이다. 독립 정적 승인 전 미완료.

Root 검토: WM_CLOSE의 직접 DestroyWindow가 defer의 알림 등록 해제보다 먼저 실행되는 경로 발견. 종료 메시지는 루프 종료만 요청하고 등록 해제/창 파괴를 defer에 모으도록 수정 중이다. 096 독립 정적 검토 전 미승인.

096 최종 정적 승인: GUID/등록 수명/오류 처리/WM_CLOSE 종료 순서/전력 재조회 callback 연결 확인, 추가 필수 정적 지적 없음. diff --check 통과, Actions 비활성 확인. Swift ABI 및 실제 이벤트 수신, Windows 빌드·실행은 검증하지 않았다. 전체 동등성은 미완료.
