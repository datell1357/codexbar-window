# Windows 네이티브 앱

상태: **CODE_WRITTEN_UNVERIFIED**. IMPL-598은 WinUI 3 초기 화면과 기존 Windows 트레이
런타임 사이의 통신 경로를 작성한 단계다. 복원·빌드·테스트·실행·패키징은 수행하지 않았다.
전체 W03/W04/W07 기능 완료나 배포 가능한 설치 파일을 의미하지 않는다.

## 작성한 화면과 동작

- 트레이의 “CodexBar 열기”가 앱 창을 연다. 이미 실행 중이면 다음 응답의 activation 값으로
  기존 창의 활성화를 요청한다. 창을 닫으면 트레이는 계속 실행한다.
- Overview는 기존 provider presentation의 사용량 행과 검색을 제공한다.
- Usage & Spend는 기존 런타임 비용 요약을 표시한다. 기간 선택·차트·모델/프로젝트/세션
  탐색은 아직 이 화면에 연결되지 않았다.
- Display settings는 PII 숨김, credits/extra 표시, 사용량 표시 방향, reset 시각 표시의
  네 키만 저장한다. 트레이와 같은 설정 저장소·렌더링 경로를 사용한다.
- 연결 실패 시 이전 데이터를 내리고 컨트롤을 잠근다. 저장 응답이 유실된 변경은 자동
  재전송하지 않고, 재연결 후 현재 설정을 다시 받는다.

## 프로세스와 통신 규약

기존 `CodexBarWindows.exe`가 단일 런타임과 credential/config 소유자다.
WinUI 프로세스는 공급자에 직접 접속하거나 두 번째 백엔드를 시작하지 않는다.

1. 트레이가 새 UUID pipe 이름과 자신의 PID를 인자로 지정하여 절대 경로의 UI를 시작한다.
   handle을 상속하지 않으며, 자식 환경은 Windows·사용자 폴더 관련 키만 허용한다.
2. UI가 native named-pipe listener를 만든다. 현재 사용자 SID의 protected DACL,
   첫 인스턴스 전용, 원격 클라이언트 거절, overlapped I/O를 요청한다.
3. 양측은 native API로 얻은 peer PID를 비교한다. Swift 측은 자신이 시작한 프로세스
   handle과 세션·사용자 identity를, UI 측은 기존 백엔드 handle·경로·세션을 사용한다.
   pipe 이름이나 클라이언트가 보낸 문자열만으로 신뢰하지 않는다.
4. JSON 앞에 4바이트 little-endian 길이를 붙인다. 요청은 최대 4 KiB, 응답은 최대
   1 MiB다. 화면 문자열 전체에 96 KiB UTF-8 예산을 적용하고 초과 시 truncation을 표시한다.
   최대 256개 카드·1024개 행 예산과 카드당 64개 상세 행 제한이 있다.
5. 연결 첫 요청은 `hello`다. protocolVersion 1, requestID, backend generation을
   확인한다. 연결당 중복 requestID는 거절하고 4096개 뒤 재연결한다.
6. 허용 메서드는 `hello`, `snapshot`, `refresh`, `setSetting`이다.
   snapshot은 2초 간격으로 요청한다. 설정 쓰기는 네 키의 고정 순서 boolean SHA-256
   revision을 대조한다. 이는 오래된 화면의 저장을 감지하는 낙관적 대조이며, 트레이와
   별도 스레드에서 발생하는 모든 설정 쓰기의 원자적 직렬화를 보장하지 않는다.
7. UI는 15초, Swift I/O는 30초의 대기를 제한한다. Swift는 취소한 overlapped 작업의
   완료를 기다린 뒤 buffer/event를 해제한다. 백엔드 종료를 감지하면 UI도 닫힌다.

전달 데이터는 표시 문자열·상태·네 설정뿐이다. API 키, cookie, OAuth token, raw config,
파일 경로를 위한 필드는 없다. 실제 Win32 PID/ACL/취소·보안 동작은 Windows 검증이 필요하다.

## 배포 위치와 의존성

계획한 파일 배치는 다음과 같다. 앱 폴더 전체를 동일 버전으로 배치해야 한다.

```text
<version-root>/
  CodexBarWindows.exe
  CodexBarCLI.exe
  <Swift runtime and backend resources>
  App/
    CodexBarApp.exe
    CodexBarApp.dll
    CodexBarApp.deps.json
    CodexBarApp.runtimeconfig.json
    <.NET and Windows App SDK publish output, XAML/PRI/resources>
```

프로젝트는 Windows 11 최소 빌드 22000, Windows SDK 26100, .NET 10, WinUI 3,
x64/ARM64를 대상으로 한다. `Microsoft.WindowsAppSDK 2.2.0` 및
`Microsoft.Windows.SDK.BuildTools 10.0.26100.4654`를 지정하고, .NET/App SDK의
self-contained 파일 배포를 요청한다. single-file publish와 trimming은 끈다.
위젯 host의 SDK 파일과 UI의 SDK 파일은 폴더를 분리한다.

**아직 배포 과정에 연결되지 않았다.** 기존 `Windows/Packaging` stager는 root DLL
중심의 import closure와 first-party 서명 목록을 사용하므로 UI publish 폴더를 임의로
추가하면 안 된다. 별도 구현 단위에서 다음을 연결해야 한다.

- Windows에서 의존성을 restore하여 실제 `packages.lock.json`을 생성·검토하고
  이후 locked restore를 적용한다. 현재 lockfile은 없고 전이 의존성을 확인하지 않았다.
- 기존 출력을 덮어쓰지 않는 아키텍처별 publish·receipt·payload manifest 작성.
- App 하위의 managed/native DLL 분류, importer별 DLL 탐색 경로, 전체 publish payload의
  hash/provenance, first-party EXE/DLL 서명, MSIX/portable 배치와 install/update/rollback.
- self-contained WinUI의 runtime/PRI/bootstrap 동작, Windows x64/ARM64, 장시간 창
  재연결·프로세스 종료·패키지 identity 상태의 실제 검증.

## 남은 앱 구현

전체 설정 pane, 계정·인증·provider 편집, 차트/heatmap·기간/모델/프로젝트/세션 탐색,
작업별 action/copy/open/login, 레이아웃 편집, 전역 단축키·창 위치/스크롤 보존,
전체 현지화, 키보드/Narrator/고대비·다중 모니터 QA가 남아 있다.
현재 UI 문구는 영어이며, 트레이의 열기 항목만 기존 en/ko 사전에 연결했다.
`WIN-007/010/012/013/015/026`은 부분 구현 상태로 유지한다.

`TestsWindows/WindowsAppProtocolTests.swift`에는 framing, JSON 키와 필수 필드,
설정 revision/allowlist, Unicode/escape byte 예산의 합성 fixture 11개를 작성했다.
실행하지 않았으며, native pipe·WinUI·실계정 기능의 동작 증거가 아니다.

## API 참고

- [CreateNamedPipeW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createnamedpipew)
- [GetNamedPipeServerProcessId](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeserverprocessid)
- [Windows App SDK self-contained 배포 문서](https://github.com/MicrosoftDocs/windows-dev-docs/blob/docs/hub/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps.md)
- [Windows App SDK 공식 릴리스](https://github.com/microsoft/WindowsAppSDK/releases)
