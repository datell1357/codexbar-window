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

- 앱이 실행 중일 때의 process launcher/상속/bootstrap/종료/재연결은 아래 IMPL-541에서 연결했다. 앱이 꺼진 상태의 OS activation 처리는 아직 미구현이다.
- MSIX COM/위젯 6종 선언과 실제 Windows broker 정책, 패키지 identity 연결이 필요하다. host와 전체 빌드 payload의 명시적 배포 입력 및 first-party signing 연결은 아래 IMPL-542에 작성했다.
- 프로젝트는 SDK component self-contained payload/activation manifest 생성 targets를 사용한다. Base 2.0.4의 자체 targets는 Widgets proxy/stub 자동 등록을 제외하므로, 이것만으로 Windows Widgets의 COM activation이 완성됐다고 보지 않는다. MSIX 등록 및 runtime DLL/metadata/라이선스의 최종 배포 구성을 별도로 연결해야 한다.
- Windows SDK/C++/WinRT/App SDK 버전 조합, 실제 빌드·패키지 설치·COM 호출·파이프 인증·timeout·취소·부분 실패·x64/ARM64와 위젯 화면은 모두 미검증이다.

## IMPL-541: 앱 launcher 연결

WindowsUsageRuntime.start는 패키지 설치 경로를 확인하고 host exe/backend DLL이 함께 있는 경우 native launcher를 시작한다. unpackaged 실행과 구성 요소가 빠진 설치는 별도 상태로 남기며 트레이를 종료하지 않는다. WindowsWidgetNativeLauncher는 blocking native 호출을 전용 Dispatch queue로 보내고, child process handle을 독립적으로 복제해 actor 호출 사이에도 같은 process object를 보관한다.

backend DLL에 추가한 launcher는 host image를 연 상태로 유지하고 CreateProcessW로 suspended child를 만든다. 상속 목록은 이미 연결한 전용 pipe client와 NUL 출력 handle 두 개다. 같은 package·설치 image·session을 대조하고 Job Object에 넣은 뒤 runtime이 backend listener를 시작한다. 이어서 child를 재개하고 IMPL-540의 CBL1 frame을 전송한다. 처음부터 PATH나 임의 PID로 host를 찾지 않는다.

provider 인증 환경변수·shell 설정·DLL search override를 그대로 상속하지 않는다. Windows API에서 얻은 SystemRoot/WINDIR/System32 PATH와 명시한 사용자/시스템 폴더 변수만 새 Unicode environment block에 넣는다. bootstrap 데이터는 명령줄과 로그에 쓰지 않는다.

runtime은 backend handshake와 child의 실제 종료 상태를 확인하도록 연결했다. 실패 시 5/15/60/300초 간격으로 새 owner를 만들며, 60초 이상 handshake가 유지된 뒤에만 backoff를 초기화한다. 이전 owner 정리가 실패하면 재시작을 중단하고 그 owner를 보관한다. 앱 shutdown은 시작/재시도 작업을 취소하고 같은 cleanup 결과를 기다린다.

정상 종료 요청은 launch pipe를 닫는 것이다. 실행 중인 host의 종료를 10초 기다리고 이후 해당 child Job만 종료한 뒤 최대 5초 더 기다린다. 실행 전 취소된 suspended child도 해당 Job에서 종료한다. forced 여부와 실제 exit code는 resource cleanup 성공과 별도로 기록하며, 앱 종료 시 강제 종료가 있었으면 OS widget 철회를 확인하지 못했다는 진단을 남긴다. cleanup 실패 시 DLL과 native owner는 유지되어 잘못된 함수 포인터나 process handle 재사용을 피한다.

현재 source에서 연결한 것은 앱이 실행 중일 때의 packaged host 시작·전달·관측·정리·재시도다. 앱이 닫힌 상태의 OS activation, 실제 MSIX COM/위젯 선언과 broker 정책, 배포 inventory/서명 연결 및 사용자-facing 위젯 진단 표면은 남아 있다. 이 launcher 또는 runtime 경로를 실제로 실행하지 않았으며 CODE_WRITTEN_UNVERIFIED다.

