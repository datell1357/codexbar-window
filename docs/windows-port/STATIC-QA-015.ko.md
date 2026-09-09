# 코드 비교 QA 015

Claude 버전 경로의 원본 TTY 반환 계약을 재대조했다. 전체 출력 대신 첫 줄만 받는 차이, stderr 누락, ANSI 제거 전 trim 순서, strict UTF8와 lossy UTF8 차이를 보완했다. WindowsProcess.captureVersionSynchronously에 opt-in fullOutput을 추가해 1MiB 한도 초과 시 종료/실패, 전체 EOF와 성공 exit 확인, strict UTF8 원문 반환을 수행하고 Claude 호출에서 stderr 병합 및 ANSI 제거 후 trim을 연결했다. 일반 버전 호출의 기존 첫줄 반환은 유지한다.

WindowsFileIdentity.swift는 CreateFileW/GetFileInformationByHandle로 volume+fileIndex,size,mtime을 같은 handle에서 수집한다. Claude fingerprint의 가짜 inode=0을 대체했고 DEBUG attributesHook 경로는 기존 주입값을 사용한다. Windows Claude 실행 cwd/PWD는 기존 preparedProbeWorkingDirectoryURL에 연결했다.

독립 정적 검토 대기. Windows ConPTY와 pipe의 터미널 동작 차이, CLI 환경 보강, cmd/bat wrapper, 기타 provider TTY 호출은 미완료이며 전체 parity로 승인하지 않는다. 빌드·컴파일러·테스트·앱·실계정·파일 identity 실제 호출·성능·Windows 실행은 하지 않았다.

독립 검토: 전체 출력/EOF/strict UTF8 및 handle 기반 fingerprint에 확정 결함 없음. cmd/bat와 환경 보강은 필수 미해결, GUI console 표시 정책은 후속 검토. overflow가 nil로 반환되는 것은 기존 private String? 버전 탐색의 실패 계약과 동일하며 typed error 외부 노출을 추가하지 않는다. 전체 이식 완료가 아니다.
