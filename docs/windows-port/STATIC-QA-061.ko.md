# QA061–065 — Windows 트레이 통합 진행 중

판정: REQUEST CHANGES / 정적 비교만 수행. 기능 완료로 집계하지 않는다.

- Win32 트레이 호스트: 문자열 포인터 수명, 메뉴 ID 폭, 커서 위치, HWND 공유 상태 잠금, 중복 run 진입, 초기 아이콘 등록 오류 처리 수정.
- Windows 전용 실행 제품/타깃 초안 추가. 공급자 조회는 CLI subprocess 대신 Core descriptor 호출 경로를 연결 중.
- CLI 계정 context를 Core로 추출하고 기존 CLI 호출 이름을 보존했다. 독립 리뷰 065 진행 중.
- 통합 검토에서 Task 반환형 불일치, reset 문자열 구문, lazy host 초기화 경쟁, startup 오류 무시, 종료 시 refresh drain 누락, 계정별 effective source 누락을 발견했다. 담당 064 수정 중이며 재검토 전 승인/커밋하지 않는다.
- 트레이 표시 모드, 설정 UI, 자동 갱신/전력 정책, 플러그인 표시 및 전체 계정 UX는 이 초안으로 완료되지 않는다.
- 빌드/컴파일러/테스트/실행/실계정 접근/성능 검증은 실시하지 않았다.

## 통합 리뷰 066 후속

- active 토큰 계정 한 개만 표시하는 현재 경로는 전체 다중 계정 표시를 충족하지 않는다. 다만 resolvedAccounts(false)는 activeIndex를 선택하므로 단순히 첫 설정 계정을 선택한다는 리뷰 표현은 부정확하다. 계정 식별 표시 및 원본 표시 정책을 추가 대조 중이다.
- 플러그인 인스턴스가 firstPartyProvider 필터에서 조용히 제외된다. 명시적 미지원 표시와 실제 플러그인 연결은 별도로 처리해야 한다.
- Main의 30초 후 조용히 종료하는 timeout을 제거하고 runtime 종료 완료를 기다리도록 수정했다. 비협조적 공급자 취소 시 대기 가능성은 남아 있으며 소스 감사를 진행한다.
- manifest의 Windows 제품/타깃은 Windows 호스트에서 SwiftPM을 실행하는 구성을 전제로 한다. macOS cross-build 지원을 주장하지 않는다.
- lifecycle helper는 현재 Antigravity만 reset하므로 Codex/Claude 종료 경로를 067에서 별도 조사한다.

## 종료 경로 감사 067

기존 shutdownPersistentSessions는 Antigravity만 reset한다. Windows 앱 종료에서는 refresh 취소와 완료 대기 후 기존 CLIProbeSessionResetter.resetAll을 재사용해 Claude/Codex/Antigravity actor 세션을 모두 정리하도록 변경했다. reset 소스는 프로세스/메모리 정리이며 파일 삭제 경로를 추가하지 않았다. 원본 POSIX TTY 종료 함수를 Windows에 무조건 연결하지 않았다. 066 재검토 대기.

## 플러그인 경로 068

실제 macOS 호출을 대조한 결과 registry refresh가 config decode/normalize보다 먼저 필요하다. Windows 조회 런타임에 원본 승인 저장소/설정/secrets/cookie resolver를 사용하는 fetchUsage 연결을 구현 중이다. 승인 자동 부여는 하지 않는다. Windows 브라우저 쿠키/승인 UI/설정 UI는 별도 미완료다. Codex configured token 선택이 존재하면 projection보다 우선하도록 원본 CLI 계약을 보존한다. 공통 updater의 try? 저장 처리는 원본에서 상속된 동작이며 추출 회귀와 구분한다.

## 부분 범위 최종 판정 — 061/062/064/066/067/068

초기 실행과 수동 Refresh로 활성 계정 및 시작 시 발견된 승인 플러그인을 조회하는 트레이 초안은 범위 내 정적 리뷰를 마쳤다. 네이티브 메시지 루프/메뉴, Core 직접 조회, 계정 환경과 설정, 플러그인 승인 검사, 취소 후 세션 정리 경로를 연결했다. source-mode 계산은 원본 CLI와 동일한 인자를 사용하며 별도 override 누락을 확정 결함으로 보지 않는다.

부분 구현 게시 가능. 전체 기능 또는 Windows 컴파일/동작 승인 아님. 미구현: 자동 갱신, 전체 계정 표시/전환, 전체 창/사용량/credits/details 표시, 설정, 플러그인 재검색 및 설치/승인 UI, Windows browser cookies, native 브랜드 아이콘/접근성/알림/위젯/배포. 현재 제품은 Windows 호스트 SwiftPM 구성을 전제로 한다. 실행 및 경량성 측정 미실시.
