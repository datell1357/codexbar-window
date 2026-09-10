# QA101/103 — CLI 세션 유지 시간

원본 ProviderRegistry.persistentCLISessionIdleWindow 및 UsageStore+TokenAccounts의 실시간 갱신 주기 전달을 비교했다. Windows의 고정 900초를 max(180, (실효 주기 ?? 120) + 60)으로 변경한다. 수동은 180초, 5분 주기는 360초, 저전력 30분 주기는 1860초다. 적응형은 기존 정책의 현재 판단을 재사용한다. Windows agent-aware 자동 갱신은 여전히 미지원이다.

소스 대조 및 diff 공백 검사만 수행하며 빌드·테스트·Windows 실행과 실제 세션 재사용은 미검증이다. 전체 기능 완료를 의미하지 않는다.
