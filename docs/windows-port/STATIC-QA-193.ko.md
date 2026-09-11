# QA193 — Windows 역사 데이터 소비 경로

독립 정적 재검토 승인. authorizedDashboard를 WindowsUsageRuntime에 전달하고, 허용된 후보와 retained owner가 같은 경우에만 이력 역채우기를 연결했다. 첨부 이메일 우선순위와 alias ambiguity/multi-account veto를 dataset 조회까지 유지한다. await 이후 generation·종료·설정 검사를 유지한다.

초기 이메일 별칭 HIGH는 expectedScopedEmail 또는 trustedCurrentUsageEmail을 사용하도록 수정했다. 원문 dashboard 이메일이나 routing hint를 owner 근거로 사용하지 않는다. timestamp 지적은 원본 UsageStore+HistoricalPace.swift의 min(snapshot, dashboard)와 동일하므로 철회했다. 주간 fallback은 같은 lane 분류이며 session 표시 cap은 주간 값에 영향을 주지 않는다.

범위: 정적 코드 비교 및 git diff --check. 빌드·테스트·실행은 하지 않았다. Windows 대시보드 이력 수집 producer가 없으므로 전체 이력 복원 기능 완료를 의미하지 않는다.
