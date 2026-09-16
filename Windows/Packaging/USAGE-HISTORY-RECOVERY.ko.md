# Windows 사용량 이력 보존과 복원

IMPL-555~556에서 코드 경로를 작성했다. 상태는 **CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION**이다. 백업/복원 명령, DPAPI, 파일/잠금, 빌드·테스트·Windows 실행은 현재 작업에서 수행하지 않았다.

## 보존 범위

기존 runtime과 같은 `WindowsPlanUtilizationHistoryStore.defaultDirectory` 및 `HistoricalUsageHistoryStore.defaultFileURL()`에서 다음을 읽는다.

- `plan-utilization-history/<provider-id>.json`: 기본/플러그인 공급자의 계정별·unscoped plan utilization 이력과 pair metadata.
- `usage-history.jsonl`: 학습형 pace의 live/backfill 표본.

원본 바이트를 보존하며 행을 파싱해 버리거나 날짜/계정 키를 재작성하지 않는다. unknown 필드, legacy 키, 빈 파일 및 손상된 행도 그대로 보존하는 **파일 복구 형식**이다. 이력이 실제 앱에서 유효하거나 현재 로그인 계정에 속한다는 인증이 아니다. 설정의 `CODEXBAR_CONFIG` 부모를 이력 경로라고 추정하지 않으며 현재 runtime의 실제 기본 이력 위치를 사용한다.

비용 집계의 SQLite/WAL 저장소, 외부 Codex/Claude session 로그, 웹 dashboard cache, 설정/위젯, plugin 소스/승인, OS credential store는 포함하지 않는다. SQLite는 별도 일관된 snapshot 경로가 필요하므로 database 본체만 일반 파일 복사해 완료로 처리하지 않는다. 전체 앱 데이터 백업은 아직 미완료다.

## 암호화된 디렉터리 형식

한 파일의 원본 상한은 32 MiB, 공급자 수는 1,024개와 pace 1개, 전체 원본은 512 MiB다. 한도 초과 시 잘라서 성공으로 처리하지 않는다. 이 한도를 넘는 저장소의 분할/대용량 보존은 남은 범위다.

각 파일을 따로 current-user DPAPI로 보호하여 `<entry-uuid>.cbhist`에 쓴다. payload에는 archive ID, entry ID, 종류/provider ID와 원본 바이트가 들어간다. 마지막에 별도 목적의 암호화된 `history-manifest.cbhm`을 CreateNew로 게시한다. manifest에는 원본/암호문 크기·SHA256, 종류/provider ID, 존재 상태가 들어간다. 로컬 파일명에는 원래 계정 키를 넣지 않는다. 암호화 파일은 48 MiB, manifest는 2 MiB로 제한한다.

restore는 magic/version/status, 중복 ID·provider·pace 항목, 크기·SHA256, 파일 payload와 manifest의 archive/entry/kind/provider 결합을 대조하도록 작성했다. 암호화 blob을 다른 백업의 파일로 바꾸거나 일부만 복사한 경우 완료로 처리하지 않는다. 경로는 프로그램의 고정 이름과 검토한 provider ID로 생성하며 archive의 문자열을 임의 출력 경로로 사용하지 않는다.

**폴더 전체를 보관해야 한다.** 마지막 manifest가 없으면 중단된 미완료 백업이다. 부분 출력은 자동 삭제하지 않는다. DPAPI는 기존 설정 복구와 같은 원래 Windows profile/key 제약을 가지며 별도 복구키/장치 간 이동 형식이 아니다. 설정·manifest·history chunk는 서로 다른 보호 목적을 사용한다. [Microsoft DPAPI](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata)

## 명령 예시 — 미실행

모든 세션의 CodexBar를 먼저 종료한다. 출력의 부모 폴더는 미리 존재해야 하고 출력 자체는 새 경로여야 한다.

