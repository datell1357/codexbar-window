# Windows 예측 알림 연결 전 잔여 계약

154 정적 분석: Codex liveCard sourceRateWindow는 primary/secondary를 300·10080·43200분으로 분류한 후 슬롯으로 대체하며 같은 lane은 secondary가 우선한다. Core descriptor 내부 분류와 같다. 표시용 visibleWindows는 주간 소진 보정/필터가 있어 대체할 수 없다.

Windows 기존 quota discriminator는 token account를 먼저 선택하고 Codex owner helper는 이메일 없는 provider account ID를 식별하지 못한다. 예측 episode에 그대로 사용하면 원본 canonical ownership과 차이가 난다. 이메일 없이 provider account ID만 있는 경우를 별도로 이식해야 한다.

주간 historical dataset, 설정 로더(predictive enable/workDays/history), 계정별 history 연결이 미구현이다. 선형 계산만 연결해 전체 예측 동등성으로 집계하지 않는다. 앱 candidate assembler 공용화에는 기존 historical pace를 주입하여 원본 동작을 유지한다.

코드 비교만 실시했다. 빌드·테스트·Windows 실행 없음.
