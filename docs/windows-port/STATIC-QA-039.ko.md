# 코드 비교 QA 039 — REQUEST CHANGES, 진행 중

TTYCommandRunner POSIX 구현을 Windows에서 제외하고 Windows API 대응 파일을 작성했으나 실제 ConPTY는 미구현이다. 현재 run은 명시적으로 실패하고 종료 추적은 비활성이다. 이 변경을 TTY 기능 구현 완료로 처리하거나 출판하지 않는다.

독립 리뷰의 필수 미해결 항목: ConPTY 입출력/시간 제한/취소/종료 추적, Codex·Claude 세션의 POSIX 경계, 원본 TTY 테스트의 POSIX 전용 helper 의존, cmd shim sourcePath를 직접 실행하는 소비자 계약. 사용자 지정 환경에 ambient PATH를 주입하는 문제도 수정 중이다.

conpty_design_040이 기존 WindowsProcess와 원본 TTY 상태 머신을 대조해 실제 backend 구현 설계를 작성 중이다. tty_windows_039는 환경 및 native-only which 보정을 담당한다. 공유 변경은 아직 커밋하지 않았다. 빌드·테스트·실제 실행을 수행하지 않았다.

040 후속: 실제 WindowsConPTYProcess backend 구현을 시작했다. 기존 WindowsProcess의 background pipe 플래그를 재사용하지 않고 pseudoconsole attribute·Job·reader/writer 수명을 별도로 처리한다. 원본 TTY 상태 머신 계약은 별도 독립 분석 중이다. HPCON attribute의 포인터 전달 방식은 설계에서 재검토가 필요해 구현 담당자에게 교차 검토를 요청했다. backend나 runner 완료·검증·출판으로 처리하지 않는다.

후속 정적 대조: backend 초안에서 writer 성공 완료 표시 누락, 호출자 취소 확인 누락, HPCON attribute 주소 전달, reader 종료 전 handle 닫기, cwd Optional 매핑 및 mutable command 버퍼 오류 후보를 발견해 수정 요청했다. tty_runner_041은 원본 일반/Codex 상태 머신과 retained Job 종료 registry를 구현 중이다. 현재 초안은 출판 가능한 상태가 아니며 QA 통과로 간주하지 않는다.

041 초안 정적 리뷰: shutdown registry의 endLaunch 정의 누락·launch 예약 수 누락·Swift 6 공유 가변 상태, DWORD→Int32 변환 trap 가능성, 저장 없이 성공을 반환하는 기존 PID 등록, idle 완료 구분 누락, stopOnURL=false 시 callback 누락, read 실패를 정상 stop으로 처리하는 문제를 발견했다. 구현 담당자가 전체 Codex 상태 머신과 함께 수정 중이다. backend worker 종료 대기 및 handle 수명 경합도 여전히 필수 수정 항목이다. 커밋·푸시하지 않았다.

재검토 정정: TTYCommandRunnerTests는 Package.swift에서 macOS 전용 타깃에 포함된다. 따라서 기존 Windows 테스트 타깃 컴파일 blocker 주장은 철회하고 Windows 테스트 대응 공백으로 분류한다. 현재 backend는 worker wait timeout 결과 무시 후 handle 해제, ClosePseudoConsole 전 reader 중단, pending writer finished 표시 누락이 남아 수정 중이다. runner는 빈 명령 Enter·Codex status 전송·deadline 종료 분류와 원본 상태 머신을 계속 보완한다.

042: 반복된 부분 수정으로 worker timeout 뒤 live pipe 해제 문제가 해소되지 않아 backend 담당을 conpty_lifetime_042로 전환했다. cleanup 전용 소유 객체가 worker 종료까지 native 자원을 유지하도록 수명 구조를 재정리한다. 이전 backend 담당자는 수정 소유권을 반납했다. runner 담당은 원본 루프 직접 대조와 launch fence 대기를 계속 구현하며 아직 출판하지 않는다.

042 재검토: background cleanup 초안도 reader를 console 종료 전에 취소하고 deinit에서 self를 강하게 탈출시키는 문제가 남았다. worker 초기화 한쪽 실패 시 다른 worker 준비 전에 정리하는 경합, native 상태 조회와 handle 해제 경합, write 호출자 취소 공백도 수정 요청했다. 별도 자원 소유 상태로 재구성 후 독립 재검토한다.

후속: HOME 보존 회귀는 수정됐다. backend는 deinit 탈출·native handle 잠금·write 취소 API를 마무리 중이며, runner는 합의된 write(data, deadline, cancellationCheck) 인터페이스를 기준으로 일반/Codex 루프를 분리 구현한다. API가 아직 파일에 없다는 이유로 독립 상태 머신 작업을 대기하지 않도록 조정했다. 현재 전체 정적 QA는 미통과다.

백엔드 수명 경계는 독립 정적 재검토에서 CLEAR를 받았다(실행 검증 아님). runner 담당은 tty_exact_043으로 갱신했다. 새 bounded write 호출 중 try?가 취소/오류를 삼키고 전역 deadline 대신 별도 시간을 쓰는 문제, passive settle 및 EOF/drain 분류가 남아 통합 QA는 BLOCK이다. deadline과 사용자 취소를 구분하는 backend 오류 계약도 보완 중이다.

044 후속 분석: PID 기반 외부 세션 등록은 별도 owned Job/process 전환 대상으로 추적한다. session_port_map_044가 지속 세션 호출 경로를 분석 중이다. runner 초안의 overflow 플래그가 defer보다 뒤에 선언된 문제를 추가 발견해 수정 요청했으며, 모든 write 경로의 공개 오류 매핑과 정확한 drain 계약을 계속 대조한다.

043 바이트 scanner 재검토: 새 chunk 전체 대신 마지막 64/128바이트만 검사해 chunk 앞쪽 marker를 놓치며 tail 자체는 계속 증가하는 결함을 발견했다. 이전 tail+새 chunk 전체를 먼저 검사하고 최대 marker 길이-1만 보존하도록 수정 요청했다. generic URL 바이트 검사와 Codex Enter 재시도도 남아 있다. SESSION-PORT-MAP-044 문서는 두 위치에 저장 완료됐다.

## 단계 종료 — 범위를 한정한 정적 CLEAR

conpty_design_040은 ConPTY 자원 수명, tty_contract_040은 최신 generic/Codex 상태 머신과 bounded write 통합을 독립 정적 검토해 CLEAR로 판정했다. 자연 종료 EOF, cursor/URL trailing 출력, deadline 및 idle 구분, bounded capture와 overflow cleanup을 대조했다. git diff --check만 수행했으며 컴파일·빌드·테스트·Windows 실행·성능 검증은 하지 않았다.

전체 기능 완료는 아니다. deadline 인접 종료 관찰 시각의 원본 대비 차이, 외부 지속 세션의 PID-only 등록 거부, Windows SDK ABI/실행 미검증이 남는다. 다음 단계는 SESSION-PORT-MAP-044에 따른 owned tracked lease와 공급자 지속 세션 연결이다. 원본 POSIX runner는 Windows 조건에서 제외하고 원본 플랫폼에서는 유지했다.
