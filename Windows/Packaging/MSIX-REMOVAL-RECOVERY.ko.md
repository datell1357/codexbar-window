# 중단된 MSIX 제거 기록 조정과 명시 재시도

상태: CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 현재 macOS 작업에서는 PowerShell·JSON/package 평가·Appx·제거/복구·데이터 삭제·빌드·테스트·Windows 실행 검증을 수행하지 않았다.

`Resume-CodexBarMSIXRemoval.ps1`은 [제거 도구](MSIX-REMOVAL.ko.md)가 남긴 정확한 operation ID와 디렉터리, 같은 원래 설치 receipt, 명시적 PackageFullName을 받는다. 원본 MSIX나 signing key는 요구하지 않는다. 기존 제거 기록이 성공을 주장하는지보다 현재 Windows 사용자 등록을 먼저 확인한다.

## 상태별 동작

| 현재 등록 상태 | 기록/선택 조건 | 작성한 동작 |
|---|---|---|
| 해당 main package 등록 없음 | 같은 user·설치 receipt byte hash·제거 operation·full name | Windows 제거 명령 없이 누락된 receipt/journal 조정 |
| 등록 없음, 일치하는 제거 receipt 존재 | identity/provenance/이전 snapshot/data policy까지 일치 | receipt를 그대로 사용하고 필요할 때 journal만 완료 처리 |
| 같은 패키지와 원래 snapshot이 그대로 있음 | 완료/부재 관측 기록이 없고 재시도·데이터 제거를 모두 명시 | exact full name에 대해 제거 명령을 한 번 다시 제출 |
| 다른 등록/위치/상태 또는 완료 관측 뒤 다시 등록됨 | 모든 모드 | 기존 파일과 등록을 보존하고 중단 |

기록 조정 중 등록 부재를 확인했는데 ownership lock을 기다린 뒤 등록이 나타나면, 재시도 옵션이 있더라도 제거로 전환하지 않는다. 조정만 한다는 확인을 받은 뒤 작업 범위를 변경하지 않기 위한 조건이다. 재시도 준비 중 대상이 이미 사라진 경우에는 기록 조정만 수행할 수 있다.

## 호출 형식

다음은 미실행 예시다. ExpectedOperationId는 removal-operation.json의 원래 32자리 ID이며, ExpectedPackageFullName은 처음 선택한 정확한 full name이다.

```powershell
.\Resume-CodexBarMSIXRemoval.ps1 `
    -InstallationReceipt C:\DeploymentRecords\CodexBar-install\package-installation-receipt.json `
    -OperationDirectory C:\DeploymentRecords\CodexBar-remove-interrupted `
    -ExpectedOperationId '<32 hexadecimal characters>' `
    -ExpectedPackageFullName '<exact package full name>' `
    -AllowUnvalidatedBuild `
    -WhatIf
```

기본값은 기록 조정이다. 같은 패키지가 아직 등록되어 있어 다시 제거하려면 `-RetryIfUnchanged`와 `-AcknowledgePackageDataRemoval`을 둘 다 명시해야 한다. 기록에 남은 과거 데이터 제거 선택만으로 새 제거 호출을 승인하지 않는다. 백업은 생성하지 않으며 패키지 데이터 보존/복원은 이 경로의 기능이 아니다.

WhatIf는 기존 receipt·journal 및 현재 등록을 읽지만 lock/기록 쓰기·제거 명령 전에 반환한다. 실제 진행은 ShouldProcess 확인을 따른다. 현재 상태에 따라 재시도할 명령은 현재 사용자에 대한 Remove-AppxPackage의 exact full name 한 개뿐이다. all-user 제거, 다른 버전으로 selector 확대, 파일/레지스트리/credential purge는 추가하지 않았다.

## 기록 결합과 보존

원래 설치 receipt는 현재 user SID와 완료 설치 계약을 대조하고 작업 종료까지 read handle로 보관한다. 제거 journal은 64 KiB 한도에서 읽고 선택한 ID, user, 설치 operation ID 및 receipt byte hash, identity/full name, 이전 snapshot, 데이터 정책, 미검증 상태를 요구한다. 기록된 observed를 현재 등록의 증거로 사용하지 않는다.

기존 설치/제거와 같은 operations.lock을 얻은 뒤 journal byte hash와 OS 등록을 다시 확인한다. hash가 달라졌으면 임의로 최신 기록을 인수하지 않는다. 재시도에는 status와 현재 OS InstallLocation도 원래 snapshot과 일치해야 한다. 손상 상태의 원래 target을 허용하되 다른 상태를 자동 채택하지 않는다.

saved InstallLocation은 운영 기록을 package 영역 밖에 유지하기 위한 경로 비교에만 사용한다. 그 경로를 열거나 삭제 대상으로 삼지 않는다. 다시 제출할 때는 현재 OS에서 읽은 InstallLocation으로도 입력/출력 위치를 대조한다. canonical 파일이 손상되거나 없으면 previous/pending generation을 임의 선택해 대체하지 않는다.

기존 제거 receipt는 작업 ID·user·설치 receipt hash·identity/provenance·이전 snapshot/위치·데이터 정책과 일치해야 재사용한다. 다르거나 읽을 수 없는 receipt는 보존하고 중단한다. 없는 경우에만 CreateOnly로 새 파일을 게시하며, 최초 제거 경로도 같은 생성/대조 helper를 사용하도록 연결했다. 새 receipt를 연 뒤 내용을 다시 대조한 상태에서 journal 완료를 기록한다.

## 결과의 범위

재개는 원래 operationId/createdAt/before를 유지하고 lastResumeId/lastResumeAt 및 새 관측을 추가한다. 조정 중에는 RECONCILING_REMOVAL, 재제출은 SUBMITTING_REMOVAL_TO_WINDOWS와 WINDOWS_COMMAND_RETURNED를 사용한다. 완료는 REMOVAL_RECORDED와 UNREGISTERED_DATA_EFFECTS_UNVERIFIED receipt다. 이미 일치하는 완료 기록이면 ALREADY_RECONCILED를 반환하고 기록을 다시 쓰지 않는다.

실패/불확실 결과는 REMOVAL_FAILED_OR_INDETERMINATE, 등록 부재를 관측했지만 기록이 미완성인 경우는 UNREGISTRATION_OBSERVED_RECORD_INCOMPLETE다. source receipt·journal generation·pending 파일을 자동 삭제하지 않는다. dataValidation/runtimeValidation은 NOT_RUN이며, 실제 데이터 삭제량이나 위젯/COM 철회 성공을 완료로 표시하지 않는다.

현재 등록 부재는 어느 프로세스가 제거했는지 또는 Windows 내부 작업이 모두 종료됐는지 증명하지 않는다. 같은 full name의 재설치가 관측 사이에 발생했는지도 snapshot만으로 판별하지 못한다. 따라서 재제출은 현재 target 제거에 대한 새로운 명시적 선택이며 자동 retry loop가 아니다. 완료 관측을 기록한 뒤 등록이 다시 나타나면 재제출을 거절한다.

외부 설치 도구와의 경합, 경로/ACL/파일 공유·전원 중단·Appx 응답·x64/ARM64 실제 동작은 미검증이다. 데이터 보존/백업·복원, 명시적 rollback, 손상 canonical 기록의 generation 선택 복구, GUI/자동 업데이트 및 전체 Windows 전용 제품 구현과 검증도 계속 남아 있다.
