# Windows 배포물 조립

구현만 작성했으며 실행·검증하지 않았다. `New-CodexBarDistribution.ps1`은 이미 준비된 파일의 명시적 목록으로 새 폴더를 조립한다. 빌드·DLL 의존성 분석·서명·압축·업로드·릴리스를 수행하지 않는다.

입력 JSON은 `schemaVersion: 1`, `architecture: "x64"` 또는 `"arm64"`, `files` 배열이다. 각 항목은 `source`, `destination`, `kind`를 갖는다. source의 상대 경로는 입력 JSON 폴더 기준이고 destination은 배포 폴더 기준이다. kind는 application/cli/runtime/resource/license 중 하나다.

Windows에서 사용할 명령 형식:

```powershell
.\New-CodexBarDistribution.ps1 -InputManifest .\distribution-input.json -OutputDirectory C:\Artifacts\CodexBar-new -WhatIf
```

실제 복사는 `-WhatIf`를 제거한 명시적 실행이다. 현재 작업에서는 둘 다 실행하지 않았다. 기존 출력 폴더는 거절하며 실패한 부분 출력은 삭제하지 않는다.

필수 입력은 루트의 CodexBarWindows.exe, CodexBarCLI.exe, runtime DLL, 라이선스, Set-CodexBarUserPath.ps1 리소스다. SwiftPM이 생성한 resource bundle의 실제 상대 경로를 보존하고 모든 리소스 파일을 목록에 넣는다. 특정 bundle 이름이나 DLL 목록을 추정하지 않는다. 서드파티·Swift 런타임의 재배포 권한 및 필요한 라이선스도 입력 작성자의 책임이다.

스크립트는 중복/상위 경로 탈출/파일-폴더 충돌을 제한하고 복사한 파일 크기·SHA-256을 distribution-inventory.json에 기록한다. 이 기록은 정품·서명·의존성 완전성·아키텍처 일치·실행 성공 증거가 아니다. architecture는 입력 선언값이다. 서명 작업을 도입하면 최종 서명 후 파일을 기준으로 인벤토리를 다시 생성해야 한다.

알려진 경계: source 상위 junction과 복사 중 파일 변경, 출력 폴더에 대한 외부 동시 편집, long-path/ACL/백신 동작은 미검증이다. 모든 DLL과 SwiftPM 리소스의 완전성 확인, 재현 가능한 빌드·서명·설치/제거·업데이트·MSIX는 별도 필수 작업이다.

## 입력 목록 생성

`New-CodexBarDistributionManifest.ps1`은 `-BuildDirectory`, `-Architecture`, `-RuntimeFiles`, `-ResourceDirectories`, `-LicenseDirectory`, `-OutputManifest`를 받는다. DLL 파일과 SwiftPM 리소스 폴더는 빌드/런타임 배포 정보로 확인한 목록을 명시적으로 넘긴다. 리소스 폴더 이름과 하위 경로를 그대로 유지하고 라이선스는 licenses 아래에 둔다. 생성한 JSON을 조립 스크립트의 InputManifest로 전달한다.

앱·CLI·지정 DLL의 DOS/PE signature와 machine 필드를 읽어 x64 또는 ARM64 선언과 다르면 중단하도록 작성했다. 이는 PE 전체 유효성이나 서명 확인이 아니다. ARM64EC/혼합 machine은 현재 허용하지 않는다. 리소스 탐색은 link를 거절하고 depth32·tree entry20000·전체 file10000 한도를 넘으면 부분 목록을 성공으로 내보내지 않는다. 비어 있는 디렉터리는 목록에 포함하지 않는다.

출력은 CreateNew로 생성해 기존 파일을 덮지 않는다. 입력 JSON의 source는 로컬 절대 경로이므로 게시용 자료가 아니다. 최종 배포 인벤토리는 source 경로를 포함하지 않는다. 출력 중 실패한 파일은 보존하며 다른 출력 이름으로 재시도한다. 자동 import/delay-load 의존성 closure 계산은 아직 미구현이고 dependencyClosure는 NOT_VERIFIED다. 이 생성기와 PE 읽기 모두 현재 macOS 작업에서 실행하지 않았다.


입력 생성기는 Read-CodexBarPEImports.ps1의 PE32+ import/delay-import 파서를 사용한다.
각 app/CLI/runtime의 DLL 이름을 dependencies에 연결하며 포함된 runtime 이름과 맞으면 included, 나머지는 external_unclassified다. Windows 시스템 DLL/API-set이라고 이름만 보고 면제하지 않는다. 이는 import graph이며 전체 dependency closure 판정이 아니다. 정적/지연 import의 모든 선택 DLL을 읽지만 LoadLibrary 동적 이름·forwarded export·OS API-set 실제 매핑은 아직 다루지 않는다.

파서는 파일 범위/중첩 RVA 모호성/section 수/descriptor 수/문자열 길이를 제한하고 null terminator가 없거나 지원하지 않는 VA 기반 delay descriptor면 중단한다. DLL을 로드하거나 실행하지 않는다. 실행 검증은 하지 않았다.


`-RuntimeSearchDirectories`에 최대32개의 명시적인 런타임 배포 폴더를 추가할 수 있다. import된 이름이 RuntimeFiles에 없으면 각 폴더의 동일 DLL 이름을 찾아 한 개일 때만 포함하며, 새 DLL의 import도 queue로 탐색한다. 둘 이상이면 임의 우선순위를 정하지 않고 중단한다. 원하는 파일을 RuntimeFiles에 직접 지정하면 명시적 선택을 우선한다. Windows system directory나 process PATH를 자동 검색하지 않는다.

후보 접근 실패·link·architecture 불일치·1024개 PE/100000개 edge 한도 초과는 중단한다. 없는 후보는 unresolvedLibraries에 남고 전체 상태는 RECURSIVE_IMPORT_GRAPH_UNVERIFIED다. 이 목록에는 아직 분류하지 않은 정상 Windows system/API-set DLL도 포함될 수 있다. OS 지원 계약에 따른 분류와 누락 release gate는 후속 작업이다. RuntimeFiles의 DLL은 재귀 탐색 이전부터 명시적으로 선택된 입력이며 중복 설치본을 검색해 자동 교체하지 않는다.


## 시스템 의존성 정책과 조립 차단

