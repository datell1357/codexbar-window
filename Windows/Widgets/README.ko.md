# Windows widget host 구현

현재 상태는 CODE_WRITTEN_UNVERIFIED다. 이 문서의 명령은 이번 macOS 작업에서 실행하지 않았다.

`Native/Host/CodexBarWidgetHost.vcxproj`는 기존 WidgetProvider·WidgetPublisher·host session runner를 사용하는 C++/WinRT Windows 실행 파일 프로젝트다. x64/ARM64, v143, Windows 11 SDK를 대상으로 한다. backend ABI DLL 프로젝트와 분리되어 있으며 Swift 또는 Mac framework를 host의 빌드 입력으로 사용하지 않는다. 제품 전체의 Windows-only graph 정리가 완료됐다는 의미는 아니다.

## 의존성과 빌드 입력

`Native/Host/packages.config`에 C++/WinRT 2.0.250303.1, Windows App SDK Widgets 2.0.5, Base 2.0.4 및 Base가 요구하는 SDK BuildTools/MSIX 도구 버전을 고정했다. Windows App SDK 전체 meta package를 사용하는 대신 위젯 component와 그 의존성을 직접 기재한다. NuGet 패키지의 실제 props/targets/nuspec 텍스트를 읽어 import 경로와 의존성 목록을 작성했다. 패키지 설치·restore·MSBuild는 실행하지 않았다.

참고: [Microsoft 위젯 공급자 구현 문서](https://learn.microsoft.com/en-us/windows/apps/develop/widgets/implement-widget-provider-win32), [Widgets 패키지](https://www.nuget.org/packages/Microsoft.WindowsAppSDK.Widgets/2.0.5), [Base 패키지](https://www.nuget.org/packages/Microsoft.WindowsAppSDK.Base/2.0.4), [C++/WinRT 패키지](https://www.nuget.org/packages/Microsoft.Windows.CppWinRT/2.0.250303.1).

Windows에서 빌드 검증을 허용받은 뒤 사용할 명령 형식:

```powershell
.\Windows\Widgets\Build-WidgetHost.ps1 `
  -MSBuildPath <absolute-MSBuild.exe> `
  -NuGetPath <absolute-NuGet.exe> `
  -WindowsSdkVersion <installed-10.0.build.revision> `
  -CallerPolicyPath <reviewed-caller-policy.json> `
  -Architecture x64 -Configuration Release
```

CallerPolicyPath는 schemaVersion 1, packageFamily 문자열, executableNames 배열의 JSON이다. 대상 Windows 환경에서 확인한 Widgets broker의 정확한 package family와 1~8개 실행 파일 이름을 입력한다. 이 값은 생성한 C++ header에 들어가 실행 파일에 고정되며 argv·bootstrap JSON에서 덮어쓰지 않는다. 이름만 같은 다른 package의 프로세스는 기존 caller 인증기가 수용하지 않는다. 아직 검증된 실제 Windows 버전별 정책 파일은 없다.

빌드 스크립트는 매번 Native/out/host-runs 아래 새 디렉터리를 만들고, NuGet restore와 MSBuild Build를 순차 호출하도록 작성했다. 기존 산출물을 정리하거나 재사용하지 않는다. 실패한 파일과 패키지도 보존한다. 완료 시 exe 크기·SHA-256, SDK/tool 정보, packages.config 및 caller policy hash를 local receipt에 남긴다. 이 receipt는 서명된 provenance 또는 런타임 검증 증거가 아니다.

## 전용 시작 채널

host는 `--private-bootstrap` 모드만 처리한다. launcher는 같은 MSIX package·Windows session에서 sibling CodexBarWindows.exe로 실행되어야 하며, STARTUPINFOEX의 명시적 handle list로 이미 연결된 overlapped byte-mode pipe의 client handle을 stdin에 상속해야 한다. 다른 argv나 현재 개발 폴더에서의 단독 실행은 위젯 공급자 시작 계약이 아니다.

host는 파이프의 서버 PID를 조회해 살아 있는 process handle을 보관하고 package full name·Windows session·설치 image 경로를 대조한 뒤 읽는다. 시작 packet은 CBL1 4바이트, little-endian UInt32 JSON 길이, little-endian UInt64 transferred event handle, 최대 4096바이트 JSON이다. 전체 시작 읽기의 제한 시간은 30초다. packet을 보내는 쪽은 connection.prepareLaunchDelivery를 사용하며 기존 JSON-only prepareBootstrap과 둘 중 하나만 호출할 수 있다.

이벤트 소유권은 인증된 channel의 transfer header에서 얻고 기존 JSON decoder가 같은 handle 값을 다시 요구한다. 시작 packet 이후 EOF는 취소 요청이다. 추가 데이터는 protocol 오류로 취소하며 backend 종료도 취소로 전달한다. 취소 시 pending overlapped read를 drain하고 monitor를 join한 뒤 handle을 해제한다. host 진입점은 기존 COM 보안 초기화·caller 인증·등록·worker·receiver·철회·정리 결과를 실행 종료 상태에 연결한다. 계정 데이터·시작 payload·경로는 진입점 로그에 출력하지 않는다.

## 아직 필요한 연결

- 앱의 실제 process launcher, 제한된 handle 상속 목록, bootstrap 전달, stopReceiver에서 host 종료를 기다리는 경로, 재연결 및 앱이 꺼진 상태의 OS activation 처리는 아직 미구현이다.
- MSIX COM/위젯 6종 선언과 실제 Windows broker 정책, 패키지 identity, first-party signing/distribution inventory 연결이 필요하다. 현재 이 exe를 기존 배포 조립기로 자동 수집하지 않는다.
- 프로젝트는 SDK component self-contained payload/activation manifest 생성 targets를 사용한다. Base 2.0.4의 자체 targets는 Widgets proxy/stub 자동 등록을 제외하므로, 이것만으로 Windows Widgets의 COM activation이 완성됐다고 보지 않는다. MSIX 등록 및 runtime DLL/metadata/라이선스의 최종 배포 구성을 별도로 연결해야 한다.
- Windows SDK/C++/WinRT/App SDK 버전 조합, 실제 빌드·패키지 설치·COM 호출·파이프 인증·timeout·취소·부분 실패·x64/ARM64와 위젯 화면은 모두 미검증이다.
