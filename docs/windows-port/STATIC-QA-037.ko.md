# 코드 비교 QA 037

CLILocalHTTPServer Windows 분기에 Winsock 소켓 생성/bind/listen/accept/getsockname, recv/send, WSAPoll 및 closesocket을 연결했다. SOCKET 원래 폭을 유지하고 INVALID_SOCKET으로 실패를 판정한다. Ws2_32를 Windows CLI 링크에 추가했다. SO_EXCLUSIVEADDRUSE를 bind 전에 적용하며 POSIX accept 루프는 Windows에서 제외한다.

WSAStartup 성공 후 runtime 객체를 서버와 client Task에서 유지하며 각 소켓 종료 뒤 명시적인 withExtendedLifetime으로 WSACleanup 순서를 보장한다. setsockopt 포인터는 closure 수명 안에서만 사용한다. Windows send 길이는 Int32.max로 나누고 recv buffer 길이도 WinSDK 타입에 맞춘다.

WSAPoll은 경과 시간을 반영해 EINTR 재시도 deadline을 유지하고 fatal error/NVAL/ERR를 accept 루프에서 오류로 전달한다. client read의 poll 실패는 잘못된 요청으로 처리한다. 기존 16 KiB head 제한, 전체 요청 read deadline, Host allowlist, connection gate 및 라우터/인증 코드는 보존했다.

독립 정적 리뷰에서 전처리기 범위, shared helper Windows 분기, async lifetime helper 오용, 포인터 수명 및 poll 오류 무시를 보완했다. git diff --check만 수행했다. Windows ABI·서버·소켓·빌드·테스트는 실행하지 않았다. 기존 raw HTTP 테스트는 Darwin/Glibc 소켓에 의존하므로 Windows 증거가 아니다.

남은 제한: 기존 sendResponse 무제한 blocking 동작 및 handler 장기 실행은 별도 대응이 필요하다. 전체 HTTP/Windows 실행 완료로 판정하지 않는다. 다음은 PathEnvironment POSIX 프로세스 경계와 native UI·공급자·설치·전수 기능 QA다.
