# Windows 로컬 설정 묶음 백업과 복원

IMPL-554에서 설정 파일, `CodexBar.Windows` persistent preferences, 위젯 설정을 묶는 코드와 명령을 작성했다. 상태는 **CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION**이다. 명령·DPAPI·Foundation preferences·파일 공유/권한·빌드·테스트·Windows 실행을 현재 작업에서 수행하지 않았다.

## 포함하는 저장소

| 저장소 | 백업/복원 계약 |
| --- | --- |
| 선택된 config | `CodexBarConfigStore.defaultURL()`의 기존 환경변수/기본 경로 선택을 사용한다. 없는 파일은 없다는 상태로 보존한다. 기존 파일은 읽기/형식/보호 실패를 부재로 바꾸지 않는다. |
| `CodexBar.Windows` preferences | persistent domain만 binary property list로 보존한다. 표시·언어·알림·로컬 경로·동의 상태 등과 unknown 저장 키를 포함한다. argument/registration domain이나 다른 앱의 `.standard` 설정을 합치지 않는다. |
| `WindowsWidgets/settings.json` | 선택된 config 파일의 부모를 기준으로 앱 runtime과 같은 `defaultURL(configFileURL:)` helper를 사용한다. 알려진 schema/인스턴스 조건을 읽고 원본 JSON 바이트를 보존한다. |

사용량·비용 이력, plugin 파일/승인/캐시, Credential Manager, 외부 CLI·browser·editor의 계정 파일은 이번 묶음에 포함하지 않는다. Windows가 관리하는 위젯 배치·instance 등록도 복구하지 않는다. 저장한 instance ID를 새 Windows 등록으로 임의 바꾸지 않으며 실제 widget inventory와의 조정은 기존 runtime 경로가 담당한다. 전체 앱 데이터 백업이나 W15 장치 간 동기화가 완료된 상태가 아니다.

로컬 복구이므로 동기화에서 제외되는 로컬 경로·동의/알림 상태도 그대로 보존한다. 다른 장치에 이 값을 적용하는 portable export가 아니다. config에 포함된 hook 설정 역시 보존된다. 파일을 선택해 앱을 다시 시작하면 저장된 설정이 적용될 수 있다.

## 명령 — 아래 예시는 미실행

모든 세션에서 CodexBar를 종료한 뒤 사용한다. 출력의 부모 폴더는 미리 존재해야 하며, 출력 파일/폴더는 새 경로여야 한다.

```powershell
& 'C:\Apps\CodexBar\CodexBarWindows.exe' --settings-backup-help
& 'C:\Apps\CodexBar\CodexBarWindows.exe' --settings-backup 'D:\Backups\codexbar-settings-001.cbsbak'
& 'C:\Apps\CodexBar\CodexBarWindows.exe' --settings-restore-new 'D:\Backups\codexbar-settings-001.cbsbak' 'C:\Recovered\CodexBar-001'
& 'C:\Apps\CodexBar\CodexBarWindows.exe' --settings-restore-preferences 'C:\Recovered\CodexBar-001\preferences.cbsbak' 'D:\Backups\preferences-operation-001' --replace-current-preferences
```

`--settings-backup`은 세 저장소를 하나의 current-user DPAPI archive로 보호한다. 기존 config-only archive와 별도의 magic/purpose/scope를 사용하며 두 형식을 혼동하지 않는다. 원본 config가 legacy plaintext secret이나 unknown 값을 포함해도 archive 전체에 보호가 적용된다. 복원과 같은 config secret 재보호/변환 후 파일 크기 조건을 백업 생성에도 적용한다. 원래 Windows profile/key를 잃은 상황의 독립 복구키 백업은 아니다. [Microsoft DPAPI 문서](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata)

`--settings-restore-new`는 **새 폴더에 파일을 준비**한다. 원본에 있던 config/위젯 파일만 각각 `config.json`, `WindowsWidgets/settings.json`에 저장하며 preferences는 평문 plist 대신 별도 `preferences.cbsbak`으로 보관한다. 모든 쓰기가 끝나면 `settings-materialization.json`을 CreateNew로 기록한다. 이 파일의 상태는 `FILES_MATERIALIZED_NOT_ACTIVATED`다. 설정이 자동 활성화되거나 환경변수/기존 파일/현재 preferences가 바뀌지는 않는다. config가 포함됐다면 다음 앱 실행에서 그 파일을 `CODEXBAR_CONFIG`로 명시적으로 선택한다.

`--settings-restore-preferences`는 로컬 설정 묶음 또는 preferences-only recovery archive의 값을 **현재 persistent domain에 적용**한다. `--replace-current-preferences`가 필수다. 기존 키와 unknown 값까지 domain 단위로 교체하므로 현재 값 일부만 병합하는 명령이 아니다. config/위젯 파일 복원과는 별도 작업이며 해당 파일의 활성 경로를 바꾸지 않는다.

## 환경설정 교체 전 보존과 중단 처리

환경설정 교체는 새 recovery 폴더에 다음을 먼저 쓴다.

