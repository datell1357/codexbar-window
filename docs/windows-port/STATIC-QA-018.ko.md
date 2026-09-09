# 코드 비교 QA 018

Claude 버전 probe Windows 실행에 원본 TTY scalar 환경 기본값을 연결했다. HOME/TERM/COLORTERM/LANG은 없거나 빈 문자열일 때 원본 기본값, CI는 없는 경우에만 0을 넣고 명시한 빈 값은 유지한다. Windows 환경명은 대소문자 비민감 조회 후 해당 키만 정규화하며 PWD는 probe 디렉터리로 설정한다.

PATH 확장·login shell 탐색·ConPTY·cmd/bat wrapper는 이 변경으로 완료되지 않는다. scalar 환경 일치만의 작은 단계다. 코드 비교와 diff 확인만 수행했고 실행 검증은 하지 않았다.

독립 검토에서 명시적 빈 HOME의 원본 TTY 전달 의미 차이를 발견해 caller의 home 인수를 원본과 맞췄다. 따라서 빈 HOME는 빈 값으로 유지된다. 재검토 scoped APPROVE이며 PATH/ConPTY 동등성 승인과 별개다. wrapper 후속 설계는 WRAPPER-CONTRACT-018.ko.md에 기록했다.
