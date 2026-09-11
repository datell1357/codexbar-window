# 이력 설정 UI 정적 검토 173–174

메뉴 명령 ID, Automatic/4/5/7 선택지, 기존 설정 키 저장, callback 연결은 정적 검토에서 승인했다. Windows 전역 트레이의 Codex 기록 토글은 원본 공급자 설정의 네이티브 대응 표면이다.

원본 설정 observation은 refreshForSettingsChange를 예약한다. 최초 Windows callback은 상태만 갱신하여 다음 예약 조회까지 반영이 지연되는 차이가 발견됐다. 런타임172에서 별도 coalesced refresh를 연결하고 재검토한다. 원본이 설정 callback에서 예측 경고를 직접 즉시 평가한다는 최초 해석은 철회했다.

빌드·테스트·실계정·앱 실행은 하지 않았다. 설정 UI 범위 승인과 전체 기능 완료는 구분한다.
