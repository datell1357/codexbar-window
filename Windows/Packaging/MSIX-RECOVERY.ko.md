# 중단된 MSIX 설치 기록 조정과 재개

상태: CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 이 문서는 나중에 Windows에서 사용할 코드의 계약이다. 현재 작업에서는 PowerShell·package/XML 평가·서명 신뢰 조회·Appx·설치/재개·파일 복구·빌드·테스트·앱 실행을 하지 않았다.

`Resume-CodexBarMSIXDeployment.ps1`은 [설치 도구](MSIX-INSTALLATION.ko.md)가 남긴 정확한 operation ID와 디렉터리, 같은 signed MSIX와 signing receipt, 운영자가 지정한 signer를 받는다. 기록에 성공 문자열이 있다는 이유만으로 완료 처리하지 않고 현재 사용자 등록을 다시 읽는다. 기존 package나 사용자 데이터를 삭제·강등하는 복구 경로는 아니다.

## 상태별 동작

| 현재 Windows 등록 | 기록과 선택 조건 | 작성한 동작 |
|---|---|---|
| 요청한 version/architecture의 정상 main package | 같은 사용자·작업·입력 hash와 일치 | Add-AppxPackage를 호출하지 않고 receipt/journal 조정 |
| 요청한 package가 등록됐고 일치하는 receipt도 존재 | receipt의 작업·입력·identity·provenance·이전/현재 등록까지 일치 | 기존 receipt를 그대로 사용하고 필요할 때 journal만 완료 처리 |
| 원래의 설치 전 상태와 일치 | 완료 관측/receipt가 없으며 `RetryIfUnchanged`를 명시 | 같은 Install/Update 명령을 한 번 다시 제출한 뒤 등록 확인 |
| 다른 사용자·작업·signed 바이트, 다른 등록/버전/아키텍처, 손상/다른 receipt | 어느 재개 모드든 | 기존 파일과 등록을 보존하고 중단 |

원래 상태가 남아 있다는 관측만으로 Windows 내부 작업이 모두 종료됐다고 판단하지 않는다. 자동 재시도·polling loop는 없다. RetryIfUnchanged는 운영자가 명시적으로 같은 작업을 다시 제출하는 선택이며, Windows deployment service나 다른 설치 도구와의 경합 가능성을 없애지는 않는다.

## 호출 형식

다음은 미실행 예시다. ExpectedOperationId는 선택한 deployment-operation.json의 원래 32자리 ID이며 파일을 읽어 임의로 가장 최근 작업을 고르지 않는다.

```powershell
.\Resume-CodexBarMSIXDeployment.ps1 `
    -PackageDirectory C:\Artifacts\CodexBar-msix-signed `
    -ExpectedSignerThumbprint '<40 hexadecimal characters>' `
    -OperationDirectory C:\DeploymentRecords\CodexBar-interrupted `
    -ExpectedOperationId '<32 hexadecimal characters>' `
    -AllowUnvalidatedBuild `
    -WhatIf
```

기본값은 기록 조정만 허용한다. 이전 상태에서 다시 제출할 때만 같은 호출에 `-RetryIfUnchanged`를 추가한다. `-WhatIf`는 signed 입력·작업 기록·현재 등록을 읽지만 서명 신뢰 확인·lock/기록 쓰기·설치 명령 전에 반환한다. 현재 등록이 재제출을 요구하는데 해당 옵션이 없으면 중단한다.

기존 완료 journal이 있는데 현재 package가 제거/변경됐거나, 정상 등록을 관측했다는 중간 상태가 남았는데 target이 사라진 경우는 자동 재설치하지 않는다. 새 설치 작업이나 명시적 별도 복구 정책이 필요한 상태다. 이전 status를 임의로 바꾸어 재개 조건을 우회하면 안 된다.

## 입력과 소유권

