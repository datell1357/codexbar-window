# 임계값 화면 경고 — 정적 검토

144 컨트롤러와 146 호스트 연결을 145·147 독립 리뷰했다. 최종 정적 blocker 없음.

4.5초 타이머, 새 알림 교체, 활성화 방지, 동일 개인정보 필터 문구, 기본 off 화면 설정, 경고 master gate 및 종료 정리를 연결한다. HWND는 Context.window만 소유하고 WM_NCDESTROY에서 비운다. 레이어/타이머 실패 시 즉시 정리하며 UTF-16 표시 버퍼를 제한한다.

클릭 통과에 관한 최초 지적은 [Microsoft Layered Windows 문서](https://learn.microsoft.com/en-us/windows/win32/winmsg/window-features)의 layered+WS_EX_TRANSPARENT 조합 계약을 확인한 뒤 철회했다. 불투명도 255는 이 입력 통과 스타일을 무효화하지 않는다. 실제 Windows 입력·렌더링 검증은 하지 않았다.

원본 SwiftUI material/animation과 시각적 동일성은 입증하지 않았으며 고정 크기 GDI 표면을 사용한다. 예측 경고 연결·전체 기능·경량 성능 검증 완료로 집계하지 않는다. 빌드·테스트·컴파일러·앱 실행 없음.