```powershell
& 'C:\Apps\CodexBar\CodexBarWindows.exe' --history-backup-help
& 'C:\Apps\CodexBar\CodexBarWindows.exe' --history-backup 'D:\Backups\usage-history-001'
& 'C:\Apps\CodexBar\CodexBarWindows.exe' --history-restore-new 'D:\Backups\usage-history-001' 'C:\Recovered\usage-history-001'
& 'C:\Apps\CodexBar\CodexBarWindows.exe' --history-restore-missing 'D:\Backups\usage-history-001' 'D:\Backups\history-operation-001' --restore-to-current-history
```

`--history-backup`은 원본 폴더의 전체 후보를 열거하고, 파일별 암호문을 새 출력에 쓴 뒤 원본 목록/내용을 다시 대조한다. 현재 registry에 없는 plugin ID도 파일 이름 계약에 맞으면 보존한다. 일반 Windows 파일 이름의 대소문자를 canonical provider ID로 취급하되 중복 ID를 거절한다. 비어 있는 `<provider-id>.lock` coordination 파일은 데이터에 넣지 않는다. 알 수 없는 항목, 비어 있지 않은 lock, reparse point/디렉터리/읽기 실패는 조용히 건너뛰지 않는다. 예를 들어 중단된 staging 파일은 별도 처리가 필요하며 자동 삭제하지 않는다.

`--history-restore-new`는 모든 chunk를 먼저 읽어 대조한 뒤 새 폴더에만 원본 파일을 준비한다. 실제 쓰기 때도 같은 manifest에 다시 결합한다. 완료 기록은 `history-materialization.json`의 `HISTORY_FILES_MATERIALIZED_NOT_ACTIVATED`다. 앱의 활성 경로를 바꾸거나 현재 이력을 덮지 않는다.

`--history-restore-missing`은 `--restore-to-current-history`가 필수이며 현재 runtime이 읽는 위치에 파일을 게시한다. **archive에 있는 모든 대상 파일과 해당 복원 표식이 없을 때만** 시작한다. 같은 내용이거나 빈 파일이라도 이미 존재하면 교체하지 않는다. archive에 없는 다른 공급자 파일은 보존한다. 계정 병합·선택 변경·키 재귀속·기존 파일 삭제는 수행하지 않는다. IMPL-556부터 원본 파일보다 먼저 복원 표식을 게시한다. 표식이 있는 이력에는 계정 자동 이관을 적용하지 않으며, 아래 소유권 경계를 따른다. 이 명령은 ownership attestation을 제공하지 않는다.

## 복원 이력의 계정 소유권 경계

IMPL-556 이후의 새 폴더/현재 저장소 복원은 각 파일보다 먼저 `<원래 파일명>.recovery-boundary.json`을 CreateNew로 게시한다. 표식에는 archive/entry ID, 원본 SHA256, 정확한 파일명과 `EXACT_STORED_ACCOUNT_KEYS_ONLY` 정책을 넣는다. 정상적인 이력 추가로 파일 내용은 바뀔 수 있으므로 원본 hash를 매번 현재 이력 hash와 일치해야 하는 조건으로 사용하지 않는다. 새 백업은 유효한 표식을 인식하고, 이후 복원 때 같은 제한 정책을 다시 생성한다.

plan 이력은 저장된 account key가 현재 key와 정확히 일치하는 bucket만 선택한다. 복원 표식이 있으면 Codex opaque/email 별칭·unscoped 단일 계정 추론과 Claude/generic 계정 자동 이관을 생략한다. 계정을 식별하지 못하면 조회·새 표본 기록을 중단하고 안내한다. boundary가 바뀌면 read/forecast cache revision도 달라지며 저장 직전에 다시 대조한다. 이력 상세에는 제한 안내를 표시한다.

pace는 표식이 있으면 정확히 일치하는 canonical account key만 읽고 기록한다. unscoped·legacy/email 별칭을 현재 canonical owner로 추정하지 않으며 표식 변경 시 메모리 자료를 다시 읽는다. 표식이 손상되거나 읽기 불가능한 경우 일반 로컬 이력으로 낮춰 처리하지 않는다. 이 제한은 계정 연결 정책이며 parser, retention 및 best-effort 저장의 기존 의미를 모두 교체하는 것은 아니다. 원본 보존용 archive를 계속 보관해야 한다.

