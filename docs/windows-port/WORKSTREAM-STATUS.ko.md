# 전체 이식 작업 현황

정적 코드 비교 기준. 기존 Swift 원본이 있는 것과 Windows 대응 완료를 구분한다. 현재 완료 판정된 작업 묶음은 없다. 기능 후보 569개는 전체 분모가 아니며 전수 기능 계약 재대조가 남았다.

| 계획 영역 | Windows 상태 | 남은 핵심 경계 |
|---|---|---|
| W01 공급자 | 부분 연결 | 69개 × 인증/조회 소스의 Windows 연결 및 오류 경로 |
| W02 계정 | Credential Manager·기본 browser profile 탐색 일부 | 외부 CLI 계정 소유권·OAuth/browser·전환 |
| W03 트레이 | native 메뉴·상세 사용량·표시 토글 일부 | native tray/popup 및 모든 표시 모드 |
| W04 설정 | 경로·사용/잔여 및 리셋 시각 메뉴 일부 | 전체 native UI·설정 상태·migration |
| W05 사용량/예측 | 원본 보존, 대응 미판정 | Windows runtime과 소비자 연결 |
| W06 비용 | 원본 보존, 대응 미판정 | 파일/증분/회전/계정별 경로 |
| W07 대시보드 | 미구현 | native 표시·집계·export 연결 |
| W08 갱신 | fixed/adaptive timer·전력 snapshot·AC/resume 일부 | agent-aware·reset boundary·Battery Saver 알림·전체 정책 |
| W09 알림 | 미구현 | Windows 알림과 전이별 중복 방지 |
| W10 위젯 | 미구현 | Windows 표면과 snapshot 연결 |
| W11 세션 | Codex/Claude/Antigravity OS 연결 일부 | 프로세스/터미널/원격 탐색 |
| W12 CLI/HTTP | process 기반 일부 | 직접 POSIX/TTY/Winsock/명령 계약 |
| W13 Hooks | native process 일부 | event runtime, Windows 시나리오 전수 대조 |
| W14 Plugins | QuickJS·승인된 plugin 조회 일부 | 재검색·cookie·설치/승인/설정 UI |
| W15 Sync/Fleet | 미구현 | CloudKit 대응·충돌·계정·offline |
| W16 운영 | 미구현 | 설치/서명/update/startup/접근성 |

단계별 코드 리뷰 기록은 STATIC-QA 문서에서 확인한다. 전체 제품 완성률을 파일/커밋 수로 계산하지 않는다. 실행 검증은 사용자 지시로 전혀 하지 않으며 별도 승인 없는 상태에서 자동 CI도 재활성화하지 않는다.
