# MSIX 개발 설치와 업데이트

상태: CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 현재 macOS 작업에서는 아래 PowerShell, archive/XML 평가, 인증서 신뢰 조회, Appx module, 설치·업데이트·앱 실행 또는 테스트를 실행하지 않았다.

`Install-CodexBarMSIXPackage.ps1`은 [서명 단계](MSIX-SIGNING.ko.md)의 `CodexBarWindows.msix`와 `package-signing-receipt.json`을 받아 현재 Windows 사용자에게 설치하거나 업데이트하도록 작성했다. SDK·개발 도구를 설치 사용자에게 요구하지 않고 Windows Appx module 및 OS 서명 확인을 사용한다. 현재 산출물은 실행 미검증이므로 기존 개발 설치 도구와 같은 `AllowUnvalidatedBuild` 명시적 선택을 요구한다. 이 단계는 정식 배포 승인이나 자동 업데이트 UI를 완성한 것이 아니다.

## 신규 설치

아래는 나중에 Windows에서 사용할 명령 형식이다. thumbprint는 운영자가 신뢰할 서명자의 실제 40자리 값으로 지정해야 하며 receipt 값으로 자동 선택하지 않는다.

```powershell
.\Install-CodexBarMSIXPackage.ps1 `
    -PackageDirectory C:\Artifacts\CodexBar-msix-signed `
    -ExpectedSignerThumbprint '<40 hexadecimal characters>' `
    -Mode Install `
    -OutputDirectory C:\DeploymentRecords\CodexBar-install-new `
    -AllowUnvalidatedBuild `
    -WhatIf
```

Install 모드는 해당 Name의 main package가 현재 사용자에게 설치되어 있지 않을 때만 진행한다. 같은 이름의 다른 publisher, framework/loose development 등록 등 지원하지 않는 상태는 자동으로 인수하지 않는다. 출력 폴더는 기존 부모 아래의 새 경로여야 하고 signed package 폴더 밖이어야 한다.

## 기존 패키지 업데이트

Update에는 현재 등록된 정확한 PackageFullName이 필요하다. 운영자가 선택한 대상과 실제 등록을 대조하며, 같은 이름/publisher/아키텍처의 정상 상태 main package 하나만 허용한다. 새 manifest의 네 자리 버전은 기존 버전보다 높아야 한다.

```powershell
Get-AppxPackage -Name '<configured package Name>' -PackageTypeFilter Main |
    Select-Object Name, Publisher, Version, Architecture, PackageFullName, PackageFamilyName, Status

.\Install-CodexBarMSIXPackage.ps1 `
    -PackageDirectory C:\Artifacts\CodexBar-msix-next-signed `
    -ExpectedSignerThumbprint '<40 hexadecimal characters>' `
    -Mode Update `
    -ExpectedInstalledPackageFullName '<exact current PackageFullName>' `
    -OutputDirectory C:\DeploymentRecords\CodexBar-update-new `
    -AllowUnvalidatedBuild `
    -WhatIf