## IMPL-542: 빌드 payload와 배포·서명 입력

Build-WidgetHost.ps1은 MSBuild가 남긴 배포 파일을 읽어 schemaVersion 2 host receipt의 payload에 상대 경로·종류·크기·SHA-256을 기록하도록 확장했다. host exe, component runtime DLL, WinMD/manifest/resource 파일과 Widgets·Base·C++/WinRT의 복원된 NuGet 라이선스 3개를 포함한다. root의 host PDB/ILK/LIB/EXP만 빌드 전용 파일로 제외하며, 알 수 없는 확장자·중복 경로·reparse 항목·한도 초과·필수 DLL/WinMD/라이선스 누락은 성공 receipt를 만들지 않는다. 어떤 산출물이 실제로 생성되는지는 Windows 빌드에서 확인해야 한다.

배포 입력 생성기의 WidgetHostEXE와 WidgetHostBuildReceipt를 backend DLL/receipt와 함께 명시하면, 선택한 exe의 디렉터리에서 receipt에 기록된 파일을 같은 상대 경로로 가져오도록 작성했다. receipt에 적힌 outputDirectory나 artifactPath를 복사 경로로 사용하지 않는다. host receipt v1은 exe만 기술하므로 이 경로에서는 받지 않으며, 이후 명시적 Windows 빌드에서 v2 receipt를 생성해야 한다. backend receipt v1 계약은 유지한다. 기존 RuntimeFiles·ResourceDirectories·LicenseDirectory는 계속 필요하며 widget payload에 이미 있는 파일을 중복 입력하지 않는다.

공유 payload 계약은 빌드 기록·입력 생성·조립에서 같은 경로/종류/필수 파일 규칙을 사용한다. 조립기는 전체 payload의 포함 여부를 먼저 대조하고, 복사 후 열어 보관한 파일의 크기·hash가 기록과 다르면 완료 inventory를 쓰지 않는다. 실패한 부분 출력은 보존한다. CodexBarWidgetHost.exe는 root first-party application으로 서명 대상에 포함되며 backend 없이 포함할 수 없다. 서명 후 inventory는 변경된 실제 파일을 기준으로 기존 서명 경로에서 다시 작성한다.

LOCAL_BUILD_NOT_ATTESTED와 COPIED_BYTES_MATCH_LOCAL_BUILD_RECORD는 로컬 빌드 기록 및 복사 byte 일치 상태다. MSIX 등록·OS activation·서명 성공·실행 성공을 뜻하지 않는다. 현재 모든 변경은 CODE_WRITTEN_UNVERIFIED이며 build/restore/PowerShell/서명/설치/검증을 실행하지 않았다. 앱이 닫힌 상태의 OS activation, MSIX COM/6종 widget 선언과 proxy/stub 등록, 실제 broker 정책 및 사용자-facing 위젯 진단은 남아 있다.

## IMPL-543: 앱 시작 소유권

위젯이 앱을 깨우는 경로의 선행 조건으로 Windows 앱 진입점에 사용자/Windows-session별 instance lease를 연결했다. OS-known local app data의 빈 lock file을 독점으로 열고, 성공한 경우에만 runtime을 생성한다. 세션 종료 cleanup 제한 시간이 지나도 process exit까지 소유권을 보관한다. 파일 존재나 충돌 종료 코드가 실제 앱/host 인증 또는 bootstrap 연결 성공을 뜻하지는 않는다.

세부 계약은 [앱 lifecycle 문서](../../docs/windows-port/APPLICATION-LIFECYCLE.ko.md)에 기록했다. 현재 OS-started host의 rendezvous/admission과 MSIX COM 등록은 아직 구현되지 않았다. 같은 package/image/session 및 peer 검증을 유지한 접속 경로가 추가로 필요하다. CODE_WRITTEN_UNVERIFIED이며 이번 작업에서 앱/파일/잠금/위젯을 실행하지 않았다.