schema 1 operation의 ID·mode·현재 사용자 SID·signed package hash·signing receipt hash·expected signer·embedded identity를 대조한다. Install의 원래 snapshot은 비어 있어야 하고 Update에는 같은 identity/architecture의 정상 이전 등록 하나와 더 낮은 버전이 있어야 한다. 기록된 observed 값은 현재 상태의 근거로 사용하지 않는다.

작업 기록은 64 KiB 이하 regular 파일로 읽고 정확한 byte hash를 보관한다. 설치와 같은 `LocalApplicationData\CodexBar\MSIXDeployment\operations.lock`을 얻은 후 journal hash와 Windows 등록을 다시 확인한다. 그 사이 기록이 바뀌면 최신 내용을 임의로 인수하지 않는다. 이 lock은 협력하는 스크립트를 직렬화하며 OS/외부 도구의 모든 변경을 잠그지는 않는다.

실제 진행에서는 서명된 입력의 현재 OS trust·signer/publisher/timestamp를 다시 요구한다. 파일 hash와 source provenance는 입력 MSIX에 대한 연결이며 현재 설치된 파일 전부의 바이트 증명이나 source attestation은 아니다. 완료 상태도 현재 사용자 identity/등록 상태의 관측 범위에 한정된다.

기존 receipt가 있으면 형식·작업 ID·user·입력 hash/크기·identity·provenance·registered/previous snapshot을 모두 대조하고 열린 read handle로 유지한다. 다른 receipt나 읽을 수 없는 파일을 삭제·교체하지 않는다. 없는 경우에만 새 installation receipt를 게시한다.

## 기록 보존과 중단

공용 `Write-CodexBarJournal`의 선택적 CreateOnly는 완성한 임시 파일을 새 목적지로 Move한다. 확인 후 다른 프로세스가 같은 이름을 만들었어도 기존 파일을 교체하지 않고 실패한다. 기존 호출의 기본 journal 교체/previous 보존 동작은 유지했다. 최초 MSIX 설치의 receipt 게시에도 CreateOnly를 연결했다.

재개 기록은 원래 operationId/createdAt/before를 유지하고 lastResumeId/lastResumeAt 및 새 관측을 남긴다. 기록 조정 중에는 RECONCILING_REGISTRATION, 재제출은 기존 SUBMITTING_TO_WINDOWS와 WINDOWS_COMMAND_RETURNED 단계를 사용한다. 완료는 REGISTRATION_RECORDED 및 REGISTERED_RUNTIME_UNVERIFIED receipt이며 runtimeValidation은 NOT_RUN이다. 이미 같은 완료 상태면 ALREADY_RECONCILED 결과를 반환하고 기록을 다시 쓰지 않는다.

createdAt은 유효한 날짜 문자열과 JSON reader가 반환하는 DateTime/DateTimeOffset을 모두 받는다. 새 PowerShell의 timestamp 자동 변환을 문자열 오류로 취급하지 않으며, Windows PowerShell에 없는 DateKind 옵션을 요구하지 않는다. 날짜 변환 차이는 [Microsoft ConvertFrom-Json 문서](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-json?view=powershell-7.5)를 참고했다. 생성 시각은 재제출 권한이나 OS 작업 종료를 판정하는 값이 아니다.

실패는 기존 DEPLOYMENT_FAILED_OR_INDETERMINATE 또는 REGISTRATION_OBSERVED_RECORD_INCOMPLETE로 기록하도록 작성했다. 이전 journal generation, pending 파일, signed 원본, 일치하는 receipt를 보존한다. canonical journal/receipt 자체가 손상됐거나 없으면 이전 generation을 임의로 골라 복구하지 않는다. 명시적 generation 선택/복구는 남은 작업이다.

실제 PowerShell/Appx/PKI·호출 취소/중단·OS 등록 전환·x64/ARM64, 외부 writer와 경로 교체·전원 차단 내구성은 미검증이다. 제거·rollback·사용자 데이터 처리, 자동 업데이트/UI 및 Windows 제품 전체의 실행 검증도 계속 남아 있다.
