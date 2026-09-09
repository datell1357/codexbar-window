# QA048 — Windows TCP 리스너 탐색

범위 한정 정적 APPROVE. Windows GetExtendedTcpTable로 IPv4/IPv6 LISTEN 행의 owner PID를 대조하고 포트를 수집한다. Antigravity listeningPorts Windows 분기와 Iphlpapi 링크를 연결했다.

통합 리뷰에서 발견한 UInt16 변환 overflow, PID 범위, native 호출 전후 취소/deadline 검사, 오류를 빈 테이블로 숨기던 동작을 수정했다. 16MB 크기 제한, 3회 재시도, 행 수 경계와 포트 바이트 순서를 대조했다. ports_review_048가 최종 소스 재검토에서 범위 내 차단 지적 없음으로 판정했다. git diff --check 통과.

Windows WinSDK ABI/컴파일/실행은 사용자 지시에 따라 검증하지 않았다. 동기 native 호출 중 강제 취소는 없으며 호출 전후 협력적 deadline이다. 전체 Antigravity 프로세스 탐색/세션 이식 완료가 아니다. Claude047의 승인 대기 변경은 이 단계 커밋에서 제외한다.