1. `previous-preferences.cbsbak`: 교체 전 persistent preferences의 암호화 백업.
2. `target-preferences.cbsbak`: 적용할 preferences의 암호화 사본.
3. `preferences-restore-prepared.json`: operation/원본 backup ID와 준비 상태. 값/토큰은 포함하지 않는다.

이후 현재 preferences를 다시 읽어 교체 전 값과 다르면 중단한다. 두 값이 이미 같으면 per-key 교체를 생략한다. 교체를 진행한 경우 synchronize 결과와 domain 재읽기 비교를 거쳐 `preferences-restore-completed.json`을 새 파일로 남기도록 작성했다. 완료 상태는 `PREFERENCES_WRITTEN_AND_READ_BACK` 또는 `PREFERENCES_ALREADY_MATCHED`이며 `runtimeValidation`은 `NOT_RUN`이다. 실제 실행/로그인/화면 동작을 확인했다는 상태가 아니다.

Swift Foundation의 `setPersistentDomain` 구현은 기존 key 제거와 새 값 쓰기 및 synchronize를 수행한다. 이 호출을 디스크/프로세스 간 atomic transaction으로 간주하지 않는다. [Swift Foundation UserDefaults 구현](https://github.com/swiftlang/swift-corelibs-foundation/blob/main/Sources/Foundation/UserDefaults.swift)

프로세스 중단/저장 실패에서는 preferences가 일부 또는 전부 바뀌었을 수 있다. 자동 rollback이나 성공을 추정하지 않고 recovery 폴더와 준비 기록을 보존한다. 이전 값으로 돌아가려면 그 폴더의 `previous-preferences.cbsbak`을 같은 명시적 명령에 넣고 **다른 새 recovery 폴더**를 지정한다. 이 명령 자체도 미검증이며, 중단 작업 자동 탐지·재개 GUI는 남아 있다. 실패한 새 출력 폴더를 자동 삭제하거나 덮어 재사용하지 않는다.

## 앱과 복구의 동시 실행 경계

정상 앱은 기존 per-session single-instance lock에 더해 `Runtime/profile-settings.lock`을 read/share-read로 유지한다. 설정 복구는 같은 파일의 read-write/exclusive handle을 요구한다. 같은 알려진 사용자 저장 경로를 사용하는 **이 잠금에 참여하는 버전의 앱**이 어느 세션에 있든 복구를 거절하고, 복구 중 새 앱 시작도 거절하도록 연결했다. 각 session의 기존 단일 인스턴스 조건은 유지한다. 새 lock도 기존의 사용자 DACL/empty regular single-link 파일/부모 directory pin 조건을 사용하며 파일을 삭제하지 않는다. [Microsoft 파일 공유 규칙](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew)

이 새 잠금을 모르는 이전 앱 버전, 외부 CLI/에디터, 다른 가상화 저장 경로를 사용하는 설치까지 잠긴다고 주장하지 않는다. 수집 후 config/위젯/preferences를 다시 읽어 관측 가능한 변화를 거절하지만, 외부 쓰기에 대한 전체 파일시스템/registry transaction이나 모든 ABA 변경의 탐지는 아니다. MSIX/비패키지 설치 간 실제 경로·가상화·파일 공유 동작은 검증이 남아 있다.

## 형식과 입출력 제한

archive는 64 MiB, config는 기존 32 MiB, preferences는 8 MiB, 위젯 설정은 기존 256 KiB 한도다. preferences는 property-list 값만 허용하고 깊이 32/총 노드 65,536/key 4,096 UTF-8 byte 한도로 제한한다. dictionary 순서와 무관하게 비교하며 Bool·정수·실수·문자열·Data·Date·array·dictionary를 구분한다. NSKeyedUnarchiver로 임의 객체를 실행하거나 JSON으로 변경해 Data/Date/unknown type 의미를 버리지 않는다.

config-only 명령과 공유하는 local path 검사, single input handle, 크기 제한, parent pin 및 private CreateNew writer를 사용한다. 누락과 접근 실패를 구분하고 출력 파일은 기존 파일을 덮지 않는다. 새 폴더는 호출자가 명시한 경로에만 생성하며 archive 안의 값을 출력 경로로 해석하지 않는다. 파일/폴더를 만드는 도중 실패하면 부분 출력을 보존하고 마지막 완료 기록이 없으면 완료 결과로 취급하지 않는다. 전원 차단·profile/key 유실·악의적인 동일 사용자·drive mapping 변경을 해결하는 보장은 아니다.

백업을 패키지/설치 제거 영향 밖에 보관하는 경로 확인, 나머지 저장소/credential 복원, 부분 작업의 GUI 안내·활성화, installer의 보존 선택 연결 및 Windows x64/ARM64 실제 round-trip은 남아 있다. [MSIX 제거](MSIX-REMOVAL.ko.md)의 `backup: NOT_CREATED` 정책은 아직 바꾸지 않았다. 이 명령을 작성했다는 이유로 전체 데이터 보존이나 배포 준비 완료를 선언하지 않는다.
