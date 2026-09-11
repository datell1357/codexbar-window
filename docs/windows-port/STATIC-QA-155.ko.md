# 예측 후보 정책과 원본 호출 연결

155 정적 리뷰 승인: 153 CandidateCore와 156 원본 앱 연결. 원본의 source-window helper 및 self.weeklyPace를 유지하여 Codex historical/work-day 계산을 계속 사용한다. 후보는 세션→주간 순서이며 합성 세션만 제외한다.

선형 주간 helper는 예측 전용 기본 진행률3% 조건에 한정한다. 기간이 명시되지 않은 창은 거부하며 history-on 특수 계산을 대체하지 않는다. 메뉴의 minimumElapsedPercent 등 일반 pace 전체 정책을 이식한 것으로 간주하지 않는다.

Windows 계정 소유권·과거 기록·설정 및 알림 연결은 미구현이다. 코드 비교만 했으며 빌드·테스트·컴파일러·앱 실행 없음.