```

스크립트는 현재 사용자만 조회/등록하고, 다른 사용자나 전체 컴퓨터에 대한 provisioning을 하지 않는다. `Get-AppxPackage -PackageTypeFilter Main`과 정확한 필드 대조를 사용한다. current-user 조회 의미는 [Microsoft Get-AppxPackage 문서](https://learn.microsoft.com/en-us/powershell/module/appx/get-appxpackage?view=windowsserver2025-ps)를 따른다.

실제 명령은 신규 설치에서 `Add-AppxPackage -Path`, 업데이트에서 `Add-AppxPackage -Path -Update`다. 앱 강제 종료, 버전 강등, defer registration, 미등록 dependency 자동 검색/설치 옵션은 사용하지 않는다. 사용 중인 앱·누락된 dependency·OS/정책 불일치는 Windows 배포 오류로 남기고 원인을 해결해야 한다. 서명 패키지의 사용자 등록과 같은 package family 업데이트는 [Microsoft Add-AppxPackage 문서](https://learn.microsoft.com/en-us/powershell/module/appx/add-appxpackage?view=windowsserver2025-ps)를 참고했다.

## 입력과 신뢰 경계

공유 `Read-CodexBarSignedMSIX.ps1`은 signed receipt의 스키마/상태/선언된 signer 및 실제 MSIX의 크기·SHA-256을 대조하도록 작성했다. unsigned 입력에서 쓰던 bounded archive parser를 공유해 embedded identity/manifest/block map과 signature footprint를 읽는다. receipt의 hash/identity와 다른 파일은 배포 대상이 아니다. 파일과 receipt stream은 설치 종료까지 FileShare.Read로 유지한다.

`-WhatIf`는 입력 파일·embedded XML 및 현재 Appx 등록 상태를 읽지만, OS 서명 신뢰 확인·lock/출력 생성·설치 전에 반환한다. 실제 진행에서는 Get-AuthenticodeSignature를 통해 현재 Valid 상태, 운영자가 고른 signer thumbprint, manifest Publisher와 certificate Subject의 정확한 텍스트 일치, receipt에 기록한 timestamp signer를 확인하도록 작성했다. receipt의 과거 성공 문자열만으로 신뢰를 인정하지 않는다. certificate/private key 생성·가져오기·신뢰 저장소 변경은 수행하지 않는다. Windows trust 확인에는 환경에 따라 revocation 네트워크 조회가 따를 수 있다.

## 소유권과 기록

Windows가 반환한 현재 사용자 LocalApplicationData 아래 `CodexBar\MSIXDeployment\operations.lock`을 share mode 0으로 열어 이 도구를 사용하는 배포 작업을 직렬화한다. 기존 regular 빈 파일만 재사용하고 기록하거나 삭제하지 않는다. 상위 경로의 관측된 reparse를 거절하며, lease를 얻은 뒤 현재 설치 상태와 Update 선택자를 다시 확인한다. 다른 세션·외부 설치 도구·Windows deployment service 전체에 대한 transaction이나 compare-and-swap은 아니다.

새 출력 폴더의 `deployment-operation.json`은 PREPARED → SUBMITTING_TO_WINDOWS → WINDOWS_COMMAND_RETURNED → REGISTRATION_RECORDED 단계를 기록하도록 작성했다. 공용 journal writer는 이전 generation과 실패한 pending 파일을 보존한다. 중간 기록에는 사용자 SID, 패키지 identity/hash, 정확한 이전 등록 상태가 있으므로 이 폴더는 로컬 운영 기록이며 배포 payload가 아니다.

Windows 명령이 반환된 후 main package를 다시 조회한다. 예상 version/architecture, 정상 Status, full/family name을 요구하며 Update는 기존 family를 유지하고 full name이 바뀌어야 한다. 조건을 만족하면 `package-installation-receipt.json`에 REGISTERED_RUNTIME_UNVERIFIED를 기록한다. 이는 현재 사용자 등록을 관측했다는 상태이며 앱 시작·위젯/COM·공급자 통신이 동작했다는 뜻이 아니다. runtimeValidation은 NOT_RUN으로 유지한다.

오류 상태는 DEPLOYMENT_FAILED_OR_INDETERMINATE, 이미 정상 등록을 관측했지만 기록 쓰기가 실패한 경우는 REGISTRATION_OBSERVED_RECORD_INCOMPLETE다. Windows 배포가 일부 진행된 뒤 명령·조회·기록이 실패할 수 있으므로 성공/실패만 추측해 자동 재설치하거나 이전 package를 제거하지 않는다. 원본 signed 파일과 기록을 보존하고 실제 현재 사용자 등록 상태를 먼저 확인해야 한다.

## 남은 작업

중단 설치와 receipt 조정/재개, 명시적 rollback과 데이터 보존 정책, 제거, stable/beta 자동 업데이트, GUI 설치 흐름, 설치된 코드/리소스의 실제 동작, WinUI/위젯/COM·앱 간 전환은 남아 있다. Source provenance는 선언값이며 빌드 attestation이 아니다. PKI/SIP 지원·Appx module 호환성, 상위 경로 race/파일 공유·ACL·백신, 디스크/전원 중단, Windows 버전·x64/ARM64 실제 검증을 하지 않았다. script success를 배포 가능 판정으로 사용하지 않는다.
