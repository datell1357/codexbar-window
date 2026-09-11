# QA200 — Windows web 전략 통합 정적 재검토

상태: 범위 내 정적 승인. Windows의 명시적 web 조회에서 수동 쿠키 또는 분리된 Firefox 프로필 후보를 HTTP 클라이언트로 전달한다. 원본 authority 정책의 attach 판정 이후에만 결과를 반환하고, 명시된 scope가 있는 쿠키만 저장한다. 자동 공급자 선택은 변경하지 않았다.

초기 지적 수정: macOS 전용 deadline 참조를 플랫폼 독립 계산으로 변경했다. Windows 전역 cache clear를 추가하지 않고 정책 거부를 유지한다. 프로필 읽기 실패를 별도 오류로 보존하고, 후보 재시도 중 첫 오류와 취소/시간초과 전달을 유지한다. 쿠키 조회는 chatgpt.com 및 .chatgpt.com만 허용한다.

미완료: DOM 역사 데이터/크레딧 이벤트, Chrome·Edge 수입, 원본과 동일한 cache 정리 정책, 전체 native 설정 및 대시보드 UI. 현재 Windows 경로는 dashboard cache를 읽어 재사용하지 않는다. 동기 SQLite 읽기 자체는 중단할 수 없고 전후 deadline을 확인한다.

HTTP196·수입198·통합200 독립 코드 검토와 git diff --check만 수행했다. 빌드·테스트·컴파일러·앱·실계정 검증을 수행하지 않았다.
