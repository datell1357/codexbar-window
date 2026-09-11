# 대시보드 권한 전달 정적 검토 185–186

범위 제한 APPROVE. 대시보드·판정 입력·판정 결과를 불변 값으로 결합하고 웹 전략에서 ProviderFetchResult와 사용량·크레딧 변환 경로까지 보존했다. raw dashboard 호출 호환은 유지하며 권한 번들이 있으면 그 dashboard를 사용한다.

factory에서 실제 dashboard 이메일과 proof 이메일이 정규화 후 일치하는지 확인하도록 수정했다. 불일치·한쪽 nil이면 failClosed 및 빈 효과로 처리한다. 리뷰186에서 재확인했다. 기존 live/cached 효과 구분은 유지한다.

Windows 웹 생산자와 역채우기 소비자, 기존 앱의 별도 raw dashboard 비동기/캐시 경로는 미완료 범위다. 빌드·테스트·컴파일·앱/계정 실행은 하지 않았다.