표식만 게시된 중단 상태도 제한을 유지하고 새 restore-missing으로 덮지 않는다. 명시적 plugin 삭제에서는 이력 파일과 표식을 모두 검토 화면에 표시하고 내용/잠금 대조 후 payload부터 삭제하도록 작성했다. 로드 실패로 ID를 모르는 plugin 파일 삭제에는 이력을 연결하지 않는다. 현재 작업에서 실제 삭제를 실행한 것은 아니다.

미지정/legacy 이력의 사용자 소유권 검토·명시적 재귀속 UI는 남아 있다. IMPL-555만으로 이미 복원한 파일에는 표식이 없을 수 있으며 이번 구현이 과거 파일을 자동 판별하거나 소급 변환하지 않는다. 표식만 복사에서 제외하거나 외부 도구가 제거하면 이 경계가 유지된다고 보장하지 않는다. inactive 복원 폴더를 옮길 때는 표식을 포함한 전체 파일 쌍을 보존한다.

## 현재 저장소 복원의 기록과 부분 실패

새 operation 폴더에 암호화된 `history-restore-plan.cbhm` 및 `history-restore-prepared.json`을 먼저 보관한다. 후자는 operation/archive ID, 예정 파일 수와 상태만 담는다. 쓰기 직전 대상 부재를 다시 요구하고, 실제 게시도 CreateNew이므로 확인 이후 생긴 파일을 덮지 않는다. provider 파일에는 기존 store의 exclusive coordination lock도 적용한다.

모든 게시가 끝나면 `history-restore-completed.json`에 `MISSING_HISTORY_FILES_PUBLISHED`와 게시한 entry ID를 기록한다. 이는 해당 파일 게시 코드의 완료 상태이며 parser/소유권/화면/forecast 검증과는 별개다. `runtimeValidation`은 `NOT_RUN`이다.

중간 실패에서는 이미 일부 파일이 만들어졌을 수 있다. `history-restore-failed.json`을 기록하도록 시도하고, 실패 기록 자체를 쓸 수 없어도 성공으로 간주하지 않는다. 준비 기록만 있거나 완료 기록이 없으면 불완전한 작업이다. 원본 archive, operation 기록과 이미 게시한 파일을 보존한다. 자동 rollback/삭제 또는 이미 존재하는 파일을 건너뛰는 암묵적 재시도는 없다. 부분 작업의 식별·명시적 재개/GUI는 남아 있으며, 같은 명령을 그대로 재실행하면 생성된 대상 때문에 거절될 수 있다.

## 동시 실행·파일 경계와 남은 범위

설정 복구에서 추가한 profile exclusive lock을 사용하므로 같은 잠금에 참여하는 앱은 백업·복원과 동시에 시작하지 못한다. 이전 버전/외부 writer 전체를 통제하는 잠금은 아니며 두 번의 원본 관측도 전체 filesystem transaction을 제공하지 않는다. native bounded 열거·단일 입력 handle·부모 pin·regular single-link 파일 조건을 공통 recovery I/O로 사용한다. 빈 이력 파일은 명시적으로 허용하지만 기존 설정/명령 입력의 빈 파일 거절 의미는 유지한다.

출력은 현재 CodexBar 이력 데이터 root 밖이어야 하고, 복원 출력은 입력 archive 내부에도 만들지 않는다. live 복원에 사용하는 archive 역시 live data root 밖에 있어야 한다. 이 경로 제한은 모든 MSIX package/install 제거 영향 밖의 저장임을 증명하지 않는다. archive는 그런 제거 대상 밖에 별도로 보관해야 한다.

비용 SQLite/웹 cache·credential 등 나머지 저장소, legacy 이력의 명시적 소유권 검토/재귀속과 과거 복원 자료 처리, 부분 복원 재개, 제거 도구의 전체 보존 선택과 GUI, profile/key 복구 정책, Windows x64/ARM64 실제 round-trip/중단/ACL/가상화 동작은 남아 있다. [MSIX 제거](MSIX-REMOVAL.ko.md)의 `backup: NOT_CREATED` 정책은 이 일부 백업 구현만으로 바꾸지 않는다.
