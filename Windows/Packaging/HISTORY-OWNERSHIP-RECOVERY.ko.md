# 복원된 plan 이력을 현재 계정에 연결

IMPL-558에서 native UI부터 runtime·store·변경 전 복구 사본까지 코드 경로를 작성했다. 상태는 **CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION**이다. 실제 UI·복원·계정·파일·DPAPI·Windows 실행, 빌드·테스트·lint·compiler/manifest 검증은 수행하지 않았다.

## 적용 범위와 사용 흐름

현재 이력 차트가 연결된 first-party 공급자의 `plan-utilization-history/<provider-id>.json`이 대상이다. 읽을 수 있는 복원 표식과 현재 조회로 식별한 scoped 계정이 있어야 한다. 원본 데이터만 보고 현재 계정을 추정하거나 preferredAccountKey로 대체하지 않는다. 표식 없는 과거 파일·계정 미식별 자료·plugin 전용 UI·pace JSONL은 이 경로의 완료 범위가 아니다.

1. 현재 공급자/계정을 선택하고 사용량을 조회한 후 **사용량 이력**을 연다.
2. 복원 표식이 있는 파일에는 **복원 이력 계정 연결…** 버튼을 표시한다.
3. 개인정보 숨기기가 켜져 있으면 대상 계정을 확인할 수 있도록 해제 안내를 표시한다.
4. 검토 창에서 현재 대상 계정과 선택한 묶음의 종류·기간·표본 수를 확인한다. 저장된 키의 SHA256 식별값은 묶음을 구분할 뿐 계정 소유권의 증거가 아니다. 원래 계정 키 자체는 UI에 전달하지 않는다.
5. 다른 비어 있지 않은 묶음 하나를 직접 선택하고, 해당 자료가 표시된 대상 계정에 속한다는 확인란을 선택해야 적용 버튼을 사용할 수 있다. 초기 선택/체크는 없고 묶음을 바꾸면 체크를 해제한다. Enter의 기본 버튼은 취소다.
6. 적용 결과에는 변경 전 복구 사본의 ID와 현재 앱이 사용하는 보관 경로를 표시한다. 다음 새로고침에서 변경된 자료를 읽는다.

검토는 3분 뒤 만료된다. 현재 계정/config context, 개인정보 표시, 창의 snapshot이 바뀌면 기존 검토를 계속 사용하지 않는다. 파일/표식 변경은 적용 단계에서도 현재 바이트와 revision을 대조하여 거절한다. UI 선택에는 일회성 review/candidate UUID만 전달하고 runtime이 보유한 실제 원본 키/대상 키에 결합한다. 사용자 확인은 선택한 자료에 대한 명시적 귀속 판단이며 서비스가 제공한 ownership attestation이 아니다.

## 변경과 데이터 의미

`PlanUtilizationHistoryOwnershipTransfer`는 선택한 unscoped 묶음 또는 다른 계정 bucket 하나만 현재 계정 bucket으로 옮긴다. 이메일·단일 계정 연속성·다른 공급자 자료를 추론에 쓰지 않는다. 기존 대상 표본과는 기존 hourly peak/리셋·기간 정규화·보관 한도 reducer를 사용한다. 동일 시간대 중복의 모든 원본 행을 활성 파일에 그대로 추가하는 방식이 아니다.

다른 계정 bucket과 root 확장 필드는 JSON 값으로 유지한다. 재작성할 원본/대상 series 또는 entry에 해석하지 못하는 확장 필드가 있으면 버리지 않고 적용을 거절한다. 활성 파일의 공백·키 순서·직렬화는 바뀔 수 있으며 바이트 단위 원본은 아래 암호화 사본에 보존한다.

동적 session/weekly pair가 같거나 비어 있는 대상으로 알려진 pair를 옮길 수 있을 때는 그 정보를 사용한다. 충돌/미확인 pair는 무효화한다. 일반 공급자의 후속 관측은 기존 구간 전환 규칙에 따라 session/weekly 이력을 새로 시작할 수 있다. 이는 화면 안내에도 명시하며, 이전 표본은 복구 사본에 남는다. Codex/Claude/Antigravity의 고정 구간 예측은 기존 provider 계약을 따른다. 동적 구간별 이력을 나눠 유지·검토하는 추가 복구 UX는 남아 있다.

