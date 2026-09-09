# 코드 비교 QA 012

GrokCLIFetchStrategy.isAvailable 및 GrokStatusProbe.detectVersion의 실행 파일 조회를 WindowsExecutableResolver로 분기했다. GROK_CLI_PATH와 case-insensitive Windows PATH 계약이 RPC constructor와 일치하도록 연결했다. non-Windows 원본 BinaryLocator 경로는 유지했다. native exe/com만 대상이며 script wrapper 지원을 완료로 세지 않는다.

버전 조회는 탐색 수정만으로 완료되지 않는다. ProviderVersionDetector.swift run은 Foundation Process + semaphore, forceExit에서 POSIX kill(SIGKILL)을 사용하며 resolveRealPath의 PATH_MAX/realpath 및 Claude TTY 경로도 남는다. 코드 비교로 후속 구현 계약을 추적 중이다. 빌드 통과 또는 실제 버전 검출 증거가 아니다.

후속 설계: Windows synchronous version helper는 root timeout 2초(호출값), 종료 후 .25초 drain, zero exit 확인, UTF8 첫 줄과 trim을 보존한다. mergeStandardError=true는 두 stream 문자열을 이어 붙이는 것이 아니라 같은 child pipe handle을 stdout/stderr에 지정해 원본 interleaving 의미를 유지해야 한다. 사용하지 않는 child pipe/handle 중복 close도 피해야 한다. 호출 자체를 실행하거나 테스트하지 않았다.

이 단계는 Grok 가용성 진입점 연결이며 전체 기능 이식은 미완료다. 독립 범위 리뷰 대기 중.

독립 version audit도 sync merged pipe/.25초 drain/zero exit 계약 및 POSIX forceExit 잔존을 확인했다. Claude cache는 run과 별도 TTY 경로이며 30분 fingerprint cache와 pending coalescing/success-only 저장을 유지해야 한다. 다른 provider version 탐색도 별도 미완료다.

최종 scoped resolver routing 리뷰 APPROVE 수신. version 실행 backend와 전체 기능 완료는 별도 미완료로 유지한다.
