# MSIX 파일 구성과 패키지 생성

상태: CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 다음은 Windows에서 나중에 사용할 스크립트의 동작 계약이다. 현재 macOS 작업에서는 PowerShell, manifest 평가, MakeAppx, 빌드, 테스트, 서명, 설치 및 실행 검증을 수행하지 않았다.

`New-CodexBarMSIXPackage.ps1`은 배포 인벤토리와 [manifest configuration](MSIX-MANIFEST.ko.md), 명시적으로 지정한 Windows SDK MakeAppx.exe를 받아 새로운 unsigned MSIX를 만들도록 작성했다. 인증서 선택·패키지 서명·설치·등록·업데이트·게시를 수행하는 진입점은 아니다.

## 입력과 출력

Windows에서 사용할 명령 형식이며 이번 작업에서는 실행하지 않았다:

```powershell
.\New-CodexBarMSIXPackage.ps1 `
    -DistributionDirectory C:\Artifacts\CodexBar-staged `
    -ConfigurationPath C:\Inputs\msix-configuration.json `
    -MakeAppxPath 'C:\Program Files (x86)\Windows Kits\10\bin\<SDK version>\x64\makeappx.exe' `
    -OutputDirectory C:\Artifacts\CodexBar-msix-new `
    -WhatIf
```

`<SDK version>`과 configuration 내용은 실제 준비한 값으로 교체해야 한다. SDK 실행 파일의 호스트 아키텍처와 배포 인벤토리의 앱 아키텍처는 서로 다른 입력이다. 앱 아키텍처는 인벤토리의 x64/arm64 선언을 manifest에 전달하며 MakeAppx 파일 이름으로 추정하지 않는다. `-WhatIf`는 입력 파일을 읽고 대조하지만 출력 생성과 manifest 생성기/MakeAppx 실행 전에 반환한다. 입력 configuration 전체에 대한 manifest 단계 검사를 대신하지 않는다.

출력 디렉터리는 배포 폴더 밖의 존재하지 않는 경로여야 하고 부모는 이미 존재해야 한다. 스크립트는 로컬 드라이브 경로를 요구하며 UNC/device 경로와 관측된 reparse 경로를 거절한다. 기존 출력의 덮어쓰기·재사용·삭제는 하지 않는다. 실패한 파일은 그대로 남으므로 재시도에는 새 OutputDirectory를 사용한다.

- `AppxManifest.xml`: 같은 배포/configuration을 기존 생성기에 전달해 새로 작성한 manifest.
- `package-files.txt`: 인벤토리 파일 전부와 새 manifest만 나열하는 MakeAppx mapping. 로컬 절대 source 경로가 있으므로 게시용 파일이 아니다.
- `CodexBarWindows.msix`: MakeAppx가 생성할 unsigned 패키지.
- `package-build-receipt.json`: MakeAppx 종료 코드 0과 비어 있지 않은 출력 파일을 확인한 뒤 기록하도록 작성한 로컬 빌드 인계 정보.

인벤토리 JSON, 별도 configuration, mapping과 receipt를 폴더 검색으로 패키지에 자동 포함하지 않는다. 인벤토리 자체에 포함된 파일은 모두 패키징 대상이므로 입력 목록 작성자가 배포할 파일만 선언해야 한다. package footprint인 AppxManifest.xml/AppxBlockMap.xml/AppxSignature.p7x/AppxMetadata/[Content_Types].xml 및 distribution-inventory.json은 payload 경로로 거절한다.

## 파일과 생성 상태의 연결

schema 1의 STAGED_UNVERIFIED 또는 SIGNED_RUNTIME_UNVERIFIED 인벤토리와 선언된 provenance/first-party 목록을 요구한다. 각 파일의 정규화한 상대 경로·종류·중복·크기·SHA-256을 읽고 실제 파일과 대조하도록 작성했다. 전체 입력 10,000개, 개별 512 MiB, 합계 8 GiB는 이 진입점의 제한이다. Windows/MSIX 전체 한도나 성능 측정 결과가 아니다.

인벤토리·configuration·MakeAppx·payload·생성한 manifest/mapping을 FileShare.Read로 열어 package 명령과 receipt 쓰기가 끝날 때까지 보관한다. 이 기간에 같은 파일을 일반적인 Windows 파일 공유 규칙으로 변경/삭제하는 것을 제한한다. 디렉터리 handle을 고정하거나 모든 파일시스템 race를 해결한 것은 아니다. 파일 확인과 열기 사이, 상위 경로 교체, 다른 writer/ACL/백신과의 상호작용은 미검증이다.

명령은 `pack /f <mapping> /p <output> /h SHA256 /no`다. `/no`로 덮어쓰기 확인 대기를 피하고 SDK의 기본 semantic 검사를 유지한다. `/nv`, 자동 실패 재실행 또는 오류 무시는 추가하지 않았다. 이 계약은 [Microsoft MakeAppx 문서](https://learn.microsoft.com/en-us/windows/msix/package/create-app-package-with-makeappx-tool)의 mapping 및 옵션에 근거한다. 문서가 설명하듯 MakeAppx 성공만으로 설치 가능성이 보장되지는 않는다.

receipt에는 원본 인벤토리/configuration/manifest/mapping/tool/package의 hash, 입력 수·크기, provenance, MakeAppx 종료 코드를 기록한다. 상태는 `PACKAGED_UNSIGNED_RUNTIME_UNVERIFIED`, signing/installation/runtimeValidation은 `NOT_RUN`이다. 내부 EXE/DLL이 서명된 배포 입력이어도 MSIX 컨테이너의 서명 상태는 별개다. caller가 선언한 provenance와 로컬 hash는 빌드 출처 attestation이 아니다. 실패하거나 receipt 쓰기가 중단된 패키지를 이 스크립트가 완료로 승격하지 않는다.

## 남은 연결

실제 이미지·locale/PRI 작성, SDK의 localized resource 처리와 Unicode mapping 읽기, manifest schema와 전체 DLL 의존성·SDK 등록 계약, 패키지 서명자 subject 연결, 설치·업데이트·제거·COM activation·Widgets·x64/ARM64 실행 검증은 남아 있다. 기본 SDK 검사가 실패하면 해당 원인을 수정해야 하며 검사를 자동으로 생략하지 않는다. 이 문서는 코드 구현 상태이며 실제 MSIX 산출물이나 배포 가능 판정이 아니다.
