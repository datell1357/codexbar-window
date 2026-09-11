# 예측 경고 네이티브 전달 정적 검토 165–167

판정: 범위 제한 APPROVE. WindowsMain publisher·설정 callback, WindowsTrayHost 최대16개 FIFO·UI 스레드 전달·모달 지연·종료 정리, 공유 balloon·overlay·사운드·개인정보 설정을 원본과 대조했다.

앱 전용 문자열 API 참조와 initializer 인자 순서를 수정했다. 계정 표시 문자열은 공백 제거 후 처리한다. 공유 오버레이의 threshold/predictive 소유권을 구분하여 한 알림을 끌 때 다른 알림의 화면 표시를 닫지 않도록 수정했고 리뷰167에서 재확인했다. 명시적 Equatable을 포함한다.

FIFO 초과 시 가장 오래된 항목을 버리는 Windows 자원 제한이 있으며 원본의 의미상 중복 억제를 대신하지 않는다. Windows 영문 표시만 포함하고 전체 현지화·과거 데이터 예측은 미완료다. 빌드·테스트·컴파일·앱 실행은 하지 않았다. 소스 비교 승인은 실제 동작 보증이 아니다.
