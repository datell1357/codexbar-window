# 동일 계정 상태의 설정·환경 API 정적 검토 182–184

제한된 API 범위 APPROVE. 캡처한 reconciliation에서 source를 선택할 때 managed activeStoredAccount도 함께 갱신하고, live/managed/profile identity 규칙을 원본과 비교했다. retained context와 명시적 source override를 함께 전달할 때 설정과 CODEX_HOME이 달라지던 문제는 동일 선택 helper로 정규화하여 수정했다.

리뷰184에서 재확인했다. 기존 context 없는 호출은 기존 읽기 동작을 유지한다. Windows 런타임의 실제 재사용 연결은187에서 별도 작업 중이다. 빌드·테스트·컴파일·계정 읽기 실행은 하지 않았다.
