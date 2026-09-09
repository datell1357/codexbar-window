# 코드 비교 002

Windows manifest에서 SweetCookieKit package와 target product를 함께 제외했다. 비-Windows 의존성은 유지하고 기존 macOS 브라우저 구현에만 필요한 import를 os(macOS)로 감쌌다. ProviderDefaults/Claude cookieClient 등 대표 소비자의 기존 조건부 경로를 읽어 대조했다. 새 브라우저 구현이나 성공 stub을 추가하지 않았다. 따라서 의존성 경계 정리는 자동 쿠키 인증 구현 완료가 아니다.

Credential Manager enumeration은 CRED_TYPE_GENERIC 항목만 반환하도록 보강했다. 서비스 prefix 및 category filter와 SDK buffer bound는 유지했다.

다음 프로세스 구현은 PROCESS-CONTRACT-002.ko.md에 정리했다. suspended launch/Job assignment/상속 handle 제한/ConPTY/취소 보호를 보존하며 Process.terminate 단독 대체는 채택하지 않는다.

이번 실행은 파일 읽기·편집·git diff만 수행했다. 컴파일러/manifest/빌드/테스트/계정 실행 없음. 전체 이식 및 독립 전체 QA는 미완료이며 루틴 계속.
