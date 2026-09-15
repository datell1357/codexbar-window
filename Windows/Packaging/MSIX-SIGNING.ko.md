# MSIX 패키지 서명 인계

상태: CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 아래 스크립트는 Windows에서 나중에 실행할 구현이며 현재 작업에서는 PowerShell, package/XML 평가, SDK, 인증서 저장소 접근, 서명·timestamp 요청, 테스트, 설치·앱 실행을 하지 않았다.

MSIX 컨테이너는 개별 EXE/DLL 서명과 별도로 서명한다. [패키지 생성기](MSIX-PACKAGE.ko.md)가 만든 정확한 unsigned MSIX와 receipt에서 요청을 만들고, 서명 직전에 다시 같은 바이트를 읽는 구조다. 기존 distribution 서명 요청은 MSIX 서명 요청으로 사용할 수 없다.

## 요청 생성

`New-CodexBarMSIXSigningRequest.ps1`은 PackageDirectory와 OutputRequest를 받는다. PackageDirectory에는 `CodexBarWindows.msix`, `package-build-receipt.json`이 있어야 한다. 요청은 이 폴더 밖에 새 JSON 파일로 기록하며 기존 파일은 덮어쓰지 않는다.

```powershell
.\New-CodexBarMSIXSigningRequest.ps1 `
    -PackageDirectory C:\Artifacts\CodexBar-msix-unsigned `
    -OutputRequest C:\Requests\codexbar-msix-signing.json `
    -WhatIf
```

공유 `Read-CodexBarMSIXBuild.ps1`은 schema 1의 PACKAGED_UNSIGNED_RUNTIME_UNVERIFIED receipt와 실제 MSIX의 크기·SHA-256을 대조한다. 로컬 드라이브의 regular 경로만 받으며 관측한 reparse와 별도 bundle/이미 서명된 입력은 거절하도록 작성했다. source provenance는 기존 DECLARED_NOT_ATTESTED 계약을 유지한다.

외부 AppxManifest.xml이나 configuration을 다시 신뢰하는 대신 MSIX 안의 manifest를 읽는다. 그 바이트 hash가 빌드 receipt와 같은지 대조하고 Identity의 name/publisher/version/architecture를 요청에 연결한다. BlockMap의 hash method가 SHA256 계약인지도 읽는다. 패키지를 추출하거나 앱/DLL을 실행하지 않는다. XML DTD와 외부 resolver를 끄고, archive 10,010개 항목·manifest 1 MiB·block map 32 MiB 및 실제 확장 바이트 수를 제한한다. 전체 SDK package validator를 구현한 것은 아니다.

요청 상태는 MSIX_SIGNING_REQUEST_ONLY다. package/receipt/embedded manifest/block map/source inventory hash와 identity를 포함하며 인증서나 private key에는 접근하지 않는다. 로컬 입력 절대 경로를 요청에 넣지 않는다. `-WhatIf`는 읽기와 바이트 대조 후 쓰기 전에 반환한다. helper에서 연 stream은 호출자가 성공·실패 모두 finally에서 닫는 계약이다.

## 선택한 인증서로 새 사본 서명

`Sign-CodexBarMSIXPackage.ps1`은 다음 입력을 요구한다. 아래 placeholder는 실제 Windows에서 준비한 SDK 경로와 인증서 thumbprint, timestamp 서비스로 교체해야 한다.

```powershell
.\Sign-CodexBarMSIXPackage.ps1 `
    -PackageDirectory C:\Artifacts\CodexBar-msix-unsigned `
    -SigningRequest C:\Requests\codexbar-msix-signing.json `
    -SignToolPath 'C:\Program Files (x86)\Windows Kits\10\bin\<SDK version>\x64\signtool.exe' `
    -CertificateThumbprint '<40 hexadecimal characters>' `
    -TimestampServer '<RFC 3161 HTTP(S) service URL>' `
    -OutputDirectory C:\Artifacts\CodexBar-msix-signed-new `
    -WhatIf
```

