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
