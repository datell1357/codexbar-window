# QA063/065 — 공통 계정 context 추출

판정: 범위 내 정적 리뷰 승인. 전체 Windows 이식 완료 또는 실행 검증을 뜻하지 않는다.

원본 HEAD의 CLI 계정 선택/설정/환경/토큰 갱신/managed Codex 계정 reconciliation/source-mode 구현을 Core로 이동했다. CLI typealias로 기존 호출 이름을 유지한다. 공개 접근 수준과 명시적 선택 초기화 외 구현 본문의 의미 변경은 확인하지 않았다.

독립 리뷰 065: Core → CLI/Commander 의존성 역전 없음, 호출 타입과 공개 API 소스 대조에서 차단 사항 없음. 빌드·테스트·컴파일러·실계정 실행은 하지 않았다. 트레이 소비자 연결은 별도 QA061/066 대상이다.
