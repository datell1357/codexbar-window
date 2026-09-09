# 코드 비교 QA 006

WindowsProcess.capture의 async let을 throwing task group으로 교체했다. 한 reader 오류 시 shared stop을 먼저 세팅해 sibling이 root 종료를 무기한 기다리지 않도록 했다. 취소도 shared stop으로 전달하며 프로세스 종료 책임은 호출부에 남긴다. maxBytes는 정확한 prefix budget으로 변경: 원본 runner처럼 explicit limit에만 +1을 적용하도록 연결 계약을 정리했다.

stdin 기본값에서 GetStdHandle NULL이면 GUI/no-console 정상 조건으로 보고 NUL read handle을 열어 복제한다. 임시 NUL handle은 defer로 닫고 상속 복제본은 기존 launch 경로에서 닫는다. INVALID_HANDLE_VALUE는 오류로 유지한다. 실제 콘솔 stdin 및 explicit Pipe/FileHandle 경로는 보존한다.

독립 launch 리뷰는 same-scope UpdateProcThreadAttribute/CreateProcessW 수명과 caller handle 비소유를 확인했다. 처음 지적된 GUI NULL 문제는 후속 수정 후 재검토 요청했다. WinSDK/ucrt imported type 및 빌드 적합성은 코드만으로 확정하지 않았다. capture 후속 독립 리뷰도 요청했다.

SubprocessRunner는 아직 미연결이며 프로세스 기능 완료로 세지 않는다. 전체 이식 완료도 아니다. 빌드/테스트/컴파일러/실행/실계정/성능 검증은 하지 않았다.

후속 독립 검토 결과: GUI NULL→NUL 분기는 소유권/수명상 확정 결함을 발견하지 않았다. capture 변경도 shared stop과 정확한 prefix budget이 정적으로 일치한다고 검토했다. 이 평가는 Windows 빌드/실행 증거가 아니며 미연결 상태는 유지한다.
