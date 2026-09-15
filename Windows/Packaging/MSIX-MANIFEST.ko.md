# Windows MSIX manifest 입력과 생성 — IMPL-545

상태: CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. New-CodexBarMSIXManifest.ps1과 입력 예제를 작성했으며 PowerShell, 빌드, manifest 평가, MakeAppx/MakePri, 서명, 설치, OS 등록 및 앱/위젯 실행은 하지 않았다.

## 입력과 출력

생성기는 DistributionDirectory, ConfigurationPath, OutputManifest를 받는다. DistributionDirectory는 기존 조립/서명 경로가 만든 distribution-inventory.json과 실제 파일이 있는 폴더다. inventory schemaVersion 1의 STAGED_UNVERIFIED 또는 SIGNED_RUNTIME_UNVERIFIED 및 x64/arm64를 받으며, 이것이 배포 승인이나 실행 검증 통과를 뜻하지는 않는다. 기존 first-party 파일 계약도 적용한다.

필수 실행 파일은 CodexBarWindows.exe, CodexBarCLI.exe, CodexBarWidgetHost.exe, CodexBarWidgetBackend.dll이다. Widgets DLL/WinMD와 Widgets/Base/C++/WinRT 라이선스 3개, resources/windows-widget-host/Microsoft.WindowsAppSDK.Widgets.appxfragment도 요구한다. 참조한 파일은 inventory의 종류·크기·SHA-256과 대조하고 manifest 작성이 끝날 때까지 읽기 핸들을 보관한다. 모든 payload DLL의 전체 실행/동적 의존성을 새로 증명하는 검사는 아니다.

출력 파일명은 AppxManifest.xml이며 기존 파일이 있으면 CreateNew에서 중단한다. ShouldProcess/WhatIf를 지원하지만 현재 작업에서 호출하지 않았다. 성공 시 MANIFEST_WRITTEN_UNVERIFIED와 RuntimeValidation=NOT_RUN을 반환하도록 작성했다. 이 단계는 새 XML을 작성하며 MSIX 압축·서명·등록·설치를 실행하지 않는다. 원본 configuration과 예제는 개발 입력이므로 별도 위치에서 관리한다.

## configuration schemaVersion 1

[입력 예제](MSIX-configuration.example.json)는 필드 구조와 6종 위젯을 보여준다. 발행자·버전·OS 선언값·이미지 경로·문구를 실제 패키지에 맞게 제공해야 한다. 예제의 REPLACE_WITH 항목과 이미지 파일들은 준비된 배포 산출물이 아니다.

| 필드 | 의미 |
| --- | --- |
| identity.name | 패키지 이름, 3~50자의 영문/숫자/점/하이픈 |
| identity.publisher | 서명 인증서 subject와 맞아야 하는 X.500 이름. 생성기는 이름 파싱만 하며 인증서를 발급하거나 서명하지 않음 |
| identity.version | 4부분 Windows package 버전, 각 부분 0~65535 |
| minimumWindowsVersion | 이 host 프로젝트의 Windows 11 기준인 10.0.22000.0 이상 |
| maximumTestedWindowsVersion | minimum 이상인 MaxVersionTested 선언값. 이 작업에서 수행한 Windows QA 근거가 아님 |
| displayName, description, publisherDisplayName | 앱/발행자 표시 문자열 또는 준비된 ms-resource 참조 |
| languages | 선언할 리소스 언어, 1~16개 중복 없는 태그 |
| visualAssets | storeLogo, square150Logo, square44Logo의 package-relative PNG 경로 |
| providerIcon | WidgetAssets 아래 provider PNG |
| widgets | 아래 ID의 정확히 6개 구성. id/displayName/description/icon/screenshot/altText 필수 |

WidgetAssets 폴더는 uap3:AppExtension의 PublicFolder다. provider/위젯 아이콘 및 선택 화면 screenshot은 이 폴더 아래에 두고 inventory에 resource로 포함해야 한다. 각 widget에 DarkMode와 LightMode 객체를 선택적으로 넣을 수 있으며 각 객체의 icon/screenshot/altText도 요구한다. 이미지 경로·종류·확장자·비어 있지 않음·inventory hash를 대조하며 PNG decoding/해상도/디자인 적합성/실제 위젯 화면과의 일치를 확인하지는 않는다.

