# 코드 비교 QA 017

WindowsProcess의 두 CreateProcessW 경로에 같은 CREATE_NO_WINDOW 포함 플래그를 사용한다. 현재 이 backend의 호출자는 pipe 기반 RPC/버전/hook/subprocess이며 상호작용 PTY는 별도 미구현이다. STARTF_USESTDHANDLES와 suspended/job 연결은 유지한다.

ProviderVersionDetector.codexVersion/geminiVersion의 Windows 실행 파일 탐색을 기존 WindowsExecutableResolver로 연결했다. CODEX_CLI_PATH/GEMINI_CLI_PATH 대소문자 비민감 조회, native exe/com 및 PATH를 사용한다. 원본 non-Windows 분기와 버전 옵션 순서는 보존한다. cmd/bat, install-directory 탐색 및 로그인 환경 보강은 완료되지 않았다.

정적 diff 비교만 진행했다. 빌드·테스트·실행·컴파일러 검증은 금지 조건에 따라 하지 않았다. 전체 Core에 POSIX 의존 호출이 남아 있고 Windows 빌드 가능/전체 기능 완료를 주장하지 않는다. 독립 검토 결과는 후속 기록한다.

console_017_review 최종 scoped APPROVE: 플래그 충돌/handle 계약 및 버전 탐색 변경에 확정 결함 없음. 기존 리뷰의 CRED_PERSIST_LOCAL_MACHINE이 전체 사용자에게 노출된다는 추측은 사용자별 Credential Manager 저장 범위와 혼동한 것으로 판정하여 결함으로 채택하지 않았다. 실제 자격 증명 접근은 하지 않았다.