입력 생성기의 선택적 SystemPolicyFile은 schemaVersion=1, architecture, minimumWindowsVersion(예:10.0.19045), libraries 배열을 갖는다. 각 library 항목에는 정확한 DLL name, kind(system/apiSet), reason, HTTPS reference가 필요하다. 예시 Windows 버전은 지원 확정값이 아니다. wildcard 면제는 없고 중복·아키텍처 불일치·근거 누락을 거절한다. 정책은 타깃 OS 지원 자료에 근거해 작성해야 하며 링크 자체를 실행 검증 증거로 간주하지 않는다. 현재 검증된 정책 목록을 동봉하지 않았다.

정책 항목은 declared_system으로 기록하며 검색 폴더에서 재배포 DLL을 자동 가져오지 않는다. 명시적으로 RuntimeFiles에 포함한 DLL은 기존 입력을 유지한다. 정책 원문은 입력 및 배포 인벤토리에 보존한다.

조립기는 입력 파일의 실제 import를 다시 읽어 root runtime DLL 또는 명시적 정책으로 해결되지 않는 이름이 있으면 출력 생성 전에 중단한다. 입력 JSON의 dependencyClosure 문자열만으로 통과시키지 않는다. 기존 수동 입력도 동일한 조건을 받는다. 동적 로딩·export forwarder·심볼/API 실제 지원은 이 단계의 범위 밖이며 전체 실행 성공은 미검증이다. 검사 후 복사 사이 파일 변경 방지도 아직 남아 있다.


조립은 복사 후 각 대상 파일을 FileShare.Read 핸들로 열고 모든 핸들을 인벤토리 기록까지 유지하도록 보완했다. 대상 app/CLI/runtime의 PE machine과 import를 다시 읽어 미해결·아키텍처 불일치 시 중단하며 같은 held file에서 해시를 계산한다. analysisSource=HELD_STAGED_FILES와 대상 파일의 dependencies를 인벤토리에 기록한다. 모든 핸들은 성공·실패 모두 finally에서 닫는다.

이 방식은 Windows 파일 공유 규칙에 따른 읽기 시점의 변경/삭제 제한이며 서명 검증이나 악의적인 상위 폴더 교체까지 보장하지 않는다. 복사 전후 원본이 바뀌었어도 최종 대상 바이트를 분석한다. 실제 Win32/.NET 공유 동작은 미검증이고 최종 서명이나 이후 편집으로 파일이 달라지면 이 인벤토리도 갱신해야 한다.


## 출처와 서명 인계

입력 생성기의 SourceRevision(40자리 commit)과 ProductVersion은 필수다. 고정 원본 repository와 함께 provenance로 전달하며 DECLARED_NOT_ATTESTED로 표시한다. 이 값은 호출자의 선언이며 git checkout·빌드 재현성이나 실제 바이너리와의 대응을 증명하지 않는다. 수동 입력도 같은 provenance를 포함해야 조립할 수 있다.

New-CodexBarSigningRequest.ps1은 DistributionDirectory와 배포 폴더 밖의 OutputRequest를 받아 인벤토리 크기·해시와 파일 내용을 대조한 다음 앱·CLI·PATH 스크립트3개를 서명 대상으로 기록하도록 작성했다. third-party DLL을 재서명 대상으로 자동 선정하지 않는다. request는 CreateNew로 만들며 경로별 서명 전 해시와 provenance만 담고 인증서·비밀정보를 요구하지 않는다.

실제 서명은 아직 연결하지 않았다. 인계 파일은 SIGNING_REQUEST_ONLY이며 시간 경과/다른 프로세스 변경을 막는 lock이나 서명 요청 인증은 없다. signer가 서명 직전 입력을 다시 대조하고 Authenticode/타임스탬프를 확인해야 한다. 서명 후 인벤토리를 갱신해야 하며 기존 해시로 릴리스하면 안 된다. 현재 작업에서 인계 생성/파일 대조/인증서 접근/서명은 실행하지 않았다.


## 서명 실행 코드

Sign-CodexBarDistribution.ps1은 DistributionDirectory, SigningRequest, CertificateThumbprint, TimestampServer, 새 OutputDirectory를 명시적으로 받는다. Windows CurrentUser/My의 지정 인증서만 선택하며 PFX·암호 입력/저장·인증서 자동 선택을 하지 않는다. WhatIf는 입력 파일을 읽지만 인증서 접근/서명/출력 생성 전 멈춘다. 실제 서명 실행은 현재 작업에서 하지 않았다.

원본을 보존하고 새 폴더에 복사한 바이트를 요청의 해시와 대조한 뒤 앱·CLI·스크립트만 SHA256/NotRoot로 서명한다. Valid 상태·지정 signer thumbprint·timestamp certificate를 요구하며 실패한 부분 출력은 보존한다. 타사 파일은 복사 후 원래 해시와 대조하고 재서명하지 않는다. timestamp URL은 사용자가 명시하며 실제 호출 시 네트워크와 키 공급자 UI가 필요할 수 있다.

성공하면 새 크기/해시/signer thumbprint로 인벤토리를 작성하며 SIGNED_RUNTIME_UNVERIFIED와 releaseApproved=false를 유지한다. dependencyAnalysis는 PRE_SIGN_INVENTORY_ONLY다. 현재 Windows 실행·실제 인증서/신뢰 체인/타임스탬프 동작은 미검증이며 서명 뒤 PE 재분석, 파일의 외부 동시 변경, inventory 서명·배포 검증은 남아 있다. 기존의 ‘실제 서명 미연결’ 문구는 이전 단계 기록이며 이 스크립트 추가로 코드 경로만 연결됐다.


서명 최종화는 서명된 각 파일의 FileShare.Read handle을 유지한 후 서명 상태·machine·import·해시를 다시 읽도록 보완했다. vendor/비서명 파일의 최종 hash가 원본 인벤토리와 다르면 중단한다. 최종 dependencies는 서명 전 기록을 복사하지 않고 다시 계산하며 dependencyAnalysis=HELD_FINAL_FILES_STATIC_AND_RVA_DELAY_IMPORT_NAMES로 표시한다. 모든 handle은 최종 인벤토리 기록 또는 실패 후 해제한다. 이전 PRE_SIGN_INVENTORY_ONLY 설명은 과거 단계다.

실제 Authenticode/.NET 파일 공유 호환성, 상위 디렉터리 변경과 최종 출력 외부 접근은 미검증이다. 유효한 동일 signer가 별도로 바꾼 파일, 동적 import/forwarder/API symbol 지원까지 확인하는 것은 아니다. SIGNED_RUNTIME_UNVERIFIED 및 releaseApproved=false는 유지한다.