서명기는 같은 helper로 unsigned package를 다시 읽고 요청의 package/receipt/manifest/block map/source inventory hash, identity, provenance와 선택 정책을 대조하도록 작성했다. `-WhatIf`는 certificate/private-key 접근, SDK 실행, 출력 생성보다 먼저 멈춘다. 실제 서명 실행의 승인 범위는 별도이며 현재 macOS 구현 작업의 권한이 아니다.

명시한 CurrentUser/My 인증서만 선택하고 private key·code-signing EKU·현재 유효 기간을 요구한다. 인증서 Subject 텍스트와 embedded manifest Publisher를 대소문자까지 정확하게 비교하며 manifest를 서명 단계에서 다시 쓰지 않는다. 따라서 configuration 작성 시 실제 선택할 인증서의 Subject 표현을 사용해야 한다. 이 구현은 DN 순서를 바꾸거나 동등한 다른 문자열 표현을 자동 수용하지 않는다. 발행자와 인증서 subject의 일치 요구는 [Microsoft package certificate 문서](https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing)에 근거한다.

출력 디렉터리는 존재하지 않아야 하고 unsigned 디렉터리 밖이어야 한다. 열린 원본 stream에서 새 파일로 복사하고 그 크기/hash를 대조한 뒤에만 서명 도구를 부른다. 원본 및 실패한 출력은 삭제·덮어쓰기하지 않는다. 인증서 자동 선택, machine store fallback, PFX/password 인자를 추가하지 않았다. timestamp URL은 HTTP(S)이며 userinfo/query/fragment는 받지 않는다.

명령은 `sign /fd SHA256 /s My /sha1 <thumbprint> /tr <service> /td SHA256 <copy>`다. package hash algorithm과 SignTool digest를 일치시키는 요구는 [Microsoft MSIX signing 문서](https://learn.microsoft.com/en-us/windows/msix/package/sign-app-package-using-signtool)를 따른다. 이어 `verify /pa /all /tw`를 실행하고 두 명령 모두 exit code 0을 요구한다. warning을 성공으로 승격하지 않는다. 옵션 의미는 [SignTool reference](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool)를 참고했다.

서명 후 파일을 FileShare.Read로 열어 유지하고, Get-AuthenticodeSignature의 Valid 상태·선택한 signer thumbprint·timestamp certificate를 요구하도록 작성했다. archive의 signature footprint와 변경되지 않은 manifest/block map을 추가로 읽은 후 실제 signed package hash를 기록한다. 이는 구현된 future Windows 검사 경로이며 이 작업에서 검사 성공을 확인했다는 뜻이 아니다.

완료 기록은 새 `package-signing-receipt.json`이며 상태는 SIGNED_MSIX_RUNTIME_UNVERIFIED다. 서명 전/후 파일 hash, 요청/빌드 receipt hash, identity/provenance, signer/timestamp signer thumbprint, SDK hash·종료 코드를 보관한다. installation/runtimeValidation은 NOT_RUN으로 유지한다. timestamp digest 필드는 요청한 알고리즘을 뜻하며 별도 ASN.1 해석 결과로 표시하지 않는다.

## 남은 경계

각 파일의 held handle은 일반적인 Windows 공유 규칙에 따라 바이트 변경을 제한하지만 상위 디렉터리 변경을 막는 전체 transaction은 아니다. 복사 후 SDK가 쓸 수 있도록 handle을 닫는 구간, 출력 경로 교체·외부 writer, PKI trust/revocation·timestamp 실패/취소, PowerShell의 MSIX SIP 지원, 실제 SDK·x64/ARM64 동작은 미검증이다. 일부 signature/receipt가 남은 실패는 자동 재개하지 않는다.

receipt와 hash는 로컬 바이트 연결이며 빌드 attestation이나 배포 승인 증거가 아니다. STAGED 입력을 container-signing했다고 내부 first-party 파일의 개별 서명·의존성 완전성이 보장되지는 않는다. 실제 이미지·locale/PRI, package identity 정책, 설치·업데이트·제거·COM/Widgets activation 및 Windows 제품 전체 검증은 계속 필요하다. 현재 작업은 인증서 생성/설치, private key 사용, 인증서 신뢰 변경, Store 제출이나 릴리스를 수행하지 않았다.
