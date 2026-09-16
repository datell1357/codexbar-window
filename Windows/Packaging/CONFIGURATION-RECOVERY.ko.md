# Windows 설정 파일 백업과 새 파일 복원

IMPL-552에서 코드 경로를 작성하고 IMPL-553에서 백업 생성과 복원의 보호 변환 조건을 공유했다. 상태는 **CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION**이며 Windows 명령·DPAPI·파일 권한·백업/복원·빌드·테스트를 실행하지 않았다.

`CodexBarWindows.exe`는 트레이/runtime를 만들기 전에 `--config-backup`, `--config-restore-new`, `--config-backup-help`를 처리하도록 연결했다. 이 명령은 provider 조회·plugin 실행·앱 시작·설치/제거를 요청하지 않는다. 성공 메시지와 오류 코드는 실제 해당 명령이 실행될 때의 경로이며, 현재 작업에서 생성한 백업이나 복원 결과물은 없다.

## 보존하는 범위

대상은 `CodexBarConfigStore.defaultURL()`이 선택하는 **설정 파일 하나**다. `CODEXBAR_CONFIG`, `XDG_CONFIG_HOME`, 기본 Windows 앱 데이터 경로의 기존 우선순위를 사용한다. 없는 설정을 기본값으로 새로 만들지 않는다. 이 파일 안에 있는 provider 설정·token 계정/비밀 필드·hook 설정 및 알려지지 않은 확장 필드를 포함한다.

UserDefaults에 저장한 별도 표시/언어/알림 설정, 위젯 설정, 사용량·비용 이력, plugin 소스/승인/캐시, Windows Credential Manager, 외부 CLI/browser/editor 계정 파일은 포함하지 않는다. W04 전체 설정 백업이나 W15 장치 간 동기화, W16의 전체 데이터 보존 선택지가 완료된 상태가 아니다. hook 설정도 보존하므로 복원 파일을 활성화하면 그 설정이 다시 적용될 수 있다.

원래 파일 바이트를 payload에 넣고 archive 전체를 현재 사용자 DPAPI로 암호화한다. 기존 protected config뿐 아니라 legacy plaintext token이나 unknown 필드도 archive 외부에 평문으로 내보내지 않는다. provider token/cache/removal journal과 별도의 entropy 목적을 사용하며, machine-wide 보호·UI prompt·평문 fallback을 사용하지 않는다. DPAPI는 통상 원래 사용자 자격 증명과 컴퓨터에 묶이며 roaming profile 등의 예외가 있다. **Windows 재설치/프로필 삭제 또는 다른 장치로의 이관을 위한 독립적인 복구 키 백업이 아니다.** [Microsoft CryptProtectData](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata)

지원하는 config version만 허용하고 잘못된 provider ID/중복 ID, 보호된 secret 형식·복호화 실패를 거절한다. 현재 구현의 검사는 파일 구조와 보호 형식에 한정하며 모든 provider 설정의 의미·서비스 로그인 성공을 검증하지 않는다. plugin registry를 발견하거나 현재 설치된 provider 목록으로 필터링하지 않는다. 원본 바이트는 암호화 payload에 보존하고, 복원에서는 공통 보호 변환으로 알려진 비밀 필드를 새로 암호화한다. 따라서 복원 파일의 JSON 공백/키 순서와 암호문은 원본과 다를 수 있다. 모델을 고정 UI 필드로 재직렬화하거나 미래 version을 현재 version으로 낮추지 않는다.

## 호출 예시 — 미실행

출력 폴더는 미리 존재해야 한다. 아래 파일명은 모두 아직 존재하지 않는 경로를 골라야 한다.

```powershell
& 'C:\Apps\CodexBar\CodexBarWindows.exe' --config-backup-help
& 'C:\Apps\CodexBar\CodexBarWindows.exe' --config-backup 'D:\Backups\codexbar-config-001.cbbak'
& 'C:\Apps\CodexBar\CodexBarWindows.exe' --config-restore-new 'D:\Backups\codexbar-config-001.cbbak' 'C:\Recovered\codexbar-config.json'
```

