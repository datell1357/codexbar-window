# Windows 앱 시작 소유권 — IMPL-543

상태: CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 이 문서는 작성한 동작 계약이다. Windows 프로세스·파일·ACL·잠금·종료·위젯 실행을 검증한 보고서가 아니다.

## 시작 순서

CodexBarWindowsMain은 WindowsApplicationInstance.acquire를 먼저 호출한다. 성공한 경우에만 WindowsTrayApplication과 usage/session/remote-session runtime을 만들고 기존 트레이 실행 흐름에 들어간다. 앱을 반복 실행하거나 나중에 위젯 OS activation이 앱을 깨워도, 같은 사용자 데이터 폴더와 Windows session에서 추가 runtime이 함께 시작되지 않도록 하는 기반이다. CLI 실행 파일에는 이 제한을 적용하지 않는다.

위치는 SHGetKnownFolderPath(FOLDERID_LocalAppData)에서 얻은 CodexBar/Runtime/instance-session-<Windows-session-ID>.lock이다. 실행 폴더, PATH, APPDATA/LOCALAPPDATA 환경변수, 임의 PID 파일에서 시작 소유권 위치를 고르지 않는다. 일반 설정 저장소의 기존 경로 선택이나 migration 정책은 이번 변경에서 바꾸지 않았다. packaged/unpackaged 실행 간 known-folder 가상화 및 사용자 데이터 위치의 일치 여부는 Windows 검증 항목이다.

파일은 OPEN_ALWAYS로 열고 읽기/쓰기 접근 및 share mode 0을 유지한다. 기존 내용은 쓰거나 truncate하지 않으며 비어 있지 않은 파일·여러 hard link·directory/reparse leaf는 거절한다. 파일 존재 자체는 실행 중이라는 뜻이 아니다. 프로세스가 종료되면 OS가 핸들을 닫고, 남아 있는 빈 파일은 다음 시작에서 다시 열 수 있다. 잠금 파일을 자동 삭제하지 않는다.

새 CodexBar/Runtime 디렉터리와 파일은 현재 process token의 user SID에 대한 보호된 DACL, non-inheritable handle로 생성한다. 이미 존재하는 디렉터리 ACL은 덮어쓰지 않는다. OS-known root부터 각 생성/접근 component를 directory handle로 열고 reparse 여부를 대조한 뒤 다음 component로 진행한다. delete sharing 없이 디렉터리를 보관해 보유 중 rename/replacement를 제한한다. known folder보다 위의 경로와 외부 계정/권한 정책 전체를 격리했다는 뜻은 아니다.

## 실패와 종료

공유/잠금 충돌은 별도 occupied 결과와 종료 코드 ERROR_ALREADY_EXISTS(183)로 남기고 새 runtime을 만들지 않는다. 이것만으로 상대가 정상 CodexBar 프로세스인지, 위젯 연결을 받을 준비가 되었는지 또는 요청을 전달받았는지는 알 수 없다. 파일 접근·구조 오류는 startup 실패로 보고하며 잠금을 우회해 시작하지 않는다. 진단 문자열에는 경로·SID·계정·자격 증명을 넣지 않는다.

잠금 획득 도중 실패하면 확보한 파일·directory handle만 닫고 만든 디렉터리/파일은 보존한다. runtime 소유권을 확보한 뒤에는 기존 정상/세션 종료 cleanup 경로를 수행하고, application 범위를 정리한 후 ExitProcess까지 instance lease를 보관한다. Windows session-ending cleanup의 제한 시간이 지나더라도 아직 살아 있는 process가 잠금을 먼저 풀지는 않도록 작성했다. 실제 강제 종료·예외·백신/ACL/파일시스템 동작은 미검증이다.

## 위젯 cold activation의 다음 연결

현재 host의 --private-bootstrap 진입은 앱이 생성한 child와 상속된 pipe만 처리한다. OS CreateInstance가 직접 시작하는 host의 bootstrap rendezvous, 앱 시작/기존 앱 접속, 실제 package/image/session 및 peer 인증, host admission/동시 시작 조정, 취소·재연결은 후속 필수 구현이다. occupied 종료 코드를 IPC 성공으로 처리해서는 안 된다. 기존 앱에 사용자 실행 요청을 전달하거나 트레이를 foreground로 여는 기능도 이번 잠금의 역할에는 포함되지 않는다.

MSIX의 COM server/6종 widget/proxy-stub 선언·실제 caller policy·설치/등록 및 Windows 실행 검증도 남아 있다. Microsoft는 IWidgetProvider 구현에 CreateInstance를 권장하며 시스템은 해당 COM 클래스를 활성화한다. 현재 COM 인터페이스를 유지하고 실제 OS-started host가 같은 runtime에 접속하도록 연결할 계획이다. [위젯 등록 규약](https://learn.microsoft.com/en-us/windows/apps/develop/widgets/widget-provider-manifest), [ActivateApplication 규약](https://learn.microsoft.com/en-us/windows/apps/develop/widgets/widget-provider-activateapplication-protocol).

사용자별 single-instance 소유권에 profile의 locked file을 사용할 수 있다는 Windows 문서와 process exit의 handle 정리 순서를 근거로 코드를 작성했다. 해당 API 설명은 이 구현의 실행 증거가 아니다. [CreateMutexExW remarks](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-createmutexexw), [ExitProcess](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-exitprocess).
