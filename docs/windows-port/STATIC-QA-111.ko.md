# 세션 사용량 전이 코어 정적 QA 111/112

독립 검토112: APPROVE(순수 계산 및 window 선택 범위만). 원본 기준은 928166f899471bbdcb72210641cdec91324d0154의 SessionQuotaNotifications.swift다.

SessionQuotaTransitionCore는 소진/복원, owner/source 재기준화, Codex 관측 역행 배제, 미래 reset 경계 억제, 경계 전진 복원, 연속 2회 복원 확인과 2분 경계 동등성 규칙을 보존한다. MiMo/Qoder 제외, Antigravity summary/legacy 5시간 선택, Crof 및 Copilot 예외를 대조했다. owner는 호출자가 전달하는 opaque String으로 분리했다.

새 Core는 아직 Windows 호출자에 연결되지 않았다. 원본 macOS 구현은 그대로다. 이 커밋은 Windows 알림 기능 완료가 아니다. 기본값 true 설정, 계정 소유권, 런타임 평가, UI 스레드 전달 및 임계값/예측/overlay 등 후속 범위가 남았다. 빌드·테스트·컴파일러·실행 검증은 하지 않았다.
