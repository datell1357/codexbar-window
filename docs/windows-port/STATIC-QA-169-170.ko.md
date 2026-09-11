# 학습 이력 공유 코어 추출 정적 검토 169–170

판정: 추출 범위 APPROVE. 기준928166f899471bbdcb72210641cdec91324d0154의 HistoricalUsagePace 및 CodexHistoryOwnership과 비교했다. 접근 수준·모듈 import·공개 초기화자·Sendable을 제외하면 저장 형식, 표본 필터, 56일 유지, 주간 곡선 복원 및 확률 평가 알고리즘이 동일하다.

Windows 기본 파일 경로만 기존 CodexBarPlatformPaths 정책의 LOCALAPPDATA/CodexBar/usage-history.jsonl로 분기한다. macOS 경로는 유지한다. Crypto는 기존 Core 의존성을 재사용한다. 기존 앱 파일은 타입얼리어스로 남겨 호출 및 테스트 접근을 유지했다. 공개 값 타입에 checked Sendable을 추가해 actor 경계를 명시했다.

리뷰170에서 새 필수 지적 없음. Windows 런타임 기록·데이터셋 연결, 대시보드 역채우기 권한 및 레거시 소유권 연속성은 별도 미완료 범위다. 빌드·테스트·컴파일·실제 파일 저장 실행은 하지 않았다.