## 사용자별 버전 설치

Install-CodexBarVersion.ps1은 DistributionDirectory와 ExpectedSignerThumbprint, 개발용 AllowUnvalidatedBuild opt-in을 받아 `%LOCALAPPDATA%/Programs/CodexBarWindows/versions/<version>-<architecture>-<revision>`에 새 payload를 설치하도록 작성됐다. 기존 version은 덮거나 지우지 않는다. installer는 앱을 실행하지 않으며 사용자 설정·PATH·startup·바로가기를 변경하지 않는다.

입력 및 복사한 파일의 hash를 대조하고 app/CLI/PATH resource의 Authenticode/지정 signer/timestamp를 확인한 뒤 INSTALLED_INACTIVE_RUNTIME_UNVERIFIED receipt를 마지막에 기록한다. 관리 작업은 operations.lock을 독점 열며 실패한 부분 출력은 보존한다. receipt가 없는 폴더는 완료된 설치로 사용하면 안 된다. installer를 현재 macOS에서 실행하지 않았다.

현재 범위는 버전별 설치다. 활성 버전 전환·Start Menu·Apps 제거 등록·upgrade/rollback·uninstall 및 호스트 OS/CPU 적합성은 다음 필수 범위다. receipt는 암호학적으로 서명된 증명이 아니며 같은 사용자에 의한 변경·상위 경로 race·런타임/리소스 전체 신뢰는 별도 검증이 필요하다. releaseApproved=false인 개발 payload를 출시 가능으로 표현하지 않는다.


## 시작 메뉴 버전 선택

Select-CodexBarVersion.ps1은 VersionID, ExpectedSignerThumbprint, AllowUnvalidatedBuild를 받아 설치 receipt와 app hash/signer를 확인하고 사용자 시작 메뉴의 CodexBar Windows.lnk를 선택한 버전으로 연결한다. 앱을 실행하거나 기존 프로세스를 종료하지 않는다. PATH/startup 경로는 별도 작업이다.

기존 링크가 관리 versions 아래 앱을 가리키고 arguments가 비어 있을 때만 교체한다. 같은 폴더의 임시 링크를 만들고 기존 링크 hash를 재확인한 뒤 File.Replace로 이전 링크 backup을 보존한다. 새 설치는 Move로 기존 파일 덮어쓰기를 거절한다. activation journal을 준비/선택 상태로 기록한다. 작업 중 실패하면 실제 링크가 이미 바뀌었을 수 있어 자동 성공이나 자동 rollback을 주장하지 않는다.

이전 버전이 남아 있으면 같은 명령으로 그 VersionID를 다시 선택할 수 있다. 자동 recovery/backup 정리·설정 schema downgrade·프로세스 전환·PATH/startup migration·제거는 남아 있다. 모든 COM/바로가기/서명/파일 교체 동작은 현재 작업에서 실행하지 않았다.


## 전환 복구

선택 스크립트는 실제 link 교체 전에 candidateHash를 기록하도록 보완했다. Restore-CodexBarActivation.ps1은 TransactionID(activation 파일명의32자리 ID)를 받아 현재 link가 기록된 candidateHash와 일치할 때만 이전 backup을 복원한다. 현재 상태가 이미 previousHash와 같으면 변경하지 않는다. 초기 설치처럼 이전 link가 없었으면 현재 link를 별도 displaced backup으로 이동한다. 모든 version과 link backup을 보존한다.

외부 변경·누락/변경된 backup·candidateHash 없는 옛 journal은 거절한다. 원래 journal 경로 필드는 예상 관리 경로와 대조하고 임의 경로에 쓰지 않는다. 복구도 operations.lock·WhatIf·별도 recovery journal을 사용한다. 작업 마지막 기록 전에 실패할 수 있으므로 실제 shortcut 상태가 우선이다. hash 확인과 replace/move는 atomic compare-and-swap이 아니며 journal 자체의 원자적 기록/복구, 상위 경로 race, 설정/프로세스/PATH/startup 복구와 Windows 실행 검증은 남아 있다.


## 복구 가능한 버전 제거

Remove-CodexBarVersion.ps1은 VersionID와 AllowUnvalidatedBuild를 받아 완료 receipt가 있는 버전의 기록된 파일만 처리한다. 시작 메뉴가 해당 버전을 선택했거나 User/Machine/Process PATH, 현재 registry view의 Run/RunOnce, 실행 중 CodexBar 앱/CLI가 해당 버전을 참조하면 중단한다. 참조는 먼저 별도 전환해야 한다. WhatIf는 조회 후 파일 이동 전에 반환한다.

해시가 일치하는 일반 파일을 install root의 removed-<transaction>/payload 아래로 옮기며 원본 receipt 사본과 removal-journal.json을 남긴다. 원래 receipt·디렉터리·설정·알 수 없는 파일은 보존한다. 수정된 파일/링크/디렉터리는 그대로 두고, 이미 없는 파일은 ALREADY_ABSENT로 처리하므로 중단 뒤 재실행 시 남은 파일을 처리할 수 있다. 복구 사본은 여러 transaction에 나뉠 수 있다. 영구 삭제나 디스크 공간 회수는 하지 않는다.

이동 뒤 해시가 달라지면 RETIRED_CHANGED_CONCURRENTLY로 기록하고 중단한다. 외부 변경과 파일 이동은 원자적으로 묶이지 않으므로 해당 파일이 원래 위치가 아닌 복구 폴더에 남을 수 있다. journal 쓰기 실패 시 파일은 이미 이동했을 수 있으며 실제 두 폴더 상태가 우선이다. 자동 복구/정리·불완전 설치 receipt 복구·상위 경로 race·새 프로세스 및 새로운 참조 생성·다른 registry view/예약 작업/별도 shortcut 검색·Apps 제거 등록은 미구현이다. 로컬 receipt는 서명된 권한 증명이 아니다. 현재 스크립트와 모든 프로세스/registry/파일 이동 동작은 실행하지 않았으며 제품 제거 완료를 의미하지 않는다.

## 제거 파일 복원 및 기록 저장

