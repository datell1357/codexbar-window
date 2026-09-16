# 현재 사용자 MSIX 제거

상태: CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 아래는 작성한 코드의 future Windows 동작 계약이다. 현재 macOS 작업에서는 PowerShell·Appx·제거·데이터 삭제·설치·빌드·테스트·Windows 실행 검증을 수행하지 않았다.

`Remove-CodexBarMSIXPackage.ps1`은 완료된 설치 receipt와 운영자가 지정한 정확한 PackageFullName을 현재 Windows 사용자 등록과 대조한 뒤 한 패키지만 제거하도록 작성했다. 원본 MSIX나 signing key/SDK는 요구하지 않는다. 디렉터리 재귀 삭제나 다른 사용자/전체 컴퓨터의 패키지 제거를 직접 수행하는 코드가 아니다.

## 데이터 처리의 명시적 선택

일반 서명 MSIX에서 `Remove-AppxPackage -PreserveApplicationData`를 사용하면 앱 데이터를 보존할 수 있다고 가정하지 않는다. Microsoft는 이 옵션을 file layout으로 등록한 개발 앱에만 적용한다고 명시한다. 현재 도구는 일반 서명 MSIX를 대상으로 한다. [Remove-AppxPackage 문서](https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage?view=windowsserver2025-ps)