복원은 새 파일 생성으로 끝나며 `CODEXBAR_CONFIG`, 기존 config, 실행 중인 앱, registry 및 credential store를 바꾸지 않는다. 실제로 사용하려면 앱을 종료하고 해당 복원 파일을 `CODEXBAR_CONFIG`로 명시적으로 선택해 다음 실행에 반영해야 한다. 다른 기존 설정 저장소를 함께 복원하거나 앱 데이터 경로 전체를 이관하지 않는다. 부분 복원 중 기존 config가 덮이는 단계나 자동 재시도/자동 활성화는 없다.

## 파일 처리 경계

백업 생성 전에도 복원과 같은 보호 변환 및 변환 후 32 MiB 상한을 적용한다. legacy plaintext config 자체는 상한 이내여도 secret 보호 후 커지거나 token 값이 보호 입력 조건에 맞지 않으면 archive 게시 전에 거절한다. archive payload에는 계속 원래 파일 바이트를 넣으며 config 원본을 이관/변경하지 않는다. 이 조건을 코드에 추가한 사실은 실제 round-trip 성공, 이후 profile/key 가용성 또는 전원 차단 복구의 검증 결과가 아니다.

설정 파일은 32 MiB, archive는 48 MiB로 제한한다. local fixed/removable drive의 절대 경로와 이미 존재하는 regular 부모 디렉터리만 받는다. UNC/device/stream 경로, traversal, 예약 파일명과 관측한 reparse point는 거절한다. 부모 디렉터리는 delete 공유 없이 열어 작업 중 이름 교체를 제한하고, 입력은 read 공유만 허용한 단일 handle에서 파일 종류·link 수·길이와 bounded 내용을 읽는다. Windows 파일 공유 규칙에 관한 경계이며 실제 OS 동작을 실행 검증한 것은 아니다. [Microsoft CreateFileW](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew)

출력은 기존 private writer의 current-user DACL, flush, 같은 폴더 staging을 사용한다. 새 `createNew` 게시 옵션은 최종 `MoveFileExW`에서 `MOVEFILE_REPLACE_EXISTING`을 사용하지 않아, 사전 확인 이후 생긴 파일도 덮지 않도록 한다. 기존 writer 호출은 기존 교체 의미를 유지한다. 입력·기존 출력은 삭제하지 않으며 writer가 실패 시 정리하는 대상은 이번 호출이 만든 임시 파일뿐이다. 전원 차단 시 남은 staging 파일의 자동 복구/정리는 이번 범위가 아니다. [Microsoft MoveFileExW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw)

백업 출력은 패키지/설치 데이터 밖의 ACL 지원 디스크에 보관해야 한다. 현재 명령은 MSIX 가상화 경로와 제거의 영향을 OS에서 대조하지 않으며, drive mapping·mount 변경·같은 사용자에 의한 악의적 조작까지 방어하는 파일시스템 transaction도 아니다. 개인 정보나 JSON/OS 원문을 오류 메시지에 출력하지 않는다. 완료 뒤 외부 프로그램이 파일을 변경하는 상황과 profile/key 유실도 별도다.

## 제거 작업과 남은 연결

[MSIX 제거](MSIX-REMOVAL.ko.md)의 `backup: NOT_CREATED` 정책은 그대로다. 설정 파일 백업 명령을 작성했다는 사실로 제거 도구가 데이터를 보존했다고 기록하거나 패키지 데이터 삭제 선택을 생략하지 않는다. 제거 도구는 이 archive를 자동 생성·확인·채택하지 않는다.

전체 저장소 인벤토리, 시점이 일치하는 다중 파일 백업, credential-store 복구 정책, 백업을 제거 영향 밖에 두는 경로 확인, 전체 설정 GUI에서 검토/선택/활성화, installer 연동 및 x64/ARM64의 실제 round-trip/실패 검증이 남아 있다. 원본 기능군과 전체 제품의 완료 판정은 계속 보류한다.