Restore-CodexBarRemovedVersion.ps1에 제거 시 출력된 TransactionID와 AllowUnvalidatedBuild를 전달하면 해당 removed 폴더에 남은 payload를 원래 version의 빈 파일 경로로 복사한다. 원래 receipt와 사본 receipt가 같아야 하며 기존 목적지 파일은 덮어쓰지 않는다. 일치한 기존 파일은 ALREADY_PRESENT, 서로 다른 파일은 충돌로 기록한다. 복사 원본은 모두 보존한다. 원래 디렉터리가 사라졌거나 링크로 바뀌었으면 중단하며 이를 임의 재생성하지 않는다.

제거 journal의 마지막 쓰기가 완료되지 않았어도 receipt에 등재된 실제 사본을 복원할 수 있다. 여러 차례 제거했으면 transaction별로 실행해야 하며, 다른 transaction의 파일이 아직 없으면 PARTIAL_RECOVERY_UNVERIFIED다. 런타임 실행·서명 승인·Start Menu/PATH/startup 복구를 수행하는 명령은 아니다. 설치 receipt가 없는 미완료 설치 복구는 별도 미구현 범위다.

Write-CodexBarJournal.ps1을 선택/선택 복구/제거/제거 복구 스크립트와 함께 배포해야 한다. 해당 스크립트들은 새 임시 파일 쓰기와 Flush(true) 이후 Move 또는 File.Replace로 journal을 게시하며, 교체 전 파일은 고유한 previous 파일로 보존한다. 실패한 pending 파일도 자동 삭제하지 않는다. 이는 journal 자체의 중간 쓰기 노출을 줄이는 구현이며 payload 이동과 journal 게시를 하나의 transaction으로 만들지는 않는다. 이전 generation 자동 복구/공간 정리, 전원 손실과 파일시스템별 내구성, 상위 경로 race, 복사 도중 외부 writer/프로세스 생성은 미검증이다. 실제 스크립트 실행과 파일 복원/교체 검증은 하지 않았다.

## 기록된 중단 설치 재개

Install-CodexBarVersion.ps1은 이제 version 디렉터리 생성 전에 install root의 installation-<versionID>.json에 정확한 배포 인벤토리 바이트 해시와 signer, VersionID를 기록한다. 새 설치에는 Write-CodexBarJournal.ps1도 함께 필요하다. ResumeIncomplete를 추가하면 같은 DistributionDirectory 내용과 ExpectedSignerThumbprint에 결합된 PREPARED/COPYING 기록만 재개한다. 인벤토리는 공백이나 순서만 바뀌어도 다른 바이트로 판단한다.

재개는 있는 파일을 덮어쓰지 않는다. 파일을 열고 전체 hash와 first-party 서명/timestamp를 다시 확인하며 완료 receipt까지 handle을 유지한다. 없는 파일만 복사하고 unknown 파일은 보존한다. 파일 일부만 기록된 채 복사가 끊긴 경우 hash 불일치로 중단하므로 현재 자동 수정 대상이 아니다. 동일한 version 이름을 가진 다른 배포물이나 이전의 기록 없는 부분 설치도 자동 수용하지 않는다.

receipt는 마지막에 임시 파일 기반 저장 함수로 게시하고 그 뒤 설치 기록을 완료 상태로 갱신한다. 마지막 기록 갱신 실패 시 receipt는 이미 있을 수 있다. receipt가 있으면 재개 명령은 중단하므로 실제 receipt와 설치 기록을 별도로 확인해야 한다. 두 기록의 자동 조정, unknown 파일이 런타임에 미치는 영향, 경로/동시 writer race, 복사 중단 파일 복구, Apps 등록과 Windows 실행 검증은 남아 있다. 실제 설치나 재개 실행은 하지 않았다.

## 설치 파일 게시 및 receipt 조정 보완

새 파일은 install root의 고유 install-staging 폴더에 복사한 뒤 디스크 flush와 크기/hash/first-party Authenticode 확인을 거쳐 최종 경로에 Move한다. 게시 뒤에도 다시 대조하고 파일 handle을 완료 receipt까지 유지한다. 복사가 끊긴 임시 파일은 version 폴더 밖에 남고 재개 시 새 임시 파일을 사용한다. 이전 구현으로 최종 경로에 남은 불완전 파일이나 사용자가 수정한 파일은 여전히 덮어쓰지 않는다. 실패한 임시 사본과 빈 staging 폴더의 자동 공간 정리는 미구현이다.

앞선 설명에서 receipt가 있으면 항상 중단한다고 한 부분은 보완됐다. PREPARED/COPYING 기록과 같은 배포물의 ResumeIncomplete에 한해 기존 receipt의 제품/버전/아키텍처/출처/서명자/파일 목록 및 모든 최종 파일을 다시 대조한다. 모두 일치하면 receipt를 교체하지 않고 진행 기록만 완료 상태로 갱신한다. receipt가 있는데 파일이나 부모 디렉터리가 없거나 내용이 다르면 중단한다. 완료된 설치를 임의 수리·재활성화하는 경로는 아니다.

임시 파일 확인 후 handle을 닫고 Move하므로 그 사이 외부 변경 가능성이 있으며 게시 후 재확인이 실패하면 해당 파일을 자동 삭제하지 않는다. 상위 경로/receipt 동시 변경, 전원 차단 내구성, 공간 회수와 실제 Windows 실행 검증은 남아 있다. 현재 구현·문서 작성만 수행했으며 설치/서명/복사 실행은 하지 않았다.

## 배포에 포함되는 설치 도구

New-CodexBarDistributionManifest.ps1은 이제 tools 아래에 Install-CodexBarVersion, Select-CodexBarVersion, Restore-CodexBarActivation, Remove-CodexBarVersion, Restore-CodexBarRemovedVersion, Write-CodexBarJournal, Read-CodexBarBuildProvenance, Read-CodexBarFirstPartyFiles의 8개 ps1 파일을 추가한다. 파일은 producer와 같은 소스 폴더에서 가져온다. 사용자가 ResourceDirectories로 같은 tools 목적지를 중복 제공하면 거절한다.

Read-CodexBarFirstPartyFiles.ps1이 앱·CLI·단일 PATH resource·8개 tools의 필수 목록과 분류를 정의한다. manifest 생성/배포 조립/서명 요청/실제 서명/설치가 이 계약을 사용하며 모든 first-party 대상이 서명 대상으로 포함된다. 따라서 이전 문서의 정확히 3개 대상이라는 설명은 과거 단계다. 새 계약은 11개 대상을 요구하며 기존 인벤토리·서명 요청은 새로 생성해야 한다. 타사 파일은 여전히 원래 서명을 보존한다.