이번 진입점은 패키지 데이터 제거를 수용하는 경우만 제공하며 `AcknowledgePackageDataRemoval`을 명시해야 한다. 백업을 생성하거나 백업이 존재한다고 확인하지 않는다. 필요한 데이터를 별도로 보존해야 하는 경우 이 제거 경로를 실행하면 안 된다. 패키지의 앱 데이터 저장소는 앱 제거와 함께 사라질 수 있다. [Microsoft 앱 데이터 문서](https://learn.microsoft.com/en-us/windows/apps/develop/data/store-and-retrieve-app-data)

외부 CLI 설정/프로젝트/브라우저 프로필/Credential Manager 항목을 찾아 지우는 별도 호출은 추가하지 않았다. 이는 해당 데이터가 모두 보존됐다는 검증 결과가 아니다. Windows의 패키지 데이터·가상화 저장소 처리 영향은 실제 검증이 필요하며, 보존/백업·복원 선택지는 남은 필수 작업이다.

## 호출 형식

미실행 예시다. 설치 도구가 만든 정확한 receipt와 실제 PackageFullName을 넣어야 한다.

```powershell
.\Remove-CodexBarMSIXPackage.ps1 `
    -InstallationReceipt C:\DeploymentRecords\CodexBar-install\package-installation-receipt.json `
    -ExpectedPackageFullName '<exact current PackageFullName>' `
    -OutputDirectory C:\DeploymentRecords\CodexBar-remove-new `
    -AcknowledgePackageDataRemoval `
    -AllowUnvalidatedBuild `
    -WhatIf
```

`-WhatIf`는 receipt와 현재 Appx 등록을 읽지만 lock/출력 생성·제거 전에 반환한다. 실제 실행은 high-impact ShouldProcess 확인을 거치며, 확인 후 Windows cmdlet에 같은 패키지 full name을 전달한다. 사용자 지시로 검증하지 않은 개발 산출물이므로 AllowUnvalidatedBuild도 요구한다.

현재 사용자에게 등록된 main package 하나의 name/publisher/version/architecture/full/family name이 receipt 및 명시한 대상과 일치해야 한다. 오래된 설치 receipt로 업데이트된 다른 버전을 제거하지 않는다. 새로운 외부 설치·다른 publisher·loose development/framework 등록은 자동 인수하지 않는다. 현재 Status가 손상됐더라도 정확한 대상이라면 제거를 막지 않으며 관측 상태를 기록한다.

## 입력과 기록 위치

공유 `Read-CodexBarMSIXInstallation`은 64 KiB 이하 regular receipt의 스키마·완료 상태·작업 ID·현재 user SID·identity·선언된 provenance 및 hash 형식을 읽는다. receipt stream은 작업이 끝날 때까지 유지한다. 이 로컬 기록은 attestation이나 현재 설치 파일 전부의 서명/바이트 증명이 아니다. 제거를 위해 만료된 원본 서명 인증서나 원본 MSIX를 다시 요구하지 않는다.

설치 위치는 현재 OS 조회의 InstallLocation을 사용한다. 저장된 설치 경로를 삭제 대상으로 사용하지 않는다. 입력 receipt 및 새 출력이 이 위치 또는 현재 사용자의 `LocalApplicationData\Packages\<PackageFamilyName>` 아래에 있으면 거절해 제거 중 운영 기록이 함께 사라지는 상황을 제한한다. 해당 데이터 경로는 [Microsoft MSIX troubleshooting 문서](https://learn.microsoft.com/en-us/windows/msix/msix-troubleshooting-guide)의 경로 계약을 참고했다. 경로 비교는 전체 파일시스템/가상화 영향의 증명은 아니다.

설치/재개와 같은 operations.lock을 확보한 뒤 target snapshot과 InstallLocation을 다시 대조한다. 기존 출력은 재사용하거나 삭제하지 않고 새 디렉터리에만 기록한다. 협력하는 스크립트의 lock이며 OS/외부 설치 도구와의 전체 transaction은 아니다.

## 결과의 범위

`removal-operation.json`은 PREPARED → SUBMITTING_REMOVAL_TO_WINDOWS → WINDOWS_COMMAND_RETURNED → REMOVAL_RECORDED를 기록하도록 작성했다. Windows에 전달하는 명령은 현재 사용자에 대한 `Remove-AppxPackage -Package <exact full name>`이다. 별도 Stop-Process, all-user 제거, provisioning 변경, 파일/레지스트리/credential purge는 호출하지 않는다. Windows 자체의 앱 종료·데이터 처리 결과는 별도로 검증해야 한다.

명령 반환 후 현재 사용자 main package를 다시 조회한다. 해당 이름의 등록이 없어야 `package-removal-receipt.json`을 CreateOnly로 게시한다. 다른 버전이 남아 있거나 동시 업데이트로 대상이 바뀌었다면 그것까지 자동 제거하지 않고 불확실 결과로 남긴다.

receipt 상태는 `UNREGISTERED_DATA_EFFECTS_UNVERIFIED`이며 observation은 `CURRENT_USER_MAIN_REGISTRATION_ABSENT`다. 이는 현재 사용자 등록 부재를 관측했다는 의미다. 다른 사용자의 설치나 디스크에 공유/스테이징된 payload, widget/COM 철회, 데이터의 실제 삭제·보존을 확인한 상태가 아니다. dataValidation/runtimeValidation은 NOT_RUN이다.

dataPolicy는 패키지 데이터 제거 선택, 별도 외부 데이터 삭제 요청 없음, 백업 미생성을 각각 기록한다. 실패 또는 응답 불확실 시 REMOVAL_FAILED_OR_INDETERMINATE, 등록 부재를 관측한 뒤 기록 실패 시 UNREGISTRATION_OBSERVED_RECORD_INCOMPLETE를 남긴다. 원래 설치 receipt, journal generation 및 실패한 pending 파일을 자동 삭제하거나 성공으로 추정하지 않는다. 운영 기록에는 user SID와 OS 설치 경로가 있으므로 로컬 진단 자료로 관리한다.

## 남은 작업

같은 설치 receipt·user·제거 operation·full name에 결합한 [중단 제거의 기록 조정/명시 재시도](MSIX-REMOVAL-RECOVERY.ko.md) 코드를 추가했다. 최초 제거와 재개가 대상/기록 위치/데이터 정책/receipt 생성·대조 helper를 공유하며, 최초 제거도 게시한 receipt를 다시 읽고 대조한 뒤 journal을 완료하도록 작성했다. 실제 제거/재개를 실행한 것은 아니다.

[설정 파일 하나의 암호화 백업·새 파일 복원](CONFIGURATION-RECOVERY.ko.md) 명령 코드를 추가했다. 전체 앱 데이터 백업이 아니며 이 제거 도구와 연결하거나 backup 정책을 변경하지 않았다. 필요한 데이터가 모두 보존됐다고 추정해 제거를 진행하면 안 된다.

[로컬 설정 묶음 백업·복원](LOCAL-SETTINGS-RECOVERY.ko.md)으로 Windows preferences/위젯 설정과 교체 전 복구 사본도 연결했다. 전체 이력/credential/외부 저장소 및 실제 제거 영향 밖의 보관을 확인하는 기능은 아니므로 이 제거 명령의 데이터 선택과 backup 정책은 유지한다.

전체 데이터 보존/복원 및 제거 연결, 명시적 rollback, 손상 canonical 기록의 generation 선택 복구, GUI 및 자동 업데이트와 연결이 남아 있다. OS 배포·실행 중 앱·패키지 가상화·경로 race·ACL·백신·전원 차단·x64/ARM64 동작도 미검증이다. 이 단계로 W16 또는 전체 Windows 제품이 완료됐다고 판정하지 않는다.