원본 bucket과 관련 pair key는 선택한 replacement document에서만 제거한다. 모든 merge/직렬화·크기 조건을 통과한 뒤 게시한다. 복원 표식은 계속 유지하므로 연결하지 않은 다른 legacy/unscoped 자료의 자동 이관을 다시 허용하지 않는다. 변경 후 열린 이력 context와 read/forecast cache를 무효화한다. pace의 계정/표본은 변경하지 않는다.

## 적용 전 사본과 실패

provider lock과 이력 디렉터리 pin 안에서 원본 바이트/표식을 읽고 검토 revision과 대조한다. 같은 Windows profile의 DPAPI와 기존 usage history archive 형식을 사용하여 다음에 저장한다.

`<CodexBar data root>/history-ownership-backups/<backup-uuid>/`

공급자 원본 파일 전체를 하나의 chunk로 보관하고 최종 암호화 manifest까지 게시해야 활성 이력을 바꾸는 단계로 간다. 기존 `--history-restore-new`가 이 사본의 consumer이므로 별도 독자 백업 형식을 만들지 않는다. 백업 폴더에는 원본/변경 후 hash와 provider·backup ID를 담은 준비 기록을 먼저 쓰고, 활성 파일 게시 후 완료 기록을 별도로 쓴다. 이 기록에는 원래 계정 키나 계정 label을 넣지 않는다.

활성 파일은 private writer의 staging/flush/replace 경로로 게시한다. 게시 직전 원본 바이트·표식·현재 계정/config context와 개인정보 표시를 다시 대조한다. 이는 참여하는 provider writer와의 조정이며 외부 writer 전체를 제어하는 filesystem transaction은 아니다.

- 백업/준비 기록 실패: 활성 파일 게시로 진행하지 않는다. 부분 파일은 보존한다.
- 게시 실패/중단: 사본이 완성됐다면 ID·경로를 안내한다. 자동 재시도·원복·기존 파일 삭제는 없다.
- 활성 파일 게시 후 완료 기록 실패: 게시 성공과 기록 누락을 구분해 안내한다. 같은 확인을 자동 재사용하지 않는다.
- 다음 새로고침 전에 프로세스가 끝나더라도 새 파일과 변경 전 사본은 디스크에 남는 경로로 작성했다. 실제 전원 장애/파일 수명 동작은 미검증이다.

앱 데이터 내부 사본은 **제거 전에 보존할 외부 백업을 대신하지 않는다.** MSIX 제거 등에서 함께 사라질 수 있으므로 보관 폴더 전체를 별도 위치에 복사해야 한다. 기존 Windows profile/key가 필요하며 다른 장치로 옮기는 복구키 형식이 아니다.

## 원본 꺼내기 예시 — 미실행

모든 앱 세션을 종료하고 UI에서 안내한 정확한 사본 경로를 사용한다. 출력 부모는 이미 존재해야 하고 출력 폴더 자체는 새 경로여야 한다.

```powershell
& 'C:\Apps\CodexBar\CodexBarWindows.exe' --history-restore-new '<안내된 사본 폴더의 절대 경로>' 'D:\Recovered\before-ownership-001'
```

이 명령은 새 폴더에 변경 전 원본과 복원 제한 표식을 준비한다. 현재 활성 이력에 자동으로 덮어쓰거나 그 이후 쌓인 표본을 삭제하지 않는다. 최신 표본과 비교해 되돌리는 GUI·중단된 연결 작업의 자동 조정은 아직 없다. 사용량 이력 archive/제한/명령 계약은 [사용량 이력 복원](USAGE-HISTORY-RECOVERY.ko.md)을 따른다.

## 남은 범위

pace JSONL의 명시적 소유권 연결·cache/retention, plugin 계정 이력 검토 화면, 표식 없는 과거 복원 파일, 동적 구간 분리/연결 취소, 전체 저장소 백업·제거/설치 UX와 Windows x64/ARM64의 실제 UI·실패·계정 교체·재실행 검증이 남아 있다. 이 단위는 전체 W01~W16/G0~G6 또는 배포 준비 완료가 아니다.
