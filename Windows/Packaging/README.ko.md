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
