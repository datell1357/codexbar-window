# Windows 기반 코드 비교 001

상태: 부분 구현, 전체 QA 전. 원본 HEAD 928166f899471bbdcb72210641cdec91324d0154와 diff 비교.

구현: Package.swift Windows SQLite 연결 및 macOS UI dependency 격리, QuickJS watchdog Windows clock, QuickJS 사용자 plugin config 유지, LOCALAPPDATA 데이터 경로 및 override 보존, GetModuleFileNameW 리소스 탐색, Credential Manager Codable cache 및 Advapi32 연결.

정적 리뷰 수정: argv[0] 대신 OS API 사용, 32768 UTF16 buffer cap 실제 재시도, XDG precedence 보존, QPC 실패 timeout 무력화 경로 제거, CredentialW/SDK blob 상한/서비스 prefix 열거/문자열 보간/NUL validation/일시 오류 분류. 작성 중 snapshot에 대한 지적도 있어 최종 코드에서 다시 확인했다.

남음: SweetCookieKit 의존성/unguarded import, SQLite 배포, Job Object/ConPTY/socket, provider auth/browser, native UI/runtime/widgets/sync/운영, 전체 기능 ledger. 캐시 구현은 전체 인증 구현이 아니다. OS blob 상한보다 큰 원본 payload 처리는 추가 설계가 필요하다.

사용자 검증 제한: 실제 검증 금지, 코드 비교만. 하위 작업에서 swift package dump-package 2회(실패), swiftc -parse 1회가 실행돼 즉시 중단 지시했다. 이 호출들은 요청 범위 밖이며 완료/실행 검증 근거로 사용하지 않는다. 이후 컴파일러/manifest 평가도 명시 금지. 앱·실계정·키체인·빌드/테스트 실행은 하지 않았다.

재개: 구현 루틴 codexbar-windows-qa가 10분마다 이어간다. 전체 후보 구현 후 독립 전체 비교 QA로 전환하고 지적이 있으면 구현으로 되돌아간다. 실제 Windows 검증은 사용자 지시대로 NOT_RUN을 유지한다.
