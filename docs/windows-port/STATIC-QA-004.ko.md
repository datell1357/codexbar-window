# 프로세스 코드 비교 004

WindowsProcess.swift 미연결 후보 수정: pipe 부분 실패 정리, SetHandleInformation 오류, cleanup 이전 오류 저장, attribute list 포인터/수명, 명시 applicationName, wait 소유자 유지와 실패 전달. 두 출력 reader는 PeekNamedPipe 후 읽으며 max+1 보존 및 root 종료 후 1초 drain을 구현했다.

독립 정적 검토는 REQUEST CHANGES: stdin을 handle list에 포함하지 않고 Pipe/FileHandle API가 없으며 SubprocessRunner 연결도 없다. 추가로 발견된 attribute size 조회 실패 검사와 cwd NUL 거부는 검토 후 수정했다. 해당 후속 수정의 독립 재검토는 남아 있다.

미완료: stdin, runner timeout/cancel/출력 초과 오류 연결, reader 오류 시 sibling 정리, onData/EOF/강제 종료 구분, PTY/process tree 직접 호출 대체. 후보 코드만 존재하므로 Windows 프로세스 기능 구현 완료로 세지 않는다. Unicode 환경 정렬의 Win32 일치성도 후속 확인한다. Unicode 환경 블록 32767 제한이라는 검토 의견은 근거 불충분으로 채택하지 않았다.

빌드·컴파일러·테스트·앱·provider·성능·Windows 실행은 실시하지 않았다. 기존 10분 주기 codexbar-windows-qa 활성 상태를 도구로 확인했다. 루틴은 상태 파일부터 재개하고 기능 누락을 구현한 뒤 독립 코드 비교를 반복한다.
