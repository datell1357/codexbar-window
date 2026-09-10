# 알림 연결 114/115 정적 검토 — 수정 진행 중

코어111은 게시됐으나 이번 Windows 호출 연결은 미커밋이다. 독립 검토116 진행 중.

상위 소스 대조에서 발견한 필수 수정: synthetic placeholder 제외, Codex window 부재 시 관측 watermark 전진 및 owner 변경 baseline 초기화, 날짜를 가진 baseline admission, disabled 상태에서 baseline 요구 보존, 비Codex 강제 baseline 제외, 원본 owner의 이메일 필수성과 domain 구분 보존. 구현자114에 수정 전달했다.

트레이115는 기본 true 설정·FIFO·UI 스레드 balloon 전달·UTF16 경계 처리를 구현했지만 독립 검토가 끝나지 않았다. hook·임계값·예측·overlay·현지화·현대 Windows toast는 이번 범위 완료에 포함하지 않는다. 빌드·테스트·실행·성능 검증 미실시. 전체 이식 미완료.

## 독립 검토116 후속

판정 REQUEST CHANGES. 트레이 host 자체는 해당 범위 차단 사항 없음. 런타임은 watermark 이하 관측을 reducer 전에 거부하지 않아 같은 시점의 소진 알림이 잘못 발생할 수 있다. email-only owner hash의 원본 domain 분리와 잘못된 profile path 거부도 미반영이었다. disabled/missing-window 경로의 원본 helper 의미까지 다시 수정하도록114에 전달했다. 비Codex 재활성 baseline 변경은 원본 근거가 없으므로 추가하지 않는다. 수정 전 통합본 커밋·푸시 없음.

## 최종 재검토116: 해당 범위 APPROVE

파일 이름의 PENDING은 최초 기록 상태를 보존한다. 현재 세션 소진/복구 알림 연결 범위는 정적 재검토 승인이다. watermark 이하 관측 거부, owner 부재에서 이전 시점 보존, window 부재에서 요구 시점 전진, synthetic 제외, domain 분리된 email owner key 및 profile 경로 검증 수정 후 재대조했다. 비Codex disabled 동작은 원본 reducer와 같아 해당 지적은 철회됐다.

기본 true 메뉴 설정, runtime publisher, UI thread FIFO와 Shell_NotifyIconW NIF_INFO 연결을 검토했다. WinSDK ABI·빌드·실제 전달·성능은 미검증이다. legacy balloon이며 현대 toast, threshold/predictive, hook, overlay, 전체 현지화는 완료 범위가 아니다. 전체 W09 미완료.