배포물의 tools만으로 설치/선택/제거/복구 helper 상대 경로를 찾을 수 있도록 작성했지만 실제 설치된 앱 목록 등록과 안전한 제거 invocation은 아직 연결하지 않았다. 서명된 installer를 처음 실행하기 전의 신뢰 확인과 PowerShell 실행 정책은 이 계약만으로 해결되지 않으며, 도구 실행·서명·설치/제거 상호작용은 미검증이다. 현재 패키징 및 실제 서명 명령은 실행하지 않았다.

## 개발 설치의 앱 목록 등록

Register-CodexBarInstallation.ps1은 VersionID, ExpectedSignerThumbprint, AllowUnvalidatedBuild를 받는다. 설치 receipt의 tool hash와 서명을 대조한 독립 사본을 install root의 management-ID에 두고, 현재 사용자 Registry64의 Software/Microsoft/Windows/CurrentVersion/Uninstall/CodexBarWindows-<VersionID>를 작성한다. 표시 이름에는 development를 넣는다. 기존 항목을 덮어쓰지 않으며 생성 도중 실패한 관리 사본과 registry 상태는 보존한다. 준비/완료 기록은 management 폴더의 registration.json이다.

제거 명령은 시스템 PowerShell의 -NoProfile -STA -ExecutionPolicy AllSigned -File과 명시적 VersionID/RegistrationID를 사용한다. Invoke-CodexBarUninstall.ps1은 기본 No인 확인 창 뒤 기존 제거 도구를 호출하고, receipt 파일 전부가 retire된 경우에만 같은 등록 ID/설치 위치의 항목을 해제한다. 추가 registry 데이터나 소유권 불일치는 보존한다. 수정 파일로 부분 제거가 됐거나 시작 메뉴/PATH/startup/프로세스 참조가 남았다면 오류를 표시하며 등록을 유지한다. 관리 도구와 복구 사본/사용자 설정은 삭제하지 않는다.

이 두 스크립트 추가로 필수 tools는 10개, 전체 first-party 서명 대상은 13개다. 이전 8개/11개 설명은 과거 단계다. 실제 앱 목록 노출, WinForms 창, 스크립트 실행 정책/인증서 신뢰, 레지스트리 쓰기/삭제, 제거 실행은 하지 않았다. registry 작업은 전체 transaction이 아니며 외부 쓰기와 생성/비교/삭제 사이 race가 남아 있다. 부분 등록 복구와 자동 참조 migration, 관리 사본 공간 정리도 남아 있다.

