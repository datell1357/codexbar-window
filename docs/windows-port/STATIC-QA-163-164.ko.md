# 예측 경고 런타임 정적 검토 163–164

판정: 제한된 런타임 연결 범위 APPROVE. 전체 기능 동등성은 미완료다.

WindowsUsageRuntime의 성공 스냅샷에서 계정 소유권, 세션·주간 후보, reset-cycle 중복 억제와 의미 이벤트 발행을 연결했다. 별도 predictive generation으로 설정 변경 전 시작된 조회를 배제하고, 최신 활성 공급자 집합으로 상태를 정리한다. 예측 계산 시각은 원본처럼 snapshot.updatedAt을 사용한다.

리뷰164의 이전 조회 결과 및 비활성 공급자 상태 정리 지적은 수정 후 재검토에서 해소됐다. Codex token UUID 누락 지적은 철회했다. 원본 PredictivePaceWarnings는 세션 quota의 token UUID가 아닌 codexOwnershipContext canonicalKey를 사용한다.

남은 범위: 과거 데이터 기반 예측과 Windows 네이티브 알림 전달. 네이티브 전달은166에서 작업 중이며 이번 승인에 포함하지 않는다. 빌드·테스트·컴파일·앱 실행·실계정 검증은 실시하지 않았다. git diff --check는 공백 검사 근거일 뿐 동작 검증이 아니다.
