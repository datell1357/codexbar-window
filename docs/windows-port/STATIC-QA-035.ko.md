# 코드 비교 QA 035

CredentialFileWriter의 Windows 분기를 추가했다. 현재 프로세스 token 사용자 SID에만 권한을 부여하는 protected DACL을 CREATE_NEW 임시 파일 생성 시 전달한다. credential bytes 전에 해당 파일 핸들의 볼륨 FILE_PERSISTENT_ACLS를 확인하고 실패하거나 미지원이면 빈 임시 파일을 정리하고 중단한다. READ_CONTROL/WRITE_DAC 접근으로 DACL 적용 실패도 쓰기 전에 중단한다.

부분 WriteFile 반복, FlushFileBuffers 및 CloseHandle 이후 beforePublish 콜백을 실행한다. 게시 전에 protected DACL을 다시 적용하고 최종 대상의 디렉터리/reparse 속성은 거부한다. MoveFileExW 동일 디렉터리 replace/write-through로 게시하며 생성 성공한 임시 파일만 오류 시 정리한다. 기존 repairPermissions의 best-effort 계약은 유지한다. POSIX 구현은 비Windows 분기로 보존했다.

독립 코드 리뷰에서 발견한 타입 불일치, 포인터 수명 이탈, 필수 ACL 볼륨 검사 누락, WRITE_DAC 누락, 오류 코드 손실, 게시 전 reparse 검사 누락을 수정했다. SetSecurityInfo/SetEntriesInAcl의 반환 상태를 직접 보존하고 WriteFile 실제 실패와 0바이트 진행을 구분한다. git diff --check만 수행했으며 빌드·컴파일·테스트·실제 자격증명/파일 ACL 검증은 하지 않았다.

한계: 신뢰할 수 있는 부모 디렉터리를 전제로 한다. 부모 junction 및 적대적 디렉터리 교체 경쟁은 해결했다고 주장하지 않는다. WinSDK ABI, ACL/atomic replace 및 공유 파일 잠금의 실제 동작은 미검증이다. Windows 전용 ACL 테스트 소스 확대도 남아 있으며 기존 POSIX permission 테스트가 Windows 검증을 대신하지 않는다. 전체 Windows 기능 완료가 아니다.

다음: dashboard atomic output, Winsock HTTP server, PathEnvironment 프로세스 경계 이식과 native UI/공급자별 인증 및 전수 기능 QA.
