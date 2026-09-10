# Windows 알림 이식 계약 (정적 분석 109)

고정 원본 928166f899471bbdcb72210641cdec91324d0154의 SessionQuotaNotifications.swift, UsageStore+SessionQuotaTransition.swift, UsageStore+QuotaWarnings.swift 및 SettingsStore를 대조했다.

세션 소진/복원 알림 기본값은 true다. 임계값 알림은 false, 기본 임계값은 [50,20], 세션/주간 lane 및 소리는 true, overlay는 false다. 설정만 영속화되며 전이·중복 억제 상태는 메모리 상태다.

첫 구현 범위는 세션 소진/복원이다. 소진 기준 <=0.0001, owner/source 변경 baseline, Codex 관측 시각 역행 배제, 신뢰 가능한 미래 reset 경계와 복원 2회 확인 규칙을 보존한다. Codex owner 부재를 정상 계정으로 추정하지 않는다. Provider별 window 선택 예외도 함께 연결한다.

111은 순수 Core만 작성한다. 이후 Windows runtime 성공 snapshot 평가, 기본값 true 설정, UI 스레드 알림 전달을 연결해야 실제 기능 구현 경로가 된다. 임계값/예측 알림·소리/overlay는 별도 미완료 범위다. 빌드·테스트·Windows 실행 검증은 하지 않는다.