등록 필드의 참고 자료: [Microsoft의 Uninstall registry 필드 문서](https://learn.microsoft.com/en-us/windows/win32/msi/uninstall-registry-key), [NoModify 설명](https://learn.microsoft.com/en-us/windows/win32/msi/arpnomodify). 이 자료의 MSI 설명만으로 사용자별 비-MSI 스크립트의 실제 Windows 동작이 검증된 것은 아니다.

## 앱 등록 재개

Register-CodexBarInstallation.ps1의 ResumeRegistrationID에 management 폴더명에 있는 32자리 ID를 지정하면 같은 VersionID·ExpectedSignerThumbprint·설치 receipt 해시에 결합된 schema 2 기록을 재사용한다. AllowUnvalidatedBuild는 여전히 필요하다. 새 기록은 관리 도구를 복사하기 전에 PREPARING_TOOLS로 저장하므로 복사 중단 후 일치한 파일을 재사용하고 없는 파일만 추가할 수 있다. 일부만 복사된 파일은 덮어쓰지 않으며 hash 불일치로 중단한다.

등록 key가 있으면 같은 CodexBarRegistrationID를 요구한다. 기존 허용 값은 자료형과 내용까지 일치해야 하며 다른 값이나 하위 key/추가 데이터가 있으면 중단한다. 일치한 값은 다시 쓰지 않고 누락된 값만 채운다. 마지막 journal 저장이 끊겼어도 동일한 완성 등록을 확인한 뒤 완료 상태를 기록할 수 있다. 기존 command와 새로 계산한 command가 다르면 자동 경로 변경을 하지 않는다.

schema 1 기록, 소유권 값이 없는 빈 registry key, 기록 없는 management 폴더를 자동 인수하지 않는다. registry 값 대조와 쓰기는 atomic compare-and-set이 아니며 외부 변경 race가 남아 있다. 관리 폴더/receipt의 동시 변경, legacy 복구·손상 tool 수리·공간 정리·Windows 실행 검증도 남아 있다. 이전 절의 기존 등록 무조건 거절 설명은 이 명시적 재개 옵션에 한해 보완됐다.

## 버전 참조 전환과 제거 전 해제

Set-CodexBarVersionReferences.ps1은 FromVersionID와 AllowUnvalidatedBuild를 받는다. ToVersionID와 ExpectedSignerThumbprint를 함께 지정하면 그 버전의 앱/CLI hash·서명을 확인하고 기존 참조를 새 버전으로 전환한다. 목적 버전을 생략하면 기존 참조를 해제한다. 대상은 literal 사용자 PATH 항목, 정확히 따옴표로 감싼 CodexBarWindows Run 명령, arguments 없는 해당 버전의 CodexBar Windows.lnk다. 활성화되지 않은 참조를 새로 만들지 않는다.

PATH의 관련 없는 원문 항목과 String/ExpandString 형식을 유지한다. 사용자 정의 startup command와 shortcut arguments는 거절한다. 변경 전 references-ID.json과 시작 메뉴의 references.previous.lnk backup을 남기며 여러 쓰기는 순차 적용한다. 실패하면 앞선 변경은 이미 적용됐을 수 있다. journal에는 로컬 PATH가 포함되므로 외부 공유 자료로 취급하지 않는다.

제거 확인창은 이제 known user references 해제를 안내하고 동의 후 이 helper를 먼저 호출한다. 현재 PowerShell PATH도 갱신하지만 이미 실행 중인 다른 프로세스의 환경은 바뀌지 않는다. 머신 PATH/간접 표현/다른 startup 항목과 살아 있는 프로세스는 제거 단계에서 계속 차단될 수 있다. 제거 실패 후 자동 참조 rollback 및 전체 환경 변경 broadcast는 미구현이다.

필수 tools는 이 helper 포함 11개, first-party 서명 대상은 14개로 확대됐다. 앞선 대상 개수는 과거 기록이다. 자동 복구, 다중 쓰기의 원자성, 외부 동시 변경, 보존 backup 정리, 실제 Windows/COM/registry/서명/UI 동작은 미검증이며 이번 작업에서 실행하지 않았다.

## 참조 전환 복구

Restore-CodexBarVersionReferences.ps1은 references 파일명의 TransactionID, 원래 버전의 ExpectedSignerThumbprint, AllowUnvalidatedBuild를 받는다. schema 2 전환 기록만 받으며 원래 버전의 receipt와 앱/CLI hash·서명이 맞아야 한다. 제거된 payload의 복원은 Restore-CodexBarRemovedVersion으로 먼저 처리한다. reference 복구가 payload 파일을 복사하거나 앱을 실행하지는 않는다.

PATH·Run 명령·shortcut은 before와 같으면 이미 복원된 것으로 두고 after와 같은 항목만 되돌린다. 값 자료형 변경·외부 수정·backup 누락/해시 불일치 시 쓰기 전 중단한다. 쓰기 직전에도 현재 값을 다시 비교하지만 비교와 쓰기가 단일 원자적 동작은 아니다. 바로가기 복구는 원래 backup을 유지하고 현재 링크를 별도 displaced 파일로 보존한다. PATH는 사용자 영구 값만 복원하며 다른 셸의 상속 환경을 되감지 않는다.

전환 스크립트도 이제 changePath/changeRun과 교체 전 shortcutNewHash를 기록한다. schema 1 기록은 안전한 자동 복구 경계가 부족해 수용하지 않는다. 필수 tools는 12개, 전체 first-party 서명 대상은 15개다. 환경 변경 통지·자동 lifecycle 복구 안내/호출·기록 신뢰 및 동시 변경 대응·보존 파일 정리·Windows 실행 검증은 남아 있다. 이번 작업에서 스크립트나 복구를 실행하지 않았다.

## 환경 변경 통지 및 복구 순서

참조 전환/복구의 사용자 PATH 쓰기 직후 Send-CodexBarEnvironmentChange를 호출하고 environmentNotification 상태를 journal에 저장한다. SENT_REFRESH_NOT_GUARANTEED는 통지 호출 성공, FAILED_OR_TIMED_OUT/UNAVAILABLE_OR_FAILED는 통지 미확인이다. 통지 실패가 PATH 쓰기 실패나 자동 rollback을 뜻하지 않는다. 기존 프로세스의 환경은 그대로일 수 있으며 통지가 확인되지 않으면 로그아웃/로그인 후 새 환경을 상속한다.

구현은 [WM_SETTINGCHANGE의 Environment 안내](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-settingchange)에 따라 동기 SendMessageTimeoutW를 사용한다. 타임아웃 100ms는 수신 창별 값으로 전체 시간 상한이 아니다. 정책이 Add-Type/native call을 막으면 통지 실패 상태를 반환한다. C# interop 코드의 실제 컴파일/호출은 하지 않았다. 필수 tools 13개와 앱·CLI·PATH resource를 합한 서명 대상은 16개다.

복구 시 어떤 단계가 이미 적용됐는지를 먼저 구분한다. 제거 payload가 일부 이동했다면 removed-ID 사본을 해당 제거 복구 도구로 먼저 복원하고, 이후 references-ID를 참조 복구 도구에 전달한다. 참조 복구는 원래 앱/CLI와 서명자를 요구하므로 순서를 뒤집으면 거절될 수 있다. registry 등록 복구에는 management-ID와 동일 receipt/signer가 필요하다. 각 도구는 기존 충돌 값을 덮어쓰지 않으며 자동 전체 rollback이나 일반 배포 완료를 의미하지 않는다. 현재 작업에서는 어떤 복구/통지/registry 명령도 실행하지 않았다.

## 제거 실패 시 복구 정보

제거 launcher는 확인 후 management 폴더의 uninstall-ID.json에 실행 단계를 기록한다. 참조 변경 도구의 PassThru 결과와 기존 제거 결과를 받아 referenceTransactionID/removalTransactionID를 연결하고 등록 해제 전에도 단계를 저장한다. 성공한 통지 여부는 environmentNotification으로 별도 남긴다.

도구가 도중에 예외를 내면 생성된 transaction ID를 Exception.Data로 전달한다. launcher는 최대 8단계 exception chain에서 32자리 ID만 받아 오류창에 표시한다. 파일이 이동했다면 제거 payload를 먼저 복구하고 원래 앱/CLI와 signer가 준비된 뒤 참조를 복원하도록 안내한다. 관리 ID는 앱 등록 복구에 사용한다. 자동 rollback을 실행하지 않는다.

최종 오류 기록 저장까지 실패하면 원래 오류와 화면 ID를 유지하고 저장 실패 사실을 안내한다. ID가 생성됐다고 반드시 journal/backup이 생성된 것은 아니며 강제 종료 시 caller 기록보다 실제 child 파일 변경이 앞설 수 있다. 실제 두 폴더와 registry 상태가 우선이다. 이번 작업에서는 WinForms UI·PowerShell 예외 전달·journal 쓰기·설치/제거를 실행하지 않았다.

## 실행 전 복구 ID 예약

제거 launcher의 schema 2 handoff는 참조 변경과 파일 제거 ID를 PLANNED 상태로 먼저 기록한 뒤 각 도구의 OperationID 인자로 전달한다. 하위 작업이 변경 뒤 결과를 반환하기 전에 종료되더라도 caller 기록의 ID로 references-ID.json 또는 removed-ID 폴더를 찾을 수 있게 작성했다. 반환 ID가 다르면 완료 결과를 수용하지 않는다.

OperationID는 선택적 새 작업 식별자다. 기존 작업의 재개/복구를 요청하는 인자가 아니며 같은 ID의 journal/바로가기 작업 파일/제거 디렉터리가 이미 있으면 거절한다. 생략하면 기존처럼 새 GUID를 만든다. 강제 종료 시 PLANNED로만 남아 있어도 실제 변경은 있을 수 있고, 예약만 하고 호출 전에 멈췄다면 해당 파일이 없을 수 있다. 실제 상태를 자동으로 추정해 성공 처리하지 않는다.

외부 변경과 경로 검사 사이 race, journal/파일 변경의 완전한 원자성, 통합 복구 실행과 강제 종료 검증은 남아 있다. 이번 작업에서 관련 스크립트나 종료 시나리오를 실행하지 않았다.

## 제거 기록으로 복구 실행

Restore-CodexBarUninstall.ps1에 RegistrationID, uninstall 파일명의 UninstallID, 원래 ExpectedSignerThumbprint, AllowUnvalidatedBuild를 지정하면 연결된 제거 payload를 먼저 복구하고 전체 복원 결과일 때만 참조 복구를 호출한다. 기존 파일 충돌로 부분 복구되면 다음 단계로 넘어가지 않는다. 작업은 명시적 실행이며 앱을 자동 실행하지 않는다.

schema 2 handoff의 버전과 child record를 대조하며 완료 결과가 있는데 해당 기록이 없으면 거절한다. PLANNED 상태에 실제 child 기록이 없으면 NO_CHILD_RECORDS_FOUND 등 실제 발견 범위만 기록한다. 이는 변경이 전혀 없었다는 증명이 아니다. 별도 uninstall-recovery journal에 현재 단계를 남기며 Apps 등록은 변경하지 않는다.

도구별 operations.lock은 사용하지만 전체 복구를 포괄하는 잠금은 아직 없다. 외부 동시 변경/기록 누락 원인 판별/앱 등록 복구 통합/자동 정리/Windows 검증은 남아 있다. tools 14개와 앱·CLI·PATH resource를 합한 서명 대상은 17개다. 이번 작업에서 복구나 검증 명령을 실행하지 않았다.

## 앱 등록까지 복원하는 옵션

Restore-CodexBarUninstall.ps1의 RestoreRegistration 옵션은 파일과 참조 복구 후 같은 management 등록 기록을 재사용해 Apps 항목까지 복원하도록 작성됐다. 기본값은 미지정이며 기존처럼 파일·참조만 처리한다. 등록 기록의 schema/ID/버전/signer를 먼저 대조하고, 이전 단계의 구조화된 완료 결과가 맞을 때만 등록 단계를 호출한다. 등록 정보가 변경되면 기존 등록 재개 규칙대로 충돌을 보존한다.

Register-CodexBarInstallation은 이제 관리 tools뿐 아니라 실제 앱·CLI의 크기/hash/서명/timestamp를 확인하고 파일 handle을 작업 종료까지 유지한다. 앱 파일이 없거나 바뀐 상태를 관리 사본만으로 등록하지 않는다. 전체 runtime DLL/resource 정상 동작이나 실제 설치 적합성까지 증명하는 것은 아니다.

복구 기록에 RESTORING_REGISTRATION 및 registrationState를 남긴다. 단계별 파일 잠금은 있으나 전체 단계를 하나의 transaction으로 만들지는 않으며 단계 사이 동시 변경은 남아 있다. 이번 작업에서는 등록·복원·서명 확인·PowerShell·빌드·테스트를 실행하지 않았다.

## IMPL-542: 위젯 host 전체 payload 입력

New-CodexBarDistributionManifest.ps1에 WidgetHostEXE와 WidgetHostBuildReceipt 입력을 추가했다. 둘을 함께 지정하고 WidgetBackendDLL/WidgetBackendBuildReceipt도 제공해야 한다. host는 Release 및 같은 architecture의 schemaVersion 2 receipt를 요구하고, backend는 기존 schemaVersion 1을 사용한다. host receipt는 exe byte identity와 caller policy/packages.config hash, self-contained component 배포 방식 및 전체 payload를 기술한다. 서명된 빌드 증거는 아니다.

입력 생성기는 명시적으로 선택한 host exe의 디렉터리에서 payload 상대 경로를 해석한다. EXE·runtime DLL·WinMD·manifest/resource·NuGet 라이선스를 종류별로 포함하며 DLL에는 기존 PE/의존성 경로를 적용한다. receipt 내부 절대 경로를 복사 대상으로 사용하지 않는다. host가 들어간 입력 JSON에는 widgetHostPayload가 필수이며, input manifest 최대 크기도 조립기의 4 MiB 제한에 맞춘다. 일반 앱/CLI/Swift runtime/resource/license 입력은 별도로 필요하며 payload 파일을 중복해서 넣지 않는다.

Read-CodexBarWidgetPayload.ps1은 빌드 및 배포 입력을 위한 공유 helper다. 최대 4096개 파일·파일당 512 MiB·상대 경로 및 hash 형식·종류·필수 host/Widgets DLL/WinMD/3개 라이선스를 요구한다. 알 수 없는 산출물과 누락을 자동으로 무시하지 않는다. 이 helper는 설치된 프로그램의 lifecycle tool 목록에 추가할 필요가 없는 빌드/조립 전용 코드다.

조립기는 payload 전체의 포함/종류를 대조하고 실제 복사 후 열린 파일의 bytes/hash가 build receipt와 같을 때만 최종 inventory에 COPIED_BYTES_MATCH_LOCAL_BUILD_RECORD를 기록한다. 변경이나 누락이 있으면 성공 inventory를 남기지 않으며 부분 출력은 보존한다. 이 상태는 실행 가능성이나 등록 성공의 증거가 아니다. 기존 source 경로/파일 경합과 Windows 동작 경계도 계속 미검증이다.

CodexBarWidgetHost.exe는 backend를 동반한 유일한 root first-party application으로 서명 대상에 포함된다. 따라서 기본 17개 대상에 widget backend와 host가 함께 있으면 first-party 대상은 19개다. 서명 요청·서명·설치에서 기존 공유 first-party 판정을 사용하며 서명 후 hash는 실제 서명된 파일로 다시 기록한다. 사전 서명 payload hash 목록을 최종 inventory의 서명 후 파일 계약으로 재사용하지 않는다.

현재 widget 구성 요소 입력은 명시적으로 선택하는 단계다. MSIX package identity·COM/6종 위젯 및 proxy/stub 선언·OS cold activation·확인된 broker 정책과 실제 Windows 배포는 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 이 변경에서 스크립트·빌드·복사·서명·설치·검증은 실행하지 않았다.

## IMPL-545: MSIX manifest 생성

New-CodexBarMSIXManifest.ps1은 기존 distribution inventory와 명시적 configuration에서 AppxManifest.xml을 새 파일로 작성하도록 추가했다. 앱 entry point, native host COM class, 6종 위젯 ID/크기·다중 인스턴스·customization, 실제 SDK proxy/stub 및 runtime class 선언을 연결한다. 참조 파일의 kind/bytes/hash와 고정된 SDK fragment를 대조하고, script 실행 종료까지 해당 읽기 handle을 보관한다.

[입력/등록 계약](MSIX-MANIFEST.ko.md)과 [configuration 예제](MSIX-configuration.example.json)에 발행자·버전·OS·리소스·이미지 필드를 기록했다. MSIX 이미지를 자동 생성하거나 placeholder를 정상 산출물로 처리하지 않는다. 기존 출력은 덮어쓰지 않으며 MakeAppx/MakePri·서명·등록·설치는 다음 연결이다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 이번 작업에서는 새 생성기나 검증을 실행하지 않았다.


## 인벤토리 기반 MSIX 패키지 생성

New-CodexBarMSIXPackage.ps1은 같은 배포/configuration으로 새 manifest를 작성하고 모든 인벤토리 파일을 명시적 mapping에 넣어 선택한 SDK MakeAppx에 전달하도록 구현했다. /no로 덮어쓰기를 거절하고 기본 SDK 검사는 유지한다. package/receipt는 새 출력 디렉터리에만 작성하며 실패 출력은 보존한다. 자세한 입력·파일 연결·상태·미구현 경계는 [MSIX 패키지 계약](MSIX-PACKAGE.ko.md)을 따른다.

receipt의 PACKAGED_UNSIGNED_RUNTIME_UNVERIFIED는 나중에 Windows 명령이 성공했을 때 기록하는 상태다. 현재는 CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION이며 스크립트·SDK·빌드·테스트·서명·설치·실행 검증을 하지 않았다. 실제 리소스/PRI, package 서명/설치/업데이트/제거 및 Windows 제품 전체의 검증은 남아 있다.


## MSIX 컨테이너 서명 인계

Read-CodexBarMSIXBuild는 실제 unsigned package와 로컬 build receipt, embedded manifest/Publisher 및 SHA256 block map을 연결한다. New-CodexBarMSIXSigningRequest는 이 값들로 새 요청을 작성하며, Sign-CodexBarMSIXPackage는 같은 바이트를 다시 대조한 뒤 선택한 CurrentUser/My 인증서로 새 사본만 서명하도록 구현했다. 내부 바이너리 서명과 MSIX 서명은 별개이며, 실제 실행하지 않았다.

입력/WhatIf/출력 보존/SDK 옵션/서명 후 기록 및 미검증 경계는 [MSIX 서명 인계](MSIX-SIGNING.ko.md)를 따른다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. SDK·인증서·timestamp 서비스·서명·설치·검증 실행은 하지 않았고, Windows 제품 전체의 설치/update/기능 검증과 릴리스 판단은 남아 있다.


## 현재 사용자 MSIX 개발 설치·업데이트

Install-CodexBarMSIXPackage.ps1에 signed MSIX/receipt/expected signer를 받아 Windows Appx로 현재 사용자에게 설치·업데이트하는 코드를 추가했다. 공유 metadata reader와 현재 OS 서명 신뢰 확인을 사용하고, Update는 정확한 기존 full name 및 더 높은 버전을 요구한다. SDK는 필요하지 않으며 runtime-unverified 산출물에는 AllowUnvalidatedBuild가 필요하다.

잠금·새 출력·단계 journal과 실제 등록 관측 뒤의 receipt를 연결했고, 자동 강제 종료/강등/제거/rollback은 수행하지 않는다. 자세한 future invocation과 경계는 [MSIX 설치 계약](MSIX-INSTALLATION.ko.md)을 따른다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION이며 설치/업데이트·PowerShell·signature/Appx·빌드·테스트·Windows 실행 검증은 하지 않았다.


## MSIX 중단 작업 기록 조정·명시 재개

Resume-CodexBarMSIXDeployment.ps1은 정확한 작업 ID·현재 user·같은 signed 입력에 결합한 기존 기록과 Windows 등록을 대조하도록 작성했다. target이 등록됐으면 Add-AppxPackage 재호출 없이 receipt를 재사용/새로 게시하고 journal을 조정한다. 원래 상태일 때 다시 제출하려면 RetryIfUnchanged를 명시해야 한다. 설치와 재개가 공유 helper를 사용하며 새 receipt는 CreateOnly로 기존 파일을 보존한다.

[MSIX 재개 계약](MSIX-RECOVERY.ko.md)에 상태별 동작, future invocation과 손상 기록/동시 변경/중단 경계를 기록했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 실제 PowerShell·서명·Appx·설치/재개·빌드·테스트·Windows 실행 검증은 하지 않았다.


## 현재 사용자 MSIX 제거

Remove-CodexBarMSIXPackage.ps1은 설치 receipt·명시적 full name과 현재 Windows 등록을 대조해 해당 사용자 package 하나만 제거하도록 작성했다. 일반 signed MSIX에서 PreserveApplicationData로 보존을 보장하지 않고 패키지 데이터 제거에 대한 명시적 선택을 요구한다. 별도 외부 데이터 purge를 추가하지 않았으며 backup은 생성하지 않는다.

[MSIX 제거 계약](MSIX-REMOVAL.ko.md)에 future invocation과 target/데이터/기록/중단 경계를 기록했다. 결과는 current-user main registration 부재의 관측 범위이며 데이터 삭제/보존이나 Windows 제품 완료 증거가 아니다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 실제 제거·삭제·PowerShell·Appx·빌드·테스트·Windows 실행 검증은 하지 않았다.


## MSIX 제거 중단 기록 조정·명시 재시도

Resume-CodexBarMSIXRemoval.ps1은 같은 설치 receipt·user·operation·full name을 현재 등록과 대조한다. 이미 등록이 없으면 Windows 제거 없이 receipt/journal을 조정하고, 원래 target이 그대로인 경우 두 명시적 재시도·데이터 제거 선택이 있어야 다시 제출하도록 작성했다. 부재 관측 뒤 재등장하거나 target/기록이 달라진 경우 자동 제거하지 않는다.

최초 제거와 재개는 공유 helper로 target/data policy/receipt 생성·대조를 통일했다. 자세한 future invocation과 경계는 [MSIX 제거 재개 계약](MSIX-REMOVAL-RECOVERY.ko.md)을 따른다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 실제 PowerShell·Appx·제거/재개·데이터 삭제·빌드·테스트·Windows 실행 검증은 하지 않았다.