ms-resource: 문자열을 쓰면 inventory에 있는 비어 있지 않은 resources.pri를 요구한다. 해당 PRI에 실제 키가 존재하는지와 locale fallback, MakePri 생성, UI 표시 검증은 별도 작업이다. 예제의 영문 literal 문자열과 languages 선언만으로 한국어 리소스가 만들어지는 것은 아니다.

## 등록 계약

| 위젯 ID | 크기 |
| --- | --- |
| CodexBarSwitcherWidget | small, medium, large |
| CodexBarUsageWidget | small, medium, large |
| CodexBarHistoryWidget | medium, large |
| CodexBarCompactWidget | small |
| CodexBarBurnDownWidget | medium |
| CodexBarCombinedBurnDownWidget | medium |

ID와 크기는 WindowsWidgetHostDefinition.swift의 현재 계약을 사용한다. 모두 AllowMultiple=true, IsCustomizable=true로 작성하고 ThemeResources의 기본 아이콘/screenshot과 선택적 명암 테마를 연결한다. 목록 누락·알 수 없는 ID·중복은 성공 출력으로 처리하지 않는다.

Application Id는 CodexBar, exe는 CodexBarWindows.exe, entry point는 Windows.FullTrustApplication이다. COM ExeServer는 실제 CoRegisterClassObject가 실행되는 CodexBarWidgetHost.exe를 가리킨다. WidgetClassFactory.h의 87b453c1-e69f-4cf4-a529-9e680ee69483을 COM Class 및 WidgetProvider/CreateInstance 양쪽에 사용한다. internetClient와 runFullTrust capability를 선언한다. 임의 registry 변경이나 기존 앱 종료로 등록을 흉내내지 않는다.

Build-WidgetHost.ps1은 복원한 Widgets 2.0.5의 runtimes-framework/package.appxfragment를 새 output resource에 복사하도록 확장했다. SDK의 native WinMD reference가 Private=false이므로 metadata/Microsoft.Windows.Widgets.winmd도 명시적으로 포함하고, 이미 MSBuild가 만든 사본이 있으면 source hash와 같을 때만 사용한다. 이후 기존 v2 build receipt의 전체 payload 및 배포 input/inventory 경로를 따른다. 이전 v2 receipt는 일반 배포에서 계속 읽을 수 있지만, fragment가 없는 이전 산출물로 이 MSIX manifest를 작성할 수는 없다.

manifest 생성기는 공개 SDK 2.0.5 fragment 원본 SHA-256 dc05acaa06f54cb75d2627fc1938049a20d398ceba6e470e61df78757091a052를 요구하고, DTD/external resolver를 끈 XML reader로 package-level Extensions를 가져온다. 이 fragment의 proxy/stub interface 및 in-process runtime class 선언을 그대로 사용한다. SDK의 feed/추가 interface 등록 항목이 존재해도 CodexBar가 그 기능을 구현했다는 뜻은 아니다. SDK 업그레이드 때는 fragment/payload/코드 계약을 함께 수정해야 한다.

## 남은 배포 작업

실제 아이콘과 위젯 screenshot, locale/PRI 산출물, manifest를 포함하는 MSIX file mapping/MakeAppx 실행 경로, 인증서 subject와 실제 signer 연결, package 서명·설치·업데이트·제거 및 COM/broker 정책과 Windows Widgets 실행 검증은 남아 있다. manifest 구성 후 파일이 바뀌는 상황과 상위 경로/ACL/백신·x64/ARM64 동작도 미검증이다. 이 소스 상태를 설치 가능하거나 릴리스 가능한 패키지로 표시하지 않는다.

공개 등록 자료: [Widgets SDK 2.0.5](https://www.nuget.org/packages/Microsoft.WindowsAppSDK.Widgets/2.0.5), [Win32 위젯 등록 예제](https://learn.microsoft.com/en-us/windows/apps/develop/widgets/implement-widget-provider-win32), [위젯 manifest 형식](https://learn.microsoft.com/en-us/windows/apps/develop/widgets/widget-provider-manifest), [Package identity](https://learn.microsoft.com/en-us/uwp/schemas/appxpackage/uapmanifestschema/element-f-identity).
